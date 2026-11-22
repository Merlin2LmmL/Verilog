/*
 * Host-side conformance runner (my own; the inspector supplies theirs).
 * Reads vectors/Vnn.txt files in the SPEC 9.3 table format, drives
 * game_reset_test / game_step, and prints every mismatching frame as
 *   <script> frame <f>: expected <row> | actual <row>
 * Exit status = number of failing scripts.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../game.h"

static GameState g;

static const char *k_worlds[W_COUNT] = { "FLAT", "STEP", "CEIL", "BLOCK", "LEDGE", "WATER" };

static int world_index(const char *line)
{
    int i;
    const char *q = strchr(line, '`');
    if (!q) return -1;
    for (i = 0; i < W_COUNT; i++) {
        size_t n = strlen(k_worlds[i]);
        if (!strncmp(q + 1, k_worlds[i], n) && q[1 + n] == '`') return i;
    }
    return -1;
}

static int field(const char *line, const char *key, int def)
{
    const char *q = strstr(line, key);
    return q ? atoi(q + strlen(key)) : def;
}

static uint8_t parse_buttons(const char *t)
{
    uint8_t b = 0;
    for (; *t; t++) {
        switch (*t) {
        case 'L': b |= BTN_LEFT; break;
        case 'R': b |= BTN_RIGHT; break;
        case 'U': b |= BTN_UP; break;
        case 'D': b |= BTN_DOWN; break;
        case 'A': b |= BTN_JUMP; break;
        case 'B': b |= BTN_RUN; break;
        default: break;
        }
    }
    return b;
}

static int run_file(const char *path, int verbose)
{
    FILE *f = fopen(path, "r");
    char line[512], name[64];
    const char *base;
    int have_world = 0, fails = 0, frames = 0;
    if (!f) { printf("%s: cannot open\n", path); return 1; }
    base = strrchr(path, '/');
    base = base ? base + 1 : path;
    snprintf(name, sizeof name, "%.*s", (int)(strcspn(base, ".")), base);

    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, "World ", 6)) {
            int w = world_index(line);
            int big = strstr(line, "big player") != NULL;
            if (w < 0) { printf("%s: unknown world\n", name); fclose(f); return 1; }
            game_reset_test(&g, (uint8_t)w, (uint16_t)field(line, " x=", 0),
                            (uint8_t)field(line, " y=", 176), (uint8_t)field(line, "state=", 0),
                            (uint8_t)big);
            g.p.b.xs = (uint8_t)(field(line, "xs=", 0) << 4);
            g.p.b.ys = (uint8_t)field(line, "ys=", 0);
            g.p.b.vx = (int8_t)field(line, "vx=", 0);
            g.p.b.vxf = (uint8_t)field(line, "vxf=", 0);
            g.p.b.vy = (int8_t)field(line, "vy=", 0);
            g.p.b.vyf = (uint8_t)field(line, "vyf=", 0);
            g.cam = (uint16_t)field(line, "left=", 0);
            g.p.prevrelx = (uint8_t)(g.p.b.x - g.cam);
            g.p.gfall = (uint8_t)field(line, "fall-gravity ", 40);
            have_world = 1;
            continue;
        }
        {
            /* split on '|' first, so the button field can never swallow a
             * separator (e.g. "LRDBA|" written without a space) */
            int fr, e[11], a[11], i, bad = 0, nf = 0;
            char in[16], buf[512], *fld[8], *q;
            if (!have_world) continue;
            snprintf(buf, sizeof buf, "%s", line);
            for (q = buf, fld[nf++] = q; *q && nf < 8; q++)
                if (*q == '|') { *q = 0; fld[nf++] = q + 1; }
            if (nf != 7) continue;
            if (sscanf(fld[0], " %d %15s", &fr, in) != 2) continue;
            if (sscanf(fld[1], "%d %d", &e[0], &e[1]) != 2 || sscanf(fld[2], "%d %d", &e[2], &e[3]) != 2 ||
                sscanf(fld[3], "%d %d", &e[4], &e[5]) != 2 || sscanf(fld[4], "%d %d", &e[6], &e[7]) != 2 ||
                sscanf(fld[5], "%d", &e[8]) != 1 || sscanf(fld[6], "%d", &e[9]) != 1) {
                printf("%s: unparsable row: %s", name, line);
                fails++;
                continue;
            }
            game_step(&g, parse_buttons(in));
            frames++;
            a[0] = g.p.b.x; a[1] = g.p.b.xs >> 4; a[2] = g.p.b.y; a[3] = g.p.b.ys;
            a[4] = g.p.b.vx; a[5] = g.p.b.vxf; a[6] = g.p.b.vy; a[7] = g.p.b.vyf;
            a[8] = g.p.pstate; a[9] = g.cam;
            for (i = 0; i < 10; i++) if (a[i] != e[i]) bad = 1;
            if (bad) {
                if (fails < 5 || verbose)
                    printf("%s frame %d (%s): expected %d %d | %d %d | %d %d | %d %d | %d | %d"
                           "   actual %d %d | %d %d | %d %d | %d %d | %d | %d\n",
                           name, fr, in, e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9],
                           a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9]);
                fails++;
            }
        }
    }
    fclose(f);
    printf("%-4s %s  (%d frames, %d mismatching)\n", name, fails ? "FAIL" : "ok  ", frames, fails);
    return fails ? 1 : 0;
}

int main(int argc, char **argv)
{
    int i, bad = 0, verbose = 0, n = 0;
    for (i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-v")) { verbose = 1; continue; }
        bad += run_file(argv[i], verbose);
        n++;
    }
    printf("%d/%d scripts pass\n", n - bad, n);
    return bad;
}
