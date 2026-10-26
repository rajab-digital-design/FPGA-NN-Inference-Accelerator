library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity scheduler_4mac_dualport is
    generic (
        NUM_INPUTS  : integer := 21;
        NUM_NEURONS : integer := 10
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
        start3 : out std_logic;
        start4 : out std_logic;

        enable1 : out std_logic;
        enable2 : out std_logic;
        enable3 : out std_logic;
        enable4 : out std_logic;

        current_group : out integer range 0 to 255;
        first_cycle : out std_logic;
        use_prefetch : out std_logic;

        running : out std_logic;
        done : out std_logic
    );
end entity;

architecture rtl of scheduler_4mac_dualport is
    constant NUM_GROUPS : integer := (NUM_NEURONS + 3) / 4;

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
        variable next_base  : integer;
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
                start1 <= '0'; start2 <= '0'; start3 <= '0'; start4 <= '0';
                enable1 <= '0'; enable2 <= '0'; enable3 <= '0'; enable4 <= '0';
                done <= '0';
            else
                start1 <= '0'; start2 <= '0'; start3 <= '0'; start4 <= '0';
                done <= '0';
                first_cycle_r <= '0';
                use_prefetch_r <= '0';

                if state = IDLE then
                    running_r <= '0';
                    enable1 <= '0'; enable2 <= '0'; enable3 <= '0'; enable4 <= '0';

                    if start = '1' then
                        running_r <= '1';
                        group_idx <= 0;
                        input_addr_r <= (others => '0');
                        weight_addr_r <= (others => '0');

                        if NUM_GROUPS > 1 then
                            prefetch_addr_r <= to_unsigned(NUM_INPUTS, 8);
                        else
                            prefetch_addr_r <= (others => '0');
                        end if;

                        state <= PRIME;
                    end if;

                elsif state = PRIME then
                    running_r <= '1';

                    if NUM_NEURONS >= 1 then enable1 <= '1'; else enable1 <= '0'; end if;
                    if NUM_NEURONS >= 2 then enable2 <= '1'; else enable2 <= '0'; end if;
                    if NUM_NEURONS >= 3 then enable3 <= '1'; else enable3 <= '0'; end if;
                    if NUM_NEURONS >= 4 then enable4 <= '1'; else enable4 <= '0'; end if;

                    if NUM_NEURONS >= 1 then start1 <= '1'; end if;
                    if NUM_NEURONS >= 2 then start2 <= '1'; end if;
                    if NUM_NEURONS >= 3 then start3 <= '1'; end if;
                    if NUM_NEURONS >= 4 then start4 <= '1'; end if;

                    first_cycle_r <= '1';
                    use_prefetch_r <= '0';

                    if NUM_INPUTS > 1 then
                        weight_addr_r <= to_unsigned(1, 8);
                    else
                        weight_addr_r <= (others => '0');
                    end if;

                    state <= RUN;

                else
                    if group_idx*4 + 1 <= NUM_NEURONS then enable1 <= '1'; else enable1 <= '0'; end if;
                    if group_idx*4 + 2 <= NUM_NEURONS then enable2 <= '1'; else enable2 <= '0'; end if;
                    if group_idx*4 + 3 <= NUM_NEURONS then enable3 <= '1'; else enable3 <= '0'; end if;
                    if group_idx*4 + 4 <= NUM_NEURONS then enable4 <= '1'; else enable4 <= '0'; end if;

                    if input_addr_r = to_unsigned(NUM_INPUTS-1, 6) then
                        if group_idx = NUM_GROUPS-1 then
                            running_r <= '0';
                            enable1 <= '0'; enable2 <= '0'; enable3 <= '0'; enable4 <= '0';
                            done <= '1';
                            state <= IDLE;
                        else
                            next_group := group_idx + 1;
                            next_base := next_group * NUM_INPUTS;

                            group_idx <= next_group;
                            input_addr_r <= (others => '0');
                            weight_addr_r <= to_unsigned(next_base + 1, 8);

                            if next_group < NUM_GROUPS-1 then
                                prefetch_addr_r <= to_unsigned(next_base + NUM_INPUTS, 8);
                            else
                                prefetch_addr_r <= (others => '0');
                            end if;

                            if next_group*4 + 1 <= NUM_NEURONS then start1 <= '1'; end if;
                            if next_group*4 + 2 <= NUM_NEURONS then start2 <= '1'; end if;
                            if next_group*4 + 3 <= NUM_NEURONS then start3 <= '1'; end if;
                            if next_group*4 + 4 <= NUM_NEURONS then start4 <= '1'; end if;

                            first_cycle_r <= '1';
                            use_prefetch_r <= '1';
                        end if;
                    else
                        input_addr_r <= input_addr_r + 1;
                        weight_addr_r <= weight_addr_r + 1;
                    end if;
                end if;
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

    prefetch_en <= '1' when (state = RUN and
                             group_idx < NUM_GROUPS-1 and
                             input_addr_r = to_unsigned(NUM_INPUTS-1, 6))
                   else '0';
end architecture;
