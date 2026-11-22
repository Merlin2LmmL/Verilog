/* Host preview of the special objects: level 3 and the water level. */
#define HOST_PREVIEW 1
#include <stdio.h>
#include <string.h>
#include "../platform.c"

uint32_t host_fb[128 * 96 / 4];
static uint8_t sheet[2][4][96][128];

static void go(GameState *s, int lvl, uint16_t x, uint8_t y, int frames, uint8_t btn, int r, int c)
{
    game_reset(s);
    s->level = (uint8_t)(lvl - 2); s->restart = 2; game_step(s, 0);
    s->lives = 9;
    {   /* spawn every listed object that falls in this screen */
        uint16_t cam = x > 112 ? (uint16_t)(x - 112) : 0;
        uint8_t k;
        for (k = 0; k < s->lvl->nenemies; k++) {
            uint16_t ex = (uint16_t)(s->lvl->enemies[k].col << 4);
            if (ex + 32u < cam || ex > cam + 260u) continue;
            s->cam = (uint16_t)(ex - 270);
            s->p.b.x = (uint16_t)(s->cam + 40); s->p.b.y = 100;
            s->next_enemy = k;
            game_step(s, 0);
        }
        s->next_enemy = 255;
    }
    s->p.b.x = x; s->p.b.y = y; s->p.pstate = PS_FALL; s->p.b.vy = 0;
    s->cam = x > 112 ? (uint16_t)(x - 112) : 0;
    if (s->cam > s->cam_max) s->cam = s->cam_max;
    s->p.prevrelx = (uint8_t)(x - s->cam);
    s->it[IT_INJURY] = 200;                    /* keep the camera robot alive */
    while (frames-- > 0) { game_step(s, btn); s->it[IT_INJURY] = 200; }
    draw_frame(s);
    memcpy(sheet[r][c], host_fb, sizeof host_fb);
}

int main(void)
{
    GameState *s = &g_state;
    int r, c, y, x;
    go(s, 3, 200, 176, 150, 0, 0, 0);           /* slag pit 15-18 */
    go(s, 3, 330, 176, 150, 0, 0, 1);            /* claw stack 24-25 */
    go(s, 3, 760, 176, 90, 0, 0, 2);            /* short chain, seeds */
    go(s, 3, 1100, 176, 40, 0, 0, 3);           /* long chain */
    go(s, 3, 1600, 176, 40, 0, 1, 0);           /* second short chain, caltrop */
    go(s, 3, 1990, 176, 200, 0, 1, 1);          /* golem breathing */
    go(s, 2, 500, 120, 60, 0, 1, 2);            /* water: drone pods */
    go(s, 2, 1050, 120, 60, 0, 1, 3);           /* water: jelly */
    {
        FILE *f = fopen("build/preview_l3.ppm", "wb");
        fprintf(f, "P6 %d %d 255\n", 4 * 128 * 3 + 9, 2 * 96 * 3 + 3);
        for (r = 0; r < 2; r++) for (y = 0; y < 96 * 3 + (r == 1 ? 0 : 3); y++)
            for (c = 0; c < 4; c++) {
                for (x = 0; x < 128 * 3; x++) {
                    uint8_t v = y < 96 * 3 ? sheet[r][c][y / 3][x / 3] : 0;
                    uint8_t rgb[3] = { (uint8_t)((v >> 5) * 255 / 7), (uint8_t)(((v >> 2) & 7) * 255 / 7),
                                       (uint8_t)((v & 3) * 255 / 3) };
                    if (y >= 96 * 3) rgb[0] = rgb[1] = rgb[2] = 0;
                    fwrite(rgb, 1, 3, f);
                }
                if (c < 3) { uint8_t z[9] = {0}; fwrite(z, 1, 9, f); }
            }
        fclose(f);
    }
    return 0;
}
