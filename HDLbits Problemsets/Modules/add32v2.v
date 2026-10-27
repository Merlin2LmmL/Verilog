module top_module (
        input [31:0] a,
        input [31:0] b,
        output [31:0] sum
    );
    
    wire unused_cout, c;
    
    add16 adder1 ( a[15:0], b[15:0], 1'b0, sum[15:0], c );
    add16 adder2 ( a[31:16], b[31:16], c, sum[31:16], unused_cout );
endmodule

module add1 ( input a, input b, input cin, output sum, output cout );
    assign sum = a ^ b ^ cin;
    assign cout = a&b | b&cin | a&cin;
endmodule

module add16(
        input  [15:0] a,
        input  [15:0] b,
        input         cin,
        output [15:0] sum,
        output        cout
    );
    
    add1 adder0 ( a[0], b[0], cin, sum[0], c1 );
    add1 adder1 ( a[1], b[1], c1, sum[1], c2 );
    add1 adder2 ( a[2], b[2], c2, sum[2], c3 );
    add1 adder3 ( a[3], b[3], c3, sum[3], c4 );
    add1 adder4 ( a[4], b[4], c4, sum[4], c5 );
    add1 adder5 ( a[5], b[5], c5, sum[5], c6 );
    add1 adder6 ( a[6], b[6], c6, sum[6], c7 );
    add1 adder7 ( a[7], b[7], c7, sum[7], c8 );
    add1 adder8 ( a[8], b[8], c8, sum[8], c9 );
    add1 adder9 ( a[9], b[9], c9, sum[9], c10 );
    add1 adder10 ( a[10], b[10], c10, sum[10], c11 );
    add1 adder11 ( a[11], b[11], c11, sum[11], c12 );
    add1 adder12 ( a[12], b[12], c12, sum[12], c13 );
    add1 adder13 ( a[13], b[13], c13, sum[13], c14 );
    add1 adder14 ( a[14], b[14], c14, sum[14], c15 );
    add1 adder15 ( a[15], b[15], c15, sum[15], cout );
endmodule