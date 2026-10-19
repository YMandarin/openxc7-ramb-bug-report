// WORKING target: the framebuffer bypasses the RAMB36E1 port B output
// register (DOB_REG = 0) and re-registers the raw output in fabric logic.
//
// openXC7/nextpnr : 10 vertical color bars.
// Vivado          : 10 vertical color bars.

module vga_ok (
    // 100 MHz board oscillator
    input  logic       clk_100mhz,

    // VGA output
    output logic [3:0] vga_red,
    output logic [3:0] vga_blue,
    output logic [3:0] vga_green,
    output logic       vga_hsync,
    output logic       vga_vsync
);

    logic clk;
    logic clk_vga;

    clk_gen clk_gen_inst (
        .clk_100mhz(clk_100mhz),
        .clk(clk),
        .clk_vga(clk_vga)
    );

    // ------------------------------------------------------------------
    // Framebuffer write side (50 MHz)
    // ------------------------------------------------------------------
    // Continuously write all 1024 words with a color that depends on the
    // address. Every address always receives the same value, so the display is
    // stable even though the write side keeps running.

    logic [9:0] fill_address;

    always_ff @(posedge clk) begin
        fill_address <= fill_address + 1'b1;
    end

    logic [3:0] fill_color;
    assign fill_color = fill_address[6:3] + 4'd1;

    logic [15:0] vga_address;
    logic [31:0] vga_read_data;

    vga_memory #(
        .DOB_REG(0)
    ) vga_memory_inst (
        .clk(clk),
        .wb_address({6'b0, fill_address}),
        .wb_write_data({8{fill_color}}),
        .wb_write_enable(4'b1111),
        .wb_read_data(),

        .clk_vga(clk_vga),
        .vga_address(vga_address),
        .vga_read_data(vga_read_data)
    );

    // ------------------------------------------------------------------
    // VGA timing (640x480 @ 60 Hz, 25.175 MHz pixel clock)
    // ------------------------------------------------------------------
    localparam LINE_WIDTH        = 640;
    localparam LINE_FRONT_PORCH  = 16;
    localparam LINE_SYNC_PULSE   = 96;
    localparam LINE_BACK_PORCH   = 48;

    localparam FRAME_HEIGHT      = 480;
    localparam FRAME_FRONT_PORCH = 10;
    localparam FRAME_SYNC_PULSE  = 2;
    localparam FRAME_BACK_PORCH  = 33;

    localparam COLUMN_MAX = LINE_WIDTH + LINE_FRONT_PORCH + LINE_SYNC_PULSE + LINE_BACK_PORCH - 1;
    localparam ROW_MAX    = FRAME_HEIGHT + FRAME_FRONT_PORCH + FRAME_SYNC_PULSE + FRAME_BACK_PORCH - 1;

    logic [9:0] column;
    logic [9:0] row;

    always_ff @(posedge clk_vga) begin
        if (column < COLUMN_MAX) begin
            column <= column + 1'b1;
        end else begin
            column <= 0;

            if (row < ROW_MAX) begin
                row <= row + 1'b1;
            end else begin
                row <= 0;
            end
        end
    end

    logic hsync;
    always_ff @(posedge clk_vga) begin
        if (column < LINE_WIDTH + LINE_FRONT_PORCH) begin
            hsync <= 1'b1;
        end else if (column < LINE_WIDTH + LINE_FRONT_PORCH + LINE_SYNC_PULSE) begin
            hsync <= 1'b0;
        end else begin
            hsync <= 1'b1;
        end
    end

    logic vsync;
    always_ff @(posedge clk_vga) begin
        if (row < FRAME_HEIGHT + FRAME_FRONT_PORCH) begin
            vsync <= 1'b1;
        end else if (row < FRAME_HEIGHT + FRAME_FRONT_PORCH + FRAME_SYNC_PULSE) begin
            vsync <= 1'b0;
        end else begin
            vsync <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Framebuffer read side
    // ------------------------------------------------------------------
    // Each word holds eight pixels. The read address only covers the first
    // 80 words, which are filled with 10 different colors (8 words per bar).

    assign vga_address = {6'b0, column[9:3]};

    // The RAMB read path has two cycles of latency. Delay draw and the pixel
    // offset by the same amount.
    logic       draw_d1;
    logic       draw_d2;
    logic [4:0] pixel_offset_d1;
    logic [4:0] pixel_offset_d2;

    always_ff @(posedge clk_vga) begin
        draw_d1         <= column < LINE_WIDTH && row < FRAME_HEIGHT;
        draw_d2         <= draw_d1;
        pixel_offset_d1 <= {column[2:0], 2'b0};
        pixel_offset_d2 <= pixel_offset_d1;
    end

    logic [31:0] vga_read_data_shifted;
    logic [ 3:0] pixel;

    assign vga_read_data_shifted = vga_read_data >> pixel_offset_d2;
    assign pixel = vga_read_data_shifted[3:0];

    logic [3:0] r;
    logic [3:0] g;
    logic [3:0] b;

    always_comb begin
        case (pixel)
            4'd0:    begin r = 4'h0; g = 4'h0; b = 4'h0; end
            4'd1:    begin r = 4'h0; g = 4'h0; b = 4'hF; end
            4'd2:    begin r = 4'h0; g = 4'hF; b = 4'h0; end
            4'd3:    begin r = 4'h0; g = 4'hF; b = 4'hF; end
            4'd4:    begin r = 4'hF; g = 4'h0; b = 4'h0; end
            4'd5:    begin r = 4'hF; g = 4'h0; b = 4'hF; end
            4'd6:    begin r = 4'hF; g = 4'h7; b = 4'h0; end
            4'd7:    begin r = 4'hF; g = 4'hF; b = 4'hF; end
            4'd8:    begin r = 4'h7; g = 4'h7; b = 4'h7; end
            4'd9:    begin r = 4'h7; g = 4'h7; b = 4'hF; end
            4'd10:   begin r = 4'h7; g = 4'hF; b = 4'h7; end
            4'd11:   begin r = 4'h7; g = 4'hF; b = 4'hF; end
            4'd12:   begin r = 4'hF; g = 4'h7; b = 4'h7; end
            4'd13:   begin r = 4'hF; g = 4'h7; b = 4'hF; end
            4'd14:   begin r = 4'hF; g = 4'hF; b = 4'h7; end
            default: begin r = 4'h0; g = 4'h0; b = 4'h0; end
        endcase
    end

    // ------------------------------------------------------------------
    // Output registers
    // ------------------------------------------------------------------
    // hsync/vsync are already registered once, so one more stage aligns them
    // with the two-cycle memory latency plus the output register below.

    logic hsync_d1;
    logic vsync_d1;

    always_ff @(posedge clk_vga) begin
        hsync_d1  <= hsync;
        vsync_d1  <= vsync;
        vga_hsync <= hsync_d1;
        vga_vsync <= vsync_d1;
        vga_red   <= draw_d2 ? r : 4'h0;
        vga_green <= draw_d2 ? g : 4'h0;
        vga_blue  <= draw_d2 ? b : 4'h0;
    end
endmodule
