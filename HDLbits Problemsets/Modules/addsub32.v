module top_module(
        input [31:0] a,
        input [31:0] b,
        input sub,
        output [31:0] sum
    );
    
    wire c, unused_carry;
    
    add16 adder_lo ( a[15:0], b[15:0] ^ {16{sub}}, sub, sum[15:0], c );
    add16 adder_hi ( a[31:16], b[31:16] ^ {16{sub}}, c, sum[31:16], unused_carry );

endmodule

module add16(
        input  [15:0] a,
        input  [15:0] b,
        input         cin,
        output [15:0] sum,
        output        cout
    );
    
    assign {cout, sum} = a + b + cin;

endmodule