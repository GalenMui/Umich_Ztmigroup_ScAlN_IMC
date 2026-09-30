# Reproducible Smart ZYNQ SL V1.2 serial-replacement project, Vivado 2025.2.
# Usage: vivado -mode batch -source vivado/create_project.tcl \
#        -tclargs /absolute/output/directory
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname $script_dir]
if {$argc > 0} {
    set build_dir [file normalize [lindex $argv 0]]
} else {
    set build_dir [file normalize [file join $root_dir build]]
}
file mkdir $build_dir
cd $build_dir
create_project imc_serial_v12 [file join $build_dir imc_serial_v12] \
    -part xc7z020clg484-2 -force
set_property target_language Verilog [current_project]
add_files [glob [file join $root_dir rtl *.sv]]
add_files [file join $root_dir board smart_zynq_sl_v12_imc.v]
add_files -fileset constrs_1 [list \
    [file join $root_dir constraints smart_zynq_sl_v12_j5.xdc] \
    [file join $root_dir constraints imc_serial_v12.xdc]]
update_compile_order -fileset sources_1

source [file join $script_dir create_bd.tcl]
generate_target all [get_files system.bd]
make_wrapper -files [get_files system.bd] -top
add_files -norecurse [glob [file join $build_dir imc_serial_v12 \
    imc_serial_v12.gen sources_1 bd system hdl system_wrapper.v]]
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT_READY [current_project]"
