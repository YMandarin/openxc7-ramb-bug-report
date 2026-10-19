// Single RAMB36E1 framebuffer wrapper.
//
// Port A (clk)     : 1024 x 32 bit write port (port B is read-only).
// Port B (clk_vga) : 1024 x 32 bit read port.
//
// DOB_REG selects the RAMB36E1 port B output register:
//
//   DOB_REG = 1 : use the primitive output register (fails on openXC7).
//   DOB_REG = 0 : bypass the primitive output register and register the raw
//                 DOBDO output in fabric logic instead (works).
//
// DOB_REG = 0 has one cycle of primitive read latency, while DOB_REG = 1 has
// two cycles. The extra fabric register restores the two-cycle latency, so the
// readout logic in vga_fail.sv and vga_ok.sv is identical.

module vga_memory #(
    parameter DOB_REG = 1
) (
    input  wire        clk,
    input  wire [15:0] wb_address,
    input  wire [31:0] wb_write_data,
    input  wire [ 3:0] wb_write_enable,
    output wire [31:0] wb_read_data,

    input  wire        clk_vga,
    input  wire [15:0] vga_address,
    output wire [31:0] vga_read_data
);

    wire [31:0] wb_read_raw;
    wire [31:0] vga_read_raw;

    reg [31:0] wb_read_pipeline;
    reg [31:0] vga_read_pipeline;

    // Port A is write-only in this design; keep its read path at the same
    // two-cycle latency for completeness.
    always @(posedge clk) begin
        wb_read_pipeline <= wb_read_raw;
    end

    // With DOB_REG = 0 the primitive presents data one cycle after the
    // address, so this register restores the two-cycle latency.
    always @(posedge clk_vga) begin
        vga_read_pipeline <= vga_read_raw;
    end

    assign wb_read_data  = wb_read_pipeline;
    assign vga_read_data = DOB_REG ? vga_read_raw : vga_read_pipeline;

    RAMB36E1 #(
        .DOA_REG(0),
        .DOB_REG(DOB_REG),
        .RAM_MODE("TDP"),
        .READ_WIDTH_A(36),
        .WRITE_WIDTH_A(36),
        .READ_WIDTH_B(36),
        .WRITE_WIDTH_B(0),
        .WRITE_MODE_A("READ_FIRST"),
        .WRITE_MODE_B("READ_FIRST"),
        .RDADDR_COLLISION_HWCONFIG("PERFORMANCE")
    ) ramb36e1_inst (
        .DOADO(wb_read_raw),
        .ADDRARDADDR({1'b1, wb_address[9:0], 5'b00000}),
        .CLKARDCLK(clk),
        .ENARDEN(1'b1),
        .REGCEAREGCE(1'b0),
        .RSTRAMARSTRAM(1'b0),
        .RSTREGARSTREG(1'b0),
        .WEA(wb_write_enable),
        .DIADI(wb_write_data),

        .DOBDO(vga_read_raw),
        .ADDRBWRADDR({1'b1, vga_address[9:0], 5'b00000}),
        .CLKBWRCLK(clk_vga),
        .ENBWREN(1'b1),
        .REGCEB(DOB_REG),
        .RSTRAMB(1'b0),
        .RSTREGB(1'b0),
        .WEBWE(8'b00000000),
        .DIBDI(32'b0),

        .CASCADEOUTA(),
        .CASCADEOUTB(),
        .DBITERR(),
        .ECCPARITY(),
        .RDADDRECC(),
        .SBITERR(),
        .DOPADOP(),
        .DOPBDOP(),
        .CASCADEINA(1'b0),
        .CASCADEINB(1'b0),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .DIPADIP(4'b0),
        .DIPBDIP(4'b0)
    );
endmodule
