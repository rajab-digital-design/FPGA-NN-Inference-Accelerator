# Run from the root of EXPERIMENT_4MAC_INPUT_READ_ONEHOT.
# This is a NEW verification run required for the modified RTL.
# No historical PASS is reused as proof for this experiment.
transcript on
transcript file onehot_buffer_equivalence_transcript.txt
onerror {quit -code 1}
onbreak {quit -code 1}
if {[file exists base_ref]} {vdel -lib base_ref -all}
if {[file exists work]} {vdel -lib work -all}
vlib base_ref
vlib work
vmap base_ref base_ref
vmap work work

# Unmodified trusted source: copied into a separate library.
vcom -work base_ref -2002 -explicit reference-source/Input_Register_Buffer.vhd
vcom -work work -2002 -explicit rtl/Input_Register_Buffer.vhd
vcom -work work -2002 -explicit tb/tb_input_buffer_one_hot_equivalence.vhd

foreach n {4 5 17 21} {
    echo "============ BUFFER EQUIVALENCE NUM_INPUTS=$n ============"
    vsim -c -gNUM_INPUTS=$n work.TB_Input_Buffer_OneHot_Equivalence
    run -all
    quit -sim
}
transcript off
quit -code 0
