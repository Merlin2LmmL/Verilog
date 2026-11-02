// instruction ROM (64 KB), loaded from +text=<file>
// outside the ROM it reads 0 = illegal instruction, so running off the end stops the cpu
module imem #(
        parameter WORDS = 16384
    ) (
        input  [31:0] addr,
        output [31:0] data
    );

    reg [31:0] mem [0:WORDS-1];
    reg [31:0] word;
    reg [8*1024-1:0] file;
    integer i, fd;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            mem[i] = 0;
        if ($value$plusargs("text=%s", file)) begin
            fd = $fopen(file, "r");
            if (fd == 0) begin
                $display("error: cannot open program file %0s", file);
            end else begin
                // not $readmemh, it warns when the file is shorter than the memory
                i = 0;
                while (i < WORDS && $fscanf(fd, "%h\n", word) == 1) begin
                    mem[i] = word;
                    i = i + 1;
                end
                $fclose(fd);
            end
        end
    end

    wire [29:0] index = addr[31:2];

    assign data = (index < WORDS) ? mem[index] : 0;

endmodule
