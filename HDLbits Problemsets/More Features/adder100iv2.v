module top_module(
        input [99:0] a, b,
        input cin,
        output [99:0] cout,
        output [99:0] sum
    );

    genvar i;
    generate
        for (i = 0; i < 100; ++i) begin : fa
            full_adder u ( a[i], b[i], (i == 0) ? cin : cout[i - 1], sum[i], cout[i] );
        end
    endgenerate

endmodule

module full_adder (
    	input a, b, cin,
    	output sum, cout
	);
    
    assign sum = a ^ b ^ cin;
    assign cout = (a & b) | (a & cin) | (b & cin);
    
endmodule