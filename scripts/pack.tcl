set work_dir   [file normalize .]
set boards_dir ${work_dir}/boards
set src_dir    ${work_dir}/src

set build_dir     [file normalize [lindex $argv 0]]
set board         [lindex $argv 1]
set axi_clk_freq  [lindex $argv 2]
set ctrl_clk_freq 100
set n_jobs        [lindex $argv 3]

set ip_build_dir ${build_dir}/ip
set proj_name    cmac_${board}
set krnl_name    cmac_${board}

file mkdir ${build_dir}
file mkdir ${ip_build_dir}
file mkdir ${build_dir}/${board}

source ${boards_dir}/${board}.tcl

set cmac_usplus     cmac_usplus_${qsfp_port}
set wrapper_module  cmac_wrapper
set wrapper_src     ${build_dir}/${board}/${wrapper_module}.v
set kernel_xml_path ${build_dir}/${board}/kernel_${board_port}.xml

# --------------------------------------------------------------------------
# Copy templated sources into build/ with token substitutions.

proc copy_with_subst {src dst subs} {
    set fi [open $src r]
    set data [read $fi]
    close $fi
    foreach {token value} $subs {
        set data [string map [list $token $value] $data]
    }
    set fo [open $dst w]
    puts -nonewline $fo $data
    close $fo
}

copy_with_subst ${src_dir}/cmac_wrapper.v $wrapper_src [list \
    cmac_wrapper_TEMPLATE $wrapper_module \
    cmac_usplus_ID        $cmac_usplus \
]

copy_with_subst ${src_dir}/kernel.xml $kernel_xml_path [list \
    CMAC_KERNEL_NAME $krnl_name \
]

# --------------------------------------------------------------------------
# Vivado project + IPs

create_project -force $proj_name ${build_dir}/${proj_name} -part $board_part

proc synthesis_ip {ip_inst n_jobs} {
    upgrade_ip [get_ips $ip_inst]
    generate_target synthesis [get_ips $ip_inst]
    export_ip_user_files -of_objects [get_ips $ip_inst] -no_script -sync -force
    create_ip_run [get_ips $ip_inst]
    launch_runs ${ip_inst}_synth_1 -jobs $n_jobs
    wait_on_run ${ip_inst}_synth_1
}

# CMAC IP — pin to the physical CMAC / GT quad tied to the target QSFP28 port.
create_ip -name cmac_usplus -vendor xilinx.com -library ip \
    -module_name $cmac_usplus -dir $ip_build_dir
set_property -dict [list \
    CONFIG.CMAC_CAUI4_MODE      {1} \
    CONFIG.USER_INTERFACE       {AXIS} \
    CONFIG.ENABLE_AXI_INTERFACE {1} \
    CONFIG.GT_DRP_CLK           $ctrl_clk_freq \
    CONFIG.CMAC_CORE_SELECT     $cmac_core_select \
    CONFIG.GT_GROUP_SELECT      $gt_group_select \
    CONFIG.GT_REF_CLK_FREQ      $gt_ref_clk_freq \
    CONFIG.INCLUDE_STATISTICS_COUNTERS {1} \
    CONFIG.INCLUDE_RS_FEC              {1} \
] [get_ips $cmac_usplus]
synthesis_ip $cmac_usplus $n_jobs

# AXIS Data FIFO for AXI-clock <-> CMAC-clock CDC
set cmac_ethcdc axis_cmac_cdc
create_ip -name axis_data_fifo -vendor xilinx.com -library ip \
    -module_name $cmac_ethcdc -dir $ip_build_dir
set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES        {64} \
    CONFIG.FIFO_DEPTH             {128} \
    CONFIG.FIFO_MODE              {2} \
    CONFIG.FIFO_MEMORY_TYPE       {auto} \
    CONFIG.IS_ACLK_ASYNC          {1} \
    CONFIG.TUSER_WIDTH            {0} \
    CONFIG.HAS_TKEEP              {1} \
    CONFIG.HAS_TLAST              {1} \
    CONFIG.SYNCHRONIZATION_STAGES {6} \
] [get_ips $cmac_ethcdc]
synthesis_ip $cmac_ethcdc $n_jobs

# --------------------------------------------------------------------------
# RTL sources and constraints

add_files -norecurse [list \
    ${wrapper_src} \
    ${src_dir}/axil_cdc.v \
]
set_property top $wrapper_module [current_fileset]
update_compile_order -fileset sources_1

add_files -fileset constrs_1 -norecurse ${src_dir}/cmac_timing.xdc
set_property USED_IN {implementation} [get_files ${src_dir}/cmac_timing.xdc]

# --------------------------------------------------------------------------
# Package as IPX

set ippack_dir ${build_dir}/${krnl_name}_ippack
file mkdir ${ippack_dir}
ipx::package_project -root_dir $ippack_dir -vendor nus.edu.sg \
    -library RTLKernel -taxonomy /KernelIP -import_files
set_property name         ${krnl_name} [ipx::current_core]
set_property display_name "CMAC 100GbE Vitis kernel for ${board} ${board_port}" [ipx::current_core]
set_property description "CMAC UltraScale+ 100GbE (CAUI-4, RS-FEC) RTL kernel: 512-bit segmented AXI-Stream data path with AXI4-Lite control/status" [ipx::current_core]
set_property -dict [list \
    version                {1.0} \
    core_revision          {1} \
    sdx_kernel             {true} \
    sdx_kernel_type        {rtl} \
    supported_families     {virtexuplus Production virtexuplusHBM Production} \
    auto_family_support_level {level_2} \
    xpm_libraries          {XPM_CDC XPM_MEMORY XPM_FIFO} \
] [ipx::current_core]
set_property vitis_drc {ctrl_protocol ap_ctrl_none} [ipx::current_core]
# ap_clk runs at the platform's aclk_kernel_00 default (300 MHz) so the CMAC's
# s_axil FREQ_HZ matches the host AXI-Lite interconnect (300 MHz) and gets a
# base address. The CMAC control clocks (init_clk / s_axi_aclk / drp_clk) are
# derived from ap_clk inside cmac_wrapper.v via an MMCM at ctrl_clk_freq (100
# MHz); GT_DRP_CLK must match that slow control clock, not ap_clk.
set_property ipi_drc {ignore_freq_hz true} [ipx::current_core]
set ab [ipx::get_address_blocks reg0 \
    -of_objects [ipx::get_memory_maps s_axil \
    -of_objects [ipx::current_core]]]
set_property range 4096 $ab
# Make the s_axil address block remappable so the BD address editor assigns it
# a base address instead of excluding it ("Base Address: not_used"). Mirrors the
# HLS s_axi_control block (Vitis/common/scripts/ipxhls.tcl), which does get a
# base address: long-form immediate base address, a generated range, and
# OFFSET_BASE_PARAM/OFFSET_HIGH_PARAM pointing at writable base-address
# parameters. Without the OFFSET params the base address stays locked at 0x0,
# which does not intersect the shell control master aperture <0x0180_0000 [8M]>
# and the segment is dropped from ulp_m_axi_ctrl_user_01.
set_property width                   32        $ab
set_property access                  read-write $ab
set_property usage                   register  $ab
set_property base_address            0         $ab
set_property base_address_format     long      $ab
set_property base_address_resolve_type immediate $ab
set_property range_format            long      $ab
set_property range_resolve_type      generated $ab
set p_offbase [ipx::add_address_block_parameter s_axil_base_addr $ab]
set_property name  OFFSET_BASE_PARAM $p_offbase
set_property value C_S_AXIL_BASEADDR $p_offbase
set p_offhigh [ipx::add_address_block_parameter s_axil_high_addr $ab]
set_property name  OFFSET_HIGH_PARAM $p_offhigh
set_property value C_S_AXIL_HIGHADDR $p_offhigh

ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums  [ipx::current_core]
ipx::check_integrity -kernel -xrt [ipx::current_core]
ipx::save_core [ipx::current_core]

# --------------------------------------------------------------------------
# Emit final XO

package_xo -xo_path ${build_dir}/${krnl_name}.xo \
    -kernel_name  $krnl_name \
    -ip_directory $ippack_dir \
    -kernel_xml   $kernel_xml_path \
    -ctrl_protocol ap_ctrl_none

ipx::unload_core [ipx::current_core]
close_project
