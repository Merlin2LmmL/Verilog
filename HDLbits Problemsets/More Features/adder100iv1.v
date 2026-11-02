module top_module(
        input [99:0] a, b,
        input cin,
        output [99:0] cout,
        output [99:0] sum
    );

    full_adder fa [99:0] (a, b, {cout[98:0], cin}, sum, cout);

endmodule

module full_adder (
    	input a, b, cin,
    	output sum, cout
	);
    
    assign sum = a ^ b ^ cin;
    assign cout = (a & b) | (a & cin) | (b & cin);
    
endmodule