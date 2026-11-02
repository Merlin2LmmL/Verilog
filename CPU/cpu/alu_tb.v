`timescale 1ns/1ps
`include "alu.v"

module alu_tb;

    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] y;
    integer errors = 0;

    alu dut (.a(a), .b(b), .op(op), .y(y));

    task check;
        input [3:0]  t_op;
        input [31:0] t_a, t_b, expected;
        begin
            op = t_op;
            a  = t_a;
            b  = t_b;
            #10;
            if (y !== expected) begin
                $display("FAIL op=%h a=%h b=%h: y=%h, expected %h", t_op, t_a, t_b, y, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("alu.vcd");
        $dumpvars(0, alu_tb);

        check(`ALU_PASSB, 32'h1234, 32'hABCD0000, 32'hABCD0000);
        check(`ALU_ADD,   7, -3, 4);
        check(`ALU_ADD,   32'hFFFF_FFFF, 1, 0);
        check(`ALU_SUB,   7, -3, 10);
        check(`ALU_SUB,   0, 1, 32'hFFFF_FFFF);
        check(`ALU_AND,   32'hF0F0_F0F0, 32'h0FF0_0FF0, 32'h00F0_00F0);
        check(`ALU_OR,    32'hF0F0_F0F0, 32'h0FF0_0FF0, 32'hFFF0_FFF0);
        check(`ALU_XOR,   32'hF0F0_F0F0, 32'h0FF0_0FF0, 32'hFF00_FF00);
        check(`ALU_SHL,   32'h8000_0001, 4,  32'h0000_0010);
        check(`ALU_SHL,   32'h8000_0001, 33, 32'h0000_0002);    // only b[4:0] counts
        check(`ALU_SHR,   32'h8000_0001, 4,  32'h0800_0000);
        check(`ALU_SRA,   32'h8000_0001, 4,  32'hF800_0000);
        check(`ALU_SRA,   32'h4000_0000, 4,  32'h0400_0000);
        check(`ALU_SLT,   -3, 7, 1);
        check(`ALU_SLT,   7, -3, 0);
        check(`ALU_SLT,   5, 5, 0);
        check(`ALU_SLTU,  -3, 7, 0);
        check(`ALU_SLTU,  7, -3, 1);
        check(`ALU_MUL,   7, -3, -21);
        check(`ALU_MUL,   32'h0001_0000, 32'h0001_0000, 0);
        check(`ALU_DIV,   -21, 4, -5);
        check(`ALU_DIV,   21, -4, -5);
        check(`ALU_DIV,   -21, 0, 32'hFFFF_FFFF);
        check(`ALU_DIV,   32'h8000_0000, -1, 32'h8000_0000);
        check(`ALU_DIVU,  32'hFFFF_FFFE, 2, 32'h7FFF_FFFF);
        check(`ALU_DIVU,  5, 0, 32'hFFFF_FFFF);
        check(`ALU_MOD,   -21, 4, -1);
        check(`ALU_MOD,   21, -4, 1);
        check(`ALU_MOD,   -21, 0, -21);
        check(`ALU_MOD,   32'h8000_0000, -1, 0);
        check(`ALU_MODU,  32'hFFFF_FFFF, 10, 5);
        check(`ALU_MODU,  -21, 0, -21);

        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
