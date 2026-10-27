// Self-checking testbench for nor.v
`timescale 1ns/1ps
`include "nor.v"

module nor_tb;
    reg  p1a, p1b, p1c, p1d, p1e, p1f;
    reg  p2a, p2b, p2c, p2d;
    wire p1y, p2y;
    integer i, errors = 0;

    top_module dut (
        .p1a(p1a), .p1b(p1b), .p1c(p1c), .p1d(p1d), .p1e(p1e), .p1f(p1f), .p1y(p1y),
        .p2a(p2a), .p2b(p2b), .p2c(p2c), .p2d(p2d), .p2y(p2y)
    );

    // all 2^10 input combinations
    task run;
        for (i = 0; i < 1024; i = i + 1) begin
            {p1a, p1b, p1c, p1d, p1e, p1f, p2a, p2b, p2c, p2d} = i[9:0];
            #10;
            if (p1y !== ((p1a && p1b && p1c) || (p1d && p1e && p1f)) ||
                p2y !== ((p2a && p2b) || (p2c && p2d))) begin
                $display("FAIL in=%b p1y=%b p2y=%b", i[9:0], p1y, p2y);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("nor.vcd");
        $dumpvars(0, nor_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
