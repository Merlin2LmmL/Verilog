/* Host preview: draws chosen game states with the real platform renderer
 * (platform.c compiled with HOST_PREVIEW) and writes build/preview.ppm. */
#define HOST_PREVIEW 1
#include <stdio.h>
#include <string.h>
#include "../platform.c"

uint32_t host_fb[128 * 96 / 4];
static uint8_t sheet[3][4][96][128];

static void grab(int r, int c) { memcpy(sheet[r][c], host_fb, sizeof host_fb); }

static void at(GameState *s, uint16_t x, uint8_t y, int frames, uint8_t btn)
{
    s->p.b.x = x; s->p.b.y = y; s->p.pstate = PS_FALL; s->p.b.vy = 0;
    s->cam = x > 112 ? (uint16_t)(x - 112) : 0;
    if (s->cam > s->cam_max) s->cam = s->cam_max;
    s->p.prevrelx = (uint8_t)(x - s->cam);
    while (frames-- > 0) game_step(s, btn);
}

int main(void)
{
    GameState *s = &g_state;
    int r, c, y, x;
    /* row 0: the redesigned opening (columns 10-60) */
    game_reset(s);                                   at(s, 230, 176, 260, 0); draw_frame(s); grab(0, 0);
    game_reset(s);                                   at(s, 470, 176, 2, 0);  draw_frame(s); grab(0, 1);
    game_reset(s); s->p.power = 1; s->p.big = 1;     at(s, 640, 176, 4, 0); draw_frame(s); grab(0, 2);
    game_reset(s);                                   at(s, 790, 176, 40, BTN_RIGHT); draw_frame(s); grab(0, 3);
    game_reset(s);                                   at(s, 1250, 100, 30, 0); draw_frame(s); grab(1, 0);
    game_reset(s);                                   at(s, 1520, 176, 40, BTN_RIGHT); draw_frame(s); grab(1, 1);
    game_reset(s);                                   at(s, 1800, 176, 6, 0); draw_frame(s); grab(1, 2);
    game_reset(s);                                   at(s, 2480, 60, 30, 0); draw_frame(s); grab(1, 3);
    game_reset(s);                                   at(s, 3000, 100, 20, 0); draw_frame(s); grab(2, 0);
    game_reset(s); s->level = 1; s->restart = 2; s->level = 0; game_step(s, 0);
    at(s, 400, 120, 20, 0); draw_frame(s); grab(2, 1);
    at(s, 900, 90, 20, BTN_JUMP); draw_frame(s); grab(2, 2);
    s->p.power = 1; s->p.big = 1; s->p.crouch = 1; at(s, 1450, 176, 2, BTN_DOWN); draw_frame(s); grab(2, 3);

    {
        FILE *f = fopen("build/preview.ppm", "wb");
        fprintf(f, "P6\n%d %d\n255\n", 4 * 130, 3 * 98);
        for (r = 0; r < 3; r++)
            for (y = 0; y < 98; y++)
                for (c = 0; c < 4; c++)
                    for (x = 0; x < 130; x++) {
                        uint8_t v = (y < 96 && x < 128) ? sheet[r][c][y][x] : 0;
                        fputc(((v >> 5) & 7) * 255 / 7, f);
                        fputc(((v >> 2) & 7) * 255 / 7, f);
                        fputc((v & 3) * 255 / 3, f);
                    }
        fclose(f);
    }
    return 0;
}
