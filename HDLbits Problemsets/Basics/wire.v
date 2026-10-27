// Simple wire module that connects input 'a' to output 'b'.
`timescale 1ns/1ps
module wire_module (
        input  a,
        output b
    );

    assign b = a;

endmodule
