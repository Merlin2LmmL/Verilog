// 40x25 text screen, one word per cell: [7:0] char, [11:8] fg color, [15:12] bg color
// gets printed to the terminal every time `show` is 1 (with colors, or +plain without)
// colors are the 16 terminal colors, fg = bg = 0 means the terminal's default colors
module screen (
        input         clk,
        input  [9:0]  index,     // y * 40 + x
        input  [31:0] wdata,
        input  [3:0]  wstrb,
        input         we,
        output [31:0] rdata,
        input         show
    );

    localparam COLS  = 40;
    localparam ROWS  = 25;
    localparam CELLS = COLS * ROWS;

    reg [31:0] cells [0:CELLS-1];
    reg        ansi;
    reg        first_frame;
    integer    i;

    initial begin
        for (i = 0; i < CELLS; i = i + 1)
            cells[i] = 0;
        ansi        = !$test$plusargs("plain");
        first_frame = 1;
    end

    assign rdata = (index < CELLS) ? cells[index] : 0;

    always @(posedge clk) begin
        if (we && index < CELLS) begin
            if (wstrb[0]) cells[index][7:0]   <= wdata[7:0];
            if (wstrb[1]) cells[index][15:8]  <= wdata[15:8];
            if (wstrb[2]) cells[index][23:16] <= wdata[23:16];
            if (wstrb[3]) cells[index][31:24] <= wdata[31:24];
        end
        if (show)
            draw;
    end

    // ansi codes: 30-37 / 90-97 text, 40-47 / 100-107 background
    function integer fg_code(input [3:0] color);
        fg_code = (color < 8) ? 30 + color : 82 + color;
    endfunction

    function integer bg_code(input [3:0] color);
        bg_code = (color < 8) ? 40 + color : 92 + color;
    endfunction

    task border;
        integer x;
        begin
            $write("+");
            for (x = 0; x < COLS; x = x + 1)
                $write("-");
            $write("+\n");
        end
    endtask

    task draw;
        integer x, y;
        reg [31:0] value;    // can't call it "cell", that's a keyword
        reg [7:0]  ch;
        reg [7:0]  colors, current;
        begin
            if (ansi && first_frame)
                $write("\033[2J");     // clear terminal
            if (ansi)
                $write("\033[H");      // cursor to top left, so frames overwrite each other
            first_frame = 0;
            border;
            for (y = 0; y < ROWS; y = y + 1) begin
                $write("|");
                current = 0;
                for (x = 0; x < COLS; x = x + 1) begin
                    value  = cells[y * COLS + x];
                    ch     = (value[7:0] < 32 || value[7:0] > 126) ? " " : value[7:0];
                    colors = ansi ? value[15:8] : 0;
                    if (colors != current) begin
                        if (colors == 0)
                            $write("\033[0m");
                        else
                            $write("\033[%0d;%0dm", fg_code(colors[3:0]), bg_code(colors[7:4]));
                        current = colors;
                    end
                    $write("%c", ch);
                end
                if (current != 0)
                    $write("\033[0m");
                $write("|\n");
            end
            border;
            $fflush;
        end
    endtask

endmodule
