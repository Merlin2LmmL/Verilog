// Self-checking testbench for addsub32.v
`timescale 1ns/1ps
`include "addsub32.v"

module addsub32_tb;
    reg  [31:0] a, b;
    reg         sub;
    wire [31:0] sum;
    integer i, errors = 0;

    top_module dut (.a(a), .b(b), .sub(sub), .sum(sum));

    task check;
        input [31:0] x, y;
        input        s;
        begin
            a = x; b = y; sub = s;
            #10;
            if (sum !== (s ? x - y : x + y)) begin
                $display("FAIL %h %s %h = %h (expected %h)", a, s ? "-" : "+", b, sum, s ? x - y : x + y);
                errors = errors + 1;
            end
        end
    endtask

    task run;
        begin
            check(32'h00000000, 32'h00000001, 1);   // borrow across the whole word
            check(32'h00010000, 32'h00000001, 1);   // borrow across the 16-bit boundary
            check(32'h0000FFFF, 32'h00000001, 0);   // carry across the 16-bit boundary
            for (i = 0; i < 200; i = i + 1) check($urandom, $urandom, i[0]);
        end
    endtask

    initial begin
        $dumpfile("addsub32.vcd");
        $dumpvars(0, addsub32_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
