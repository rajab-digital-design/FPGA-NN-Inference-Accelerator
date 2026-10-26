# Run from the experiment root in modelsim SE-64 2020.4 (VHDL-2002).
# Fixed 4->8->1 network: hidden, ReLU, Q8.8 -38 and 19-cycle window.
transcript on
transcript file EXP_FANOUT_full_network_regression_transcript.txt
onerror {quit -code 1}
onbreak {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vmap work work
vcom -work work -2002 -explicit rtl/Input_Memory_Generic.vhd
vcom -work work -2002 -explicit rtl/Input_Register_Buffer.vhd
vcom -work work -2002 -explicit rtl/Weight_Memory_DualPort_Generic.vhd
vcom -work work -2002 -explicit rtl/Scheduler_4MAC_DualPort.vhd
vcom -work work -2002 -explicit rtl/MAC_Array_Optimized_Masked.vhd
vcom -work work -2002 -explicit baselines/Output_Layer_1MAC_Sequential_FIXED5.vhd
vcom -work work -2002 -explicit rtl/Output_Layer_1MAC_Pipelined.vhd
vcom -work work -2002 -explicit rtl/NN_Accelerator_4MAC_DualPort.vhd
vcom -work work -2002 -explicit rtl/NN_Accelerator_4x8x1_DualPort.vhd
vcom -work work -2002 -explicit rtl/NN_Accelerator_1MAC_Hidden_Sequential.vhd
vcom -work work -2002 -explicit rtl/NN_Accelerator_1x8x1_Sequential.vhd
vcom -work work -2002 -explicit tb/tb_real_network_parallel_vs_sequential.vhd
vsim -c work.NN_Accelerator_Parallel_vs_Sequential_RealNetwork_tb_FIXED5_PIPELINED4MAC
run 10 us
transcript off
quit -code 0
