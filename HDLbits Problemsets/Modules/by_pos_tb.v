// Self-checking testbench for by_pos.v
`timescale 1ns/1ps
`include "by_pos.v"

module by_pos_tb;
    reg  a, b, c, d;
    wire out1, out2;
    integer i, errors = 0;

    top_module dut (.a(a), .b(b), .c(c), .d(d), .out1(out1), .out2(out2));

    task run;
        for (i = 0; i < 16; i = i + 1) begin
            {a, b, c, d} = i[3:0];
            #10;
            if (out1 !== (a | b) || out2 !== (c | d)) begin
                $display("FAIL abcd=%b out1=%b out2=%b", i[3:0], out1, out2);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("by_pos.vcd");
        $dumpvars(0, by_pos_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
