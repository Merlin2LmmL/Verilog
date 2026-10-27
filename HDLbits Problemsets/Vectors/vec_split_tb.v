// Self-checking testbench for vec_split.v
`timescale 1ns/1ps
`include "vec_split.v"

module vec_split_tb;
    reg  [15:0] in;
    wire [7:0]  out_hi, out_lo;
    integer i, errors = 0;

    top_module dut (.in(in), .out_hi(out_hi), .out_lo(out_lo));

    task check;
        input [15:0] value;
        begin
            in = value;
            #10;
            if (out_hi !== value[15:8] || out_lo !== value[7:0]) begin
                $display("FAIL in=%h hi=%h lo=%h", in, out_hi, out_lo);
                errors = errors + 1;
            end
        end
    endtask

    task run;
        begin
            check(16'hABCD);   // expect hi=AB lo=CD
            check(16'h0000);
            check(16'hFFFF);
            for (i = 0; i < 100; i = i + 1) check($urandom);
        end
    endtask

    initial begin
        $dumpfile("vec_split.vcd");
        $dumpvars(0, vec_split_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
