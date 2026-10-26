library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity weight_memory_dualport_generic is
    generic (
        DATA_WIDTH  : integer := 16;
        NUM_INPUTS  : integer := 21;
        NUM_NEURONS : integer := 10;
        ADDR_WIDTH  : integer := 8
    );
    port (
        clk : in std_logic;

        wr_en   : in std_logic;
        wr_bank : in unsigned(2 downto 0);
        wr_addr : in unsigned(ADDR_WIDTH-1 downto 0);
        wr_data : in signed(DATA_WIDTH-1 downto 0);

        rd_a_en : in std_logic;
        rd_a_addr : in unsigned(ADDR_WIDTH-1 downto 0);
        rd_a_weight1 : out signed(DATA_WIDTH-1 downto 0);
        rd_a_weight2 : out signed(DATA_WIDTH-1 downto 0);
        rd_a_weight3 : out signed(DATA_WIDTH-1 downto 0);
        rd_a_weight4 : out signed(DATA_WIDTH-1 downto 0);

        rd_b_en : in std_logic;
        rd_b_addr : in unsigned(ADDR_WIDTH-1 downto 0);
        rd_b_weight1 : out signed(DATA_WIDTH-1 downto 0);
        rd_b_weight2 : out signed(DATA_WIDTH-1 downto 0);
        rd_b_weight3 : out signed(DATA_WIDTH-1 downto 0);
        rd_b_weight4 : out signed(DATA_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of weight_memory_dualport_generic is
    constant NUM_GROUPS : integer := (NUM_NEURONS + 3) / 4;
    constant DEPTH      : integer := NUM_INPUTS * NUM_GROUPS;

    type bank_t is array (0 to DEPTH-1) of signed(DATA_WIDTH-1 downto 0);
    signal bank1 : bank_t := (others => (others => '0'));
    signal bank2 : bank_t := (others => (others => '0'));
    signal bank3 : bank_t := (others => (others => '0'));
    signal bank4 : bank_t := (others => (others => '0'));

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
    -- The 4-input/8-neuron synthesis configuration has DEPTH=8. Using a
    -- 3-bit index makes every possible array index legal and lets XST retain
    -- distributed-RAM inference. Full-width comparisons still reject any
    -- nonzero high bits on the external address bus.
    GEN_POWER_OF_TWO : if (2 ** INDEX_WIDTH) = DEPTH generate
        process(clk)
        begin
            if rising_edge(clk) then
                if wr_en = '1' and to_integer(wr_addr) < DEPTH then
                    case wr_bank is
                        when "001" => bank1(to_integer(wr_addr(INDEX_WIDTH-1 downto 0))) <= wr_data;
                        when "010" => bank2(to_integer(wr_addr(INDEX_WIDTH-1 downto 0))) <= wr_data;
                        when "011" => bank3(to_integer(wr_addr(INDEX_WIDTH-1 downto 0))) <= wr_data;
                        when "100" => bank4(to_integer(wr_addr(INDEX_WIDTH-1 downto 0))) <= wr_data;
                        when others => null;
                    end case;
                end if;

                if rd_a_en = '1' then
                    if to_integer(rd_a_addr) < DEPTH then
                        rd_a_weight1 <= bank1(to_integer(rd_a_addr(INDEX_WIDTH-1 downto 0)));
                        rd_a_weight2 <= bank2(to_integer(rd_a_addr(INDEX_WIDTH-1 downto 0)));
                        rd_a_weight3 <= bank3(to_integer(rd_a_addr(INDEX_WIDTH-1 downto 0)));
                        rd_a_weight4 <= bank4(to_integer(rd_a_addr(INDEX_WIDTH-1 downto 0)));
                    else
                        rd_a_weight1 <= (others => '0');
                        rd_a_weight2 <= (others => '0');
                        rd_a_weight3 <= (others => '0');
                        rd_a_weight4 <= (others => '0');
                    end if;
                end if;

                if rd_b_en = '1' then
                    if to_integer(rd_b_addr) < DEPTH then
                        rd_b_weight1 <= bank1(to_integer(rd_b_addr(INDEX_WIDTH-1 downto 0)));
                        rd_b_weight2 <= bank2(to_integer(rd_b_addr(INDEX_WIDTH-1 downto 0)));
                        rd_b_weight3 <= bank3(to_integer(rd_b_addr(INDEX_WIDTH-1 downto 0)));
                        rd_b_weight4 <= bank4(to_integer(rd_b_addr(INDEX_WIDTH-1 downto 0)));
                    else
                        rd_b_weight1 <= (others => '0');
                        rd_b_weight2 <= (others => '0');
                        rd_b_weight3 <= (others => '0');
                        rd_b_weight4 <= (others => '0');
                    end if;
                end if;
            end if;
        end process;
    end generate;

    GEN_NON_POWER_OF_TWO : if (2 ** INDEX_WIDTH) /= DEPTH generate
        process(clk)
            variable wa : integer;
            variable ra : integer;
            variable rb : integer;
        begin
            if rising_edge(clk) then
                if wr_en = '1' then
                    wa := to_integer(wr_addr);
                    if wa < DEPTH then
                        case wr_bank is
                            when "001" => bank1(wa) <= wr_data;
                            when "010" => bank2(wa) <= wr_data;
                            when "011" => bank3(wa) <= wr_data;
                            when "100" => bank4(wa) <= wr_data;
                            when others => null;
                        end case;
                    end if;
                end if;

                if rd_a_en = '1' then
                    ra := to_integer(rd_a_addr);
                    if ra < DEPTH then
                        rd_a_weight1 <= bank1(ra);
                        rd_a_weight2 <= bank2(ra);
                        rd_a_weight3 <= bank3(ra);
                        rd_a_weight4 <= bank4(ra);
                    else
                        rd_a_weight1 <= (others => '0');
                        rd_a_weight2 <= (others => '0');
                        rd_a_weight3 <= (others => '0');
                        rd_a_weight4 <= (others => '0');
                    end if;
                end if;

                if rd_b_en = '1' then
                    rb := to_integer(rd_b_addr);
                    if rb < DEPTH then
                        rd_b_weight1 <= bank1(rb);
                        rd_b_weight2 <= bank2(rb);
                        rd_b_weight3 <= bank3(rb);
                        rd_b_weight4 <= bank4(rb);
                    else
                        rd_b_weight1 <= (others => '0');
                        rd_b_weight2 <= (others => '0');
                        rd_b_weight3 <= (others => '0');
                        rd_b_weight4 <= (others => '0');
                    end if;
                end if;
            end if;
        end process;
    end generate;
end architecture;
