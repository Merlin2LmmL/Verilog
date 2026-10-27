module top_module ( input a, input b, output out );
    mod_a instance1 (
        .in1(a),
        .in2(b),
        .in3(),
        .in4(),
        .out1(out),
        .out2()
    );

endmodule

module mod_a ( input in1, input in2, input in3, input in4, output out1, output out2);
    assign out1 = in1 | in2;
    assign out2 = in3 | in4;
endmodule