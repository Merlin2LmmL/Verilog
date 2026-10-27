// Self-checking testbench for gates.v
`timescale 1ns/1ps
`include "gates.v"

module gates_tb;
    reg  a, b, c, d;
    wire out, out_n;
    reg  exp;
    integer i, errors = 0;

    top_module dut (.a(a), .b(b), .c(c), .d(d), .out(out), .out_n(out_n));

    task run;
        for (i = 0; i < 16; i = i + 1) begin
            {a, b, c, d} = i[3:0];
            #10;
            exp = (a && b) || (c && d);
            if (out !== exp || out_n !== !exp) begin
                $display("FAIL abcd=%b out=%b out_n=%b", i[3:0], out, out_n);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("gates.vcd");
        $dumpvars(0, gates_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
