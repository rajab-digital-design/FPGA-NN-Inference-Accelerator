library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nn_accelerator_2x8x1_dualport is
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;
        done  : out std_logic;

        -- Hidden-layer configuration
        -- 000 = input, 001..100 = hidden weight banks, 101 = hidden bias
        -- 110 = output weights W2, 111 = output bias b2
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

        relu_n1 : out signed(19 downto 0);
        relu_n2 : out signed(19 downto 0);
        relu_n3 : out signed(19 downto 0);
        relu_n4 : out signed(19 downto 0);
        relu_n5 : out signed(19 downto 0);
        relu_n6 : out signed(19 downto 0);
        relu_n7 : out signed(19 downto 0);
        relu_n8 : out signed(19 downto 0);

        output_result : out signed(31 downto 0);
        output_running : out std_logic;
        output_mac_index : out unsigned(3 downto 0);

        debug_hidden_running : out std_logic;
        debug_hidden_group   : out integer range 0 to 255;
        debug_hidden_first_cycle : out std_logic;
        debug_hidden_prefetch_en : out std_logic
    );
end entity;

architecture structural of nn_accelerator_2x8x1_dualport is
    signal hidden_cfg_rd_data : signed(15 downto 0);

    signal hidden_done : std_logic;
    signal hidden_running : std_logic;
    signal hidden_group : integer range 0 to 255;
    signal hidden_first_cycle : std_logic;
    signal hidden_prefetch_en : std_logic;

    signal dbg_acc1, dbg_acc2 : signed(19 downto 0);

    signal hidden_r1, hidden_r2, hidden_r3, hidden_r4 : signed(19 downto 0) := (others => '0');
    signal hidden_r5, hidden_r6, hidden_r7, hidden_r8 : signed(19 downto 0) := (others => '0');

    signal output_w1, output_w2, output_w3, output_w4 : signed(15 downto 0) := (others => '0');
    signal output_w5, output_w6, output_w7, output_w8 : signed(15 downto 0) := (others => '0');
    signal output_bias : signed(15 downto 0) := (others => '0');

    signal output_start : std_logic := '0';
    signal output_done  : std_logic;
    signal output_result_r : signed(31 downto 0);
    signal output_running_r : std_logic;
    signal output_mac_index_r : unsigned(3 downto 0);

    type net_state_t is (NET_IDLE, NET_WAIT_HIDDEN, NET_WAIT_OUTPUT);
    signal net_state : net_state_t := NET_IDLE;

begin
    --------------------------------------------------------------------
    -- Hidden layer: two-MAC, dual-port core using the same Q8.8 datapath and config interface.
    --------------------------------------------------------------------
    HIDDEN : entity work.nn_accelerator_2mac_dualport
        generic map (
            NUM_INPUTS  => 4,
            NUM_NEURONS => 8
        )
        port map (
            clk => clk,
            rst => rst,
            start => start,
            done => hidden_done,
            cfg_we => cfg_we,
            cfg_mem_sel => cfg_mem_sel,
            cfg_addr => cfg_addr,
            cfg_data => cfg_data,
            cfg_rd_en => cfg_rd_en,
            cfg_rd_mem_sel => cfg_rd_mem_sel,
            cfg_rd_addr => cfg_rd_addr,
            cfg_rd_data => hidden_cfg_rd_data,
            debug_input_addr => open,
            debug_weight_addr => open,
            debug_prefetch_addr => open,
            debug_current_group => hidden_group,
            debug_first_cycle => hidden_first_cycle,
            debug_use_prefetch => open,
            debug_prefetch_en => hidden_prefetch_en,
            debug_running => hidden_running,
            debug_acc1 => dbg_acc1,
            debug_acc2 => dbg_acc2
        );

    --------------------------------------------------------------------
    -- Output weights and bias storage.
    --------------------------------------------------------------------
    process(clk)
        variable a : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                output_w1 <= (others => '0'); output_w2 <= (others => '0');
                output_w3 <= (others => '0'); output_w4 <= (others => '0');
                output_w5 <= (others => '0'); output_w6 <= (others => '0');
                output_w7 <= (others => '0'); output_w8 <= (others => '0');
                output_bias <= (others => '0');
            else
                if cfg_we = '1' and cfg_mem_sel = "110" then
                    a := to_integer(cfg_addr);
                    case a is
                        when 0 => output_w1 <= cfg_data;
                        when 1 => output_w2 <= cfg_data;
                        when 2 => output_w3 <= cfg_data;
                        when 3 => output_w4 <= cfg_data;
                        when 4 => output_w5 <= cfg_data;
                        when 5 => output_w6 <= cfg_data;
                        when 6 => output_w7 <= cfg_data;
                        when 7 => output_w8 <= cfg_data;
                        when others => null;
                    end case;
                elsif cfg_we = '1' and cfg_mem_sel = "111" then
                    if cfg_addr = to_unsigned(0, 7) then
                        output_bias <= cfg_data;
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Capture hidden-layer results on rising edges.
    --
    -- IMPORTANT timing rule:
    -- At a transition, hidden_group names the newly started group while
    -- dbg_acc1/2 still hold the preceding group's completed pair at the
    -- sampling edge. The final pair is captured when hidden_done is high.
    -- This capture method does not depend on falling-edge behavior.
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                hidden_r1 <= (others => '0');
                hidden_r2 <= (others => '0');
                hidden_r3 <= (others => '0');
                hidden_r4 <= (others => '0');
                hidden_r5 <= (others => '0');
                hidden_r6 <= (others => '0');
                hidden_r7 <= (others => '0');
                hidden_r8 <= (others => '0');
            else
                -- When first_cycle marks a transition, group_index is the
                -- newly started group while dbg_acc1/2 still hold the
                -- previous group's completed results at this sampling edge.
                if hidden_first_cycle = '1' then
                    case hidden_group is
                        when 1 =>
                            hidden_r1 <= dbg_acc1; hidden_r2 <= dbg_acc2;
                        when 2 =>
                            hidden_r3 <= dbg_acc1; hidden_r4 <= dbg_acc2;
                        when 3 =>
                            hidden_r5 <= dbg_acc1; hidden_r6 <= dbg_acc2;
                        when others => null;
                    end case;
                elsif hidden_done = '1' then
                    -- Final group (neurons 7 and 8) is captured on done.
                    hidden_r7 <= dbg_acc1;
                    hidden_r8 <= dbg_acc2;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Network sequencing: hidden layer first, output layer second.
    --------------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                net_state <= NET_IDLE;
                output_start <= '0';
            else
                output_start <= '0';

                case net_state is
                    when NET_IDLE =>
                        if start = '1' then
                            net_state <= NET_WAIT_HIDDEN;
                        end if;

                    when NET_WAIT_HIDDEN =>
                        if hidden_done = '1' then
                            output_start <= '1';
                            net_state <= NET_WAIT_OUTPUT;
                        end if;

                    when NET_WAIT_OUTPUT =>
                        if output_done = '1' then
                            net_state <= NET_IDLE;
                        end if;

                    when others =>
                        net_state <= NET_IDLE;
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- ReLU layer. Negative hidden outputs become zero.
    --------------------------------------------------------------------
    relu_n1 <= (others => '0') when hidden_r1(19) = '1' else hidden_r1;
    relu_n2 <= (others => '0') when hidden_r2(19) = '1' else hidden_r2;
    relu_n3 <= (others => '0') when hidden_r3(19) = '1' else hidden_r3;
    relu_n4 <= (others => '0') when hidden_r4(19) = '1' else hidden_r4;
    relu_n5 <= (others => '0') when hidden_r5(19) = '1' else hidden_r5;
    relu_n6 <= (others => '0') when hidden_r6(19) = '1' else hidden_r6;
    relu_n7 <= (others => '0') when hidden_r7(19) = '1' else hidden_r7;
    relu_n8 <= (others => '0') when hidden_r8(19) = '1' else hidden_r8;

    OUTPUT : entity work.output_layer_1mac_sequential
        port map (
            clk => clk,
            rst => rst,
            start => output_start,
            hidden1 => hidden_r1,
            hidden2 => hidden_r2,
            hidden3 => hidden_r3,
            hidden4 => hidden_r4,
            hidden5 => hidden_r5,
            hidden6 => hidden_r6,
            hidden7 => hidden_r7,
            hidden8 => hidden_r8,
            weight1 => output_w1,
            weight2 => output_w2,
            weight3 => output_w3,
            weight4 => output_w4,
            weight5 => output_w5,
            weight6 => output_w6,
            weight7 => output_w7,
            weight8 => output_w8,
            bias => output_bias,
            result => output_result_r,
            running => output_running_r,
            done => output_done,
            mac_index => output_mac_index_r
        );

    --------------------------------------------------------------------
    -- Configuration readback.
    --------------------------------------------------------------------
    process(cfg_rd_mem_sel, cfg_rd_addr, hidden_cfg_rd_data,
            output_w1, output_w2, output_w3, output_w4,
            output_w5, output_w6, output_w7, output_w8, output_bias)
        variable a : integer;
    begin
        a := to_integer(cfg_rd_addr);

        case cfg_rd_mem_sel is
            when "110" =>
                case a is
                    when 0 => cfg_rd_data <= output_w1;
                    when 1 => cfg_rd_data <= output_w2;
                    when 2 => cfg_rd_data <= output_w3;
                    when 3 => cfg_rd_data <= output_w4;
                    when 4 => cfg_rd_data <= output_w5;
                    when 5 => cfg_rd_data <= output_w6;
                    when 6 => cfg_rd_data <= output_w7;
                    when 7 => cfg_rd_data <= output_w8;
                    when others => cfg_rd_data <= (others => '0');
                end case;

            when "111" =>
                if a = 0 then
                    cfg_rd_data <= output_bias;
                else
                    cfg_rd_data <= (others => '0');
                end if;

            when others =>
                cfg_rd_data <= hidden_cfg_rd_data;
        end case;
    end process;

    done <= output_done;

    hidden_n1 <= hidden_r1;
    hidden_n2 <= hidden_r2;
    hidden_n3 <= hidden_r3;
    hidden_n4 <= hidden_r4;
    hidden_n5 <= hidden_r5;
    hidden_n6 <= hidden_r6;
    hidden_n7 <= hidden_r7;
    hidden_n8 <= hidden_r8;

    output_result <= output_result_r;
    output_running <= output_running_r;
    output_mac_index <= output_mac_index_r;

    debug_hidden_running <= hidden_running;
    debug_hidden_group <= hidden_group;
    debug_hidden_first_cycle <= hidden_first_cycle;
    debug_hidden_prefetch_en <= hidden_prefetch_en;
end architecture;
