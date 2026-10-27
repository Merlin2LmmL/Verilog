// Self-checking testbench for unary_reduction.v
`timescale 1ns/1ps
`include "unary_reduction.v"

module unary_reduction_tb;
    reg  [3:0] in;
    wire       out_and, out_or, out_xor;
    integer i, j, ones, errors = 0;

    top_module dut (.in(in), .out_and(out_and), .out_or(out_or), .out_xor(out_xor));

    task run;
        for (i = 0; i < 16; i = i + 1) begin
            in = i[3:0];
            #10;
            ones = 0;
            for (j = 0; j < 4; j = j + 1) ones = ones + in[j];
            if (out_and !== (ones == 4) || out_or !== (ones > 0) || out_xor !== ones[0]) begin
                $display("FAIL in=%b and=%b or=%b xor=%b", in, out_and, out_or, out_xor);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("unary_reduction.vcd");
        $dumpvars(0, unary_reduction_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
