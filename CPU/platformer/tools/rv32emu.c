/*
 * rv32emu - tiny RV32IM(E) interpreter used only to measure the game:
 * instructions per frame, and PPM dumps of the 128x96 RGB332 framebuffer.
 *
 * usage: rv32emu game.elf input.txt outdir [dump_every]
 * input.txt lines: "<frames> <keys>" with keys from U D L R J or '-'.
 * MMIO: FB 0xFFFD0000 (12288 B), PRESENT 0xFFFF0020 (write = frame done),
 *       VSYNC 0xFFFF0024 (counts presented frames), KEYS 0xFFFF0028.
 * Prints max/avg instructions per frame and the worst frames.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define RAM_SIZE (1u << 20)
static uint8_t ram[RAM_SIZE];
static uint8_t fb[128 * 96];
static uint32_t x[32], pc;
static uint32_t vsync, keys;
static int presented;
static uint32_t prof_lo = 1, prof_hi = 0;   /* optional pc range to attribute */

static void die(const char *m, uint32_t a) { fprintf(stderr, "%s 0x%08x pc=0x%08x\n", m, a, pc); exit(2); }

static uint32_t rd(uint32_t a, int n)
{
    if (a >= 0xFFFD0000u && a < 0xFFFD0000u + sizeof fb) {
        uint32_t v = 0; int i;
        for (i = 0; i < n; i++) v |= (uint32_t)fb[a - 0xFFFD0000u + i] << (8 * i);
        return v;
    }
    if (a == 0xFFFF0024u) return vsync;
    if (a == 0xFFFF0028u) return keys;
    if (a + n > RAM_SIZE) die("bad read", a);
    if (n == 1) return ram[a];
    if (n == 2) return ram[a] | (ram[a + 1] << 8);
    return ram[a] | (ram[a + 1] << 8) | (ram[a + 2] << 16) | ((uint32_t)ram[a + 3] << 24);
}

static void wr(uint32_t a, uint32_t v, int n)
{
    int i;
    if (a >= 0xFFFD0000u && a < 0xFFFD0000u + sizeof fb) {
        if (n == 4 && (a & 3)) die("unaligned fb store", a);
        for (i = 0; i < n; i++) fb[a - 0xFFFD0000u + i] = (uint8_t)(v >> (8 * i));
        return;
    }
    if (a == 0xFFFF0020u) { presented = 1; vsync++; return; }
    if (a + n > RAM_SIZE) die("bad write", a);
    if ((a & (n - 1)) != 0) die("unaligned store", a);
    for (i = 0; i < n; i++) ram[a + i] = (uint8_t)(v >> (8 * i));
}

static void load_elf(const char *path)
{
    FILE *f = fopen(path, "rb");
    uint8_t h[52];
    uint32_t phoff, i;
    uint16_t phnum;
    if (!f || fread(h, 1, 52, f) != 52) die("cannot read elf", 0);
    pc = h[24] | h[25] << 8 | h[26] << 16 | (uint32_t)h[27] << 24;
    phoff = h[28] | h[29] << 8 | h[30] << 16 | (uint32_t)h[31] << 24;
    phnum = (uint16_t)(h[44] | h[45] << 8);
    for (i = 0; i < phnum; i++) {
        uint8_t p[32];
        uint32_t type, off, va, filesz;
        fseek(f, (long)(phoff + i * 32), SEEK_SET);
        if (fread(p, 1, 32, f) != 32) die("bad phdr", i);
        type = p[0] | p[1] << 8;
        off = p[4] | p[5] << 8 | p[6] << 16 | (uint32_t)p[7] << 24;
        va = p[8] | p[9] << 8 | p[10] << 16 | (uint32_t)p[11] << 24;
        filesz = p[16] | p[17] << 8 | p[18] << 16 | (uint32_t)p[19] << 24;
        if (type != 1) continue;
        if (va + filesz > RAM_SIZE) die("segment too big", va);
        fseek(f, (long)off, SEEK_SET);
        if (filesz && fread(ram + va, 1, filesz, f) != filesz) die("short segment", va);
    }
    fclose(f);
}

static int32_t sext(uint32_t v, int bits) { return (int32_t)(v << (32 - bits)) >> (32 - bits); }

/* execute one instruction; returns 1 if it was a mul/div */
static int step(void)
{
    uint32_t ins = rd(pc, 4), op = ins & 0x7F, rdi = (ins >> 7) & 31, f3 = (ins >> 12) & 7;
    uint32_t rs1 = x[(ins >> 15) & 31], rs2 = x[(ins >> 20) & 31], f7 = ins >> 25;
    uint32_t npc = pc + 4, v = 0;
    int32_t imm;
    int wrd = 1, md = 0;
    if (((ins >> 15) & 31) > 15 || ((ins >> 20) & 31) > 15 || rdi > 15) {
        if (op != 0x37 && op != 0x17 && op != 0x6F) { /* rs fields unused by U/J types */ }
    }
    switch (op) {
    case 0x37: v = ins & 0xFFFFF000u; break;
    case 0x17: v = pc + (ins & 0xFFFFF000u); break;
    case 0x6F:
        imm = sext(((ins >> 31) << 20) | (((ins >> 12) & 0xFF) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21);
        v = npc; npc = pc + (uint32_t)imm; break;
    case 0x67: v = npc; npc = (rs1 + (uint32_t)sext(ins >> 20, 12)) & ~1u; break;
    case 0x63: {
        int t = 0;
        imm = sext(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13);
        switch (f3) {
        case 0: t = rs1 == rs2; break; case 1: t = rs1 != rs2; break;
        case 4: t = (int32_t)rs1 < (int32_t)rs2; break; case 5: t = (int32_t)rs1 >= (int32_t)rs2; break;
        case 6: t = rs1 < rs2; break; case 7: t = rs1 >= rs2; break;
        default: die("bad branch", ins);
        }
        if (t) npc = pc + (uint32_t)imm;
        wrd = 0; break;
    }
    case 0x03: {
        uint32_t a = rs1 + (uint32_t)sext(ins >> 20, 12);
        switch (f3) {
        case 0: v = (uint32_t)sext(rd(a, 1), 8); break; case 1: v = (uint32_t)sext(rd(a, 2), 16); break;
        case 2: v = rd(a, 4); break; case 4: v = rd(a, 1); break; case 5: v = rd(a, 2); break;
        default: die("bad load", ins);
        }
        break;
    }
    case 0x23: {
        uint32_t a = rs1 + (uint32_t)sext(((ins >> 25) << 5) | ((ins >> 7) & 31), 12);
        wr(a, rs2, f3 == 0 ? 1 : f3 == 1 ? 2 : 4);
        wrd = 0; break;
    }
    case 0x13: {
        uint32_t im = (uint32_t)sext(ins >> 20, 12), sh = (ins >> 20) & 31;
        switch (f3) {
        case 0: v = rs1 + im; break; case 2: v = (int32_t)rs1 < (int32_t)im; break;
        case 3: v = rs1 < im; break; case 4: v = rs1 ^ im; break;
        case 6: v = rs1 | im; break; case 7: v = rs1 & im; break;
        case 1: v = rs1 << sh; break;
        case 5: v = (f7 & 0x20) ? (uint32_t)((int32_t)rs1 >> sh) : rs1 >> sh; break;
        }
        break;
    }
    case 0x33:
        if (f7 == 1) {
            md = 1;
            switch (f3) {
            case 0: v = rs1 * rs2; break;
            case 1: v = (uint32_t)(((int64_t)(int32_t)rs1 * (int64_t)(int32_t)rs2) >> 32); break;
            case 2: v = (uint32_t)(((int64_t)(int32_t)rs1 * (int64_t)(uint64_t)rs2) >> 32); break;
            case 3: v = (uint32_t)(((uint64_t)rs1 * rs2) >> 32); break;
            case 4: v = rs2 ? (uint32_t)((int32_t)rs1 / (int32_t)rs2) : 0xFFFFFFFFu; break;
            case 5: v = rs2 ? rs1 / rs2 : 0xFFFFFFFFu; break;
            case 6: v = rs2 ? (uint32_t)((int32_t)rs1 % (int32_t)rs2) : rs1; break;
            default: v = rs2 ? rs1 % rs2 : rs1; break;
            }
        } else {
            switch (f3) {
            case 0: v = (f7 & 0x20) ? rs1 - rs2 : rs1 + rs2; break;
            case 1: v = rs1 << (rs2 & 31); break;
            case 2: v = (int32_t)rs1 < (int32_t)rs2; break;
            case 3: v = rs1 < rs2; break;
            case 4: v = rs1 ^ rs2; break;
            case 5: v = (f7 & 0x20) ? (uint32_t)((int32_t)rs1 >> (rs2 & 31)) : rs1 >> (rs2 & 31); break;
            case 6: v = rs1 | rs2; break;
            default: v = rs1 & rs2; break;
            }
        }
        break;
    case 0x0F: wrd = 0; break;
    default: die("illegal instruction", ins);
    }
    if (wrd && rdi) { if (rdi > 15) die("register beyond rv32e", rdi); x[rdi] = v; }
    pc = npc;
    return md;
}

static void dump(const char *dir, int frame)
{
    char path[512];
    FILE *f;
    int i;
    snprintf(path, sizeof path, "%s/frame%05d.ppm", dir, frame);
    f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "P6\n128 96\n255\n");
    for (i = 0; i < 128 * 96; i++) {
        uint8_t c = fb[i];
        uint8_t r = (uint8_t)(((c >> 5) & 7) * 255 / 7), g = (uint8_t)(((c >> 2) & 7) * 255 / 7), b = (uint8_t)((c & 3) * 255 / 3);
        fputc(r, f); fputc(g, f); fputc(b, f);
    }
    fclose(f);
}

int main(int argc, char **argv)
{
    FILE *in;
    char line[128];
    int frame = 0, every = argc > 4 ? atoi(argv[4]) : 60;
    uint64_t total = 0, maxc = 0, muls = 0;
    int maxf = 0, over = 0;
    uint64_t prof_total = 0, prof_max = 0;
    if (getenv("PROF")) sscanf(getenv("PROF"), "%x:%x", &prof_lo, &prof_hi);
    if (argc < 4) { fprintf(stderr, "usage: rv32emu game.elf input.txt outdir [dump_every]\n"); return 1; }
    load_elf(argv[1]);
    in = fopen(argv[2], "r");
    if (!in) die("no input file", 0);
    while (fgets(line, sizeof line, in)) {
        int n = 0, k;
        char ks[32] = "-";
        if (line[0] == '#' || sscanf(line, "%d %31s", &n, ks) < 1) continue;
        keys = 0;
        for (k = 0; ks[k]; k++) {
            if (ks[k] == 'U') keys |= 1;
            if (ks[k] == 'D') keys |= 2;
            if (ks[k] == 'L') keys |= 4;
            if (ks[k] == 'R') keys |= 8;
            if (ks[k] == 'J') keys |= 16;
        }
        while (n-- > 0) {
            uint64_t c = 0;
            presented = 0;
            uint64_t inr = 0;
            while (!presented) {
                if (pc >= prof_lo && pc < prof_hi) inr++;
                muls += (uint64_t)step(); c++;
                if (c > 5000000) die("frame never presented", 0);
            }
            prof_total += inr;
            if (inr > prof_max) prof_max = inr;
            /* the instructions of the vsync spin after PRESENT belong to the next frame */
            total += c;
            if (frame > 0 && c > maxc) { maxc = c; maxf = frame; }
            if (c > 41000) over++;
            if (getenv("TRACE") && c > (uint64_t)atoi(getenv("TRACE"))) printf("frame %d: %llu\n", frame, (unsigned long long)c);
            if (every > 0 && frame % every == 0) dump(argv[3], frame);
            frame++;
        }
    }
    printf("frames %d  avg %llu  max %llu (frame %d)  frames over 41000: %d  mul/div executed: %llu\n",
           frame, (unsigned long long)(total / (frame ? frame : 1)), (unsigned long long)maxc, maxf, over,
           (unsigned long long)muls);
    if (prof_hi > prof_lo)
        printf("in pc range %x..%x: avg %llu  max %llu\n", prof_lo, prof_hi,
               (unsigned long long)(prof_total / (frame ? frame : 1)), (unsigned long long)prof_max);
    dump(argv[3], frame);
    return 0;
}
