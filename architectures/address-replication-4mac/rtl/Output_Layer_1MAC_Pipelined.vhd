library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Experimental pipelined output layer, reused for the 2-MAC and 4-MAC studies.
-- Three registered stages:
--   1) select/ReLU and register hidden value + weight
--   2) multiply and register the full product
--   3) shift/scale and accumulate into the output accumulator
-- The hidden layer and configuration interface remain unchanged.
entity output_layer_1mac_pipelined is
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

        result    : out signed(31 downto 0);
        running   : out std_logic;
        done      : out std_logic;
        mac_index : out unsigned(3 downto 0)
    );
end entity;

architecture rtl of output_layer_1mac_pipelined is
    type hidden_array_t is array (0 to 7) of signed(19 downto 0);
    type weight_array_t is array (0 to 7) of signed(15 downto 0);

    signal hidden_v : hidden_array_t;
    signal weight_v : weight_array_t;

    type state_t is (IDLE, RUN);
    signal state : state_t := IDLE;

    -- Issue index remains in 0..7. issued_all prevents an invalid index 8.
    signal issue_idx_r  : integer range 0 to 7 := 0;
    signal issued_all_r : std_logic := '0';

    -- Stage 1: selected operands and their neuron tag.
    signal operand_hidden_r : signed(19 downto 0) := (others => '0');
    signal operand_weight_r : signed(15 downto 0) := (others => '0');
    signal operand_index_r  : integer range 0 to 7 := 0;
    signal operand_valid_r : std_logic := '0';

    -- Stage 2: registered full-precision product and tag.
    signal product_r       : signed(35 downto 0) := (others => '0');
    signal product_index_r : integer range 0 to 7 := 0;
    signal product_valid_r : std_logic := '0';

    signal acc_r     : signed(31 downto 0) := (others => '0');
    signal result_r  : signed(31 downto 0) := (others => '0');
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

    --------------------------------------------------------------------
    -- Datapath pipeline. Products are committed in the original neuron
    -- order, so the Q8.8 shift and signed accumulation order are retained.
    --------------------------------------------------------------------
    DATAPATH : process(clk)
        variable hidden_relu_v : signed(19 downto 0);
        variable scaled_v      : signed(31 downto 0);
        variable next_acc_v    : signed(31 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                product_r       <= (others => '0');
                product_index_r <= 0;
                product_valid_r <= '0';
                acc_r            <= (others => '0');
                result_r         <= (others => '0');
            else
                -- Stage 2: multiply previously registered operands.
                product_valid_r <= operand_valid_r;
                if operand_valid_r = '1' then
                    product_r       <= operand_hidden_r * operand_weight_r;
                    product_index_r <= operand_index_r;
                end if;

                -- A new transaction starts only from IDLE, after the prior
                -- operation has drained. Initialize the accumulator to bias.
                if state = IDLE and start = '1' then
                    acc_r <= resize(bias, 32);
                    product_valid_r <= '0';
                elsif product_valid_r = '1' then
                    -- Stage 3: Q8.8 scaling and signed accumulation.
                    scaled_v := resize(shift_right(product_r, 8), 32);
                    next_acc_v := acc_r + scaled_v;
                    acc_r <= next_acc_v;
                    if product_index_r = 7 then
                        result_r <= next_acc_v;
                    end if;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- Controller and Stage 1 operand selection.
    --------------------------------------------------------------------
    CONTROL : process(clk)
        variable selected_hidden_v : signed(19 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state            <= IDLE;
                issue_idx_r      <= 0;
                issued_all_r     <= '0';
                operand_hidden_r <= (others => '0');
                operand_weight_r <= (others => '0');
                operand_index_r  <= 0;
                operand_valid_r  <= '0';
                running_r        <= '0';
                done              <= '0';
            else
                done <= '0';
                operand_valid_r <= '0';

                case state is
                    when IDLE =>
                        running_r <= '0';
                        if start = '1' then
                            issue_idx_r  <= 0;
                            issued_all_r <= '0';
                            running_r    <= '1';
                            state        <= RUN;
                        end if;

                    when RUN =>
                        running_r <= '1';

                        -- Stage 1: issue one hidden neuron per cycle.
                        if issued_all_r = '0' then
                            if hidden_v(issue_idx_r)(19) = '1' then
                                selected_hidden_v := (others => '0');
                            else
                                selected_hidden_v := hidden_v(issue_idx_r);
                            end if;

                            operand_hidden_r <= selected_hidden_v;
                            operand_weight_r <= weight_v(issue_idx_r);
                            operand_index_r  <= issue_idx_r;
                            operand_valid_r  <= '1';

                            if issue_idx_r = 7 then
                                issued_all_r <= '1';
                            else
                                issue_idx_r <= issue_idx_r + 1;
                            end if;
                        end if;

                        -- Finish only when the final tagged product has been
                        -- accumulated (pipeline drained, neuron 7 committed).
                        if product_valid_r = '1' and product_index_r = 7 then
                            running_r    <= '0';
                            done          <= '1';
                            state         <= IDLE;
                            issued_all_r  <= '0';
                        end if;
                end case;
            end if;
        end if;
    end process;

    result <= result_r;
    running <= running_r;
    -- This index reports the product currently reaching the accumulator.
    mac_index <= to_unsigned(product_index_r, 4);
end architecture;
