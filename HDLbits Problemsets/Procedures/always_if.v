// synthesis verilog_input_version verilog_2001
module top_module(
        input a,
        input b,
        input sel_b1,
        input sel_b2,
        output wire out_assign,
        output reg out_always
    );
    
    wire [1:0] sel = { sel_b1, sel_b2 };
    
    assign out_assign = (sel == 2'b11) ? b : a;
    
    always @(*) begin
        case (sel)
            2'b11: out_always = b;
            default: out_always = a;
        endcase
    end

endmodule