// Self-checking testbench for wire.v
`timescale 1ns/1ps
`include "wire.v"

module wire_tb;
    reg  a;
    wire b;
    integer i, errors = 0;

    wire_module dut (.a(a), .b(b));

    task run;
        for (i = 0; i < 2; i = i + 1) begin
            a = i[0];
            #10;
            if (b !== a) begin
                $display("FAIL a=%b b=%b", a, b);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("wire.vcd");
        $dumpvars(0, wire_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
