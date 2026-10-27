// Self-checking testbench for reverse.v
`timescale 1ns/1ps
`include "reverse.v"

module reverse_tb;
    reg  [31:0] in;
    wire [31:0] out;
    integer i, errors = 0;

    top_module dut (.in(in), .out(out));

    task check;
        input [31:0] value;
        begin
            in = value;
            #10;
            if (out !== {value[7:0], value[15:8], value[23:16], value[31:24]}) begin
                $display("FAIL in=%h out=%h", in, out);
                errors = errors + 1;
            end
        end
    endtask

    task run;
        begin
            check(32'h01020304);   // expect 04030201
            check(32'h00000000);
            check(32'hFFFFFFFF);
            for (i = 0; i < 100; i = i + 1) check($urandom);
        end
    endtask

    initial begin
        $dumpfile("reverse.vcd");
        $dumpvars(0, reverse_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
