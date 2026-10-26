library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library base_ref;

entity TB_Scheduler_Address_Replica_Equivalence is
    generic (
        NUM_INPUTS : integer := 4;
        NUM_NEURONS : integer := 8
    );
end entity;

architecture test of TB_Scheduler_Address_Replica_Equivalence is
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal start : std_logic := '0';
    signal b_input, e_input, e_buffer : unsigned(5 downto 0);
    signal b_weight, e_weight, b_prefetch, e_prefetch : unsigned(7 downto 0);
    signal b_prefetch_en, e_prefetch_en : std_logic;
    signal b_start, e_start, b_enable, e_enable : std_logic_vector(3 downto 0);
    signal b_group, e_group : integer range 0 to 255;
    signal b_first,e_first,b_use,e_use,b_running,e_running,b_done,e_done : std_logic;
    signal check_count : integer := 0;
begin
    clk <= not clk after 5 ns;
    BASE : entity base_ref.scheduler_4mac_dualport(rtl)
        generic map (NUM_INPUTS=>NUM_INPUTS, NUM_NEURONS=>NUM_NEURONS)
        port map (
            clk=>clk,rst=>rst,start=>start,
            input_addr=>b_input,weight_addr=>b_weight,
            prefetch_addr=>b_prefetch,prefetch_en=>b_prefetch_en,
            start1=>b_start(0),start2=>b_start(1),start3=>b_start(2),start4=>b_start(3),
            enable1=>b_enable(0),enable2=>b_enable(1),enable3=>b_enable(2),enable4=>b_enable(3),
            current_group=>b_group,first_cycle=>b_first,use_prefetch=>b_use,
            running=>b_running,done=>b_done
        );
    EXPERIMENT : entity work.scheduler_4mac_dualport(rtl)
        generic map (NUM_INPUTS=>NUM_INPUTS, NUM_NEURONS=>NUM_NEURONS)
        port map (
            clk=>clk,rst=>rst,start=>start,
            input_addr=>e_input,buffer_read_addr=>e_buffer,weight_addr=>e_weight,
            prefetch_addr=>e_prefetch,prefetch_en=>e_prefetch_en,
            start1=>e_start(0),start2=>e_start(1),start3=>e_start(2),start4=>e_start(3),
            enable1=>e_enable(0),enable2=>e_enable(1),enable3=>e_enable(2),enable4=>e_enable(3),
            current_group=>e_group,first_cycle=>e_first,use_prefetch=>e_use,
            running=>e_running,done=>e_done
        );
    -- Check all externally observable scheduler signals after every edge,
    -- including the private datapath address against the trusted counter.
    monitor : process
    begin
        wait until rising_edge(clk);
        wait for 1 ns;
        assert b_input=e_input and e_buffer=b_input
            report "ADDR MISMATCH at cycle " & integer'image(check_count) severity failure;
        assert b_weight=e_weight and b_prefetch=e_prefetch and b_prefetch_en=e_prefetch_en
            report "WEIGHT/PREFETCH MISMATCH" severity failure;
        assert b_start=e_start and b_enable=e_enable
            report "START/ENABLE MISMATCH" severity failure;
        assert b_group=e_group and b_first=e_first and b_use=e_use
            report "GROUP/FLAGS MISMATCH" severity failure;
        assert b_running=e_running and b_done=e_done
            report "RUNNING/DONE MISMATCH" severity failure;
        check_count <= check_count+1;
    end process;
    stimulus : process
        variable completed : integer := 0;
    begin
        wait for 24 ns;
        wait until falling_edge(clk);rst <= '0';
        wait until falling_edge(clk);start <= '1';
        wait until falling_edge(clk);start <= '0';
        -- Two full runs exercise reset, prime, run, group transition and done.
        for k in 1 to 2 loop
            for n in 0 to 3*NUM_INPUTS+16 loop
                wait until falling_edge(clk);
                if e_done = '1' then
                    completed := completed+1;
                    exit;
                end if;
            end loop;
            assert completed = k report "Scheduler timeout/no DONE" severity failure;
            if k=1 then
                wait until falling_edge(clk);start <= '1';
                wait until falling_edge(clk);start <= '0';
            end if;
        end loop;
        assert check_count > NUM_INPUTS*2
            report "Insufficient equivalence cycles" severity failure;
        report "PASS: SCHEDULER ADDRESS REPLICA NUM_INPUTS=" & integer'image(NUM_INPUTS) &
               ", NUM_NEURONS=" & integer'image(NUM_NEURONS) &
               ", completed=" & integer'image(completed) &
               ", compared_cycles=" & integer'image(check_count) severity note;
        wait;
    end process;
end architecture;
