// 16 registers, r0 is always 0
module regfile (
        input         clk,
        input         rst,
        input  [3:0]  ra1,
        output [31:0] rd1,
        input  [3:0]  ra2,
        output [31:0] rd2,
        input         we,
        input  [3:0]  wa,
        input  [31:0] wd
    );

    reg [31:0] regs [0:15];
    integer i;

    assign rd1 = (ra1 == 0) ? 0 : regs[ra1];
    assign rd2 = (ra2 == 0) ? 0 : regs[ra2];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1)
                regs[i] <= 0;
        end else if (we && wa != 0) begin
            regs[wa] <= wd;
        end
    end

    // gtkwave can't show arrays, so copy them out
    wire [31:0] r1  = regs[1],  r2  = regs[2],  r3  = regs[3],  r4  = regs[4];
    wire [31:0] r5  = regs[5],  r6  = regs[6],  r7  = regs[7],  r8  = regs[8];
    wire [31:0] r9  = regs[9],  r10 = regs[10], r11 = regs[11], r12 = regs[12];
    wire [31:0] r13 = regs[13], sp  = regs[14], lr  = regs[15];

endmodule
