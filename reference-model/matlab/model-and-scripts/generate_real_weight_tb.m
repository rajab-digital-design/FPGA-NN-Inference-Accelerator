%% ================================================================
% generate_real_weight_tb.m
%
% Generate a VHDL testbench from the trained MATLAB MLP parameters.
%
% Source:
%   MLP_reference.mat
%
% Target DUT:
%   nn_accelerator_4mac_dualport
%
% Current hardware configuration:
%   NUM_INPUTS  = 4
%   NUM_NEURONS = 8
%
% Hidden layer:
%   4 inputs -> 8 neurons
%   4 MAC parallel architecture
%   Group 1 = N1..N4
%   Group 2 = N5..N8
%
% Weight memory mapping:
%   Bank 1 = N1, N5
%   Bank 2 = N2, N6
%   Bank 3 = N3, N7
%   Bank 4 = N4, N8
%
% Fixed-point:
%   Q8.8
%
% The generated testbench:
%   1) Loads the 4 test inputs
%   2) Loads W1 weights
%   3) Loads hidden-layer biases
%   4) Starts the accelerator
%   5) Captures Group-1 results
%   6) Captures Group-2 results
%   7) Compares FPGA accumulators against MATLAB Q8.8 reference
%
% ================================================================

clear;
clc;

fprintf('\n');
fprintf('============================================================\n');
fprintf('     REAL MATLAB WEIGHT -> VHDL TESTBENCH GENERATOR\n');
fprintf('============================================================\n');


%% ---------------------------------------------------------------
% 1. Load trained network
% ---------------------------------------------------------------

if ~isfile('MLP_reference.mat')
    error( ...
        'MLP_reference.mat was not found in the current MATLAB folder.');
end

load('MLP_reference.mat');


%% ---------------------------------------------------------------
% 2. Check required variables
% ---------------------------------------------------------------

required_vars = {
    'W1_q'
    'b1_q'
    'x_ref_q'
    'hidden_acc_q'
    'hidden_relu_q'
    'W2_q'
    'b2_q'
};

for k = 1:length(required_vars)

    if ~exist(required_vars{k}, 'var')
        error( ...
            'Required variable "%s" is missing from MLP_reference.mat.', ...
            required_vars{k});
    end

end


%% ---------------------------------------------------------------
% 3. Network dimensions
% ---------------------------------------------------------------

[NUM_NEURONS, NUM_INPUTS] = size(W1_q);

if NUM_INPUTS ~= 4
    error( ...
        'This testbench generator expects NUM_INPUTS = 4, but W1_q has %d inputs.', ...
        NUM_INPUTS);
end

if NUM_NEURONS ~= 8
    error( ...
        'This testbench generator expects NUM_NEURONS = 8, but W1_q has %d neurons.', ...
        NUM_NEURONS);
end

if length(b1_q) ~= NUM_NEURONS
    error('b1_q dimension does not match W1_q.');
end

if length(x_ref_q) ~= NUM_INPUTS
    error('x_ref_q dimension does not match W1_q.');
end

if length(hidden_acc_q) ~= NUM_NEURONS
    error('hidden_acc_q dimension does not match W1_q.');
end


%% ---------------------------------------------------------------
% 4. Convert vectors to columns
% ---------------------------------------------------------------

b1_q = b1_q(:);
x_ref_q = x_ref_q(:);
hidden_acc_q = hidden_acc_q(:);
hidden_relu_q = hidden_relu_q(:);


%% ---------------------------------------------------------------
% 5. Output file
% ---------------------------------------------------------------

filename = 'tb_4mac_real_weights.vhd';

fid = fopen(filename, 'w');

if fid == -1
    error('Unable to create file "%s".', filename);
end


%% ---------------------------------------------------------------
% 6. Header
% ---------------------------------------------------------------

fprintf(fid, 'library ieee;\n');
fprintf(fid, 'use ieee.std_logic_1164.all;\n');
fprintf(fid, 'use ieee.numeric_std.all;\n');
fprintf(fid, '\n');

fprintf(fid, 'entity nn_accelerator_4mac_realweights_tb is\n');
fprintf(fid, 'end entity;\n');
fprintf(fid, '\n');

fprintf(fid, 'architecture sim of nn_accelerator_4mac_realweights_tb is\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 7. DUT signals
% ---------------------------------------------------------------

fprintf(fid, '    signal clk   : std_logic := ''0'';\n');
fprintf(fid, '    signal rst   : std_logic := ''1'';\n');
fprintf(fid, '    signal start : std_logic := ''0'';\n');
fprintf(fid, '    signal done  : std_logic;\n');
fprintf(fid, '\n');

fprintf(fid, '    signal cfg_we      : std_logic := ''0'';\n');
fprintf(fid, '    signal cfg_mem_sel : unsigned(2 downto 0) := (others => ''0'');\n');
fprintf(fid, '    signal cfg_addr    : unsigned(6 downto 0) := (others => ''0'');\n');
fprintf(fid, '    signal cfg_data    : signed(15 downto 0) := (others => ''0'');\n');
fprintf(fid, '\n');

fprintf(fid, '    signal cfg_rd_en      : std_logic := ''0'';\n');
fprintf(fid, '    signal cfg_rd_mem_sel : unsigned(2 downto 0) := (others => ''0'');\n');
fprintf(fid, '    signal cfg_rd_addr    : unsigned(6 downto 0) := (others => ''0'');\n');
fprintf(fid, '    signal cfg_rd_data    : signed(15 downto 0);\n');
fprintf(fid, '\n');

fprintf(fid, '    signal debug_input_addr     : unsigned(5 downto 0);\n');
fprintf(fid, '    signal debug_weight_addr    : unsigned(7 downto 0);\n');
fprintf(fid, '    signal debug_prefetch_addr  : unsigned(7 downto 0);\n');
fprintf(fid, '    signal debug_current_group  : integer range 0 to 255;\n');
fprintf(fid, '    signal debug_first_cycle    : std_logic;\n');
fprintf(fid, '    signal debug_use_prefetch   : std_logic;\n');
fprintf(fid, '    signal debug_prefetch_en    : std_logic;\n');
fprintf(fid, '    signal debug_running        : std_logic;\n');
fprintf(fid, '\n');

fprintf(fid, '    signal debug_acc1 : signed(19 downto 0);\n');
fprintf(fid, '    signal debug_acc2 : signed(19 downto 0);\n');
fprintf(fid, '    signal debug_acc3 : signed(19 downto 0);\n');
fprintf(fid, '    signal debug_acc4 : signed(19 downto 0);\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 8. Clock
% ---------------------------------------------------------------

fprintf(fid, 'begin\n');
fprintf(fid, '\n');

fprintf(fid, '    CLK_PROCESS : process\n');
fprintf(fid, '    begin\n');
fprintf(fid, '        while true loop\n');
fprintf(fid, '            clk <= ''0'';\n');
fprintf(fid, '            wait for 5 ns;\n');
fprintf(fid, '            clk <= ''1'';\n');
fprintf(fid, '            wait for 5 ns;\n');
fprintf(fid, '        end loop;\n');
fprintf(fid, '    end process;\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 9. DUT
% ---------------------------------------------------------------

fprintf(fid, '    DUT : entity work.nn_accelerator_4mac_dualport\n');
fprintf(fid, '        generic map (\n');
fprintf(fid, '            NUM_INPUTS  => 4,\n');
fprintf(fid, '            NUM_NEURONS => 8\n');
fprintf(fid, '        )\n');
fprintf(fid, '        port map (\n');
fprintf(fid, '            clk   => clk,\n');
fprintf(fid, '            rst   => rst,\n');
fprintf(fid, '            start => start,\n');
fprintf(fid, '            done  => done,\n');
fprintf(fid, '\n');

fprintf(fid, '            cfg_we      => cfg_we,\n');
fprintf(fid, '            cfg_mem_sel => cfg_mem_sel,\n');
fprintf(fid, '            cfg_addr    => cfg_addr,\n');
fprintf(fid, '            cfg_data    => cfg_data,\n');
fprintf(fid, '\n');

fprintf(fid, '            cfg_rd_en      => cfg_rd_en,\n');
fprintf(fid, '            cfg_rd_mem_sel => cfg_rd_mem_sel,\n');
fprintf(fid, '            cfg_rd_addr    => cfg_rd_addr,\n');
fprintf(fid, '            cfg_rd_data    => cfg_rd_data,\n');
fprintf(fid, '\n');

fprintf(fid, '            debug_input_addr    => debug_input_addr,\n');
fprintf(fid, '            debug_weight_addr   => debug_weight_addr,\n');
fprintf(fid, '            debug_prefetch_addr => debug_prefetch_addr,\n');
fprintf(fid, '            debug_current_group => debug_current_group,\n');
fprintf(fid, '            debug_first_cycle   => debug_first_cycle,\n');
fprintf(fid, '            debug_use_prefetch  => debug_use_prefetch,\n');
fprintf(fid, '            debug_prefetch_en   => debug_prefetch_en,\n');
fprintf(fid, '            debug_running       => debug_running,\n');
fprintf(fid, '\n');

fprintf(fid, '            debug_acc1 => debug_acc1,\n');
fprintf(fid, '            debug_acc2 => debug_acc2,\n');
fprintf(fid, '            debug_acc3 => debug_acc3,\n');
fprintf(fid, '            debug_acc4 => debug_acc4\n');
fprintf(fid, '        );\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 10. Stimulus process
% ---------------------------------------------------------------

fprintf(fid, '    STIMULUS : process\n');
fprintf(fid, '\n');

fprintf(fid, '        procedure cfg_write(\n');
fprintf(fid, '            constant mem_sel_v : in unsigned(2 downto 0);\n');
fprintf(fid, '            constant addr_v     : in integer;\n');
fprintf(fid, '            constant data_v     : in integer\n');
fprintf(fid, '        ) is\n');
fprintf(fid, '        begin\n');
fprintf(fid, '            cfg_mem_sel <= mem_sel_v;\n');
fprintf(fid, '            cfg_addr    <= to_unsigned(addr_v, 7);\n');
fprintf(fid, '            cfg_data    <= to_signed(data_v, 16);\n');
fprintf(fid, '            cfg_we      <= ''1'';\n');
fprintf(fid, '            wait until rising_edge(clk);\n');
fprintf(fid, '            cfg_we <= ''0'';\n');
fprintf(fid, '        end procedure;\n');
fprintf(fid, '\n');

fprintf(fid, '        variable group1_captured : boolean := false;\n');
fprintf(fid, '        variable g1_acc1 : integer := 0;\n');
fprintf(fid, '        variable g1_acc2 : integer := 0;\n');
fprintf(fid, '        variable g1_acc3 : integer := 0;\n');
fprintf(fid, '        variable g1_acc4 : integer := 0;\n');
fprintf(fid, '\n');

fprintf(fid, '        variable g2_acc1 : integer := 0;\n');
fprintf(fid, '        variable g2_acc2 : integer := 0;\n');
fprintf(fid, '        variable g2_acc3 : integer := 0;\n');
fprintf(fid, '        variable g2_acc4 : integer := 0;\n');
fprintf(fid, '\n');

fprintf(fid, '    begin\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 11. Reset
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Reset\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

fprintf(fid, '        rst <= ''1'';\n');
fprintf(fid, '        wait for 30 ns;\n');
fprintf(fid, '        wait until rising_edge(clk);\n');
fprintf(fid, '        rst <= ''0'';\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 12. Input configuration
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Load test input vector\n');
fprintf(fid, '        -- Config mem select = 000\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

for i = 1:NUM_INPUTS

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(0, 3), %d, %d); -- x%d\n', ...
        i-1, ...
        double(x_ref_q(i)), ...
        i);

end

fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 13. Weight Group 1
%
% Bank mapping:
%
% Bank 1 -> N1
% Bank 2 -> N2
% Bank 3 -> N3
% Bank 4 -> N4
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Group 1 weights: N1..N4\n');
fprintf(fid, '        -- Weight bank 1 = mem_sel 001\n');
fprintf(fid, '        -- Weight bank 2 = mem_sel 010\n');
fprintf(fid, '        -- Weight bank 3 = mem_sel 011\n');
fprintf(fid, '        -- Weight bank 4 = mem_sel 100\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

for i = 1:NUM_INPUTS

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(1, 3), %d, %d); -- N1 W(%d,%d)\n', ...
        i-1, ...
        double(W1_q(1,i)), ...
        1, ...
        i);

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(2, 3), %d, %d); -- N2 W(%d,%d)\n', ...
        i-1, ...
        double(W1_q(2,i)), ...
        2, ...
        i);

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(3, 3), %d, %d); -- N3 W(%d,%d)\n', ...
        i-1, ...
        double(W1_q(3,i)), ...
        3, ...
        i);

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(4, 3), %d, %d); -- N4 W(%d,%d)\n', ...
        i-1, ...
        double(W1_q(4,i)), ...
        4, ...
        i);

end

fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 14. Weight Group 2
%
% Addresses 4..7
%
% Bank 1 -> N5
% Bank 2 -> N6
% Bank 3 -> N7
% Bank 4 -> N8
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Group 2 weights: N5..N8\n');
fprintf(fid, '        -- Stored at weight addresses 4..7\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

for i = 1:NUM_INPUTS

    addr = NUM_INPUTS + i - 1;

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(1, 3), %d, %d); -- N5 W(%d,%d)\n', ...
        addr, ...
        double(W1_q(5,i)), ...
        5, ...
        i);

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(2, 3), %d, %d); -- N6 W(%d,%d)\n', ...
        addr, ...
        double(W1_q(6,i)), ...
        6, ...
        i);

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(3, 3), %d, %d); -- N7 W(%d,%d)\n', ...
        addr, ...
        double(W1_q(7,i)), ...
        7, ...
        i);

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(4, 3), %d, %d); -- N8 W(%d,%d)\n', ...
        addr, ...
        double(W1_q(8,i)), ...
        8, ...
        i);

end

fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 15. Biases
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Hidden layer biases\n');
fprintf(fid, '        -- Config mem select = 101\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

for n = 1:NUM_NEURONS

    fprintf( ...
        fid, ...
        '        cfg_write(to_unsigned(5, 3), %d, %d); -- b%d\n', ...
        n-1, ...
        double(b1_q(n)), ...
        n);

end

fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 16. Start accelerator
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Start accelerator\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

fprintf(fid, '        wait until rising_edge(clk);\n');
fprintf(fid, '        start <= ''1'';\n');
fprintf(fid, '        wait until rising_edge(clk);\n');
fprintf(fid, '        start <= ''0'';\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 17. Monitor and capture
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Wait for execution\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

fprintf(fid, '        while done /= ''1'' loop\n');
fprintf(fid, '\n');

fprintf(fid, '            wait until falling_edge(clk);\n');
fprintf(fid, '\n');

fprintf(fid, '            if (debug_current_group = 1) and\n');
fprintf(fid, '               (debug_first_cycle = ''1'') and\n');
fprintf(fid, '               (not group1_captured) then\n');
fprintf(fid, '\n');

fprintf(fid, '                g1_acc1 := to_integer(debug_acc1);\n');
fprintf(fid, '                g1_acc2 := to_integer(debug_acc2);\n');
fprintf(fid, '                g1_acc3 := to_integer(debug_acc3);\n');
fprintf(fid, '                g1_acc4 := to_integer(debug_acc4);\n');
fprintf(fid, '\n');

fprintf(fid, '                group1_captured := true;\n');
fprintf(fid, '\n');

fprintf(fid, '                report "GROUP 1 CAPTURED";\n');
fprintf(fid, '\n');

fprintf(fid, '            end if;\n');
fprintf(fid, '\n');

fprintf(fid, '        end loop;\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 18. Capture final group
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Capture Group 2\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

fprintf(fid, '        wait until falling_edge(clk);\n');
fprintf(fid, '\n');

fprintf(fid, '        g2_acc1 := to_integer(debug_acc1);\n');
fprintf(fid, '        g2_acc2 := to_integer(debug_acc2);\n');
fprintf(fid, '        g2_acc3 := to_integer(debug_acc3);\n');
fprintf(fid, '        g2_acc4 := to_integer(debug_acc4);\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 19. Print MATLAB expected values
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- MATLAB Q8.8 expected results\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

fprintf(fid, ...
    '        report "MATLAB expected G1: N1=" & integer''image(%d) &\n', ...
    double(hidden_acc_q(1)));

fprintf(fid, ...
    '               " N2=" & integer''image(%d) &\n', ...
    double(hidden_acc_q(2)));

fprintf(fid, ...
    '               " N3=" & integer''image(%d) &\n', ...
    double(hidden_acc_q(3)));

fprintf(fid, ...
    '               " N4=" & integer''image(%d);\n', ...
    double(hidden_acc_q(4)));

fprintf(fid, '\n');

fprintf(fid, ...
    '        report "FPGA G1: N1=" & integer''image(g1_acc1) &\n');

fprintf(fid, ...
    '               " N2=" & integer''image(g1_acc2) &\n');

fprintf(fid, ...
    '               " N3=" & integer''image(g1_acc3) &\n');

fprintf(fid, ...
    '               " N4=" & integer''image(g1_acc4);\n');

fprintf(fid, '\n');

fprintf(fid, ...
    '        report "MATLAB expected G2: N5=" & integer''image(%d) &\n', ...
    double(hidden_acc_q(5)));

fprintf(fid, ...
    '               " N6=" & integer''image(%d) &\n', ...
    double(hidden_acc_q(6)));

fprintf(fid, ...
    '               " N7=" & integer''image(%d) &\n', ...
    double(hidden_acc_q(7)));

fprintf(fid, ...
    '               " N8=" & integer''image(%d);\n', ...
    double(hidden_acc_q(8)));

fprintf(fid, '\n');

fprintf(fid, ...
    '        report "FPGA G2: N5=" & integer''image(g2_acc1) &\n');

fprintf(fid, ...
    '               " N6=" & integer''image(g2_acc2) &\n');

fprintf(fid, ...
    '               " N7=" & integer''image(g2_acc3) &\n');

fprintf(fid, ...
    '               " N8=" & integer''image(g2_acc4);\n');

fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 20. Assertions Group 1
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Verify Group 1\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

for n = 1:4

    fprintf( ...
        fid, ...
        '        assert g1_acc%d = %d\n', ...
        n, ...
        double(hidden_acc_q(n)));

    fprintf( ...
        fid, ...
        '            report "FAIL: FPGA N%d does not match MATLAB Q8.8 reference"\n', ...
        n);

    fprintf(fid, '            severity error;\n');
    fprintf(fid, '\n');

end


%% ---------------------------------------------------------------
% 21. Assertions Group 2
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Verify Group 2\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

for n = 5:8

    fpga_index = n - 4;

    fprintf( ...
        fid, ...
        '        assert g2_acc%d = %d\n', ...
        fpga_index, ...
        double(hidden_acc_q(n)));

    fprintf( ...
        fid, ...
        '            report "FAIL: FPGA N%d does not match MATLAB Q8.8 reference"\n', ...
        n);

    fprintf(fid, '            severity error;\n');
    fprintf(fid, '\n');

end


%% ---------------------------------------------------------------
% 22. Performance report
% ---------------------------------------------------------------

fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '        -- Performance information\n');
fprintf(fid, '        ------------------------------------------------------------\n');
fprintf(fid, '\n');

fprintf(fid, '        report "================================================";\n');
fprintf(fid, '        report "REAL MATLAB WEIGHT TEST FINISHED";\n');
fprintf(fid, '        report "4 inputs x 8 hidden neurons";\n');
fprintf(fid, '        report "2 parallel groups";\n');
fprintf(fid, '        report "================================================";\n');
fprintf(fid, '\n');


%% ---------------------------------------------------------------
% 23. Finish
% ---------------------------------------------------------------

fprintf(fid, '        wait;\n');
fprintf(fid, '\n');

fprintf(fid, '    end process;\n');
fprintf(fid, '\n');

fprintf(fid, 'end architecture;\n');


%% ---------------------------------------------------------------
% 24. Close file
% ---------------------------------------------------------------

fclose(fid);


%% ---------------------------------------------------------------
% 25. MATLAB-side summary
% ---------------------------------------------------------------

fprintf('\n');
fprintf('============================================================\n');
fprintf('VHDL TESTBENCH GENERATED SUCCESSFULLY\n');
fprintf('============================================================\n');

fprintf('File:\n');
fprintf('  %s\n\n', filename);

fprintf('Network:\n');
fprintf('  %d inputs\n', NUM_INPUTS);
fprintf('  %d hidden neurons\n\n', NUM_NEURONS);

fprintf('Test input Q8.8:\n');

for i = 1:NUM_INPUTS

    fprintf( ...
        '  x%d = %d  (%+.6f)\n', ...
        i, ...
        double(x_ref_q(i)), ...
        double(x_ref_q(i))/256);

end

fprintf('\n');

fprintf('Expected hidden-layer Q8.8 accumulators:\n');

for n = 1:NUM_NEURONS

    fprintf( ...
        '  N%d = %d  (%+.6f)\n', ...
        n, ...
        double(hidden_acc_q(n)), ...
        double(hidden_acc_q(n))/256);

end

fprintf('\n');

fprintf('Expected hidden-layer ReLU values:\n');

for n = 1:NUM_NEURONS

    fprintf( ...
        '  N%d = %d  (%+.6f)\n', ...
        n, ...
        double(hidden_relu_q(n)), ...
        double(hidden_relu_q(n))/256);

end

fprintf('\n');

fprintf('============================================================\n');