library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity NN_Accelerator_Parallel_vs_Sequential_RealNetwork_tb_FIXED5_PIPELINED4MAC is
end entity;

architecture tb of NN_Accelerator_Parallel_vs_Sequential_RealNetwork_tb_FIXED5_PIPELINED4MAC is
    type vec4_t is array (0 to 3) of integer;
    type vec8_t is array (0 to 7) of integer;
    type mat8x4_t is array (0 to 7, 0 to 3) of integer;

    constant TEST_INPUT : vec4_t := (-206, -233, -161, 21);

    constant W1 : mat8x4_t := (
        (  37,   96,  -52, -177),
        (   6,  -53,   92,   55),
        (-490,  194,  -60,   26),
        (  41,  -64,   96, -123),
        (   2,   38,   21,   36),
        ( 103, -195,   56,   50),
        ( 225,  111,  155, -110),
        (   2,  149,  -77,   90)
    );

    constant B1 : vec8_t := (-49, -1, 16, -111, -26, -18, 38, 8);
    constant W2 : vec8_t := (-34, -224, -53, -98, -46, 197, 108, 129);
    constant B2 : integer := -14;

    constant EXP_H : vec8_t := (-150, -12, 272, -158, -75, 44, -354, -75);
    constant EXP_R : vec8_t := (0, 0, 272, 0, 0, 44, 0, 0);
    constant EXP_OUT : integer := -38;

    signal clk : std_logic := '0';

    --------------------------------------------------------------------
    -- Parallel DUT signals
    --------------------------------------------------------------------
    signal p_rst : std_logic := '1';
    signal p_start : std_logic := '0';
    signal p_done : std_logic;
    signal p_cfg_we : std_logic := '0';
    signal p_cfg_mem_sel : unsigned(2 downto 0) := (others => '0');
    signal p_cfg_addr : unsigned(6 downto 0) := (others => '0');
    signal p_cfg_data : signed(15 downto 0) := (others => '0');
    signal p_cfg_rd_en : std_logic := '0';
    signal p_cfg_rd_mem_sel : unsigned(2 downto 0) := (others => '0');
    signal p_cfg_rd_addr : unsigned(6 downto 0) := (others => '0');
    signal p_cfg_rd_data : signed(15 downto 0);
    signal p_h1,p_h2,p_h3,p_h4,p_h5,p_h6,p_h7,p_h8 : signed(19 downto 0);
    signal p_r1,p_r2,p_r3,p_r4,p_r5,p_r6,p_r7,p_r8 : signed(19 downto 0);
    signal p_out : signed(31 downto 0);
    signal p_out_running : std_logic;
    signal p_out_idx : unsigned(3 downto 0);
    signal p_hidden_running : std_logic;
    signal p_hidden_group : integer range 0 to 255;
    signal p_hidden_first : std_logic;
    signal p_hidden_prefetch : std_logic;

    --------------------------------------------------------------------
    -- Sequential DUT signals
    --------------------------------------------------------------------
    signal s_rst : std_logic := '1';
    signal s_start : std_logic := '0';
    signal s_done : std_logic;
    signal s_cfg_we : std_logic := '0';
    signal s_cfg_mem_sel : unsigned(2 downto 0) := (others => '0');
    signal s_cfg_addr : unsigned(6 downto 0) := (others => '0');
    signal s_cfg_data : signed(15 downto 0) := (others => '0');
    signal s_cfg_rd_en : std_logic := '0';
    signal s_cfg_rd_mem_sel : unsigned(2 downto 0) := (others => '0');
    signal s_cfg_rd_addr : unsigned(6 downto 0) := (others => '0');
    signal s_cfg_rd_data : signed(15 downto 0);
    signal s_h1,s_h2,s_h3,s_h4,s_h5,s_h6,s_h7,s_h8 : signed(19 downto 0);
    signal s_r1,s_r2,s_r3,s_r4,s_r5,s_r6,s_r7,s_r8 : signed(19 downto 0);
    signal s_out : signed(31 downto 0);
    signal s_out_running : std_logic;
    signal s_out_idx : unsigned(3 downto 0);
    signal s_hidden_running : std_logic;
    signal s_hidden_mac_active : std_logic;
    signal s_hidden_first_mac : std_logic;
    signal s_hidden_neuron : integer range 0 to 255;
    signal s_hidden_input_idx : unsigned(5 downto 0);

    --------------------------------------------------------------------
    -- Counters
    --------------------------------------------------------------------
    signal p_hidden_running_cycles : integer := 0;
    signal p_hidden_first_count : integer := 0;
    signal p_prefetch_count : integer := 0;
    signal p_output_running_cycles : integer := 0;

    signal s_hidden_running_cycles : integer := 0;
    signal s_hidden_mac_cycles : integer := 0;
    signal s_hidden_first_count : integer := 0;
    signal s_output_running_cycles : integer := 0;

    signal p_finished : std_logic := '0';
    signal s_finished : std_logic := '0';

begin
    clk <= not clk after 5 ns;

    --------------------------------------------------------------------
    -- Parallel 4-MAC DUT
    --------------------------------------------------------------------
    P_DUT : entity work.nn_accelerator_4x8x1_dualport
        port map (
            clk => clk,
            rst => p_rst,
            start => p_start,
            done => p_done,
            cfg_we => p_cfg_we,
            cfg_mem_sel => p_cfg_mem_sel,
            cfg_addr => p_cfg_addr,
            cfg_data => p_cfg_data,
            cfg_rd_en => p_cfg_rd_en,
            cfg_rd_mem_sel => p_cfg_rd_mem_sel,
            cfg_rd_addr => p_cfg_rd_addr,
            cfg_rd_data => p_cfg_rd_data,
            hidden_n1 => p_h1, hidden_n2 => p_h2, hidden_n3 => p_h3, hidden_n4 => p_h4,
            hidden_n5 => p_h5, hidden_n6 => p_h6, hidden_n7 => p_h7, hidden_n8 => p_h8,
            relu_n1 => p_r1, relu_n2 => p_r2, relu_n3 => p_r3, relu_n4 => p_r4,
            relu_n5 => p_r5, relu_n6 => p_r6, relu_n7 => p_r7, relu_n8 => p_r8,
            output_result => p_out,
            output_running => p_out_running,
            output_mac_index => p_out_idx,
            debug_hidden_running => p_hidden_running,
            debug_hidden_group => p_hidden_group,
            debug_hidden_first_cycle => p_hidden_first,
            debug_hidden_prefetch_en => p_hidden_prefetch
        );

    --------------------------------------------------------------------
    -- Sequential 1-MAC DUT
    --------------------------------------------------------------------
    S_DUT : entity work.nn_accelerator_1x8x1_sequential
        port map (
            clk => clk,
            rst => s_rst,
            start => s_start,
            done => s_done,
            cfg_we => s_cfg_we,
            cfg_mem_sel => s_cfg_mem_sel,
            cfg_addr => s_cfg_addr,
            cfg_data => s_cfg_data,
            cfg_rd_en => s_cfg_rd_en,
            cfg_rd_mem_sel => s_cfg_rd_mem_sel,
            cfg_rd_addr => s_cfg_rd_addr,
            cfg_rd_data => s_cfg_rd_data,
            hidden_n1 => s_h1, hidden_n2 => s_h2, hidden_n3 => s_h3, hidden_n4 => s_h4,
            hidden_n5 => s_h5, hidden_n6 => s_h6, hidden_n7 => s_h7, hidden_n8 => s_h8,
            relu_n1 => s_r1, relu_n2 => s_r2, relu_n3 => s_r3, relu_n4 => s_r4,
            relu_n5 => s_r5, relu_n6 => s_r6, relu_n7 => s_r7, relu_n8 => s_r8,
            output_result => s_out,
            output_running => s_out_running,
            output_mac_index => s_out_idx,
            debug_hidden_running => s_hidden_running,
            debug_hidden_mac_active => s_hidden_mac_active,
            debug_hidden_first_mac => s_hidden_first_mac,
            debug_hidden_neuron => s_hidden_neuron,
            debug_hidden_input_index => s_hidden_input_idx
        );

    --------------------------------------------------------------------
    -- Cycle monitor
    --------------------------------------------------------------------
    MONITOR : process(clk)
    begin
        if rising_edge(clk) then
            if p_rst = '1' or s_rst = '1' then
                p_hidden_running_cycles <= 0;
                p_hidden_first_count <= 0;
                p_prefetch_count <= 0;
                p_output_running_cycles <= 0;
                s_hidden_running_cycles <= 0;
                s_hidden_mac_cycles <= 0;
                s_hidden_first_count <= 0;
                s_output_running_cycles <= 0;
            else
                if p_hidden_running = '1' then p_hidden_running_cycles <= p_hidden_running_cycles + 1; end if;
                if p_hidden_first = '1' then p_hidden_first_count <= p_hidden_first_count + 1; end if;
                if p_hidden_prefetch = '1' then p_prefetch_count <= p_prefetch_count + 1; end if;
                if p_out_running = '1' then p_output_running_cycles <= p_output_running_cycles + 1; end if;

                if s_hidden_running = '1' then s_hidden_running_cycles <= s_hidden_running_cycles + 1; end if;
                if s_hidden_mac_active = '1' then s_hidden_mac_cycles <= s_hidden_mac_cycles + 1; end if;
                if s_hidden_first_mac = '1' then s_hidden_first_count <= s_hidden_first_count + 1; end if;
                if s_out_running = '1' then s_output_running_cycles <= s_output_running_cycles + 1; end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Stimulus / verification
    --------------------------------------------------------------------
    STIMULUS : process
        procedure cfg_write_p(
            signal p_clk : in std_logic;
            signal p_we : out std_logic;
            signal p_sel : out unsigned(2 downto 0);
            signal p_addr : out unsigned(6 downto 0);
            signal p_data : out signed(15 downto 0);
            constant sel_i : integer;
            constant addr_i : integer;
            constant data_i : integer
        ) is
        begin
            p_sel <= to_unsigned(sel_i, 3);
            p_addr <= to_unsigned(addr_i, 7);
            p_data <= to_signed(data_i, 16);
            p_we <= '1';
            wait until rising_edge(p_clk);
            p_we <= '0';
            wait until rising_edge(p_clk);
        end procedure;

        procedure cfg_write_s(
            signal p_clk : in std_logic;
            signal p_we : out std_logic;
            signal p_sel : out unsigned(2 downto 0);
            signal p_addr : out unsigned(6 downto 0);
            signal p_data : out signed(15 downto 0);
            constant sel_i : integer;
            constant addr_i : integer;
            constant data_i : integer
        ) is
        begin
            p_sel <= to_unsigned(sel_i, 3);
            p_addr <= to_unsigned(addr_i, 7);
            p_data <= to_signed(data_i, 16);
            p_we <= '1';
            wait until rising_edge(p_clk);
            p_we <= '0';
            wait until rising_edge(p_clk);
        end procedure;

        variable failures : integer := 0;
        variable p_compute_cycles : integer := 0;
        variable s_compute_cycles : integer := 0;
        variable p_actual_mac_cycles : integer := 0;
        variable s_actual_mac_cycles : integer := 0;
        variable speedup_num : real;
        variable reduction_pct : real;
    begin
        report "============================================================";
        report "REAL MATLAB NETWORK BENCHMARK";
        report "PARALLEL 4-MAC WITH PIPELINED OUTPUT vs SEQUENTIAL 1-MAC";
        report "4 INPUTS -> 8 HIDDEN -> ReLU -> 1 OUTPUT";
        report "============================================================";

        p_rst <= '1';
        s_rst <= '1';
        wait for 30 ns;
        wait until rising_edge(clk);
        p_rst <= '0';
        s_rst <= '0';
        wait until rising_edge(clk);

        ----------------------------------------------------------------
        -- Load inputs into both DUTs.
        ----------------------------------------------------------------
        for i in 0 to 3 loop
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data,
                        0, i, TEST_INPUT(i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data,
                        0, i, TEST_INPUT(i));
        end loop;

        ----------------------------------------------------------------
        -- Load W1 banks: Bank1=N1/N5, Bank2=N2/N6, etc.
        ----------------------------------------------------------------
        for i in 0 to 3 loop
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 1, i, W1(0,i));
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 2, i, W1(1,i));
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 3, i, W1(2,i));
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 4, i, W1(3,i));

            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 1, i, W1(0,i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 2, i, W1(1,i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 3, i, W1(2,i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 4, i, W1(3,i));
        end loop;

        for i in 0 to 3 loop
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 1, 4+i, W1(4,i));
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 2, 4+i, W1(5,i));
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 3, 4+i, W1(6,i));
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 4, 4+i, W1(7,i));

            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 1, 4+i, W1(4,i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 2, 4+i, W1(5,i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 3, 4+i, W1(6,i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 4, 4+i, W1(7,i));
        end loop;

        ----------------------------------------------------------------
        -- Hidden biases
        ----------------------------------------------------------------
        for i in 0 to 7 loop
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 5, i, B1(i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 5, i, B1(i));
        end loop;

        ----------------------------------------------------------------
        -- Output weights and bias
        ----------------------------------------------------------------
        for i in 0 to 7 loop
            cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 6, i, W2(i));
            cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 6, i, W2(i));
        end loop;

        cfg_write_p(clk, p_cfg_we, p_cfg_mem_sel, p_cfg_addr, p_cfg_data, 7, 0, B2);
        cfg_write_s(clk, s_cfg_we, s_cfg_mem_sel, s_cfg_addr, s_cfg_data, 7, 0, B2);

        report "ALL REAL PARAMETERS LOADED INTO BOTH DUTs";

        ----------------------------------------------------------------
        -- Start both architectures together.
        ----------------------------------------------------------------
        wait until rising_edge(clk);
        p_start <= '1';
        s_start <= '1';
        wait until rising_edge(clk);
        p_start <= '0';
        s_start <= '0';

        -- The two DONE signals are one-clock pulses and the parallel
        -- architecture finishes before the sequential architecture.
        -- Therefore they do NOT overlap in time. Waiting for both to be
        -- high simultaneously causes the testbench to wait forever.
        wait until p_done = '1';
        report "PARALLEL DUT DONE";

        wait until s_done = '1';
        report "SEQUENTIAL DUT DONE";

        wait for 1 ns;

        ----------------------------------------------------------------
        -- Verify hidden values and ReLU values.
        ----------------------------------------------------------------
        report "============================================================";
        report "OUTPUT COMPARISON";
        report "P N1..N8 = " & integer'image(to_integer(p_h1)) & "," &
               integer'image(to_integer(p_h2)) & "," & integer'image(to_integer(p_h3)) & "," &
               integer'image(to_integer(p_h4)) & "," & integer'image(to_integer(p_h5)) & "," &
               integer'image(to_integer(p_h6)) & "," & integer'image(to_integer(p_h7)) & "," &
               integer'image(to_integer(p_h8));
        report "S N1..N8 = " & integer'image(to_integer(s_h1)) & "," &
               integer'image(to_integer(s_h2)) & "," & integer'image(to_integer(s_h3)) & "," &
               integer'image(to_integer(s_h4)) & "," & integer'image(to_integer(s_h5)) & "," &
               integer'image(to_integer(s_h6)) & "," & integer'image(to_integer(s_h7)) & "," &
               integer'image(to_integer(s_h8));

        for i in 0 to 7 loop
            -- Hidden equality checks
            case i is
                when 0 =>
                    if to_integer(p_h1) /= EXP_H(0) or to_integer(s_h1) /= EXP_H(0) then failures := failures + 1; end if;
                    if to_integer(p_r1) /= EXP_R(0) or to_integer(s_r1) /= EXP_R(0) then failures := failures + 1; end if;
                when 1 =>
                    if to_integer(p_h2) /= EXP_H(1) or to_integer(s_h2) /= EXP_H(1) then failures := failures + 1; end if;
                    if to_integer(p_r2) /= EXP_R(1) or to_integer(s_r2) /= EXP_R(1) then failures := failures + 1; end if;
                when 2 =>
                    if to_integer(p_h3) /= EXP_H(2) or to_integer(s_h3) /= EXP_H(2) then failures := failures + 1; end if;
                    if to_integer(p_r3) /= EXP_R(2) or to_integer(s_r3) /= EXP_R(2) then failures := failures + 1; end if;
                when 3 =>
                    if to_integer(p_h4) /= EXP_H(3) or to_integer(s_h4) /= EXP_H(3) then failures := failures + 1; end if;
                    if to_integer(p_r4) /= EXP_R(3) or to_integer(s_r4) /= EXP_R(3) then failures := failures + 1; end if;
                when 4 =>
                    if to_integer(p_h5) /= EXP_H(4) or to_integer(s_h5) /= EXP_H(4) then failures := failures + 1; end if;
                    if to_integer(p_r5) /= EXP_R(4) or to_integer(s_r5) /= EXP_R(4) then failures := failures + 1; end if;
                when 5 =>
                    if to_integer(p_h6) /= EXP_H(5) or to_integer(s_h6) /= EXP_H(5) then failures := failures + 1; end if;
                    if to_integer(p_r6) /= EXP_R(5) or to_integer(s_r6) /= EXP_R(5) then failures := failures + 1; end if;
                when 6 =>
                    if to_integer(p_h7) /= EXP_H(6) or to_integer(s_h7) /= EXP_H(6) then failures := failures + 1; end if;
                    if to_integer(p_r7) /= EXP_R(6) or to_integer(s_r7) /= EXP_R(6) then failures := failures + 1; end if;
                when 7 =>
                    if to_integer(p_h8) /= EXP_H(7) or to_integer(s_h8) /= EXP_H(7) then failures := failures + 1; end if;
                    if to_integer(p_r8) /= EXP_R(7) or to_integer(s_r8) /= EXP_R(7) then failures := failures + 1; end if;
            end case;
        end loop;

        ----------------------------------------------------------------
        -- Cycle calculations
        ----------------------------------------------------------------
        -- Parallel has one global PRIME/setup cycle. first_cycle is also
        -- asserted at group transitions, so it is not a MAC-cycle count.
        p_actual_mac_cycles := p_hidden_running_cycles - 1;
        s_actual_mac_cycles := s_hidden_mac_cycles;
        p_compute_cycles := p_hidden_running_cycles + p_output_running_cycles;
        s_compute_cycles := s_hidden_running_cycles + s_output_running_cycles;

        report "============================================================";
        report "PERFORMANCE";
        report "Parallel hidden running cycles      = " & integer'image(p_hidden_running_cycles);
        report "Parallel hidden running cycles include setup/control; use the measured count above.";
        report "Parallel group-transition markers      = " & integer'image(p_hidden_first_count);
        report "Parallel hidden actual MAC cycles  = " & integer'image(p_actual_mac_cycles);
        report "Parallel prefetch events           = " & integer'image(p_prefetch_count);
        report "4-MAC pipelined output running cycles = " & integer'image(p_output_running_cycles);
        report "Parallel processing cycles         = " & integer'image(p_compute_cycles);

        report "Sequential hidden running cycles      = " & integer'image(s_hidden_running_cycles);
        report "Sequential hidden PRIME/setup cycles = " & integer'image(s_hidden_first_count);
        report "Sequential hidden actual MAC cycles  = " & integer'image(s_actual_mac_cycles);
        report "Sequential output MAC cycles         = " & integer'image(s_output_running_cycles);
        report "Sequential processing cycles         = " & integer'image(s_compute_cycles);

        report "Reference workload: 32 hidden MAC operations + 8 output MAC operations per architecture; 4-MAC output is pipelined.";
        report "Reference operation counts: sequential hidden 32 MAC operations; parallel hidden 8 MAC time slots.";
        ----------------------------------------------------------------
        -- FIXED5 functional checks: cycle counts are measured, not fixed
        -- to the older RTL's 9/40/17/48-cycle expectations.
        ----------------------------------------------------------------
        -- The four-MAC hidden layer remains at 9 running cycles. The
        -- registered output pipeline is expected to take 10 running cycles,
        -- yielding 19 total processing cycles for this network.
        if p_hidden_running_cycles /= 9 then
            failures := failures + 1;
            report "FAIL: 4-MAC hidden running cycles expected 9, observed " &
                   integer'image(p_hidden_running_cycles) severity error;
        end if;
        if p_output_running_cycles /= 10 then
            failures := failures + 1;
            report "FAIL: pipelined output running cycles expected 10, observed " &
                   integer'image(p_output_running_cycles) severity error;
        end if;
        if p_compute_cycles /= 19 then
            failures := failures + 1;
            report "FAIL: total 4-MAC pipelined processing window expected 19, observed " &
                   integer'image(p_compute_cycles) severity error;
        end if;
        if to_integer(p_out) /= EXP_OUT then
            failures := failures + 1;
            report "FAIL: parallel output != -38" severity error;
        end if;
        if to_integer(s_out) /= EXP_OUT then
            failures := failures + 1;
            report "FAIL: sequential output != -38" severity error;
        end if;
        if p_hidden_running_cycles <= 0 or s_hidden_running_cycles <= 0 or
           p_output_running_cycles <= 0 or s_output_running_cycles <= 0 or
           p_compute_cycles <= 0 or s_compute_cycles <= 0 then
            failures := failures + 1;
            report "FAIL: zero/invalid measured running or compute counter" severity error;
        else
            speedup_num := real(s_compute_cycles) / real(p_compute_cycles);
            reduction_pct := real(s_compute_cycles - p_compute_cycles) * 100.0 / real(s_compute_cycles);
            report "Measured end-to-end compute speedup = " & real'image(speedup_num) & "x";
            report "Measured compute-window reduction = " & real'image(reduction_pct) & "%";
        end if;

        report "TOTAL CHECK FAILURES = " & integer'image(failures);
        report "Cycle values above are measured observations for FIXED5; the pipelined 4-MAC output is expected to use 10 running cycles and a 19-cycle processing window.";
        report "============================================================";
        if failures = 0 then
            report "PASS: FIXED5 REAL MATLAB NETWORK VALIDATION WITH 4-MAC PIPELINED OUTPUT";
            report "PASS: PIPELINED 4-MAC AND SEQUENTIAL 1-MAC MATCH EXPECTED HIDDEN, RELU, AND FINAL OUTPUT VALUES";
        else
            report "FAIL: FIXED5 FUNCTIONAL VALIDATION; mismatch/check count = " & integer'image(failures) severity error;
        end if;
        report "============================================================";

        wait;
    end process;

end architecture;
