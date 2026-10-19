# Build the two bug-report targets with Vivado.
#
# Usage:
#   vivado -mode batch -source vivado.tcl
#   vivado -mode batch -source vivado.tcl -tclargs vga_fail
#
# The bitstreams are written to build/vivado/vga_fail.bit and
# build/vivado/vga_ok.bit.

set ROOT [file normalize [file dirname [info script]]]
set BUILD_DIR [file join $ROOT build vivado]
file mkdir $BUILD_DIR

set PART    xc7a35tcpg236-1
set SOURCES [list [file join $ROOT clk_gen.v] [file join $ROOT vga_memory.v]]
set XDC     [file join $ROOT basys3.xdc]

if {[llength $argv] > 0} {
    set TOPS $argv
} else {
    set TOPS [list vga_fail vga_ok]
}

# Keep the log readable.
set_msg_config -id {Synth 8-7080} -suppress
set_msg_config -id {Synth 8-6014} -suppress

foreach top $TOPS {

    puts "================================================"
    puts "Building $top"
    puts "================================================"

    read_verilog -sv [concat $SOURCES [list [file join $ROOT $top.sv]]]
    read_xdc $XDC

    synth_design -top $top -part $PART
    opt_design
    place_design
    phys_opt_design
    route_design
    phys_opt_design

    write_bitstream -force [file join $BUILD_DIR $top.bit]

    close_design
}

puts "Done. Bitstreams are in $BUILD_DIR"
