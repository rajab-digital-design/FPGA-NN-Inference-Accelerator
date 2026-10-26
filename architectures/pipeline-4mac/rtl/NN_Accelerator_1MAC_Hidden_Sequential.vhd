library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nn_accelerator_1mac_hidden_sequential is
    generic (
        NUM_INPUTS  : integer := 4;
        NUM_NEURONS : integer := 8
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;
        done  : out std_logic;

        -- 000 = input memory
        -- 001..100 = weight banks
        -- 101 = bias memory
        cfg_we      : in std_logic;
        cfg_mem_sel : in unsigned(2 downto 0);
        cfg_addr    : in unsigned(6 downto 0);
        cfg_data    : in signed(15 downto 0);

        cfg_rd_en      : in std_logic;
        cfg_rd_mem_sel : in unsigned(2 downto 0);
        cfg_rd_addr    : in unsigned(6 downto 0);
        cfg_rd_data    : out signed(15 downto 0);

        hidden_n1 : out signed(19 downto 0);
        hidden_n2 : out signed(19 downto 0);
        hidden_n3 : out signed(19 downto 0);
        hidden_n4 : out signed(19 downto 0);
        hidden_n5 : out signed(19 downto 0);
        hidden_n6 : out signed(19 downto 0);
        hidden_n7 : out signed(19 downto 0);
        hidden_n8 : out signed(19 downto 0);

        debug_hidden_running : out std_logic;
        debug_hidden_mac_active : out std_logic;
        debug_hidden_first_mac : out std_logic;
        debug_hidden_neuron : out integer range 0 to 255;
        debug_hidden_input_index : out unsigned(5 downto 0)
    );
end entity;

architecture structural of nn_accelerator_1mac_hidden_sequential is
    type bias_mem_t is array (0 to NUM_NEURONS-1) of signed(15 downto 0);
    type hidden_mem_t is array (0 to NUM_NEURONS-1) of signed(19 downto 0);

    signal bias_mem : bias_mem_t := (others => (others => '0'));
    signal hidden_mem : hidden_mem_t := (others => (others => '0'));

    signal input_wr_en   : std_logic;
    signal input_wr_addr : unsigned(5 downto 0);
    signal input_wr_data : signed(15 downto 0);

    signal input_mem_addr : unsigned(5 downto 0);
    signal input_mem_data : signed(15 downto 0);
    signal input_load_start : std_logic := '0';
    signal input_load_done  : std_logic;
    signal input_compute_index : unsigned(5 downto 0) := (others => '0');
    signal input_compute_data  : signed(15 downto 0);
    signal cfg_input_rd_en : std_logic;

    signal weight_wr_en   : std_logic;
    signal weight_wr_bank : unsigned(2 downto 0);
    signal weight_wr_addr : unsigned(7 downto 0);
    signal weight_wr_data : signed(15 downto 0);

    signal weight_rd_addr : unsigned(7 downto 0) := (others => '0');
    signal weight1, weight2, weight3, weight4 : signed(15 downto 0);

    signal active_weight : signed(15 downto 0);
    signal active_bias   : signed(15 downto 0);

    signal neuron_idx_r : integer range 0 to NUM_NEURONS-1 := 0;
    signal input_idx_r  : integer range 0 to NUM_INPUTS-1 := 0;
    signal acc_r        : signed(19 downto 0) := (others => '0');

    type compute_state_t is (C_IDLE, C_PRIME, C_RUN);
    signal compute_state : compute_state_t := C_IDLE;
    signal compute_running_r : std_logic := '0';
    signal compute_mac_active_r : std_logic := '0';
    signal compute_first_mac_r : std_logic := '0';

    type top_state_t is (T_IDLE, T_WAIT_INPUT);
    signal top_state : top_state_t := T_IDLE;

    signal cfg_weight_rd_addr : unsigned(7 downto 0);
    signal cfg_weight_rd_en   : std_logic;
    signal cfg_rd_weight1, cfg_rd_weight2, cfg_rd_weight3, cfg_rd_weight4 : signed(15 downto 0);

begin
    --------------------------------------------------------------------
    -- Configuration writes
    --------------------------------------------------------------------
    input_wr_en    <= cfg_we when cfg_mem_sel = "000" else '0';
    input_wr_addr  <= cfg_addr(5 downto 0);
    input_wr_data  <= cfg_data;

    weight_wr_en   <= cfg_we when (cfg_mem_sel = "001" or cfg_mem_sel = "010" or
                                   cfg_mem_sel = "011" or cfg_mem_sel = "100") else '0';
    weight_wr_bank <= cfg_mem_sel;
    weight_wr_addr <= resize(cfg_addr, 8);
    weight_wr_data <= cfg_data;

    --------------------------------------------------------------------
    -- Bias register file
    --------------------------------------------------------------------
    process(clk)
        -- Validate the wider configuration address before using it as an
        -- index into the per-neuron bias register file.
        variable a : integer range 0 to NUM_NEURONS-1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                bias_mem <= (others => (others => '0'));
            elsif cfg_we = '1' and cfg_mem_sel = "101" then
                if to_integer(cfg_addr) < NUM_NEURONS then
                    a := to_integer(cfg_addr);
                    bias_mem(a) <= cfg_data;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Input memory + corrected synchronous-read input buffer
    --------------------------------------------------------------------
    INPUT_MEMORY : entity work.input_memory_generic
        generic map (
            DATA_WIDTH => 16,
            ADDR_WIDTH => 6,
            DEPTH      => NUM_INPUTS
        )
        port map (
            clk      => clk,
            rd_en    => '1',
            rd_addr  => input_mem_addr,
            data_out => input_mem_data,
            wr_en    => input_wr_en,
            wr_addr  => input_wr_addr,
            wr_data  => input_wr_data
        );

    INPUT_BUFFER : entity work.input_register_buffer
        generic map (
            DATA_WIDTH => 16,
            NUM_INPUTS => NUM_INPUTS,
            ADDR_WIDTH => 6
        )
        port map (
            clk => clk,
            rst => rst,
            load_start => input_load_start,
            mem_addr => input_mem_addr,
            mem_data => input_mem_data,
            load_done => input_load_done,
            read_index => input_compute_index,
            data_out => input_compute_data,
            external_read_en => cfg_input_rd_en,
            external_read_addr => cfg_rd_addr(5 downto 0)
        );

    --------------------------------------------------------------------
    -- Dual-port weight RAM. Port A is used for the sequential reader.
    --------------------------------------------------------------------
    WEIGHT_MEMORY : entity work.weight_memory_dualport_generic
        generic map (
            DATA_WIDTH => 16,
            NUM_INPUTS => NUM_INPUTS,
            NUM_NEURONS => NUM_NEURONS,
            ADDR_WIDTH => 8
        )
        port map (
            clk => clk,
            wr_en => weight_wr_en,
            wr_bank => weight_wr_bank,
            wr_addr => weight_wr_addr,
            wr_data => weight_wr_data,

            rd_a_en => '1',
            rd_a_addr => weight_rd_addr,
            rd_a_weight1 => weight1,
            rd_a_weight2 => weight2,
            rd_a_weight3 => weight3,
            rd_a_weight4 => weight4,

            rd_b_en => cfg_weight_rd_en,
            rd_b_addr => cfg_weight_rd_addr,
            rd_b_weight1 => cfg_rd_weight1,
            rd_b_weight2 => cfg_rd_weight2,
            rd_b_weight3 => cfg_rd_weight3,
            rd_b_weight4 => cfg_rd_weight4
        );

    --------------------------------------------------------------------
    -- Active bank selection.
    -- N1/N5 -> Bank1, N2/N6 -> Bank2, etc.
    --------------------------------------------------------------------
    process(neuron_idx_r, weight1, weight2, weight3, weight4, bias_mem)
        variable bank_sel : integer;
    begin
        bank_sel := (neuron_idx_r mod 4) + 1;

        case bank_sel is
            when 1 => active_weight <= weight1;
            when 2 => active_weight <= weight2;
            when 3 => active_weight <= weight3;
            when 4 => active_weight <= weight4;
            when others => active_weight <= (others => '0');
        end case;

        active_bias <= bias_mem(neuron_idx_r);
    end process;

    --------------------------------------------------------------------
    -- Sequential hidden-layer controller.
    -- One PRIME cycle per neuron + NUM_INPUTS MAC cycles per neuron.
    -- For 8 neurons / 4 inputs: 8*(1+4)=40 running cycles,
    -- containing 32 actual MAC cycles.
    --------------------------------------------------------------------
    process(clk)
        variable prod_v   : signed(31 downto 0);
        variable scaled_v : signed(19 downto 0);
        variable bias_v   : signed(19 downto 0);
        variable next_acc : signed(19 downto 0);
        variable next_neuron_base : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                neuron_idx_r <= 0;
                input_idx_r <= 0;
                acc_r <= (others => '0');
                weight_rd_addr <= (others => '0');
                compute_state <= C_IDLE;
                compute_running_r <= '0';
                compute_mac_active_r <= '0';
                compute_first_mac_r <= '0';
                hidden_mem <= (others => (others => '0'));

            else
                done <= '0';
                compute_mac_active_r <= '0';
                compute_first_mac_r <= '0';

                case compute_state is
                    when C_IDLE =>
                        compute_running_r <= '0';

                        if input_load_done = '1' then
                            neuron_idx_r <= 0;
                            input_idx_r <= 0;
                            acc_r <= (others => '0');
                            weight_rd_addr <= (others => '0');
                            compute_running_r <= '0';
                            compute_state <= C_PRIME;
                        end if;

                    when C_PRIME =>
                        -- The first weight for the active neuron is already
                        -- valid from the synchronous RAM read at the previous
                        -- edge. Prepare the NEXT weight address now so the
                        -- following MAC cycle sees the next weight.
                        compute_running_r <= '1';

                        if NUM_INPUTS > 1 then
                            weight_rd_addr <= to_unsigned(
                                (neuron_idx_r / 4) * NUM_INPUTS + 1, 8);
                        else
                            weight_rd_addr <= to_unsigned(
                                (neuron_idx_r / 4) * NUM_INPUTS, 8);
                        end if;

                        compute_state <= C_RUN;

                    when C_RUN =>
                        compute_running_r <= '1';
                        compute_mac_active_r <= '1';

                        if input_idx_r = 0 then
                            compute_first_mac_r <= '1';
                        end if;

                        prod_v := input_compute_data * active_weight;
                        scaled_v := resize(shift_right(prod_v, 8), 20);
                        bias_v := resize(active_bias, 20);

                        if input_idx_r = 0 then
                            next_acc := bias_v + scaled_v;
                        else
                            next_acc := acc_r + scaled_v;
                        end if;

                        acc_r <= next_acc;

                        if input_idx_r = NUM_INPUTS-1 then
                            hidden_mem(neuron_idx_r) <= next_acc;

                            if neuron_idx_r = NUM_NEURONS-1 then
                                compute_running_r <= '0';
                                compute_state <= C_IDLE;
                                done <= '1';

                            else
                                next_neuron_base := ((neuron_idx_r + 1) / 4) * NUM_INPUTS;
                                neuron_idx_r <= neuron_idx_r + 1;
                                input_idx_r <= 0;
                                acc_r <= (others => '0');
                                weight_rd_addr <= to_unsigned(next_neuron_base, 8);
                                compute_running_r <= '0';
                                compute_state <= C_PRIME;
                            end if;
                        else
                            input_idx_r <= input_idx_r + 1;
                            weight_rd_addr <= weight_rd_addr + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Top-level start sequencing: only the input-load handshake is here.
    -- The compute controller itself starts when input_load_done is seen.
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                top_state <= T_IDLE;
                input_load_start <= '0';
            else
                input_load_start <= '0';

                case top_state is
                    when T_IDLE =>
                        if start = '1' then
                            input_load_start <= '1';
                            top_state <= T_WAIT_INPUT;
                        end if;

                    when T_WAIT_INPUT =>
                        if input_load_done = '1' then
                            top_state <= T_IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    cfg_input_rd_en <= cfg_rd_en when (compute_running_r = '0' and cfg_rd_mem_sel = "000") else '0';
    cfg_weight_rd_addr <= resize(cfg_rd_addr, 8);
    cfg_weight_rd_en <= cfg_rd_en when (compute_running_r = '0' and
                                        (cfg_rd_mem_sel = "001" or cfg_rd_mem_sel = "010" or
                                         cfg_rd_mem_sel = "011" or cfg_rd_mem_sel = "100")) else '0';

    --------------------------------------------------------------------
    -- Configuration readback.
    --------------------------------------------------------------------
    process(cfg_rd_mem_sel, cfg_rd_addr, input_mem_data,
            cfg_rd_weight1, cfg_rd_weight2, cfg_rd_weight3, cfg_rd_weight4,
            bias_mem)
        variable a : integer range 0 to NUM_NEURONS-1;
    begin
        case cfg_rd_mem_sel is
            when "000" => cfg_rd_data <= input_mem_data;
            when "001" => cfg_rd_data <= cfg_rd_weight1;
            when "010" => cfg_rd_data <= cfg_rd_weight2;
            when "011" => cfg_rd_data <= cfg_rd_weight3;
            when "100" => cfg_rd_data <= cfg_rd_weight4;
            when "101" =>
                if to_integer(cfg_rd_addr) < NUM_NEURONS then
                    a := to_integer(cfg_rd_addr);
                    cfg_rd_data <= bias_mem(a);
                else
                    cfg_rd_data <= (others => '0');
                end if;
            when others => cfg_rd_data <= (others => '0');
        end case;
    end process;

    --------------------------------------------------------------------
    -- Outputs
    --------------------------------------------------------------------
    hidden_n1 <= hidden_mem(0);
    hidden_n2 <= hidden_mem(1);
    hidden_n3 <= hidden_mem(2);
    hidden_n4 <= hidden_mem(3);
    hidden_n5 <= hidden_mem(4);
    hidden_n6 <= hidden_mem(5);
    hidden_n7 <= hidden_mem(6);
    hidden_n8 <= hidden_mem(7);

    -- The hidden controller must drive the input-buffer read index.
    -- Without this assignment, the index stayed at zero and x0 was used
    -- for every MAC operation.
    input_compute_index <= to_unsigned(input_idx_r, 6);

    -- Debug running includes the PRIME/setup cycle as part of the hidden
    -- processing window. The actual MAC cycle counter remains separate.
    debug_hidden_running <= '1' when compute_state /= C_IDLE else '0';
    debug_hidden_mac_active <= compute_mac_active_r;
    debug_hidden_first_mac <= compute_first_mac_r;
    debug_hidden_neuron <= neuron_idx_r;
    debug_hidden_input_index <= to_unsigned(input_idx_r, 6);
end architecture;
