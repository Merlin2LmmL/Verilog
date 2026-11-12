// Opcodes, ALU codes and memory map (see ../ISA.md)
`ifndef ISA_VH
`define ISA_VH

// alu, register
`define OP_ADD   8'h01
`define OP_SUB   8'h02
`define OP_AND   8'h03
`define OP_OR    8'h04
`define OP_XOR   8'h05
`define OP_SHL   8'h06
`define OP_SHR   8'h07
`define OP_SRA   8'h08
`define OP_SLT   8'h09
`define OP_SLTU  8'h0A
// alu, immediate
`define OP_ADDI  8'h11
`define OP_ANDI  8'h13
`define OP_ORI   8'h14
`define OP_XORI  8'h15
`define OP_SHLI  8'h16
`define OP_SHRI  8'h17
`define OP_SRAI  8'h18
`define OP_SLTI  8'h19
`define OP_SLTIU 8'h1A
`define OP_LUI   8'h1F
// mul / div
`define OP_MUL   8'h20
`define OP_DIV   8'h24
`define OP_DIVU  8'h25
`define OP_MOD   8'h26
`define OP_MODU  8'h27
// load / store
`define OP_LD    8'h30
`define OP_LDB   8'h31
`define OP_LDBU  8'h32
`define OP_ST    8'h38
`define OP_STB   8'h39
// branches
`define OP_BEQ   8'h40
`define OP_BNE   8'h41
`define OP_BLT   8'h42
`define OP_BGE   8'h43
`define OP_BLTU  8'h44
`define OP_BGEU  8'h45
// jumps
`define OP_JAL   8'h50
`define OP_JALR  8'h51
`define OP_HALT  8'hFF

// ALU ops. 1-A are the low digit of the opcode (add = 01 and addi = 11 -> 1)
`define ALU_PASSB 4'h0
`define ALU_ADD   4'h1
`define ALU_SUB   4'h2
`define ALU_AND   4'h3
`define ALU_OR    4'h4
`define ALU_XOR   4'h5
`define ALU_SHL   4'h6
`define ALU_SHR   4'h7
`define ALU_SRA   4'h8
`define ALU_SLT   4'h9
`define ALU_SLTU  4'hA
`define ALU_MUL   4'hB
`define ALU_DIV   4'hC
`define ALU_DIVU  4'hD
`define ALU_MOD   4'hE
`define ALU_MODU  4'hF

// what gets written back to rd
`define WB_ALU 2'd0
`define WB_MEM 2'd1
`define WB_PC4 2'd2

// memory map
`define RAM_END     32'h0004_0000
`define FB_BASE     32'hFFFD_0000
`define FB_END      32'hFFFD_3000   // 128 * 96 pixels * 1 byte
`define SCREEN_BASE 32'hFFFE_0000
`define SCREEN_END  32'hFFFE_0FA0   // 40 * 25 cells * 4 bytes
`define IO_BASE     32'hFFFF_0000

`endif
