// 7458 chip
`timescale 1ns/1ps
module top_module (
        input  p1a, p1b, p1c, p1d, p1e, p1f,
        output p1y,
        input  p2a, p2b, p2c, p2d,
        output p2y
    );

    wire p1w1, p1w2, p2w1, p2w2;

    assign p1w1 = p1a & p1b & p1c;
    assign p1w2 = p1d & p1e & p1f;
    assign p1y = p1w1 | p1w2;

    assign p2w1 = p2a & p2b;
    assign p2w2 = p2c & p2d;
    assign p2y = p2w1 | p2w2;

endmodule
