module top_module #(
        parameter N = 100
    )(
        input      [N-1:0] in,
        output reg [N-1:0] out
    );

    integer i;
    always @(*) begin
        for (i = 0; i < N; i = i + 1)
            out[i] = in[N - 1 - i];
    end

endmodule