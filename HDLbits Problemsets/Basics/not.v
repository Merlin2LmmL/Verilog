// Simple NOT gate module that inverts the input signal 'a' and outputs it as 'b'
`timescale 1ns/1ps
module not_module (
        input  a,
        output b
    );

    assign b = ~a;

endmodule
