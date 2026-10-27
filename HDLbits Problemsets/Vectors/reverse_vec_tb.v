// Self-checking testbench for reverse_vec.v
`timescale 1ns/1ps
`include "reverse_vec.v"

module reverse_vec_tb;
    reg  [7:0] in;
    wire [7:0] out;
    integer i, j, errors = 0;

    top_module dut (.in(in), .out(out));

    // out[j] must equal in[7-j] (bit order reversed); all 256 inputs
    task run;
        for (i = 0; i < 256; i = i + 1) begin
            in = i[7:0];
            #10;
            for (j = 0; j < 8; j = j + 1)
                if (out[j] !== in[7-j]) begin
                    $display("FAIL in=%b out=%b (out[%0d] should be %b)", in, out, j, in[7-j]);
                    errors = errors + 1;
                    j = 8;
                end
        end
    endtask

    initial begin
        $dumpfile("reverse_vec.vcd");
        $dumpvars(0, reverse_vec_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
