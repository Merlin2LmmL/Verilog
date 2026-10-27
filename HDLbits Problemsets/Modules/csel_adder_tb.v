// Self-checking testbench for csel_adder.v
`timescale 1ns/1ps
`include "csel_adder.v"

module csel_adder_tb;
    reg  [31:0] a, b;
    wire [31:0] sum;
    integer i, errors = 0;

    top_module dut (.a(a), .b(b), .sum(sum));

    task check;
        input [31:0] x, y;
        begin
            a = x; b = y;
            #10;
            if (sum !== x + y) begin
                $display("FAIL %h + %h = %h (expected %h)", a, b, sum, x + y);
                errors = errors + 1;
            end
        end
    endtask

    task run;
        begin
            check(32'h0000FFFF, 32'h00000001);   // carry from low half into high half
            check(32'hFFFFFFFF, 32'h00000001);   // wraps to 0
            check(32'h00000000, 32'h00000000);
            check(32'h7FFFFFFF, 32'h7FFFFFFF);
            for (i = 0; i < 200; i = i + 1) check($urandom, $urandom);
        end
    endtask

    initial begin
        $dumpfile("csel_adder.vcd");
        $dumpvars(0, csel_adder_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
