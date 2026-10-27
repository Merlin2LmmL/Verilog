// Self-checking testbench for and.v
`timescale 1ns/1ps
`include "and.v"

module and_tb;
    reg  a, b;
    wire out;
    integer i, errors = 0;

    top_module dut (.a(a), .b(b), .out(out));

    task run;
        for (i = 0; i < 4; i = i + 1) begin
            {a, b} = i[1:0];
            #10;
            if (out !== (a && b)) begin
                $display("FAIL a=%b b=%b out=%b", a, b, out);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("and.vcd");
        $dumpvars(0, and_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
