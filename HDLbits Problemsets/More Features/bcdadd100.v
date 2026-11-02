module top_module( 
        input [399:0] a, b,
        input cin,
        output cout,
        output [399:0] sum
    );
    
    wire cout_fadd [99:0];
    
    genvar i;
    generate
        for (i = 0; i < 100; ++i) begin : bcd_adder
            bcd_fadd u (
                .a(a[(i * 4) + 3 : i * 4]),
                .b(b[(i * 4) + 3 : i * 4]),
                .cin((i == 0) ? cin : cout_fadd[i - 1]),
                .cout(cout_fadd[i]),
                .sum(sum[(i * 4) + 3 : i * 4])
            );
        end
    endgenerate
    
    assign cout = cout_fadd[99];

endmodule

// Provided by HDLbits
module bcd_fadd(
        input [3:0] a, b,
        input cin,
        output cout,
        output [3:0] sum
    );
    
    wire [4:0] bin = a + b + cin;

    assign cout = (bin > 5'd9);
    assign sum  = cout ? bin - 5'd10 : bin[3:0];

endmodule