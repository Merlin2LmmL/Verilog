// Self-checking testbench for chain.v
`timescale 1ns/1ps
`include "chain.v"

module chain_tb;
    reg  clk = 0, d = 0;
    wire q;
    reg  m1, m2, m3;
    integer cycle = 0, errors = 0;

    top_module dut (.clk(clk), .d(d), .q(q));

    always #5 clk = ~clk;

    // reference model: three flip-flops in series
    always @(posedge clk) begin
        m1 <= d;
        m2 <= m1;
        m3 <= m2;
    end

    // check just before the clock's falling edge, then drive new input
    task run;
        repeat (60) begin
            @(negedge clk);
            cycle = cycle + 1;
            if (cycle > 4 && q !== m3) begin
                $display("FAIL cycle %0d: q=%b expected %b", cycle, q, m3);
                errors = errors + 1;
            end
            d = $urandom;
        end
    endtask

    initial begin
        $dumpfile("chain.vcd");
        $dumpvars(0, chain_tb);
        run;
        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
