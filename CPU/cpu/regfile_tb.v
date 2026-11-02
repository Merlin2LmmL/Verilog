`timescale 1ns/1ps
`include "regfile.v"

module regfile_tb;

    reg         clk = 0, rst = 1, we = 0;
    reg  [3:0]  ra1 = 0, ra2 = 0, wa = 0;
    reg  [31:0] wd = 0;
    wire [31:0] rd1, rd2;
    integer i, errors = 0;

    regfile dut (
        .clk(clk), .rst(rst),
        .ra1(ra1), .rd1(rd1),
        .ra2(ra2), .rd2(rd2),
        .we(we), .wa(wa), .wd(wd)
    );

    always #5 clk = ~clk;

    function [31:0] pattern(input integer n);
        pattern = n * 32'h0101_0101 + 32'h1000_0000;
    endfunction

    task expect_reads;
        input [3:0]  port1, port2;
        input [31:0] value1, value2;
        begin
            ra1 = port1;
            ra2 = port2;
            #1;
            if (rd1 !== value1 || rd2 !== value2) begin
                $display("FAIL r%0d=%h (expected %h), r%0d=%h (expected %h)",
                         port1, rd1, value1, port2, rd2, value2);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("regfile.vcd");
        $dumpvars(0, regfile_tb);

        @(negedge clk) rst = 0;
        expect_reads(5, 15, 0, 0);

        // write all of them, r0 has to ignore it
        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            we = 1;
            wa = i;
            wd = pattern(i);
        end
        @(negedge clk) we = 0;

        for (i = 0; i < 16; i = i + 1)
            expect_reads(i, 15 - i, (i == 0) ? 0 : pattern(i), (i == 15) ? 0 : pattern(15 - i));

        // we = 0, so nothing changes
        wa = 3;
        wd = 32'hDEAD_BEEF;
        @(negedge clk);
        expect_reads(3, 3, pattern(3), pattern(3));

        rst = 1;
        @(negedge clk) rst = 0;
        expect_reads(7, 14, 0, 0);

        if (errors == 0) $display("PASS: all tests passed");
        else             $display("FAILED: %0d mismatches", errors);
        $finish;
    end

endmodule
