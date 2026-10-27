// 16-bit to 8-bit Vector Split
`timescale 1ns/1ps
`default_nettype none     // Disable implicit nets. Reduces some types of bugs.
module top_module (
        input wire [15:0] in,
        output wire [7:0] out_hi,
        output wire [7:0] out_lo
    );

    assign out_hi = in[15:8];
    assign out_lo = in[7:0];

endmodule
