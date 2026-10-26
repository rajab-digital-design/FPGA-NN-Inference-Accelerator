library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nn_accelerator_4mac_dualport is
    generic (
        NUM_INPUTS  : integer := 21;
        NUM_NEURONS : integer := 10
    );
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;
        done  : out std_logic;

        cfg_we      : in std_logic;
        cfg_mem_sel : in unsigned(2 downto 0);
        cfg_addr    : in unsigned(6 downto 0);
        cfg_data    : in signed(15 downto 0);

        cfg_rd_en      : in std_logic;
        cfg_rd_mem_sel : in unsigned(2 downto 0);
        cfg_rd_addr    : in unsigned(6 downto 0);
        cfg_rd_data    : out signed(15 downto 0);

        debug_input_addr     : out unsigned(5 downto 0);
        debug_weight_addr    : out unsigned(7 downto 0);
        debug_prefetch_addr  : out unsigned(7 downto 0);
        debug_current_group  : out integer range 0 to 255;
        debug_first_cycle    : out std_logic;
        debug_use_prefetch   : out std_logic;
        debug_prefetch_en    : out std_logic;
        debug_running        : out std_logic;

        debug_acc1 : out signed(19 downto 0);
        debug_acc2 : out signed(19 downto 0);
        debug_acc3 : out signed(19 downto 0);
        debug_acc4 : out signed(19 downto 0)
    );
end entity;

architecture structural of nn_accelerator_4mac_dualport is
    type bias_mem_t is array (0 to NUM_NEURONS-1) of signed(15 downto 0);
    signal bias_mem : bias_mem_t := (others => (others => '0'));

    signal input_wr_en   : std_logic;
    signal input_wr_addr : unsigned(5 downto 0);
    signal input_wr_data : signed(15 downto 0);

    signal weight_wr_en   : std_logic;
    signal weight_wr_bank : unsigned(2 downto 0);
    signal weight_wr_addr : unsigned(7 downto 0);
    signal weight_wr_data : signed(15 downto 0);

    signal input_load_start : std_logic := '0';
    signal input_load_done  : std_logic;
    signal input_mem_addr   : unsigned(5 downto 0);
    signal input_mem_data   : signed(15 downto 0);
    signal input_compute_data : signed(15 downto 0);
    signal input_compute_index : unsigned(5 downto 0);
    signal cfg_input_rd_en : std_logic;

    signal scheduler_start : std_logic := '0';
    signal scheduler_input_addr : unsigned(5 downto 0);
    signal scheduler_buffer_read_addr : unsigned(5 downto 0);
    signal scheduler_weight_addr : unsigned(7 downto 0);
    signal scheduler_prefetch_addr : unsigned(7 downto 0);
    signal scheduler_prefetch_en : std_logic;
    signal scheduler_start1, scheduler_start2, scheduler_start3, scheduler_start4 : std_logic;
    signal scheduler_enable1, scheduler_enable2, scheduler_enable3, scheduler_enable4 : std_logic;
    signal scheduler_group : integer range 0 to 255;
    signal scheduler_first_cycle : std_logic;
    signal scheduler_use_prefetch : std_logic;
    signal scheduler_running : std_logic;
    signal scheduler_done : std_logic;

    signal weight_a1, weight_a2, weight_a3, weight_a4 : signed(15 downto 0);
    signal weight_b1, weight_b2, weight_b3, weight_b4 : signed(15 downto 0);
    signal cfg_weight_rd_addr : unsigned(7 downto 0);
    signal cfg_weight_rd_en : std_logic;
    signal weight_b_addr_sel : unsigned(7 downto 0);
    signal weight_b_en_sel : std_logic;
    signal mac_weight1, mac_weight2, mac_weight3, mac_weight4 : signed(15 downto 0);
    signal bias1, bias2, bias3, bias4 : signed(15 downto 0);
    signal acc1, acc2, acc3, acc4 : signed(19 downto 0);

    type top_state_t is (TOP_IDLE, TOP_WAIT_INPUT, TOP_RUN);
    signal top_state : top_state_t := TOP_IDLE;
begin

    ----------------------------------------------------------------
    -- Configuration WRITE decode.
    -- 000 = input, 001..100 = weight banks, 101 = bias.
    ----------------------------------------------------------------
    input_wr_en    <= cfg_we when cfg_mem_sel = "000" else '0';
    input_wr_addr  <= cfg_addr(5 downto 0);
    input_wr_data  <= cfg_data;

    weight_wr_en   <= cfg_we when (cfg_mem_sel = "001" or cfg_mem_sel = "010" or
                                   cfg_mem_sel = "011" or cfg_mem_sel = "100") else '0';
    weight_wr_bank <= cfg_mem_sel;
    weight_wr_addr <= resize(cfg_addr, 8);
    weight_wr_data <= cfg_data;

    ----------------------------------------------------------------
    -- Bias register file.
    ----------------------------------------------------------------
    process(clk)
        -- cfg_addr can represent more values than bias_mem contains.
        -- Only assign a valid address to this constrained index variable.
        variable a : integer range 0 to NUM_NEURONS-1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                bias_mem <= (others => (others => '0'));
            else
                if cfg_we = '1' and cfg_mem_sel = "101" then
                    if to_integer(cfg_addr) < NUM_NEURONS then
                        a := to_integer(cfg_addr);
                        bias_mem(a) <= cfg_data;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Input memory.
    ----------------------------------------------------------------
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

    ----------------------------------------------------------------
    -- Input register buffer.
    ----------------------------------------------------------------
    INPUT_BUFFER : entity work.input_register_buffer
        generic map (
            DATA_WIDTH => 16,
            NUM_INPUTS => NUM_INPUTS,
            ADDR_WIDTH => 6
        )
        port map (
            clk         => clk,
            rst         => rst,
            load_start  => input_load_start,
            mem_addr    => input_mem_addr,
            mem_data    => input_mem_data,
            load_done   => input_load_done,
            read_index  => input_compute_index,
            data_out    => input_compute_data,
            external_read_en => cfg_input_rd_en,
            external_read_addr => cfg_rd_addr(5 downto 0)
        );

    ----------------------------------------------------------------
    -- Dual-port weight memory.
    ----------------------------------------------------------------
    WEIGHT_MEMORY : entity work.weight_memory_dualport_generic
        generic map (
            DATA_WIDTH  => 16,
            NUM_INPUTS  => NUM_INPUTS,
            NUM_NEURONS => NUM_NEURONS,
            ADDR_WIDTH  => 8
        )
        port map (
            clk => clk,

            wr_en   => weight_wr_en,
            wr_bank => weight_wr_bank,
            wr_addr => weight_wr_addr,
            wr_data => weight_wr_data,

            rd_a_en => '1',
            rd_a_addr => scheduler_weight_addr,
            rd_a_weight1 => weight_a1,
            rd_a_weight2 => weight_a2,
            rd_a_weight3 => weight_a3,
            rd_a_weight4 => weight_a4,

            rd_b_en => weight_b_en_sel,
            rd_b_addr => weight_b_addr_sel,
            rd_b_weight1 => weight_b1,
            rd_b_weight2 => weight_b2,
            rd_b_weight3 => weight_b3,
            rd_b_weight4 => weight_b4
        );

    ----------------------------------------------------------------
    -- Weight source selection.
    -- Group 0 first cycle uses Port-A weight 0.
    -- Later group first cycles use Port-B's synchronous output from
    -- the prefetch read performed on the previous edge.
    ----------------------------------------------------------------
    mac_weight1 <= weight_b1 when scheduler_use_prefetch = '1' else weight_a1;
    mac_weight2 <= weight_b2 when scheduler_use_prefetch = '1' else weight_a2;
    mac_weight3 <= weight_b3 when scheduler_use_prefetch = '1' else weight_a3;
    mac_weight4 <= weight_b4 when scheduler_use_prefetch = '1' else weight_a4;

    ----------------------------------------------------------------
    -- Bias selection for the four neurons of the active group.
    ----------------------------------------------------------------
    process(bias_mem, scheduler_group)
        variable n0 : integer;
    begin
        n0 := scheduler_group * 4;

        if n0 < NUM_NEURONS then bias1 <= bias_mem(n0); else bias1 <= (others => '0'); end if;
        if n0+1 < NUM_NEURONS then bias2 <= bias_mem(n0+1); else bias2 <= (others => '0'); end if;
        if n0+2 < NUM_NEURONS then bias3 <= bias_mem(n0+2); else bias3 <= (others => '0'); end if;
        if n0+3 < NUM_NEURONS then bias4 <= bias_mem(n0+3); else bias4 <= (others => '0'); end if;
    end process;

    ----------------------------------------------------------------
    -- Scheduler.
    ----------------------------------------------------------------
    SCHEDULER : entity work.scheduler_4mac_dualport
        generic map (
            NUM_INPUTS  => NUM_INPUTS,
            NUM_NEURONS => NUM_NEURONS
        )
        port map (
            clk => clk,
            rst => rst,
            start => scheduler_start,

            input_addr => scheduler_input_addr,
            buffer_read_addr => scheduler_buffer_read_addr,
            weight_addr => scheduler_weight_addr,
            prefetch_addr => scheduler_prefetch_addr,
            prefetch_en => scheduler_prefetch_en,

            start1 => scheduler_start1,
            start2 => scheduler_start2,
            start3 => scheduler_start3,
            start4 => scheduler_start4,

            enable1 => scheduler_enable1,
            enable2 => scheduler_enable2,
            enable3 => scheduler_enable3,
            enable4 => scheduler_enable4,

            current_group => scheduler_group,
            first_cycle => scheduler_first_cycle,
            use_prefetch => scheduler_use_prefetch,

            running => scheduler_running,
            done => scheduler_done
        );

    ----------------------------------------------------------------
    -- MAC array.
    ----------------------------------------------------------------
    MAC_ARRAY : entity work.mac_array_optimized_masked
        port map (
            clk => clk,
            rst => rst,

            start1 => scheduler_start1,
            start2 => scheduler_start2,
            start3 => scheduler_start3,
            start4 => scheduler_start4,

            enable1 => scheduler_enable1,
            enable2 => scheduler_enable2,
            enable3 => scheduler_enable3,
            enable4 => scheduler_enable4,

            x_in => input_compute_data,

            weight1 => mac_weight1,
            weight2 => mac_weight2,
            weight3 => mac_weight3,
            weight4 => mac_weight4,

            bias1 => bias1,
            bias2 => bias2,
            bias3 => bias3,
            bias4 => bias4,

            acc1 => acc1,
            acc2 => acc2,
            acc3 => acc3,
            acc4 => acc4
        );

    ----------------------------------------------------------------
    -- Top-level sequencing:
    -- start -> load input vector -> run scheduler.
    ----------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                top_state <= TOP_IDLE;
                input_load_start <= '0';
                scheduler_start <= '0';
            else
                input_load_start <= '0';
                scheduler_start <= '0';

                case top_state is
                    when TOP_IDLE =>
                        if start = '1' then
                            input_load_start <= '1';
                            top_state <= TOP_WAIT_INPUT;
                        end if;

                    when TOP_WAIT_INPUT =>
                        if input_load_done = '1' then
                            scheduler_start <= '1';
                            top_state <= TOP_RUN;
                        end if;

                    when TOP_RUN =>
                        if scheduler_done = '1' then
                            top_state <= TOP_IDLE;
                        end if;

                    when others =>
                        top_state <= TOP_IDLE;
                end case;
            end if;
        end if;
    end process;

    done <= scheduler_done;
    -- Dedicated address FFs drive the buffer read mux. Control/debug
    -- continue to use the original counter. No extra pipeline stage.
    input_compute_index <= scheduler_buffer_read_addr;

    weight_b_addr_sel <= scheduler_prefetch_addr when scheduler_running = '1' else cfg_weight_rd_addr;
    weight_b_en_sel <= scheduler_prefetch_en or cfg_weight_rd_en;

    cfg_input_rd_en <= cfg_rd_en when (scheduler_running = '0' and cfg_rd_mem_sel = "000") else '0';

    cfg_weight_rd_addr <= resize(cfg_rd_addr, 8);
    cfg_weight_rd_en <= cfg_rd_en when (scheduler_running = '0' and
                                        (cfg_rd_mem_sel = "001" or cfg_rd_mem_sel = "010" or
                                         cfg_rd_mem_sel = "011" or cfg_rd_mem_sel = "100"))
                        else '0';

    ----------------------------------------------------------------
    -- Configuration READBACK.
    -- Memory reads are synchronous through Port-A. Bias is a register
    -- file and is exposed directly.
    ----------------------------------------------------------------
    process(cfg_rd_mem_sel, cfg_rd_addr, input_mem_data,
            weight_b1, weight_b2, weight_b3, weight_b4, bias_mem)
        -- Used only in the bias-read branch after range validation.
        variable a : integer range 0 to NUM_NEURONS-1;
    begin
        case cfg_rd_mem_sel is
            when "000" =>
                cfg_rd_data <= input_mem_data;
            when "001" =>
                cfg_rd_data <= weight_b1;
            when "010" =>
                cfg_rd_data <= weight_b2;
            when "011" =>
                cfg_rd_data <= weight_b3;
            when "100" =>
                cfg_rd_data <= weight_b4;
            when "101" =>
                if to_integer(cfg_rd_addr) < NUM_NEURONS then
                    a := to_integer(cfg_rd_addr);
                    cfg_rd_data <= bias_mem(a);
                else
                    cfg_rd_data <= (others => '0');
                end if;
            when others =>
                cfg_rd_data <= (others => '0');
        end case;
    end process;

    debug_input_addr    <= scheduler_input_addr;
    debug_weight_addr   <= scheduler_weight_addr;
    debug_prefetch_addr <= scheduler_prefetch_addr;
    debug_current_group <= scheduler_group;
    debug_first_cycle   <= scheduler_first_cycle;
    debug_use_prefetch  <= scheduler_use_prefetch;
    debug_prefetch_en   <= scheduler_prefetch_en;
    debug_running       <= scheduler_running;

    debug_acc1 <= acc1;
    debug_acc2 <= acc2;
    debug_acc3 <= acc3;
    debug_acc4 <= acc4;
end architecture;
