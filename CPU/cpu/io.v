// I/O registers at 0xFFFF_0000 (ISA.md section 7)
// keys come from +keys=<file> (one byte = one key), +seed=N changes the random numbers
module io (
        input             clk,
        input             rst,
        input      [7:0]  offset,
        input      [31:0] wdata,
        input             we,
        input             re,
        output reg [31:0] rdata,
        output            screen_show,
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

    reg [31:0] timer;
    reg [31:0] rng;
    reg [31:0] seed;

    reg [7:0]        keys [0:65535];
    reg [8*1024-1:0] key_file;
    integer          key_count, key_pos, fd, ch;

    initial begin
        key_count = 0;
        if (!$value$plusargs("seed=%d", seed) || seed == 0)
            seed = 32'h2545_F491;    // xorshift can't start at 0
        if ($value$plusargs("keys=%s", key_file)) begin
            fd = $fopen(key_file, "r");
            if (fd == 0) begin
                $display("warning: cannot open key file %0s", key_file);
            end else begin
                ch = $fgetc(fd);
                while (ch != -1 && key_count < 65536) begin
                    keys[key_count] = ch;
                    key_count = key_count + 1;
                    ch = $fgetc(fd);
                end
                $fclose(fd);
            end
        end
    end

    wire       key_waiting = key_pos < key_count;
    wire [7:0] next_key    = keys[key_pos[15:0]];

    function [31:0] xorshift(input [31:0] s);
        reg [31:0] t;
        begin
            t = s ^ (s << 13);
            t = t ^ (t >> 17);
            xorshift = t ^ (t << 5);
        end
    endfunction

    assign screen_show = we && offset == SCREEN_SHOW;

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
            key_pos <= 0;
        end else begin
            timer <= timer + 1;
            if (re && offset == KEY_DATA && key_waiting)
                key_pos <= key_pos + 1;
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
