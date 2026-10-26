library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Synthesis/implementation wrapper for the 2-MAC 4->8->1 accelerator.
-- Keep the configuration interface exposed so synthesized hardware remains loadable.
-- Debug and per-neuron observation ports are intentionally left open here.
entity nn_accelerator_2x8x1_synth_top is
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        start : in std_logic;
        done  : out std_logic;

        cfg_we      : in std_logic;
        cfg_mem_sel : in unsigned(2 downto 0);
        cfg_addr    : in unsigned(6 downto 0);
        cfg_data    : in signed(15 downto 0);

        cfg_rd_en      : in std_logic;
        cfg_rd_mem_sel : in unsigned(2 downto 0);
        cfg_rd_addr    : in unsigned(6 downto 0);
        cfg_rd_data    : out signed(15 downto 0);

        out_result : out signed(31 downto 0)
    );
end entity;

architecture structural of nn_accelerator_2x8x1_synth_top is
begin
    UUT : entity work.nn_accelerator_2x8x1_dualport
        port map (
            clk => clk,
            rst => rst,
            start => start,
            done => done,
            cfg_we => cfg_we,
            cfg_mem_sel => cfg_mem_sel,
            cfg_addr => cfg_addr,
            cfg_data => cfg_data,
            cfg_rd_en => cfg_rd_en,
            cfg_rd_mem_sel => cfg_rd_mem_sel,
            cfg_rd_addr => cfg_rd_addr,
            cfg_rd_data => cfg_rd_data,
            hidden_n1 => open,
            hidden_n2 => open,
            hidden_n3 => open,
            hidden_n4 => open,
            hidden_n5 => open,
            hidden_n6 => open,
            hidden_n7 => open,
            hidden_n8 => open,
            relu_n1 => open,
            relu_n2 => open,
            relu_n3 => open,
            relu_n4 => open,
            relu_n5 => open,
            relu_n6 => open,
            relu_n7 => open,
            relu_n8 => open,
            output_result => out_result,
            output_running => open,
            output_mac_index => open,
            debug_hidden_running => open,
            debug_hidden_group => open,
            debug_hidden_first_cycle => open,
            debug_hidden_prefetch_en => open
        );
end architecture;
