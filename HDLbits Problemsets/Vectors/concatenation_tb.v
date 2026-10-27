// Self-checking testbench for concatenation.v
`timescale 1ns/1ps
`include "concatenation.v"

module concatenation_tb;
    reg  [4:0]  a, b, c, d, e, f;
    wire [7:0]  w, x, y, z;
    reg  [31:0] cat;
    integer i, errors = 0;

    top_module dut (
        .a(a), .b(b), .c(c), .d(d), .e(e), .f(f),
        .w(w), .x(x), .y(y), .z(z)
    );

    // 6 x 5 bits + 2'b11 = 32 bits, split into four bytes: w x y z
    task run;
        for (i = 0; i < 200; i = i + 1) begin
            {a, b, c, d, e, f} = $urandom;
            #10;
            cat = {a, b, c, d, e, f, 2'b11};
            if ({w, x, y, z} !== cat) begin
                $display("FAIL cat=%h got=%h", cat, {w, x, y, z});
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("concatenation.vcd");
        $dumpvars(0, concatenation_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
