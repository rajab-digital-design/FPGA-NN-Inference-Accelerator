library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nn_accelerator_4mac_realweights_tb is
end entity;

architecture sim of nn_accelerator_4mac_realweights_tb is

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal start : std_logic := '0';
    signal done  : std_logic;

    signal cfg_we      : std_logic := '0';
    signal cfg_mem_sel : unsigned(2 downto 0) := (others => '0');
    signal cfg_addr    : unsigned(6 downto 0) := (others => '0');
    signal cfg_data    : signed(15 downto 0) := (others => '0');

    signal cfg_rd_en      : std_logic := '0';
    signal cfg_rd_mem_sel : unsigned(2 downto 0) := (others => '0');
    signal cfg_rd_addr    : unsigned(6 downto 0) := (others => '0');
    signal cfg_rd_data    : signed(15 downto 0);

    signal debug_input_addr     : unsigned(5 downto 0);
    signal debug_weight_addr    : unsigned(7 downto 0);
    signal debug_prefetch_addr  : unsigned(7 downto 0);
    signal debug_current_group  : integer range 0 to 255;
    signal debug_first_cycle    : std_logic;
    signal debug_use_prefetch   : std_logic;
    signal debug_prefetch_en    : std_logic;
    signal debug_running        : std_logic;

    signal debug_acc1 : signed(19 downto 0);
    signal debug_acc2 : signed(19 downto 0);
    signal debug_acc3 : signed(19 downto 0);
    signal debug_acc4 : signed(19 downto 0);

begin

    CLK_PROCESS : process
    begin
        while true loop
            clk <= '0';
            wait for 5 ns;
            clk <= '1';
            wait for 5 ns;
        end loop;
    end process;

    DUT : entity work.nn_accelerator_4mac_dualport
        generic map (
            NUM_INPUTS  => 4,
            NUM_NEURONS => 8
        )
        port map (
            clk   => clk,
            rst   => rst,
            start => start,
            done  => done,

            cfg_we      => cfg_we,
            cfg_mem_sel => cfg_mem_sel,
            cfg_addr    => cfg_addr,
            cfg_data    => cfg_data,

            cfg_rd_en      => cfg_rd_en,
            cfg_rd_mem_sel => cfg_rd_mem_sel,
            cfg_rd_addr    => cfg_rd_addr,
            cfg_rd_data    => cfg_rd_data,

            debug_input_addr    => debug_input_addr,
            debug_weight_addr   => debug_weight_addr,
            debug_prefetch_addr => debug_prefetch_addr,
            debug_current_group => debug_current_group,
            debug_first_cycle   => debug_first_cycle,
            debug_use_prefetch  => debug_use_prefetch,
            debug_prefetch_en   => debug_prefetch_en,
            debug_running       => debug_running,

            debug_acc1 => debug_acc1,
            debug_acc2 => debug_acc2,
            debug_acc3 => debug_acc3,
            debug_acc4 => debug_acc4
        );

    STIMULUS : process

        procedure cfg_write(
            constant mem_sel_v : in unsigned(2 downto 0);
            constant addr_v     : in integer;
            constant data_v     : in integer
        ) is
        begin
            cfg_mem_sel <= mem_sel_v;
            cfg_addr    <= to_unsigned(addr_v, 7);
            cfg_data    <= to_signed(data_v, 16);
            cfg_we      <= '1';
            wait until rising_edge(clk);
            cfg_we <= '0';
        end procedure;

        variable group1_captured : boolean := false;
        variable g1_acc1 : integer := 0;
        variable g1_acc2 : integer := 0;
        variable g1_acc3 : integer := 0;
        variable g1_acc4 : integer := 0;

        variable g2_acc1 : integer := 0;
        variable g2_acc2 : integer := 0;
        variable g2_acc3 : integer := 0;
        variable g2_acc4 : integer := 0;

    begin

        ------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------

        rst <= '1';
        wait for 30 ns;
        wait until rising_edge(clk);
        rst <= '0';

        ------------------------------------------------------------
        -- Load test input vector
        -- Config mem select = 000
        ------------------------------------------------------------

        cfg_write(to_unsigned(0, 3), 0, -206); -- x1
        cfg_write(to_unsigned(0, 3), 1, -233); -- x2
        cfg_write(to_unsigned(0, 3), 2, -161); -- x3
        cfg_write(to_unsigned(0, 3), 3, 21); -- x4

        ------------------------------------------------------------
        -- Group 1 weights: N1..N4
        -- Weight bank 1 = mem_sel 001
        -- Weight bank 2 = mem_sel 010
        -- Weight bank 3 = mem_sel 011
        -- Weight bank 4 = mem_sel 100
        ------------------------------------------------------------

        cfg_write(to_unsigned(1, 3), 0, 37); -- N1 W(1,1)
        cfg_write(to_unsigned(2, 3), 0, 6); -- N2 W(2,1)
        cfg_write(to_unsigned(3, 3), 0, -490); -- N3 W(3,1)
        cfg_write(to_unsigned(4, 3), 0, 41); -- N4 W(4,1)
        cfg_write(to_unsigned(1, 3), 1, 96); -- N1 W(1,2)
        cfg_write(to_unsigned(2, 3), 1, -53); -- N2 W(2,2)
        cfg_write(to_unsigned(3, 3), 1, 194); -- N3 W(3,2)
        cfg_write(to_unsigned(4, 3), 1, -64); -- N4 W(4,2)
        cfg_write(to_unsigned(1, 3), 2, -52); -- N1 W(1,3)
        cfg_write(to_unsigned(2, 3), 2, 92); -- N2 W(2,3)
        cfg_write(to_unsigned(3, 3), 2, -60); -- N3 W(3,3)
        cfg_write(to_unsigned(4, 3), 2, 96); -- N4 W(4,3)
        cfg_write(to_unsigned(1, 3), 3, -177); -- N1 W(1,4)
        cfg_write(to_unsigned(2, 3), 3, 55); -- N2 W(2,4)
        cfg_write(to_unsigned(3, 3), 3, 26); -- N3 W(3,4)
        cfg_write(to_unsigned(4, 3), 3, -123); -- N4 W(4,4)

        ------------------------------------------------------------
        -- Group 2 weights: N5..N8
        -- Stored at weight addresses 4..7
        ------------------------------------------------------------

        cfg_write(to_unsigned(1, 3), 4, 2); -- N5 W(5,1)
        cfg_write(to_unsigned(2, 3), 4, 103); -- N6 W(6,1)
        cfg_write(to_unsigned(3, 3), 4, 225); -- N7 W(7,1)
        cfg_write(to_unsigned(4, 3), 4, 2); -- N8 W(8,1)
        cfg_write(to_unsigned(1, 3), 5, 38); -- N5 W(5,2)
        cfg_write(to_unsigned(2, 3), 5, -195); -- N6 W(6,2)
        cfg_write(to_unsigned(3, 3), 5, 111); -- N7 W(7,2)
        cfg_write(to_unsigned(4, 3), 5, 149); -- N8 W(8,2)
        cfg_write(to_unsigned(1, 3), 6, 21); -- N5 W(5,3)
        cfg_write(to_unsigned(2, 3), 6, 56); -- N6 W(6,3)
        cfg_write(to_unsigned(3, 3), 6, 155); -- N7 W(7,3)
        cfg_write(to_unsigned(4, 3), 6, -77); -- N8 W(8,3)
        cfg_write(to_unsigned(1, 3), 7, 36); -- N5 W(5,4)
        cfg_write(to_unsigned(2, 3), 7, 50); -- N6 W(6,4)
        cfg_write(to_unsigned(3, 3), 7, -110); -- N7 W(7,4)
        cfg_write(to_unsigned(4, 3), 7, 90); -- N8 W(8,4)

        ------------------------------------------------------------
        -- Hidden layer biases
        -- Config mem select = 101
        ------------------------------------------------------------

        cfg_write(to_unsigned(5, 3), 0, -49); -- b1
        cfg_write(to_unsigned(5, 3), 1, -1); -- b2
        cfg_write(to_unsigned(5, 3), 2, 16); -- b3
        cfg_write(to_unsigned(5, 3), 3, -111); -- b4
        cfg_write(to_unsigned(5, 3), 4, -26); -- b5
        cfg_write(to_unsigned(5, 3), 5, -18); -- b6
        cfg_write(to_unsigned(5, 3), 6, 38); -- b7
        cfg_write(to_unsigned(5, 3), 7, 8); -- b8

        ------------------------------------------------------------
        -- Start accelerator
        ------------------------------------------------------------

        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';

        ------------------------------------------------------------
        -- Wait for execution
        ------------------------------------------------------------

        while done /= '1' loop

            wait until falling_edge(clk);

            if (debug_current_group = 1) and
               (debug_first_cycle = '1') and
               (not group1_captured) then

                g1_acc1 := to_integer(debug_acc1);
                g1_acc2 := to_integer(debug_acc2);
                g1_acc3 := to_integer(debug_acc3);
                g1_acc4 := to_integer(debug_acc4);

                group1_captured := true;

                report "GROUP 1 CAPTURED";

            end if;

        end loop;

        ------------------------------------------------------------
        -- Capture Group 2
        ------------------------------------------------------------

        wait until falling_edge(clk);

        g2_acc1 := to_integer(debug_acc1);
        g2_acc2 := to_integer(debug_acc2);
        g2_acc3 := to_integer(debug_acc3);
        g2_acc4 := to_integer(debug_acc4);

        ------------------------------------------------------------
        -- MATLAB Q8.8 expected results
        ------------------------------------------------------------

        report "MATLAB expected G1: N1=" & integer'image(-150) &
               " N2=" & integer'image(-12) &
               " N3=" & integer'image(272) &
               " N4=" & integer'image(-158);

        report "FPGA G1: N1=" & integer'image(g1_acc1) &
               " N2=" & integer'image(g1_acc2) &
               " N3=" & integer'image(g1_acc3) &
               " N4=" & integer'image(g1_acc4);

        report "MATLAB expected G2: N5=" & integer'image(-75) &
               " N6=" & integer'image(44) &
               " N7=" & integer'image(-354) &
               " N8=" & integer'image(-75);

        report "FPGA G2: N5=" & integer'image(g2_acc1) &
               " N6=" & integer'image(g2_acc2) &
               " N7=" & integer'image(g2_acc3) &
               " N8=" & integer'image(g2_acc4);

        ------------------------------------------------------------
        -- Verify Group 1
        ------------------------------------------------------------

        assert g1_acc1 = -150
            report "FAIL: FPGA N1 does not match MATLAB Q8.8 reference"
            severity error;

        assert g1_acc2 = -12
            report "FAIL: FPGA N2 does not match MATLAB Q8.8 reference"
            severity error;

        assert g1_acc3 = 272
            report "FAIL: FPGA N3 does not match MATLAB Q8.8 reference"
            severity error;

        assert g1_acc4 = -158
            report "FAIL: FPGA N4 does not match MATLAB Q8.8 reference"
            severity error;

        ------------------------------------------------------------
        -- Verify Group 2
        ------------------------------------------------------------

        assert g2_acc1 = -75
            report "FAIL: FPGA N5 does not match MATLAB Q8.8 reference"
            severity error;

        assert g2_acc2 = 44
            report "FAIL: FPGA N6 does not match MATLAB Q8.8 reference"
            severity error;

        assert g2_acc3 = -354
            report "FAIL: FPGA N7 does not match MATLAB Q8.8 reference"
            severity error;

        assert g2_acc4 = -75
            report "FAIL: FPGA N8 does not match MATLAB Q8.8 reference"
            severity error;

        ------------------------------------------------------------
        -- Performance information
        ------------------------------------------------------------

        report "================================================";
        report "REAL MATLAB WEIGHT TEST FINISHED";
        report "4 inputs x 8 hidden neurons";
        report "2 parallel groups";
        report "================================================";

        wait;

    end process;

end architecture;
