// Clock generation for the bug report.
//
//   clk     : 50.000 MHz  (MMCM: 100 MHz * 10 / 1 / 20)
//   clk_vga : 25.175 MHz  (PLL1: 106 MHz, PLL2: 106 MHz * 19 / 2 / 40)
//
// The intermediate 106 MHz clock feeds the VGA PLL.

module clk_gen (
    input  wire clk_100mhz,
    output wire clk,
    output wire clk_vga
);
    // Input oscillator: 100 MHz, 95 ps jitter.
    localparam real INPUT_CLK_PERIOD_NS = 10.000;
    localparam real REF_JITTER          = 0.010;

    // MMCM: 100 MHz / 1 * 10 / 20 = 50 MHz.
    localparam real MMCM_MUL   = 10.000;
    localparam int  MMCM_DIV   = 1;
    localparam real MMCM_DIV_0 = 20.000;

    // PLL1: 100 MHz / 5 * 53 / 10 = 106 MHz.
    localparam int  PLL1_MUL   = 53;
    localparam int  PLL1_DIV   = 5;
    localparam int  PLL1_DIV_0 = 10;

    // PLL2: 106 MHz / 2 * 19 / 40 = 25.175 MHz.
    localparam int  PLL2_MUL   = 19;
    localparam int  PLL2_DIV   = 2;
    localparam int  PLL2_DIV_0 = 40;

    // 1000 / 106 = 9.433962 ns.
    localparam real PLL1_PERIOD_NS = 9.433962;

    wire clk_fb;
    wire clk_106mhz, clk_106mhz_fb;
    wire clk_106mhz_buf;
    wire clk_vga_fb;

    MMCME2_BASE #(
        .CLKFBOUT_MULT_F(MMCM_MUL),
        .CLKIN1_PERIOD(INPUT_CLK_PERIOD_NS),
        .CLKOUT0_DIVIDE_F(MMCM_DIV_0),
        .DIVCLK_DIVIDE(MMCM_DIV),
        .REF_JITTER1(REF_JITTER),
        .STARTUP_WAIT("TRUE")
    ) mmcm (
        .CLKIN1(clk_100mhz),
        .CLKOUT0(clk),
        .CLKFBOUT(clk_fb),
        .CLKFBIN(clk_fb),
        .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUTB(), .LOCKED(),
        .PWRDWN(1'b0), .RST(1'b0)
    );

    PLLE2_BASE #(
        .CLKIN1_PERIOD(INPUT_CLK_PERIOD_NS),
        .DIVCLK_DIVIDE(PLL1_DIV),
        .CLKFBOUT_MULT(PLL1_MUL),
        .CLKOUT0_DIVIDE(PLL1_DIV_0),
        .REF_JITTER1(REF_JITTER),
        .STARTUP_WAIT("TRUE")
    ) pll_vga_0 (
        .CLKIN1(clk_100mhz),
        .CLKOUT0(clk_106mhz),
        .CLKFBOUT(clk_106mhz_fb),
        .CLKFBIN(clk_106mhz_fb),
        .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(), .PWRDWN(1'b0), .RST(1'b0)
    );

    BUFG BUFG_106mhz (.I(clk_106mhz), .O(clk_106mhz_buf));

    PLLE2_BASE #(
        .CLKIN1_PERIOD(PLL1_PERIOD_NS),
        .DIVCLK_DIVIDE(PLL2_DIV),
        .CLKFBOUT_MULT(PLL2_MUL),
        .CLKOUT0_DIVIDE(PLL2_DIV_0),
        .REF_JITTER1(REF_JITTER),
        .STARTUP_WAIT("TRUE")
    ) pll_vga_1 (
        .CLKIN1(clk_106mhz_buf),
        .CLKOUT0(clk_vga),
        .CLKFBOUT(clk_vga_fb),
        .CLKFBIN(clk_vga_fb),
        .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(), .PWRDWN(1'b0), .RST(1'b0)
    );
endmodule
