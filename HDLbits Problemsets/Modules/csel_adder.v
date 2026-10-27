module top_module(
        input  [31:0] a,
        input  [31:0] b,
        output [31:0] sum
    );

    wire sel, unused_cout;
    wire [15:0] sum_hi0, sum_hi1;

    add16 adder_lo  ( a[15:0],  b[15:0],  1'b0, sum[15:0], sel );
    add16 adder_hi0 ( a[31:16], b[31:16], 1'b0, sum_hi0, unused_cout );
    add16 adder_hi1 ( a[31:16], b[31:16], 1'b1, sum_hi1, unused_cout );

    assign sum[31:16] = sel ? sum_hi1 : sum_hi0;

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