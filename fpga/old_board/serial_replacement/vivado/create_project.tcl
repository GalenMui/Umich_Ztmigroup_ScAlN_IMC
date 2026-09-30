# Recreate the Smart ZYNQ SL V1.2 Vivado project skeleton.
# Usage: vivado -mode batch -source vivado/create_project.tcl [-tclargs BUILD_DIR]
set script_dir [file dirname [file normalize [info script]]]
set target_dir [file dirname $script_dir]
if {$argc > 1} {
    error "Usage: create_project.tcl ?BUILD_DIR?"
}
if {$argc == 1} {
    set build_dir [file normalize [lindex $argv 0]]
} else {
    set build_dir [file join $target_dir build]
}

file mkdir $build_dir
set project_name smart_zynq_sl_v12
create_project $project_name [file join $build_dir $project_name] \
    -part xc7z020clg484-2 -force

set constraint_dir [file join $target_dir constraints]
add_files -fileset constrs_1 [list \
    [file join $constraint_dir smart_zynq_sl_v12_base.xdc] \
    [file join $constraint_dir smart_zynq_sl_v12_j5.xdc]]
source [file join $script_dir create_bd.tcl]
puts "PROJECT_READY [file join $build_dir $project_name $project_name.xpr]"
