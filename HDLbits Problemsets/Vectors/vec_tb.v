// Self-checking testbench for vec.v
`timescale 1ns/1ps
`include "vec.v"

module vec_tb;
    reg  [2:0] vec;
    wire [2:0] outv;
    wire       o2, o1, o0;
    integer i, errors = 0;

    top_module dut (.vec(vec), .outv(outv), .o2(o2), .o1(o1), .o0(o0));

    task run;
        for (i = 0; i < 8; i = i + 1) begin
            vec = i[2:0];
            #10;
            if (outv !== vec || o2 !== vec[2] || o1 !== vec[1] || o0 !== vec[0]) begin
                $display("FAIL vec=%b outv=%b o2=%b o1=%b o0=%b", vec, outv, o2, o1, o0);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("vec.vcd");
        $dumpvars(0, vec_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
