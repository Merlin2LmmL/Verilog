// Self-checking testbench for chain8.v
`timescale 1ns/1ps
`include "chain8.v"

module chain8_tb;
    reg        clk = 0;
    reg  [7:0] d = 0;
    reg  [1:0] sel = 0;
    wire [7:0] q;
    reg  [7:0] m1, m2, m3, exp;
    integer cycle = 0, errors = 0;

    top_module dut (.clk(clk), .d(d), .sel(sel), .q(q));

    always #5 clk = ~clk;

    // reference model: three 8-bit registers in series
    always @(posedge clk) begin
        m1 <= d;
        m2 <= m1;
        m3 <= m2;
    end

    // sel picks d, or d delayed by 1, 2 or 3 clocks
    task run;
        repeat (80) begin
            @(negedge clk);
            cycle = cycle + 1;
            case (sel)
                2'd0: exp = d;
                2'd1: exp = m1;
                2'd2: exp = m2;
                2'd3: exp = m3;
            endcase
            if (cycle > 4 && q !== exp) begin
                $display("FAIL cycle %0d: sel=%0d q=%h expected %h", cycle, sel, q, exp);
                errors = errors + 1;
            end
            d   = $urandom;
            sel = $urandom;
        end
    endtask

    initial begin
        $dumpfile("chain8.vcd");
        $dumpvars(0, chain8_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
