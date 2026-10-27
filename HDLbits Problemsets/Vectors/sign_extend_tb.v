// Self-checking testbench for sign_extend.v
`timescale 1ns/1ps
`include "sign_extend.v"

module sign_extend_tb;
    reg  [7:0]  in;
    wire [31:0] out;
    reg  [31:0] exp;
    integer i, errors = 0;

    top_module dut (.in(in), .out(out));

    task run;
        for (i = 0; i < 256; i = i + 1) begin
            in = i[7:0];
            #10;
            exp = $signed(in);
            if (out !== exp) begin
                $display("FAIL in=%h out=%h expected=%h", in, out, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sign_extend.vcd");
        $dumpvars(0, sign_extend_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
