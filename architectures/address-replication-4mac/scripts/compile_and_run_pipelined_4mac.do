transcript on
transcript file benchmark_4MAC_PIPELINED_FIXED5_transcript.txt
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vcom -work work -2002 -explicit -vopt -stats=none rtl/Input_Memory_Generic.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/Input_Register_Buffer.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/Weight_Memory_DualPort_Generic.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/Scheduler_4MAC_DualPort.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/MAC_Array_Optimized_Masked.vhd
vcom -work work -2002 -explicit -vopt -stats=none baselines/Output_Layer_1MAC_Sequential_FIXED5.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/Output_Layer_1MAC_Pipelined.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/NN_Accelerator_4MAC_DualPort.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/NN_Accelerator_4x8x1_DualPort.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/NN_Accelerator_1MAC_Hidden_Sequential.vhd
vcom -work work -2002 -explicit -vopt -stats=none rtl/NN_Accelerator_1x8x1_Sequential.vhd
vcom -work work -2002 -explicit -vopt -stats=none tb/tb_real_network_parallel_vs_sequential.vhd

vsim -voptargs=+acc work.NN_Accelerator_Parallel_vs_Sequential_RealNetwork_tb_FIXED5_PIPELINED4MAC
run 10 us
transcript off
