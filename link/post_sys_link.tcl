# Post-sys-link overlay Tcl for v++.
#
# The Vitis U50 xdma_5 platform's ULP block design ALREADY has two shell-side
# interface_ports wired to the physical QSFP0 cage:
#   * io_gt_qsfp_00           (xilinx.com:interface:gt_rtl:1.0)
#   * io_clk_qsfp_refclka_00  (xilinx.com:interface:diff_clock_rtl:1.0)
# See ext_metadata.json in the platform hw.xsa. These are visible in the
# ULP BD but are unconnected until we bind the CMAC kernel's matching
# intf pins to them here. `--connectivity.sp` in cmac_krnl.cfg only handles
# memory sptags, not GT interfaces, so we do it via BD API.

set bd [current_bd_design]
puts "post_sys_link: opened BD '$bd'"

# Map: kernel intf pin (on cmac_0)  ->  shell interface_port
set connections {
    gt_serial_port  io_gt_qsfp_00
    gt_refclk       io_clk_qsfp_refclka_00
}

foreach cell [get_bd_cells -filter { VLNV =~ "nus.edu.sg:RTLKernel:cmac_*" }] {
    puts "post_sys_link: wiring GT interfaces on $cell"

    foreach {kern_pin plat_port} $connections {
        set pin  [get_bd_intf_pins  -quiet $cell/$kern_pin]
        set port [get_bd_intf_ports -quiet /$plat_port]
        if {[llength $pin] == 0} {
            puts "post_sys_link: WARNING: $cell/$kern_pin not found; skipping"
            continue
        }
        if {[llength $port] == 0} {
            puts "post_sys_link: WARNING: shell interface_port /$plat_port not found; skipping"
            continue
        }
        puts "post_sys_link:   connect_bd_intf_net $pin <-> $port"
        connect_bd_intf_net $pin $port
    }
}

validate_bd_design
save_bd_design
puts "post_sys_link: done"
