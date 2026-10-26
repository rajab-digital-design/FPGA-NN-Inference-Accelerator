library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library base_ref;

-- Compare the reference and opt-in experimental buffer on every test clock.
-- VHDL-2002.  The same clocked ROM model drives both memories.
-- The reference is compiled into library base_ref; experiment into work.
entity TB_Input_Buffer_OneHot_Equivalence is
    generic (NUM_INPUTS : integer := 4);
end entity;

architecture test of TB_Input_Buffer_OneHot_Equivalence is
    constant ADDR_WIDTH : integer := 6;
    signal clk : std_logic := '0';
    signal clock_active : boolean := true;
    signal rst : std_logic := '1';
    signal load_start : std_logic := '0';
    signal mem_data : signed(15 downto 0) := (others => '0');
    signal ref_addr, trial_addr : unsigned(ADDR_WIDTH-1 downto 0);
    signal ref_done, trial_done : std_logic;
    signal read_index : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal ref_data, trial_data : signed(15 downto 0);
    signal external_read_en : std_logic := '0';
    signal external_read_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal checks : integer := 0;

    function rom_value(i : integer) return signed is
    begin
        return to_signed((i * 357) mod 40000 - 20000, 16);
    end function;
begin
    CLOCK_DRIVER : process
    begin
        while clock_active loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    -- Model the synchronous input memory used in the actual NPU.
    MEMORY_MODEL : process(clk)
    begin
        if rising_edge(clk) then
            if to_integer(ref_addr) < NUM_INPUTS then
                mem_data <= rom_value(to_integer(ref_addr));
            else
                mem_data <= (others => '0');
            end if;
        end if;
    end process;

    REF_BUFFER : entity base_ref.input_register_buffer
        generic map (DATA_WIDTH => 16, NUM_INPUTS => NUM_INPUTS, ADDR_WIDTH => ADDR_WIDTH)
        port map (clk => clk, rst => rst, load_start => load_start,
                  mem_addr => ref_addr, mem_data => mem_data, load_done => ref_done,
                  read_index => read_index, data_out => ref_data,
                  external_read_en => external_read_en,
                  external_read_addr => external_read_addr);

    EXP_BUFFER : entity work.input_register_buffer
        generic map (DATA_WIDTH => 16, NUM_INPUTS => NUM_INPUTS, ADDR_WIDTH => ADDR_WIDTH,
                     OPTIMIZE_FOUR_INPUT_READ => true)
        port map (clk => clk, rst => rst, load_start => load_start,
                  mem_addr => trial_addr, mem_data => mem_data, load_done => trial_done,
                  read_index => read_index, data_out => trial_data,
                  external_read_en => external_read_en,
                  external_read_addr => external_read_addr);

    CYCLE_MONITOR : process
    begin
        while clock_active loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert ref_addr = trial_addr
                report "FAIL: mem_addr differs" severity failure;
            assert ref_done = trial_done
                report "FAIL: load_done differs" severity failure;
            assert ref_data = trial_data
                report "FAIL: data_out differs at clock edge" severity failure;
        end loop;
        wait;
    end process;

    STIMULUS : process
    begin
        assert NUM_INPUTS >= 1 and NUM_INPUTS <= 63
            report "NUM_INPUTS must be between 1 and 63" severity failure;
        wait until rising_edge(clk);
        wait for 2 ns;
        rst <= '0';

        -- Load twice, so loader restart/reload behavior is also compared.
        for repeat_index in 1 to 2 loop
            load_start <= '1';
            wait until rising_edge(clk);
            wait for 2 ns;
            load_start <= '0';

            for tick in 0 to NUM_INPUTS + 6 loop
                wait until rising_edge(clk);
                wait for 2 ns;
                assert ref_addr = trial_addr
                    report "FAIL: memory-load address mismatch" severity failure;
                assert ref_done = trial_done
                    report "FAIL: memory-load completion mismatch" severity failure;
            end loop;

            -- Exhaustively check all 64 six-bit read indices, including
            -- out-of-range values (which must return zero).
            for idx in 0 to 63 loop
                read_index <= to_unsigned(idx, ADDR_WIDTH);
                wait for 2 ns;
                assert ref_data = trial_data
                    report "FAIL: read data mismatch at index " & integer'image(idx)
                    severity failure;
                if idx < NUM_INPUTS then
                    assert trial_data = rom_value(idx)
                        report "FAIL: wrong stored value at valid index " & integer'image(idx)
                        severity failure;
                else
                    assert trial_data = to_signed(0, 16)
                        report "FAIL: out-of-range index did not return zero"
                        severity failure;
                end if;
                checks <= checks + 1;
            end loop;
        end loop;

        -- The reference intentionally reads buffer(0) for metastate address
        -- during simulation before the scheduler becomes initialized.
        read_index <= (others => 'X');
        wait for 2 ns;
        assert ref_data = trial_data
            report "FAIL: unknown-address fallback mismatch" severity failure;
        assert trial_data = rom_value(0)
            report "FAIL: unknown-address fallback is not buffer(0)" severity failure;

        external_read_en <= '1';
        external_read_addr <= to_unsigned(NUM_INPUTS - 1, ADDR_WIDTH);
        wait for 2 ns;
        assert ref_addr = trial_addr and ref_addr = external_read_addr
            report "FAIL: external memory readback mux mismatch" severity failure;

        clock_active <= false;
        wait for 15 ns;
        assert false
            report "PASS: BUFFER ONEHOT EQUIVALENCE, NUM_INPUTS=" & integer'image(NUM_INPUTS) &
                   ", exhaustive indices checked twice=128"
            severity note;
        wait;
    end process;
end architecture;
