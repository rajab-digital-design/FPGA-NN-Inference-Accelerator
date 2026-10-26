library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_memory_generic is
    generic (
        DATA_WIDTH : integer := 16;
        ADDR_WIDTH : integer := 6;
        DEPTH      : integer := 21
    );
    port (
        clk      : in  std_logic;
        rd_en    : in  std_logic;
        rd_addr  : in  unsigned(ADDR_WIDTH-1 downto 0);
        data_out : out signed(DATA_WIDTH-1 downto 0);
        wr_en    : in  std_logic;
        wr_addr  : in  unsigned(ADDR_WIDTH-1 downto 0);
        wr_data  : in  signed(DATA_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of input_memory_generic is
    type mem_t is array (0 to DEPTH-1) of signed(DATA_WIDTH-1 downto 0);
    signal mem : mem_t := (others => (others => '0'));

    -- A power-of-two depth can use an address slice whose range is exactly
    -- the memory's legal index range. This helps XST infer distributed RAM
    -- instead of turning the memory into individual flip-flops.
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

    constant INDEX_WIDTH : integer := clog2_ceil(DEPTH);
begin
    GEN_POWER_OF_TWO : if (2 ** INDEX_WIDTH) = DEPTH generate
        process(clk)
        begin
            if rising_edge(clk) then
                if wr_en = '1' and to_integer(wr_addr) < DEPTH then
                    mem(to_integer(wr_addr(INDEX_WIDTH-1 downto 0))) <= wr_data;
                end if;

                if rd_en = '1' then
                    if to_integer(rd_addr) < DEPTH then
                        data_out <= mem(to_integer(rd_addr(INDEX_WIDTH-1 downto 0)));
                    else
                        data_out <= (others => '0');
                    end if;
                end if;
            end if;
        end process;
    end generate;

    GEN_NON_POWER_OF_TWO : if (2 ** INDEX_WIDTH) /= DEPTH generate
        process(clk)
            variable raddr : integer;
            variable waddr : integer;
        begin
            if rising_edge(clk) then
                if wr_en = '1' then
                    waddr := to_integer(wr_addr);
                    if waddr < DEPTH then
                        mem(waddr) <= wr_data;
                    end if;
                end if;

                if rd_en = '1' then
                    raddr := to_integer(rd_addr);
                    if raddr < DEPTH then
                        data_out <= mem(raddr);
                    else
                        data_out <= (others => '0');
                    end if;
                end if;
            end if;
        end process;
    end generate;
end architecture;
