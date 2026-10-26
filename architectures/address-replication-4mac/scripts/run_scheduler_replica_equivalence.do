# Run from experiment root in modelsim SE 2020.4; VHDL-2002.
transcript on
transcript file EXP_FANOUT_scheduler_equivalence_transcript.txt
onerror {quit -code 1}
onbreak {quit -code 1}
if {[file exists base_ref]} {vdel -lib base_ref -all}
if {[file exists work]} {vdel -lib work -all}
vlib base_ref
vlib work
vmap base_ref base_ref
vmap work work
vcom -work base_ref -2002 -explicit reference-source/Scheduler_4MAC_DualPort.vhd
vcom -work work -2002 -explicit rtl/Scheduler_4MAC_DualPort.vhd
vcom -work work -2002 -explicit tb/tb_scheduler_address_replica_equivalence.vhd
foreach n {4 5 17 21} {
    echo "=== SCHEDULER REPLICA: NUM_INPUTS=$n ==="
    vsim -c -gNUM_INPUTS=$n -gNUM_NEURONS=8 work.TB_Scheduler_Address_Replica_Equivalence
    run [expr {($n * 7 + 150) * 10}] ns
    quit -sim
}
transcript off
