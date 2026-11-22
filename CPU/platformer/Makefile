# Clean-room platformer: build for the custom rv32em CPU, plus host-side checks.
#
#   make            assembly for the target (build/*.s), the required deliverable
#   make test       host conformance runner over vectors/*.txt + scenario checks
#   make preview    host render of selected game states -> build/preview.ppm
#   make elf        link build/*.s into build/game.elf (needs ld.lld) and print sizes
#   make emu        run game.elf in tools/rv32emu: instructions per frame + PPM frames
#   make sim        build/sim.html: playable browser sim running build/game.elf
#   make tiles      regenerate tiles.c / tiles.h from tools/gen_tiles.py
#   make vectors    re-extract vectors/*.txt from SPEC.md

CC      := clang
TARGET  := --target=riscv32 -march=rv32em -mabi=ilp32e
CFLAGS  := $(TARGET) -O2 -ffreestanding -std=c99 -Wall -Wextra -pedantic
SRCS    := game.c levels.c tiles.c platform.c
ASMS    := $(SRCS:%.c=build/%.s)
HOSTCC  ?= cc

.PHONY: all asm test elf emu preview sim tiles vectors clean cpu cpu-data

all: asm
asm: $(ASMS)

build/%.s: %.c game.h tiles.h | build
	$(CC) $(CFLAGS) -S $< -o $@

build:
	mkdir -p build

# ---- host conformance runner ----
test/run_vectors: test/run_vectors.c game.c levels.c game.h
	$(HOSTCC) -std=c99 -O2 -Wall -Wextra -pedantic -o $@ test/run_vectors.c game.c levels.c

test/scenarios: test/scenarios.c game.c levels.c game.h
	$(HOSTCC) -std=c99 -O2 -Wall -Wextra -o $@ test/scenarios.c game.c levels.c

test: test/run_vectors test/scenarios
	./test/run_vectors vectors/*.txt
	./test/scenarios | tail -1

test/preview: test/preview.c platform.c game.c levels.c tiles.c game.h tiles.h | build
	$(HOSTCC) -std=c99 -O1 -Wall -Wno-unused-function -I. -o $@ test/preview.c game.c levels.c tiles.c

preview: test/preview test/preview_l3
	./test/preview
	./test/preview_l3

test/preview_l3: test/preview_l3.c platform.c game.c levels.c tiles.c game.h tiles.h | build
	$(HOSTCC) -std=c99 -O1 -Wall -Wno-unused-function -I. -o $@ test/preview_l3.c game.c levels.c tiles.c

# ---- link and measure (optional, needs ld.lld) ----
build/%.o: build/%.s
	$(CC) $(TARGET) -c $< -o $@

build/crt0.o: tools/crt0.s | build
	$(CC) $(TARGET) -c $< -o $@

build/game.elf: build/crt0.o $(SRCS:%.c=build/%.o) tools/link.ld
	ld.lld -T tools/link.ld -o $@ build/crt0.o $(SRCS:%.c=build/%.o)
	llvm-size -A $@ | grep -E 'text|rodata|data|bss|Total'

elf: build/game.elf

tools/rv32emu: tools/rv32emu.c
	$(HOSTCC) -std=c99 -O2 -Wall -o $@ $<

emu: build/game.elf tools/rv32emu
	mkdir -p build/frames
	./tools/rv32emu build/game.elf tools/playthrough.txt build/frames
	./tools/rv32emu build/game.elf tools/random_keys.txt build/frames 0
	mkdir -p build/l3
	for f in $(SRCS:%.c=%); do $(CC) $(CFLAGS) -DSTART_LEVEL=3 -c $$f.c -o build/l3/$$f.o || exit 1; done
	ld.lld -T tools/link.ld -o build/l3/game.elf build/crt0.o $(SRCS:%.c=build/l3/%.o)
	./tools/rv32emu build/l3/game.elf tools/level3_run.txt build/frames

build/offsets.txt: game.h tools/offsets.c | build
	$(CC) $(TARGET) -O2 -ffreestanding -I. -S tools/offsets.c -o - | awk '/\.word/{printf "%s ", $$2}' > $@

sim: build/game.elf build/offsets.txt
	llvm-objcopy -O binary build/game.elf build/game.bin
	python3 tools/make_sim.py build/game.bin $$(llvm-nm build/game.elf | awk '$$3=="g_state"{print $$1}') "$$(cat build/offsets.txt)" build/sim.html

tiles:
	python3 tools/gen_tiles.py .

vectors:
	python3 tools/extract_vectors.py SPEC.md vectors

clean:
	rm -rf build test/run_vectors test/scenarios test/preview tools/rv32emu
# ---- the custom CPU (Harvard: code and data memory are separate, data starts at address 0) ----
#   make cpu         translate the compiler's RV32E assembly with tools/rv2cpu.py and assemble it:
#                    build/platformer.asm, .text.hex (instructions) and .data.hex (RAM image)
#   make cpu-data    data.bin = the RAM image (tiles, level tables, constants, then the zeroed
#                    variables) from address 0, for loading by hand
CPUFLAGS := $(TARGET) -O2 -ffreestanding -std=c99 -fno-jump-tables

build/%.rv.s: %.c game.h tiles.h | build
	$(CC) $(CPUFLAGS) -S $< -o $@

build/platformer.asm: $(SRCS:%.c=build/%.rv.s) tools/rv2cpu.py
	python3 tools/rv2cpu.py -o $@ $(SRCS:%.c=build/%.rv.s)

cpu: build/platformer.asm
	python3 ../tools/asm.py build/platformer.asm -o build/platformer

cpu-data: cpu
	python3 tools/hex2bin.py build/platformer.data.hex data.bin
