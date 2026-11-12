// Runs a program on the whole system, started by ../run.sh
// (no self-check, so it's not called *_tb.v and sim.sh leaves it alone)
//
//   +text=<file> +data=<file>   hex files from tools/asm.py
//   +max_cycles=N               stop after N cycles (default 50 000 000)
//   +trace                      print every instruction
//   +vcd=<file>                 waveform
//   +keys=<file> +seed=N        see io.v
//   +plain                      screen without colors, see screen.v
//   +fb=<file>                  save the shown framebuffer picture, see framebuffer.v
`timescale 1ns/1ps
`include "isa.vh"
`include "alu.v"
`include "regfile.v"
`include "decoder.v"
`include "cpu.v"
`include "imem.v"
`include "ram.v"
`include "framebuffer.v"
`include "screen.v"
`include "io.v"
`include "soc.v"

module soc_sim;

    reg         clk = 0;
    reg         rst = 1;
    wire        halted, trapped;
    wire [31:0] leds;

    soc dut (
        .clk(clk), .rst(rst),
        .halted(halted), .trapped(trapped), .leds(leds)
    );

    always #5 clk = ~clk;

    reg [8*1024-1:0] vcd_file;
    reg              trace;
    integer          max_cycles;
    integer          cycles = 0;

    initial begin
        if (!$test$plusargs("text=")) begin
            $display("No program given. Run a program with:  ./run.sh programs/<name>.asm");
            $finish(0);
        end
        if (!$value$plusargs("max_cycles=%d", max_cycles))
            max_cycles = 50_000_000;
        trace = $test$plusargs("trace");
        if ($value$plusargs("vcd=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, soc_sim);
        end
        repeat (2) @(posedge clk);
        @(negedge clk) rst = 0;
    end

    always @(posedge clk) begin
        if (!rst) begin
            if (halted) begin
                if (trapped)
                    $display("\n--- stopped by an illegal instruction after %0d cycles ---", cycles);
                else
                    $display("\n--- halted after %0d cycles ---", cycles);
                $finish(0);
            end

            if (trace) begin
                $write("%08h: %08h", dut.core.pc, dut.core.instr);
                if (dut.core.reg_we && dut.core.rd != 0)
                    $write("   r%0d = %08h", dut.core.rd, dut.core.wb_val);
                if (dut.core.dmem_we)
                    $write("   [%08h] = %08h", dut.core.alu_y,
                           dut.core.mem_byte ? {24'd0, dut.core.rs2_val[7:0]} : dut.core.rs2_val);
                $write("\n");
            end

            cycles = cycles + 1;
            if (cycles >= max_cycles) begin
                $display("\n--- timeout: still running after %0d cycles (change with +max_cycles=N) ---", cycles);
                $finish(0);
            end
        end
    end

endmodule
