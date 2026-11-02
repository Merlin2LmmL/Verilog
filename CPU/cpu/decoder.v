`include "isa.vh"

// instruction -> control signals
module decoder (
        input      [31:0] instr,
        output     [3:0]  rs1,         // field B
        output     [3:0]  rs2,         // field C (R-type) or A (store, branch)
        output     [3:0]  rd,          // field A
        output reg [31:0] imm,
        output reg [3:0]  alu_op,
        output reg        alu_b_imm,   // ALU b = imm instead of rs2
        output reg        reg_we,
        output reg [1:0]  wb_sel,
        output reg        mem_re,
        output reg        mem_we,
        output reg        mem_byte,
        output reg        mem_signed,
        output reg        branch,
        output reg        jal,
        output reg        jalr,
        output reg        halt,
        output reg        illegal
    );

    wire [7:0]  op    = instr[31:24];
    wire [3:0]  a     = instr[23:20];
    wire [3:0]  b     = instr[19:16];
    wire [3:0]  c     = instr[15:12];
    wire [15:0] imm16 = instr[15:0];
    wire [19:0] imm20 = instr[19:0];

    reg rs2_is_c;

    assign rs1 = b;
    assign rs2 = rs2_is_c ? c : a;
    assign rd  = a;

    always @(*) begin
        // defaults first, so nothing becomes a latch
        imm        = {{16{imm16[15]}}, imm16};
        alu_op     = `ALU_ADD;
        alu_b_imm  = 0;
        reg_we     = 0;
        wb_sel     = `WB_ALU;
        mem_re     = 0;
        mem_we     = 0;
        mem_byte   = 0;
        mem_signed = 0;
        branch     = 0;
        jal        = 0;
        jalr       = 0;
        halt       = 0;
        illegal    = 0;
        rs2_is_c   = 0;

        case (op)
            `OP_ADD, `OP_SUB, `OP_AND, `OP_OR, `OP_XOR,
            `OP_SHL, `OP_SHR, `OP_SRA, `OP_SLT, `OP_SLTU: begin
                alu_op   = op[3:0];
                rs2_is_c = 1;
                reg_we   = 1;
            end
            `OP_MUL:  begin alu_op = `ALU_MUL;  rs2_is_c = 1; reg_we = 1; end
            `OP_DIV:  begin alu_op = `ALU_DIV;  rs2_is_c = 1; reg_we = 1; end
            `OP_DIVU: begin alu_op = `ALU_DIVU; rs2_is_c = 1; reg_we = 1; end
            `OP_MOD:  begin alu_op = `ALU_MOD;  rs2_is_c = 1; reg_we = 1; end
            `OP_MODU: begin alu_op = `ALU_MODU; rs2_is_c = 1; reg_we = 1; end

            `OP_ADDI, `OP_SHLI, `OP_SHRI, `OP_SRAI, `OP_SLTI, `OP_SLTIU: begin
                alu_op    = op[3:0];
                alu_b_imm = 1;
                reg_we    = 1;
            end
            `OP_ANDI, `OP_ORI, `OP_XORI: begin
                alu_op    = op[3:0];
                imm       = {16'd0, imm16};    // zero-extended
                alu_b_imm = 1;
                reg_we    = 1;
            end
            `OP_LUI: begin
                alu_op    = `ALU_PASSB;
                imm       = {imm16, 16'd0};
                alu_b_imm = 1;
                reg_we    = 1;
            end

            `OP_LD, `OP_LDB, `OP_LDBU: begin   // the ALU adds rs + imm for the address
                alu_b_imm  = 1;
                mem_re     = 1;
                mem_byte   = (op != `OP_LD);
                mem_signed = (op == `OP_LDB);
                reg_we     = 1;
                wb_sel     = `WB_MEM;
            end
            `OP_ST, `OP_STB: begin
                alu_b_imm = 1;
                mem_we    = 1;
                mem_byte  = (op == `OP_STB);
            end

            `OP_BEQ, `OP_BNE, `OP_BLT, `OP_BGE, `OP_BLTU, `OP_BGEU: begin
                branch = 1;
                imm    = {{14{imm16[15]}}, imm16, 2'b00};   // instructions -> bytes
            end
            `OP_JAL: begin
                jal    = 1;
                imm    = {{10{imm20[19]}}, imm20, 2'b00};
                reg_we = 1;
                wb_sel = `WB_PC4;
            end
            `OP_JALR: begin
                jalr      = 1;
                alu_b_imm = 1;
                reg_we    = 1;
                wb_sel    = `WB_PC4;
            end

            `OP_HALT: halt    = 1;
            default:  illegal = 1;
        endcase
    end

endmodule
