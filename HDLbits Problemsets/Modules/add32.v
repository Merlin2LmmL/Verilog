module top_module(
        input [31:0] a,
        input [31:0] b,
        output [31:0] sum
    );
    
    wire c;
    wire unused_cout;
    
    add16 adder1 ( a[15:0], b[15:0], 1'b0, sum[15:0], c );
    add16 adder2 ( a[31:16], b[31:16], c, sum[31:16], unused_cout );

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