library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_array_2mac is
    port (
        clk     : in std_logic;
        rst     : in std_logic;
        start1  : in std_logic;
        start2  : in std_logic;
        enable1 : in std_logic;
        enable2 : in std_logic;
        x_in    : in signed(15 downto 0);
        weight1 : in signed(15 downto 0);
        weight2 : in signed(15 downto 0);
        bias1   : in signed(15 downto 0);
        bias2   : in signed(15 downto 0);
        acc1    : out signed(19 downto 0);
        acc2    : out signed(19 downto 0)
    );
end entity;

architecture rtl of mac_array_2mac is
    signal acc1_r : signed(19 downto 0) := (others => '0');
    signal acc2_r : signed(19 downto 0) := (others => '0');
begin
    process(clk)
        variable prod1_v, prod2_v : signed(31 downto 0);
        variable scaled1_v, scaled2_v : signed(19 downto 0);
        variable bias1_v, bias2_v : signed(19 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                acc1_r <= (others => '0');
                acc2_r <= (others => '0');
            else
                prod1_v := x_in * weight1;
                prod2_v := x_in * weight2;
                scaled1_v := resize(shift_right(prod1_v, 8), 20);
                scaled2_v := resize(shift_right(prod2_v, 8), 20);
                bias1_v := resize(bias1, 20);
                bias2_v := resize(bias2, 20);

                if start1 = '1' then
                    acc1_r <= bias1_v + scaled1_v;
                elsif enable1 = '1' then
                    acc1_r <= acc1_r + scaled1_v;
                end if;
                if start2 = '1' then
                    acc2_r <= bias2_v + scaled2_v;
                elsif enable2 = '1' then
                    acc2_r <= acc2_r + scaled2_v;
                end if;
            end if;
        end if;
    end process;
    acc1 <= acc1_r;
    acc2 <= acc2_r;
end architecture;
