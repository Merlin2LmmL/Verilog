// AND gate: Bitweise AND of two inputs
`timescale 1ns/1ps
module top_module (
        input  a,
        input  b,
        output out
    );

    assign out = a & b;

endmodule
