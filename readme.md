# RAMB36E1 `DOB_REG` bug in openXC7

## Summary

A RAMB36E1 used as a VGA framebuffer does not output any data when its port B
output register is enabled (`DOB_REG = 1`) and the design is built with the
openXC7 flow. The same RTL built with Vivado works.

Disabling `DOB_REG` and re-registering the raw `DOBDO` output in fabric logic is
a workaround and works with both toolchains. Both configurations have the same
two-cycle read latency, so the rest of the pixel pipeline is unchanged.

This directory contains a minimal, single-block reproducer:

| Target      | RAMB36E1 configuration                                | openXC7        | Vivado         |
|-------------|-------------------------------------------------------|----------------|----------------|
| `vga_fail`  | `DOB_REG = 1`, output register in the primitive       | black screen   | color bars     |
| `vga_ok`    | `DOB_REG = 0`, registered output in fabric logic       | color bars     | color bars     |

If the BRAM works, the monitor shows ten vertical color bars:

    blue, green, cyan, red, magenta, orange, white, gray, light blue, light green

The failing target produces a completely black picture.

## Background

The test design stores a 1024 x 32 bit framebuffer in one RAMB36E1. Port A is
written from the system clock and port B is read from the VGA pixel clock:

* `clk` = 50 MHz (MMCM output; 100 MHz input / 2)
* `clk_vga` = 25.175 MHz (pixel clock for 640x480 @ 60 Hz)

The port B output register is the only variable between the two targets. With
the optional BRAM output register enabled (`DOB_REG = 1`), the primitive
provides the registered read data directly. A RAMB36E1 read has:

* `DOB_REG = 0`: one clock cycle of latency
* `DOB_REG = 1`: two clock cycles of latency

The `vga_ok` workaround uses `DOB_REG = 0` plus one external register, which
restores the two-cycle latency and makes the readout logic identical in both
targets.

`DOA_REG` is 0 in both targets, and the port A read output is unused.

## Files

| File            | Purpose                                                        |
|-----------------|----------------------------------------------------------------|
| `basys3.xdc`    | Basys 3 pins for the 100 MHz clock and the VGA connector       |
| `clk_gen.v`     | MMCM/PLL clock generation (self-contained)                     |
| `vga_memory.v`  | Single RAMB36E1 wrapper with the `DOB_REG` parameter           |
| `vga_fail.sv`   | Top level using `DOB_REG = 1`                                  |
| `vga_ok.sv`     | Top level using `DOB_REG = 0` plus a fabric re-register        |
| `Makefile`      | openXC7 build for both targets, plus a Vivado target           |
| `vivado.tcl`    | Vivado batch build for both targets                            |

## Build with openXC7

The default toolchain location is `/opt/openxc7`. Override it if necessary:

```sh
make OPENXC7=/path/to/openxc7
```

Build both targets:

```sh
make
```

or only one of them:

```sh
make vga_fail
make vga_ok
```

The bitstreams are written to:

```
build/openxc7/vga_fail.bit
build/openxc7/vga_ok.bit
```

The first build also generates the nextpnr chip database in `build/chipdb`
(about 29 MB). The flow is:

```
*.v/*.sv --[yosys]--> *.yosys.json --[nextpnr-xilinx]--> *.fasm --[fpga-as]--> *.bit
```

The Makefile sources `/opt/openxc7/export.sh` for every tool invocation, so no
environment setup is required in the calling shell.

Program a target with openFPGALoader, for example:

```sh
openFPGALoader -b basys3 build/openxc7/vga_fail.bit
```

## Build with Vivado

```sh
make vivado
```

or directly:

```sh
vivado -mode batch -source vivado.tcl
```

The bitstreams are written to `build/vivado/vga_fail.bit` and
`build/vivado/vga_ok.bit`, so they do not overwrite the openXC7 results. To
build only one target:

```sh
vivado -mode batch -source vivado.tcl -tclargs vga_fail
```

If Vivado is not in `PATH`, override it:

```sh
make vivado VIVADO=/path/to/vivado
```

## Expected and observed behavior

Expected for both targets:

* a stable 640x480 @ 60 Hz picture
* ten vertical color bars over the whole visible area

Observed:

* `build/openxc7/vga_fail.bit`: black screen
* `build/vivado/vga_fail.bit`: ten color bars
* `build/openxc7/vga_ok.bit`: ten color bars
* `build/vivado/vga_ok.bit`: ten color bars

## Evidence in the generated bitstream

The parameter is not lost during synthesis. The intermediate FASM files are
kept because the Makefile marks them as secondary targets. After `make`:

```sh
grep -E 'DOB_REG|ZINV_REGCLKB' build/openxc7/vga_fail.fasm
grep -E 'DOB_REG|ZINV_REGCLKB' build/openxc7/vga_ok.fasm
```

For the failing build this reports the port B output-register configuration:

```
BRAM_L_X6Y45.RAMB18_Y0.DOB_REG
BRAM_L_X6Y45.RAMB18_Y0.ZINV_REGCLKB
BRAM_L_X6Y45.RAMB18_Y1.DOB_REG
BRAM_L_X6Y45.RAMB18_Y1.ZINV_REGCLKB
```

The working build has none of these features. The tile coordinates can change
between runs; the important part is that `vga_fail` emits `DOB_REG` and
`vga_ok` does not. In the nextpnr JSON, `vga_fail` has `DOB_REG = 1` and
`vga_ok` has `DOB_REG = 0`.

This shows that nextpnr accepts the primitive parameter and emits the
corresponding bits. The data nevertheless does not reach the VGA output on
hardware. The `ZINV_REGCLKB` bit (register clock inversion) is a likely place
to look, together with the `REGCEB`/reset routing of the output register.

## Workaround

Use `DOB_REG = 0` and add one register on the raw `DOBDO` output:

```verilog
always @(posedge clk_vga) begin
    vga_read_pipeline <= vga_read_raw;
end

assign vga_read_data = DOB_REG ? vga_read_raw : vga_read_pipeline;
```

This is what `vga_memory.v` does and what `vga_ok.sv` selects. The extra fabric
register costs very little and gives the same two-cycle latency as the built-in
output register.

## Environment used

* Basys 3 (`xc7a35tcpg236-1`)
* openXC7 in `/opt/openxc7`
* Yosys 0.69
* nextpnr-himbaechel 1.0.0-41-g3e5c2cdd (through the `nextpnr-xilinx` shim)
* Vivado 2026.1
