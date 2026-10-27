// Concatenation of differently sized vectors
`timescale 1ns/1ps
module top_module (
        input [4:0]  a, b, c, d, e, f,
        output [7:0] w, x, y, z
    );

    assign { w, x, y, z } = { a, b, c, d, e, f, 2'b11 };

endmodule
