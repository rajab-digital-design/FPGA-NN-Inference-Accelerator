library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity output_layer_1mac_sequential is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        start : in  std_logic;

        hidden1 : in signed(19 downto 0);
        hidden2 : in signed(19 downto 0);
        hidden3 : in signed(19 downto 0);
        hidden4 : in signed(19 downto 0);
        hidden5 : in signed(19 downto 0);
        hidden6 : in signed(19 downto 0);
        hidden7 : in signed(19 downto 0);
        hidden8 : in signed(19 downto 0);

        weight1 : in signed(15 downto 0);
        weight2 : in signed(15 downto 0);
        weight3 : in signed(15 downto 0);
        weight4 : in signed(15 downto 0);
        weight5 : in signed(15 downto 0);
        weight6 : in signed(15 downto 0);
        weight7 : in signed(15 downto 0);
        weight8 : in signed(15 downto 0);

        bias : in signed(15 downto 0);

        result  : out signed(31 downto 0);
        running : out std_logic;
        done    : out std_logic;
        mac_index : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of output_layer_1mac_sequential is
    type hidden_array_t is array (0 to 7) of signed(19 downto 0);
    type weight_array_t is array (0 to 7) of signed(15 downto 0);

    signal hidden_v : hidden_array_t;
    signal weight_v : weight_array_t;

    type state_t is (IDLE, RUN);
    signal state : state_t := IDLE;
    signal idx_r : integer range 0 to 7 := 0;
    signal acc_r : signed(31 downto 0) := (others => '0');
    signal result_r : signed(31 downto 0) := (others => '0');
    signal running_r : std_logic := '0';

begin
    hidden_v(0) <= hidden1;
    hidden_v(1) <= hidden2;
    hidden_v(2) <= hidden3;
    hidden_v(3) <= hidden4;
    hidden_v(4) <= hidden5;
    hidden_v(5) <= hidden6;
    hidden_v(6) <= hidden7;
    hidden_v(7) <= hidden8;

    weight_v(0) <= weight1;
    weight_v(1) <= weight2;
    weight_v(2) <= weight3;
    weight_v(3) <= weight4;
    weight_v(4) <= weight5;
    weight_v(5) <= weight6;
    weight_v(6) <= weight7;
    weight_v(7) <= weight8;

    process(clk)
        variable hidden_relu_v : signed(19 downto 0);
        variable prod_v        : signed(35 downto 0);
        variable scaled_v      : signed(31 downto 0);
        variable next_acc_v    : signed(31 downto 0);
        variable bias_v        : signed(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                idx_r <= 0;
                acc_r <= (others => '0');
                result_r <= (others => '0');
                running_r <= '0';
                done <= '0';
            else
                done <= '0';

                if state = IDLE then
                    running_r <= '0';

                    if start = '1' then
                        idx_r <= 0;
                        bias_v := resize(bias, 32);
                        acc_r <= bias_v;
                        running_r <= '1';
                        state <= RUN;
                    end if;

                else
                    running_r <= '1';

                    if hidden_v(idx_r)(19) = '1' then
                        hidden_relu_v := (others => '0');
                    else
                        hidden_relu_v := hidden_v(idx_r);
                    end if;

                    prod_v := hidden_relu_v * weight_v(idx_r);
                    scaled_v := resize(shift_right(prod_v, 8), 32);
                    next_acc_v := acc_r + scaled_v;

                    if idx_r = 7 then
                        acc_r <= next_acc_v;
                        result_r <= next_acc_v;
                        running_r <= '0';
                        done <= '1';
                        state <= IDLE;
                    else
                        acc_r <= next_acc_v;
                        idx_r <= idx_r + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    result <= result_r;
    running <= running_r;
    mac_index <= to_unsigned(idx_r, 4);
end architecture;
