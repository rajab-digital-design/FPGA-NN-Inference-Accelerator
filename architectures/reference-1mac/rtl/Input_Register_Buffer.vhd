library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_register_buffer is
    generic (
        DATA_WIDTH : integer := 16;
        NUM_INPUTS : integer := 21;
        ADDR_WIDTH : integer := 6
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        load_start : in std_logic;
        mem_addr : out unsigned(ADDR_WIDTH-1 downto 0);
        mem_data : in signed(DATA_WIDTH-1 downto 0);
        load_done : out std_logic;

        read_index : in unsigned(ADDR_WIDTH-1 downto 0);
        data_out : out signed(DATA_WIDTH-1 downto 0);

        external_read_en : in std_logic;
        external_read_addr : in unsigned(ADDR_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of input_register_buffer is
    type buffer_t is array (0 to NUM_INPUTS-1)
        of signed(DATA_WIDTH-1 downto 0);

    signal buffer_reg : buffer_t := (others => (others => '0'));
    signal load_active : std_logic := '0';
    signal load_primed : std_logic := '0';
    signal load_addr_reg : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal load_count : integer range 0 to NUM_INPUTS-1 := 0;
    function clog2_ceil(n : integer) return integer is
        variable value : integer := n - 1;
        variable bits  : integer := 0;
    begin
        while value > 0 loop
            bits := bits + 1;
            value := value / 2;
        end loop;
        if bits = 0 then
            return 1;
        else
            return bits;
        end if;
    end function;

    constant INDEX_WIDTH : integer := clog2_ceil(NUM_INPUTS);

    -- Simulation-only guard for the delta-cycle before scheduler outputs settle.
    -- Unknown read_index values historically made numeric_std.to_integer return 0;
    -- use buffer_reg(0) directly in that case, preserving that value without warning.
    -- XST must ignore this diagnostic-only logic, so it does not alter hardware.
    -- synthesis translate_off
    function has_metavalue(addr : unsigned) return boolean is
    begin
        for i in addr'range loop
            case addr(i) is
                when 'U' | 'X' | 'Z' | 'W' | '-' => return true;
                when others => null; -- Includes '0', '1', 'L', and 'H'.
            end case;
        end loop;
        return false;
    end function;
    -- synthesis translate_on
begin

    ----------------------------------------------------------------
    -- Combinational read from the internal input register buffer.
    -- Power-of-two depths use an address slice with exactly the legal
    -- index width, which supports distributed-RAM inference in XST.
    -- Other depths keep an explicit full-width bounds check.
    ----------------------------------------------------------------
    GEN_BUFFER_POWER_OF_TWO : if (2 ** INDEX_WIDTH) = NUM_INPUTS generate
        process(buffer_reg, read_index)
        begin
            -- synthesis translate_off
            if has_metavalue(read_index) then
                data_out <= buffer_reg(0);
            else
            -- synthesis translate_on
                if to_integer(read_index) < NUM_INPUTS then
                    data_out <= buffer_reg(to_integer(read_index(INDEX_WIDTH-1 downto 0)));
                else
                    data_out <= (others => '0');
                end if;
            -- synthesis translate_off
            end if;
            -- synthesis translate_on
        end process;
    end generate;

    GEN_BUFFER_NON_POWER_OF_TWO : if (2 ** INDEX_WIDTH) /= NUM_INPUTS generate
        process(buffer_reg, read_index)
            variable idx : integer;
        begin
            -- synthesis translate_off
            if has_metavalue(read_index) then
                data_out <= buffer_reg(0);
            else
            -- synthesis translate_on
                idx := to_integer(read_index);
                if idx < NUM_INPUTS then
                    data_out <= buffer_reg(idx);
                else
                    data_out <= (others => '0');
                end if;
            -- synthesis translate_off
            end if;
            -- synthesis translate_on
        end process;
    end generate;

    ----------------------------------------------------------------
    -- Synchronous input-memory loader.
    --
    -- IMPORTANT:
    -- The external Input Memory has synchronous read behavior:
    -- the data for address A becomes visible AFTER the rising edge
    -- at which A is presented. Therefore the buffer must PRIME the
    -- memory address before it starts capturing data.
    --
    -- Correct sequence for a 4-element vector:
    --
    --   edge 0 : present address 0
    --   edge 1 : present address 1, no capture
    --            memory output becomes input[0]
    --   edge 2 : capture input[0], present address 2
    --            memory output becomes input[1]
    --   edge 3 : capture input[1], present address 3
    --            memory output becomes input[2]
    --   edge 4 : capture input[2], present address 4
    --            memory output becomes input[3]
    --   edge 5 : capture input[3], done
    --
    -- The previous implementation captured mem_data one cycle too
    -- early. Because the RAM itself updates data_out at the same
    -- rising edge, that caused input[0] to be observed twice:
    --
    --   [x0, x0, x1, x2]
    --
    -- This was exactly the pattern required to produce the measured
    -- N1..N8 mismatch in the real MATLAB network test.
    ----------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                load_active   <= '0';
                load_primed   <= '0';
                load_done     <= '0';
                load_addr_reg <= (others => '0');
                load_count    <= 0;

            else
                load_done <= '0';

                --------------------------------------------------------
                -- Start loading. Address 0 is presented during this
                -- cycle; its data will become visible after the edge.
                --------------------------------------------------------
                if load_start = '1' and load_active = '0' then
                    load_active   <= '1';
                    load_primed   <= '0';
                    load_addr_reg <= (others => '0');
                    load_count    <= 0;

                elsif load_active = '1' then

                    ----------------------------------------------------
                    -- Prime cycle: advance to address 1 without
                    -- consuming mem_data yet.
                    ----------------------------------------------------
                    if load_primed = '0' then
                        load_primed <= '1';

                        if NUM_INPUTS > 1 then
                            load_addr_reg <= to_unsigned(1, ADDR_WIDTH);
                        end if;

                    ----------------------------------------------------
                    -- Capture one memory output per cycle. At this
                    -- point mem_data belongs to the address presented
                    -- during the previous cycle.
                    ----------------------------------------------------
                    else
                        -- load_count is constrained to 0..NUM_INPUTS-1,
                        -- so this write can never address outside buffer_reg.
                        buffer_reg(load_count) <= mem_data;

                        if load_count = NUM_INPUTS-1 then
                            load_active <= '0';
                            load_done   <= '1';
                            -- Keep load_count at its last valid index.
                        else
                            load_count    <= load_count + 1;
                            load_addr_reg <= load_addr_reg + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Normal mode: loading address.
    -- Idle readback mode: externally requested address.
    ----------------------------------------------------------------
    mem_addr <= external_read_addr when external_read_en = '1'
                else load_addr_reg;

end architecture;
