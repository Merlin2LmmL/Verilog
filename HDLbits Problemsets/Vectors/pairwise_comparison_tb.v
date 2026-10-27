// Self-checking testbench for pairwise_comparison.v
`timescale 1ns/1ps
`include "pairwise_comparison.v"

module pairwise_comparison_tb;
    reg  a, b, c, d, e;
    wire [24:0] out;
    reg  [24:0] exp;
    reg  [4:0]  s;
    integer i, r, k, errors = 0;

    top_module dut (.a(a), .b(b), .c(c), .d(d), .e(e), .out(out));

    // out[24 - 5*r - k] = ~in[r] ^ in[k], with in = {a,b,c,d,e} (a is index 0 = r)
    task run;
        for (i = 0; i < 32; i = i + 1) begin
            {a, b, c, d, e} = i[4:0];
            s = {a, b, c, d, e};
            #10;
            for (r = 0; r < 5; r = r + 1)
                for (k = 0; k < 5; k = k + 1)
                    exp[24 - 5*r - k] = ~s[4 - r] ^ s[4 - k];
            if (out !== exp) begin
                $display("FAIL abcde=%b out=%b expected=%b", s, out, exp);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("pairwise_comparison.vcd");
        $dumpvars(0, pairwise_comparison_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
