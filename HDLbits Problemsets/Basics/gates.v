`default_nettype none
module top_module (
        input  a,
        input  b,
        input  c,
        input  d,
        output out,
        output out_n
    );

    wire out_and_1;
    wire out_and_2;

    assign out_and_1 = a & b;
    assign out_and_2 = c & d;
    assign out = out_and_1 | out_and_2;
    assign out_n = ~out;

endmodule
