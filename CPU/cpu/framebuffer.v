// 128x96 pixel framebuffer, one byte per pixel: [7:5] red, [4:2] green, [1:0] blue (RGB332)
// pixel (x, y) is byte y * 128 + x, so one word store sets 4 pixels side by side
//
// the program draws into the framebuffer, and only a write to FB_SHOW (show = 1) puts
// the picture on the display, so half-drawn frames are never seen:
//   - in the terminal with 24-bit colors, two pixels per character (upper half block),
//     and only the characters that changed since the last frame are printed again
//   - +fb=<file> also saves every shown frame as a PPM image (the file has the last one)
//   - +plain turns the terminal picture off (colors are the whole point of it)
//   - +resize=<file>: tools/keyboard.sh adds a byte to this file whenever the terminal gets
//     resized. Then the whole picture is drawn again (a resize scrambles what was on screen)
module framebuffer (
        input         clk,
        input  [11:0] index,     // word index = (y * 128 + x) / 4
        input  [31:0] wdata,
        input  [3:0]  wstrb,
        input         we,
        output [31:0] rdata,
        input         show
    );

    localparam W     = 128;
    localparam H     = 96;
    localparam WORDS = W * H / 4;

    reg [31:0] pixels [0:WORDS-1];
    reg [7:0]  shown  [0:W*H-1];     // what the terminal shows right now
    reg        ansi;
    reg        first_frame;
    reg        any_shown;            // a picture is on the terminal
    reg        save;
    reg [8*1024-1:0] resize_file;
    integer    resize_fd, rch;
    reg [13:0] resize_tick;
    reg [8*1024-1:0] file;
    integer    i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            pixels[i] = 0;
        for (i = 0; i < W * H; i = i + 1)
            shown[i] = 0;
        ansi        = !$test$plusargs("plain");
        save        = $value$plusargs("fb=%s", file);
        first_frame = 1;
        any_shown   = 0;
        resize_fd   = 0;
        resize_tick = 0;
        if ($value$plusargs("resize=%s", resize_file))
            resize_fd = $fopen(resize_file, "r");
    end

    assign rdata = (index < WORDS) ? pixels[index] : 0;

    always @(posedge clk) begin
        if (we && index < WORDS) begin
            if (wstrb[0]) pixels[index][7:0]   <= wdata[7:0];
            if (wstrb[1]) pixels[index][15:8]  <= wdata[15:8];
            if (wstrb[2]) pixels[index][23:16] <= wdata[23:16];
            if (wstrb[3]) pixels[index][31:24] <= wdata[31:24];
        end
        if (show) begin
            if (ansi) draw(0);
            if (save) save_ppm;
            first_frame = 0;
            any_shown   = 1;
        end
        // every 16384 cycles: was the terminal resized? Then print the picture again
        resize_tick <= resize_tick + 1;
        if (resize_fd != 0 && resize_tick == 0 && ansi && any_shown) begin
            rch = $fgetc(resize_fd);
            if (rch != -1) begin
                while (rch != -1)
                    rch = $fgetc(resize_fd);
                rch = $fseek(resize_fd, 0, 1);    // clears end-of-file, so new bytes can be read
                first_frame = 1;
                draw(1);
                first_frame = 0;
            end else
                rch = $fseek(resize_fd, 0, 1);
        end
    end

    function [7:0] pixel(input integer n);
        reg [31:0] word;
        begin
            word  = pixels[n / 4] >> (8 * (n % 4));
            pixel = word[7:0];
        end
    endfunction

    // 3 bits red / green and 2 bits blue -> 0..255
    function integer red(input [7:0] c);   red   = c[7:5] * 255 / 7; endfunction
    function integer green(input [7:0] c); green = c[4:2] * 255 / 7; endfunction
    function integer blue(input [7:0] c);  blue  = c[1:0] * 85;      endfunction

    // from_shown = 1: print what the terminal showed (again), not the picture being drawn
    task draw(input from_shown);
        integer    x, row, cx, crow;
        reg [8:0]  fg, bg;           // colors the terminal uses right now, 256 = don't know
        reg [7:0]  top, bottom;
        begin
            if (first_frame)
                $write("\033[2J");
            cx = -1; crow = -1;
            fg = 256; bg = 256;
            for (row = 0; row < H / 2; row = row + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    top    = from_shown ? shown[2 * row * W + x]       : pixel(2 * row * W + x);
                    bottom = from_shown ? shown[(2 * row + 1) * W + x] : pixel((2 * row + 1) * W + x);
                    if (first_frame || top != shown[2 * row * W + x] || bottom != shown[(2 * row + 1) * W + x]) begin
                        if (row != crow || x != cx)
                            $write("\033[%0d;%0dH", row + 1, x + 1);
                        if (fg != {1'b0, top}) begin
                            $write("\033[38;2;%0d;%0d;%0dm", red(top), green(top), blue(top));
                            fg = {1'b0, top};
                        end
                        if (bg != {1'b0, bottom}) begin
                            $write("\033[48;2;%0d;%0d;%0dm", red(bottom), green(bottom), blue(bottom));
                            bg = {1'b0, bottom};
                        end
                        $write("%c%c%c", 8'hE2, 8'h96, 8'h80);   // upper half block in UTF-8
                        shown[2 * row * W + x]       = top;
                        shown[(2 * row + 1) * W + x] = bottom;
                        cx = x + 1; crow = row;
                    end
                end
            end
            // normal colors again, and the cursor below the picture for the next output
            $write("\033[0m\033[%0d;1H", H / 2 + 1);
            $fflush;
        end
    endtask

    task save_ppm;
        integer fd, n;
        reg [7:0] c;
        begin
            fd = $fopen(file, "w");
            if (fd == 0) begin
                $display("warning: cannot write %0s", file);
                save = 0;
            end else begin
                $fwrite(fd, "P3\n%0d %0d\n255\n", W, H);
                for (n = 0; n < W * H; n = n + 1) begin
                    c = pixel(n);
                    $fwrite(fd, "%0d %0d %0d\n", red(c), green(c), blue(c));
                end
                $fclose(fd);
            end
        end
    endtask

endmodule
