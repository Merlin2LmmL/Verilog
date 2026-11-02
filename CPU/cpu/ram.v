// data RAM (256 KB), byte-writable, starts with the .data from +data=<file>
module ram #(
        parameter WORDS = 65536
    ) (
        input         clk,
        input  [31:0] addr,
        input  [31:0] wdata,
        input  [3:0]  wstrb,
        input         we,
        output [31:0] rdata
    );

    localparam AW = $clog2(WORDS);

    reg [31:0] mem [0:WORDS-1];
    reg [31:0] word;
    reg [8*1024-1:0] file;
    integer i, fd;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 0;
        if ($value$plusargs("data=%s", file)) begin
            fd = $fopen(file, "r");
            if (fd == 0) begin
                $display("error: cannot open data file %0s", file);
            end else begin
                i = 0;
                while (i < WORDS && $fscanf(fd, "%h\n", word) == 1) begin
                    mem[i] = word;
                    i = i + 1;
                end
                $fclose(fd);
            end
        end
    end

    wire [AW-1:0] index = addr[AW+1:2];

    assign rdata = mem[index];

    always @(posedge clk) begin
        if (we) begin
            if (wstrb[0]) mem[index][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[index][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[index][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[index][31:24] <= wdata[31:24];
        end
    end

endmodule
