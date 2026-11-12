// I/O registers at 0xFFFF_0000 (ISA.md section 7)
// keys come from +keys=<file> (one byte = one key, read while the program runs),
// +seed=N changes the random numbers
module io (
        input             clk,
        input             rst,
        input      [7:0]  offset,
        input      [31:0] wdata,
        input             we,
        input             re,
        output reg [31:0] rdata,
        output            screen_show,
        output            fb_show,
        output reg [31:0] leds
    );

    localparam CONSOLE_OUT = 8'h00;   // W: print a character
    localparam PRINT_INT   = 8'h04;   // W: print a signed number
    localparam KEY_STATUS  = 8'h08;   // R: 1 if a key is waiting
    localparam KEY_DATA    = 8'h0C;   // R: next key (reading removes it)
    localparam TIMER       = 8'h10;   // R: cycles since reset
    localparam RANDOM      = 8'h14;   // R: new random number on every read
    localparam SCREEN_SHOW = 8'h18;   // W: draw the text screen
    localparam LEDS        = 8'h1C;   // R/W
    localparam FB_SHOW     = 8'h20;   // W: show the framebuffer

    reg [31:0] timer;
    reg [31:0] rng;
    reg [31:0] seed;

    // keyboard: the key file is read while the program runs, one byte at a time, so keys
    // that get added to the file later arrive too (tools/keyboard.sh does that with what
    // you type). When the file has no more bytes, it is checked again every KEY_POLL cycles
    localparam KEY_POLL = 1000;

    reg [8*1024-1:0] key_file;
    integer          key_fd, ch;
    reg              key_waiting;    // next_key holds a key that wasn't read yet
    reg [7:0]        next_key;
    reg              keys_ran_out;
    reg [31:0]       ran_out_at;

    initial begin
        key_fd       = 0;
        key_waiting  = 0;
        next_key     = 0;
        keys_ran_out = 0;
        ran_out_at   = 0;
        if (!$value$plusargs("seed=%d", seed) || seed == 0)
            seed = 32'h2545_F491;    // xorshift can't start at 0
        if ($value$plusargs("keys=%s", key_file)) begin
            key_fd = $fopen(key_file, "r");
            if (key_fd == 0)
                $display("warning: cannot open key file %0s", key_file);
        end
    end

    // get the next byte of the key file into next_key (at a clock edge)
    task fetch_key;
        begin
            ch = $fgetc(key_fd);
            if (ch == -1) begin
                key_waiting  <= 0;
                keys_ran_out <= 1;
                ran_out_at   <= timer;
                ch = $fseek(key_fd, 0, 1);   // clears end-of-file, so new bytes can be read
            end else begin
                next_key     <= ch[7:0];
                key_waiting  <= 1;
                keys_ran_out <= 0;
            end
        end
    endtask

    function [31:0] xorshift(input [31:0] s);
        reg [31:0] t;
        begin
            t = s ^ (s << 13);
            t = t ^ (t >> 17);
            xorshift = t ^ (t << 5);
        end
    endfunction

    assign screen_show = we && offset == SCREEN_SHOW;
    assign fb_show     = we && offset == FB_SHOW;

    always @(*) begin
        case (offset)
            KEY_STATUS: rdata = key_waiting;
            KEY_DATA:   rdata = key_waiting ? next_key : 0;
            TIMER:      rdata = timer;
            RANDOM:     rdata = rng;
            LEDS:       rdata = leds;
            default:    rdata = 0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            timer   <= 0;
            rng     <= seed;
            leds    <= 0;
        end else begin
            timer <= timer + 1;
            if (key_fd != 0) begin
                if (re && offset == KEY_DATA && key_waiting)
                    fetch_key;                   // the key was taken, get the next one
                else if (!key_waiting && (!keys_ran_out || timer - ran_out_at >= KEY_POLL))
                    fetch_key;
            end
            if (re && offset == RANDOM)
                rng <= xorshift(rng);
            if (we) begin
                case (offset)
                    CONSOLE_OUT: begin $write("%c", wdata[7:0]); $fflush; end
                    PRINT_INT:   begin $write("%0d", $signed(wdata)); $fflush; end
                    LEDS:        leds <= wdata;
                    default:     ;
                endcase
            end
        end
    end

endmodule
