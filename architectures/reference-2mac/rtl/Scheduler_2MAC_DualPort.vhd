library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Two-lane scheduler for the same four-bank weight layout used by FIXED5.
-- Two adjacent neurons are processed per group.  Bank selection alternates:
-- groups 0,2,4,... use banks 1/2; groups 1,3,5,... use banks 3/4.
entity scheduler_2mac_dualport is
    generic (
        NUM_INPUTS  : integer := 4;
        NUM_NEURONS : integer := 8
    );
    port (
        clk : in std_logic;
        rst : in std_logic;
        start : in std_logic;
        input_addr : out unsigned(5 downto 0);
        weight_addr : out unsigned(7 downto 0);
        prefetch_addr : out unsigned(7 downto 0);
        prefetch_en : out std_logic;
        start1 : out std_logic;
        start2 : out std_logic;
        enable1 : out std_logic;
        enable2 : out std_logic;
        current_group : out integer range 0 to 255;
        first_cycle : out std_logic;
        use_prefetch : out std_logic;
        running : out std_logic;
        done : out std_logic
    );
end entity;

architecture rtl of scheduler_2mac_dualport is
    constant NUM_GROUPS : integer := (NUM_NEURONS + 1) / 2;
    type state_t is (IDLE, PRIME, RUN);
    signal state : state_t := IDLE;
    signal input_addr_r : unsigned(5 downto 0) := (others => '0');
    signal weight_addr_r : unsigned(7 downto 0) := (others => '0');
    signal prefetch_addr_r : unsigned(7 downto 0) := (others => '0');
    signal group_idx : integer range 0 to 255 := 0;
    signal first_cycle_r : std_logic := '0';
    signal use_prefetch_r : std_logic := '0';
    signal running_r : std_logic := '0';
begin
    process(clk)
        variable next_group : integer;
        variable next_base : integer;
        variable lookahead_base : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                input_addr_r <= (others => '0');
                weight_addr_r <= (others => '0');
                prefetch_addr_r <= (others => '0');
                group_idx <= 0;
                first_cycle_r <= '0';
                use_prefetch_r <= '0';
                running_r <= '0';
                start1 <= '0'; start2 <= '0';
                enable1 <= '0'; enable2 <= '0';
                done <= '0';
            else
                start1 <= '0'; start2 <= '0';
                done <= '0';
                first_cycle_r <= '0';
                use_prefetch_r <= '0';

                case state is
                    when IDLE =>
                        running_r <= '0';
                        enable1 <= '0'; enable2 <= '0';
                        if start = '1' then
                            running_r <= '1';
                            group_idx <= 0;
                            input_addr_r <= (others => '0');
                            weight_addr_r <= (others => '0');
                            if NUM_GROUPS > 1 then
                                -- Base row of the next two-neuron group.
                                prefetch_addr_r <= to_unsigned(0, 8);
                            else
                                prefetch_addr_r <= (others => '0');
                            end if;
                            state <= PRIME;
                        end if;

                    when PRIME =>
                        running_r <= '1';
                        enable1 <= '1';
                        if NUM_NEURONS >= 2 then enable2 <= '1'; else enable2 <= '0'; end if;
                        start1 <= '1';
                        if NUM_NEURONS >= 2 then start2 <= '1'; end if;
                        first_cycle_r <= '1';
                        use_prefetch_r <= '0';
                        if NUM_INPUTS > 1 then
                            weight_addr_r <= to_unsigned(1, 8);
                        else
                            weight_addr_r <= (others => '0');
                        end if;
                        state <= RUN;

                    when RUN =>
                        if group_idx * 2 + 1 <= NUM_NEURONS then enable1 <= '1'; else enable1 <= '0'; end if;
                        if group_idx * 2 + 2 <= NUM_NEURONS then enable2 <= '1'; else enable2 <= '0'; end if;

                        if input_addr_r = to_unsigned(NUM_INPUTS-1, 6) then
                            if group_idx = NUM_GROUPS-1 then
                                running_r <= '0';
                                enable1 <= '0'; enable2 <= '0';
                                done <= '1';
                                state <= IDLE;
                            else
                                next_group := group_idx + 1;
                                -- Weight rows are stored by original groups of four neurons.
                                next_base := (next_group / 2) * NUM_INPUTS;
                                lookahead_base := ((next_group + 1) / 2) * NUM_INPUTS;
                                group_idx <= next_group;
                                input_addr_r <= (others => '0');
                                weight_addr_r <= to_unsigned(next_base + 1, 8);
                                if next_group * 2 + 1 <= NUM_NEURONS then enable1 <= '1'; else enable1 <= '0'; end if;
                                if next_group * 2 + 2 <= NUM_NEURONS then enable2 <= '1'; else enable2 <= '0'; end if;
                                if next_group < NUM_GROUPS-1 then
                                    prefetch_addr_r <= to_unsigned(lookahead_base, 8);
                                else
                                    prefetch_addr_r <= (others => '0');
                                end if;
                                if next_group * 2 + 1 <= NUM_NEURONS then start1 <= '1'; end if;
                                if next_group * 2 + 2 <= NUM_NEURONS then start2 <= '1'; end if;
                                first_cycle_r <= '1';
                                use_prefetch_r <= '1';
                            end if;
                        else
                            input_addr_r <= input_addr_r + 1;
                            weight_addr_r <= weight_addr_r + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    input_addr <= input_addr_r;
    weight_addr <= weight_addr_r;
    prefetch_addr <= prefetch_addr_r;
    current_group <= group_idx;
    first_cycle <= first_cycle_r;
    use_prefetch <= use_prefetch_r;
    running <= running_r;
    prefetch_en <= '1' when (state = RUN and group_idx < NUM_GROUPS-1 and
                             input_addr_r = to_unsigned(NUM_INPUTS-1, 6)) else '0';
end architecture;
