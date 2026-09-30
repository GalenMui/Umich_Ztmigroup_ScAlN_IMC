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

set rtl_dir [file join $target_dir rtl]
add_files -norecurse [list \
    [file join $rtl_dir control_regs.sv] \
    [file join $rtl_dir row_shift_controller.sv] \
    [file join $rtl_dir imc_top.sv] \
    [file join $target_dir board imc_row_axi_wrapper.v]]
add_files -fileset constrs_1 \
    [file join $target_dir constraints smart_zynq_sl_v12_j5.xdc]
update_compile_order -fileset sources_1
source [file join $script_dir create_bd.tcl]
generate_target all [get_files platform.bd]
make_wrapper -files [get_files platform.bd] -top
add_files -norecurse [glob [file join $build_dir $project_name \
    ${project_name}.gen sources_1 bd platform hdl platform_wrapper.v]]
set_property top platform_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "PROJECT_READY [file join $build_dir $project_name $project_name.xpr]"
