`include "isa.vh"

// cpu + ROM + RAM + screen + io, memory map in ISA.md section 7
module soc (
        input         clk,
        input         rst,
        output        halted,
        output        trapped,
        output [31:0] leds
    );

    wire [31:0] imem_addr, imem_data;

    wire [31:0] addr, wdata, rdata;
    wire [3:0]  wstrb;
    wire        we, re;

    cpu core (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data),
        .dmem_addr(addr), .dmem_wdata(wdata), .dmem_wstrb(wstrb),
        .dmem_we(we), .dmem_re(re), .dmem_rdata(rdata),
        .halted(halted), .trapped(trapped)
    );

    imem rom (
        .addr(imem_addr),
        .data(imem_data)
    );

    // address decoder
    wire sel_ram    = addr < `RAM_END;
    wire sel_screen = addr >= `SCREEN_BASE && addr < `SCREEN_END;
    wire sel_io     = (addr & 32'hFFFF_FF00) == `IO_BASE;

    wire [31:0] ram_rdata, screen_rdata, io_rdata;
    wire        screen_show;

    ram data_ram (
        .clk(clk),
        .addr(addr), .wdata(wdata), .wstrb(wstrb),
        .we(we && sel_ram),
        .rdata(ram_rdata)
    );

    screen text_screen (
        .clk(clk),
        .index(addr[11:2]), .wdata(wdata), .wstrb(wstrb),
        .we(we && sel_screen),
        .rdata(screen_rdata),
        .show(screen_show)
    );

    io io_regs (
        .clk(clk), .rst(rst),
        .offset(addr[7:0]), .wdata(wdata),
        .we(we && sel_io), .re(re && sel_io),
        .rdata(io_rdata),
        .screen_show(screen_show),
        .leds(leds)
    );

    assign rdata = sel_ram    ? ram_rdata    :
                   sel_screen ? screen_rdata :
                   sel_io     ? io_rdata     :
                                0;

    always @(posedge clk) begin
        if (!rst && (we || re) && !(sel_ram || sel_screen || sel_io))
            $display("\nwarning: %s unmapped address %08h (PC %08h)",
                     we ? "store to" : "load from", addr, imem_addr);
    end

endmodule
