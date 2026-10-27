// Self-checking testbench for vectorgates.v
`timescale 1ns/1ps
`include "vectorgates.v"

module vectorgates_tb;
    reg  [2:0] a, b;
    wire [2:0] out_or_bitwise;
    wire       out_or_logical;
    wire [5:0] out_not;
    integer i, errors = 0;

    top_module dut (
        .a(a), .b(b),
        .out_or_bitwise(out_or_bitwise),
        .out_or_logical(out_or_logical),
        .out_not(out_not)
    );

    // all 2^6 input combinations; out_not = {~b, ~a}
    task run;
        for (i = 0; i < 64; i = i + 1) begin
            {a, b} = i[5:0];
            #10;
            if (out_or_bitwise !== (a | b) ||
                out_or_logical !== ((a != 0) || (b != 0)) ||
                out_not        !== {~b, ~a}) begin
                $display("FAIL a=%b b=%b bitwise=%b logical=%b not=%b",
                         a, b, out_or_bitwise, out_or_logical, out_not);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("vectorgates.vcd");
        $dumpvars(0, vectorgates_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
