// Sign extend an 8-bit vector to a 32-bit vector
`timescale 1ns/1ps
module top_module (
    	input [7:0] in,
    	output [31:0] out
	);

    assign out = { {24{in[7]}}, in };

endmodule