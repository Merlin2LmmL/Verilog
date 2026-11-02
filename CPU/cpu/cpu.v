`include "isa.vh"

// single-cycle core: one instruction per clock
module cpu (
        input             clk,
        input             rst,
        output     [31:0] imem_addr,
        input      [31:0] imem_data,
        output     [31:0] dmem_addr,    // always word-aligned
        output     [31:0] dmem_wdata,
        output     [3:0]  dmem_wstrb,   // which bytes to write
        output            dmem_we,
        output            dmem_re,
        input      [31:0] dmem_rdata,
        output reg        halted,
        output reg        trapped       // halted by an illegal instruction
    );

    reg  [31:0] pc;
    wire [31:0] instr    = imem_data;
    wire [31:0] pc_plus4 = pc + 4;

    assign imem_addr = pc;

    wire [3:0]  rs1, rs2, rd, alu_op;
    wire [31:0] imm;
    wire [1:0]  wb_sel;
    wire        alu_b_imm, reg_we, mem_re, mem_we, mem_byte, mem_signed;
    wire        branch, jal, jalr, halt, illegal;

    decoder dec (
        .instr(instr),
        .rs1(rs1), .rs2(rs2), .rd(rd), .imm(imm),
        .alu_op(alu_op), .alu_b_imm(alu_b_imm),
        .reg_we(reg_we), .wb_sel(wb_sel),
        .mem_re(mem_re), .mem_we(mem_we), .mem_byte(mem_byte), .mem_signed(mem_signed),
        .branch(branch), .jal(jal), .jalr(jalr), .halt(halt), .illegal(illegal)
    );

    wire running = !halted;

    wire [31:0] rs1_val, rs2_val, wb_val;

    regfile regs (
        .clk(clk), .rst(rst),
        .ra1(rs1), .rd1(rs1_val),
        .ra2(rs2), .rd2(rs2_val),
        .we(reg_we && running), .wa(rd), .wd(wb_val)
    );

    wire [31:0] alu_y;

    alu alu_unit (
        .a(rs1_val),
        .b(alu_b_imm ? imm : rs2_val),
        .op(alu_op),
        .y(alu_y)
    );

    // "blt ra, rb" jumps if R[ra] < R[rb], and ra is on read port 2
    reg take_branch;

    always @(*) begin
        case (instr[26:24])
            3'd0:    take_branch = (rs2_val == rs1_val);                    // beq
            3'd1:    take_branch = (rs2_val != rs1_val);                    // bne
            3'd2:    take_branch = ($signed(rs2_val) <  $signed(rs1_val));  // blt
            3'd3:    take_branch = ($signed(rs2_val) >= $signed(rs1_val));  // bge
            3'd4:    take_branch = (rs2_val <  rs1_val);                    // bltu
            3'd5:    take_branch = (rs2_val >= rs1_val);                    // bgeu
            default: take_branch = 0;
        endcase
    end

    // the ALU computes the address, byte loads/stores use one of the 4 bytes of the word
    wire [1:0] lane = alu_y[1:0];

    assign dmem_addr  = {alu_y[31:2], 2'b00};
    assign dmem_re    = mem_re && running;
    assign dmem_we    = mem_we && running;
    assign dmem_wstrb = mem_byte ? (4'b0001 << lane) : 4'b1111;
    assign dmem_wdata = mem_byte ? {4{rs2_val[7:0]}} : rs2_val;

    reg [7:0] load_byte;

    always @(*) begin
        case (lane)
            2'd0: load_byte = dmem_rdata[7:0];
            2'd1: load_byte = dmem_rdata[15:8];
            2'd2: load_byte = dmem_rdata[23:16];
            2'd3: load_byte = dmem_rdata[31:24];
        endcase
    end

    wire [31:0] load_val = !mem_byte  ? dmem_rdata :
                           mem_signed ? {{24{load_byte[7]}}, load_byte} :
                                        {24'd0, load_byte};

    assign wb_val = (wb_sel == `WB_MEM) ? load_val :
                    (wb_sel == `WB_PC4) ? pc_plus4 :
                                          alu_y;

    wire [31:0] pc_next = jalr                             ? {alu_y[31:2], 2'b00} :
                          (jal || (branch && take_branch)) ? pc + imm :
                                                             pc_plus4;

    always @(posedge clk) begin
        if (rst) begin
            pc      <= 0;
            halted  <= 0;
            trapped <= 0;
        end else if (running) begin
            if (halt || illegal) begin
                halted  <= 1;    // pc stays on the halt
                trapped <= illegal;
            end else begin
                pc <= pc_next;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && running) begin
            if (illegal)
                $display("\n*** illegal instruction %08h at PC %08h", instr, pc);
            if ((mem_re || mem_we) && !mem_byte && lane != 0)
                $display("\nwarning: misaligned %s at address %08h (PC %08h)",
                         mem_we ? "st" : "ld", alu_y, pc);
        end
    end

endmodule
