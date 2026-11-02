`include "isa.vh"

module alu (
        input      [31:0] a,
        input      [31:0] b,
        input      [3:0]  op,
        output reg [31:0] y
    );

    // only computed signed if all operands are signed
    wire signed [31:0] sa = a;
    wire signed [31:0] sb = b;

    // dividing by 0 and -2^31 / -1 have fixed results (ISA.md 5.3)
    wire        div_zero = (b == 0);
    wire        div_ovf  = (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);
    wire [31:0] quot     = sa / sb;
    wire [31:0] rem      = sa % sb;

    always @(*) begin
        case (op)
            `ALU_PASSB: y = b;
            `ALU_ADD:   y = a + b;
            `ALU_SUB:   y = a - b;
            `ALU_AND:   y = a & b;
            `ALU_OR:    y = a | b;
            `ALU_XOR:   y = a ^ b;
            `ALU_SHL:   y = a << b[4:0];
            `ALU_SHR:   y = a >> b[4:0];
            `ALU_SRA:   y = sa >>> b[4:0];
            `ALU_SLT:   y = (sa < sb) ? 1 : 0;
            `ALU_SLTU:  y = (a < b)   ? 1 : 0;
            `ALU_MUL:   y = a * b;
            `ALU_DIV:   y = div_zero ? 32'hFFFF_FFFF : div_ovf ? 32'h8000_0000 : quot;
            `ALU_DIVU:  y = div_zero ? 32'hFFFF_FFFF : a / b;
            `ALU_MOD:   y = div_zero ? a : div_ovf ? 0 : rem;
            `ALU_MODU:  y = div_zero ? a : a % b;
        endcase
    end

endmodule
