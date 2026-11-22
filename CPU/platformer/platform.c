/*
 * platform.c - thin platform layer: keys in, one game_step per frame, draw.
 *
 * Screen: 128 x 96, one RGB332 byte per pixel at 0xFFFD0000.
 * The game world is drawn at half scale: one 16 x 16 level tile becomes one
 * 8 x 8 art tile, and the visible window is level rows 0..11
 * (logical screen y 32..223). Logical (x, y) maps to screen
 * ((x >> 1) - (camera >> 1), (y - 32) >> 1). Screen rows 0..7 are the HUD
 * bar, so the playfield actually shown is grid rows 1..11.
 *
 * Key mapping (KEYS_HELD bit -> game button):
 *   bit 0 Up    -> BTN_UP and BTN_RUN  (run / fireball / climb up)
 *   bit 1 Down  -> BTN_DOWN            (crouch / climb down)
 *   bit 2 Left  -> BTN_LEFT
 *   bit 3 Right -> BTN_RIGHT
 *   bit 4 Space -> BTN_JUMP
 *
 * Assumes the framebuffer accepts aligned 32-bit stores (little-endian:
 * the lowest byte is the leftmost pixel).
 */
#include "game.h"
#include "tiles.h"

#ifdef HOST_PREVIEW          /* test/preview.c draws into a host buffer */
extern uint32_t host_fb[128 * 96 / 4];
#define FB8      ((volatile uint8_t *)host_fb)
#define FB32     ((volatile uint32_t *)host_fb)
#else
#define FB8      ((volatile uint8_t *)0xFFFD0000u)
#define FB32     ((volatile uint32_t *)0xFFFD0000u)
#endif
#define REG_PRESENT (*(volatile uint32_t *)0xFFFF0020u)
#define REG_VSYNC   (*(volatile uint32_t *)0xFFFF0024u)
#define REG_KEYS    (*(volatile uint32_t *)0xFFFF0028u)

#define SCR_W 128
#define SCR_H 96

static GameState g_state;

#ifndef HOST_PREVIEW
/* The compiler may emit calls to these for struct copies and clears. */
void *memset(void *d, int c, size_t n);
void *memcpy(void *d, const void *s, size_t n);
void *memset(void *d, int c, size_t n)
{
    uint8_t *p = (uint8_t *)d;
    while (n--) *p++ = (uint8_t)c;
    return d;
}
void *memcpy(void *d, const void *s, size_t n)
{
    uint8_t *p = (uint8_t *)d;
    const uint8_t *q = (const uint8_t *)s;
    while (n--) *p++ = *q++;
    return d;
}
#endif

/* ------------------------------------------------------------------ */
/* background                                                           */
/* ------------------------------------------------------------------ */
/*
 * Screen rows 0..7 are the HUD bar, so grid row 0 is never drawn and the
 * background covers grid rows 1..11 (screen rows 8..95). The horizontal
 * fine offset o = (camera / 2) & 7 screen px splits into a whole-word part
 * (half = o / 4) and a byte part (sr = 8 * (o & 3)). Output words are
 * funnel shifts of two neighbouring source words, so every store is an
 * aligned 32-bit store. The loops go tile column by tile column with the
 * 8 lines unrolled, which keeps register pressure low on RV32E.
 */

#define HUD_ROWS 8u

/* one tile column, 8 lines; F = output for words 0 and 1 of line L */
#define BG8(F) do { F(0); F(1); F(2); F(3); F(4); F(5); F(6); F(7); } while (0)

#define COPY0(L)  do { fb[(L) * 32] = A[2 * (L)];     fb[(L) * 32 + 1] = A[2 * (L) + 1]; } while (0)
#define COPY1(L)  do { fb[(L) * 32] = A[2 * (L) + 1]; fb[(L) * 32 + 1] = B[2 * (L)];     } while (0)
#define SHIFT0(L) do { uint32_t a0 = A[2 * (L)], a1 = A[2 * (L) + 1], b0 = B[2 * (L)]; \
                       fb[(L) * 32] = (a0 >> sr) | (a1 << sl); \
                       fb[(L) * 32 + 1] = (a1 >> sr) | (b0 << sl); } while (0)
#define SHIFT1(L) do { uint32_t a1 = A[2 * (L) + 1], b0 = B[2 * (L)], b1 = B[2 * (L) + 1]; \
                       fb[(L) * 32] = (a1 >> sr) | (b0 << sl); \
                       fb[(L) * 32 + 1] = (b0 >> sr) | (b1 << sl); } while (0)

static void draw_background(const GameState *s)
{
    const uint32_t (*art)[16] = g_tile_art[0];
    uint32_t col0 = (uint32_t)s->cam >> 4;
    uint32_t o = ((uint32_t)s->cam >> 1) & 7u;
    uint32_t sr = (o & 3u) << 3, sl = 32u - sr;
    uint32_t mode = (o >> 2) | (sr ? 2u : 0u);
    const uint32_t *pt[17];
    uint32_t tr, c;

    if (s->lvl->sky) art = g_tile_art[1];
    for (tr = 1; tr < 12u; tr++) {
        const uint8_t *row = &s->m.map[tr << 8];
        volatile uint32_t *fb = FB32 + (tr << 8);   /* 8 lines x 32 words */
        for (c = 0; c < 17u; c++) pt[c] = art[row[col0 + c > 255u ? 255u : col0 + c]];
        for (c = 0; c < 16u; c++, fb += 2) {
            const uint32_t *A = pt[c], *B = pt[c + 1u];
            switch (mode) {
            case 0: BG8(COPY0); break;
            case 1: BG8(COPY1); break;
            case 2: BG8(SHIFT0); break;
            default: BG8(SHIFT1); break;
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/* sprites                                                              */
/* ------------------------------------------------------------------ */

#define FLIP_H 1u
#define FLIP_V 2u

/* draw an 8x8 sprite at screen (sx, sy); rows at screen y >= maxy are cut */
static void blit(const uint8_t *src, int32_t sx, int32_t sy, uint32_t flags,
                 uint8_t from, uint8_t to, int32_t maxy, uint32_t opaque)
{
    int32_t r0 = 0, r1 = 8, c0 = 0, c1 = 8, r, n;
    int32_t step = (flags & FLIP_H) ? -1 : 1;
    if (maxy > SCR_H) maxy = SCR_H;
    if (sy < (int32_t)HUD_ROWS) r0 = (int32_t)HUD_ROWS - sy;
    if (sy + 8 > maxy) r1 = maxy - sy;
    if (sx < 0) c0 = -sx;
    if (sx + 8 > SCR_W) c1 = SCR_W - sx;
    if (r0 >= r1 || c0 >= c1) return;
    for (r = r0; r < r1; r++) {
        const uint8_t *line = src + (((flags & FLIP_V) ? 7 - r : r) << 3);
        const uint8_t *q = (flags & FLIP_H) ? line + 7 - c0 : line + c0;
        volatile uint8_t *dst = FB8 + ((uint32_t)(sy + r) << 7) + (uint32_t)(sx + c0);
        for (n = c1 - c0; n > 0; n--, q += step, dst++) {
            uint8_t v = *q;
            if (v == COL_TRANSPARENT && !opaque) continue;
            *dst = v == from ? to : v;
        }
    }
}

/* level coordinates -> screen; works for objects left of the camera too */
static int32_t scr_x(const GameState *s, uint16_t x)
{
    return (int32_t)(x >> 1) - (int32_t)(s->cam >> 1);
}
static int32_t scr_y(int32_t y)
{
    return ((y + 480) >> 1) - 256;    /* (y - 32) / 2, floor, y >= -480 */
}

static void sprite(const GameState *s, uint8_t id, uint16_t x, int32_t y, uint32_t flags,
                   uint8_t from, uint8_t to)
{
    blit(g_sprite_art[id], scr_x(s, x), scr_y(y), flags, from, to, SCR_H, 0);
}

/* ------------------------------------------------------------------ */
/* digits and HUD                                                       */
/* ------------------------------------------------------------------ */

/* 3x5 digit into an 8-bit pixel buffer with a 128 byte stride */
static void glyph(volatile uint8_t *base, uint8_t d, int32_t x, int32_t y, uint8_t col)
{
    uint32_t r, c;
    for (r = 0; r < 5u; r++) {
        uint8_t bits = g_font[d][r];
        int32_t yy = y + (int32_t)r;
        if (yy < (int32_t)HUD_ROWS || yy >= SCR_H) continue;
        for (c = 0; c < 3u; c++) {
            int32_t xx = x + (int32_t)c;
            if ((bits & (4u >> c)) && xx >= 0 && xx < SCR_W) base[((uint32_t)yy << 7) + (uint32_t)xx] = col;
        }
    }
}

static const uint32_t k_pow10[7] = {1u, 10u, 100u, 1000u, 10000u, 100000u, 1000000u};

/* next decimal digit of v for place value p, by repeated subtraction */
static uint8_t take_digit(uint32_t *v, uint32_t p)
{
    uint8_t d = 0;
    while (*v >= p && d < 9u) { *v -= p; d++; }
    return d;
}

/* floating score in the playfield: white digits with a black shadow */
static void number(uint32_t v, uint32_t digits, int32_t x, int32_t y)
{
    uint32_t i;
    for (i = digits; i > 0; i--) {
        uint8_t d = take_digit(&v, k_pow10[i - 1u]);
        glyph(FB8, d, x + 1, y + 1, COL_BLACK);
        glyph(FB8, d, x, y, COL_WHITE);
        x += 4;
    }
}

/* HUD bar (screen rows 0..7), rebuilt in RAM only when a value changes */
static uint32_t g_hud[HUD_ROWS * 32u];
static uint32_t g_hud_key[4] = {0xFFFFFFFFu, 0, 0, 0};

static void hud_digits(uint8_t *buf, uint32_t v, uint32_t digits, int32_t x)
{
    uint32_t i, r, c;
    for (i = digits; i > 0; i--) {
        uint8_t d = take_digit(&v, k_pow10[i - 1u]);
        for (r = 0; r < 5u; r++)
            for (c = 0; c < 3u; c++)
                if (g_font[d][r] & (4u >> c)) buf[((r + 1u) << 7) + (uint32_t)x + c] = COL_WHITE;
        x += 4;
    }
}

static void hud_icon(uint8_t *buf, uint8_t id, uint32_t x)
{
    uint32_t r, c;
    for (r = 0; r < 4u; r++)
        for (c = 0; c < 5u; c++) {
            uint8_t v = g_sprite_art[id][(r << 3) + c];
            if (v != COL_TRANSPARENT) buf[((r + 1u) << 7) + x + c] = v;
        }
}

static void draw_hud(const GameState *s)
{
    volatile uint32_t *fb = FB32;
    uint32_t i;
    if (g_hud_key[0] != s->score || g_hud_key[1] != s->coins ||
        g_hud_key[2] != s->lives || g_hud_key[3] != s->time) {
        uint8_t *buf = (uint8_t *)g_hud;
        g_hud_key[0] = s->score; g_hud_key[1] = s->coins;
        g_hud_key[2] = s->lives; g_hud_key[3] = s->time;
        for (i = 0; i < HUD_ROWS * 32u; i++) g_hud[i] = 0;   /* COL_BLACK is 0 */
        hud_digits(buf, s->score, 6, 1);
        hud_icon(buf, SPR_HUD_NUT, 31);
        hud_digits(buf, s->coins, 2, 37);
        hud_icon(buf, SPR_HUD_HEART, 53);
        hud_digits(buf, s->lives, 2, 59);
        if (s->time) hud_digits(buf, s->time, 3, 114);
    }
    for (i = 0; i < HUD_ROWS * 32u; i += 4u) {
        fb[i] = g_hud[i]; fb[i + 1u] = g_hud[i + 1u];
        fb[i + 2u] = g_hud[i + 2u]; fb[i + 3u] = g_hud[i + 3u];
    }
}

/* ------------------------------------------------------------------ */
/* frame                                                                */
/* ------------------------------------------------------------------ */

static const uint16_t k_popup_points[11] = {0, 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000};

static void draw_player(const GameState *s)
{
    const Player *p = &s->p;
    uint32_t flags = p->face == 2u ? FLIP_H : 0u;
    uint8_t from = COL_BODY, to = COL_BODY;
    uint8_t walk = (uint8_t)((p->b.x >> 3) & 1u);
    uint8_t air = p->pstate == PS_RISE || p->pstate == PS_FALL;
    if (p->b.yh != 1u) return;
    if (s->it[IT_INJURY] && (s->fc & 1u)) return;
    if (p->power == 2u) to = COL_FIRE;
    if (s->it[IT_STAR]) to = (uint8_t)(s->fc << 3);
    if (p->mode == PM_GROW && s->freeze > 248u && (s->fc & 4u)) {  /* grow flicker */
        sprite(s, SPR_SMALL_STAND, p->b.x, p->b.y + 16, flags, from, to);
        return;
    }
    if (p->mode == PM_DYING) {
        sprite(s, SPR_DEAD, p->b.x, p->b.y + 16, 0, from, to);
        return;
    }
    if (!p->big) {
        uint8_t id = air ? SPR_SMALL_JUMP : (p->b.vx && walk ? SPR_SMALL_WALK : SPR_SMALL_STAND);
        if (p->pstate == PS_CLIMB) id = (p->b.y & 8u) ? SPR_SMALL_WALK : SPR_SMALL_STAND;
        sprite(s, id, p->b.x, p->b.y + 16, flags, from, to);
    } else if (p->crouch) {
        sprite(s, SPR_BIG_CROUCH, p->b.x, p->b.y + 16, flags, from, to);
    } else {
        uint8_t bot = (air || (p->b.vx && walk) || (p->pstate == PS_CLIMB && (p->b.y & 8u)))
                      ? SPR_BIG_BOT_WALK : SPR_BIG_BOT;
        sprite(s, SPR_BIG_TOP, p->b.x, p->b.y, flags, from, to);
        sprite(s, bot, p->b.x, p->b.y + 16, flags, from, to);
    }
}

/* fire chain segment: the middle 4 x 4 of SPR_EMBER at the segment's
 * 8 x 8 level-px square (sx, sy = its top-left on the screen) */
static void ember(int32_t sx, int32_t sy)
{
    const uint8_t *src = g_sprite_art[SPR_EMBER] + 2 * 8 + 2;
    int32_t r, c;
    for (r = 0; r < 4; r++) {
        int32_t y = sy + r;
        if (y < (int32_t)HUD_ROWS || y >= SCR_H) continue;
        for (c = 0; c < 4; c++) {
            int32_t x = sx + c;
            uint8_t v = src[r * 8 + c];
            if (x < 0 || x >= SCR_W || v == COL_TRANSPARENT) continue;
            FB8[(y << 7) + x] = v;
        }
    }
}

/* 2 x 2 sprite group (32 x 32 level px) at level (x, y), optional flips */
static void quad(const GameState *s, uint8_t tl, uint8_t tr, uint8_t bl, uint8_t br,
                 uint16_t x, int32_t y, uint32_t flags)
{
    uint8_t id[4];
    uint32_t q;
    id[0] = tl; id[1] = tr; id[2] = bl; id[3] = br;
    for (q = 0; q < 4u; q++) {
        uint32_t col = q & 1u, row = q >> 1;
        if (flags & FLIP_H) col ^= 1u;
        if (flags & FLIP_V) row ^= 1u;
        sprite(s, id[q], (uint16_t)(x + (col << 4)), y + (int32_t)(row << 4), flags, 0, 0);
    }
}

static void draw_special(const GameState *s, const Enemy *e)
{
    uint8_t anim = (uint8_t)((s->fc >> 3) & 1u), id;
    uint32_t flags = (e->state & ESF_D) ? FLIP_V : 0u;
    int32_t y = (int32_t)e->b.y + 8;
    switch (e->type) {
    case E_CHAIN: case E_CHAIN_LONG: {
        uint8_t n, segs = e->type == E_CHAIN ? 6u : 12u;
        for (n = 0; n < segs; n++) {
            int8_t dx, dy;
            game_chain_offset(e, n, &dx, &dy);
            ember(scr_x(s, (uint16_t)(CHAIN_PX(e) + dx)), scr_y((int32_t)CHAIN_PY(e) + dy));
        }
        return;
    }
    case E_BOSS:
        if (e->b.yh != 1u) return;
        if (e->dir == 1u) flags |= FLIP_H;
        if (e->aux) quad(s, SPR_BOSS_A_TL, SPR_BOSS_A_TR, SPR_BOSS_B_BL, SPR_BOSS_B_BR, e->b.x, e->b.y, flags);
        else quad(s, SPR_BOSS_A_TL, SPR_BOSS_A_TR, SPR_BOSS_A_BL, SPR_BOSS_A_BR, e->b.x, e->b.y, flags);
        return;
    case E_PLANT:
        if (e->b.yh != 1u) return;
        id = anim ? SPR_CLAW_B : SPR_CLAW_A;
        if (flags) { sprite(s, id, e->b.x, y, flags, 0, 0); return; }
        {   /* clipped at the pipe top, so the hidden part stays inside */
            int32_t top = scr_y((int32_t)e->hy + 8);
            blit(g_sprite_art[id], scr_x(s, e->b.x), scr_y(y), 0, 0, 0, top, 0);
            blit(g_sprite_art[SPR_CLAW_ROD], scr_x(s, e->b.x), scr_y(y + 16), 0, 0, 0, top, 0);
        }
        return;
    case E_LAVA:
        if (e->b.yh != 1u) return;
        sprite(s, SPR_SLAG, e->b.x, y, e->b.vy >= 0 ? FLIP_V : 0u, 0, 0);
        return;
    case E_SPIKE:
        if (e->b.yh != 1u) return;
        if ((e->state & ES_LOW) == ES_EGG) id = SPR_CALTROP_EGG;
        else {
            id = anim ? SPR_CALTROP_B : SPR_CALTROP_A;
            if ((e->state & ES_LOW) == ES_KNOCK || (e->state & ES_LOW) == ES_LANDED) flags |= FLIP_V;
            if (e->dir == 1u) flags |= FLIP_H;
        }
        break;
    case E_SQUID: id = e->aux == 2u ? SPR_JELLY_B : SPR_JELLY_A; break;
    case E_MISSILE: id = SPR_DART; if (e->dir == 1u) flags |= FLIP_H; break;
    default: /* fish */
        id = anim ? SPR_DRONE_B : SPR_DRONE_A;
        if (e->b.vx > 0) flags |= FLIP_H;
        break;
    }
    if (e->b.yh != 1u) return;
    sprite(s, id, e->b.x, y, flags, 0, 0);
}

static void draw_enemy(const GameState *s, const Enemy *e)
{
    uint8_t st = e->state, low = st & ES_LOW, id;
    uint32_t flags = 0;
    uint8_t from = COL_SHELL, to = COL_SHELL;
    uint8_t anim = (uint8_t)((s->fc >> 3) & 1u);
    int32_t y = (int32_t)e->b.y + 8;
    if (e->type >= E_SPIKE) { draw_special(s, e); return; }
    if (e->b.yh != 1u) return;
    if (st & ESF_D) flags |= FLIP_V;
    switch (e->type) {
    case E_SQUAT:
        id = low == ES_STOMPED ? SPR_MITE_FLAT : (anim ? SPR_MITE_B : SPR_MITE_A);
        break;
    case E_HOPPER:
        id = SPR_BEETLE_WING;
        if (e->dir == 1u) flags |= FLIP_H;
        break;
    case E_ITEM_GROW: id = SPR_BATTERY; break;
    case E_ITEM_FIRE: id = SPR_CORE; break;
    case E_ITEM_STAR: id = SPR_GEAR; flags |= anim ? FLIP_H : 0u; break;
    case E_ITEM_1UP:  id = SPR_HEART; break;
    default: /* shell types */
        if (e->type == E_ARMOR) to = COL_ARMOR;
        if ((st & (ESF_S | ESF_D)) || low == ES_LANDED || low == ES_STOMPED || low == ES_KNOCK) {
            id = SPR_SHELL;
            if (low == ES_KNOCK || low == ES_LANDED) flags |= FLIP_V;
        } else {
            id = anim ? SPR_BEETLE_B : SPR_BEETLE_A;
            if (e->dir == 1u) flags |= FLIP_H;
        }
        break;
    }
    if (low == ES_EMERGE && !(st & (ESF_S | ESF_A))) {
        /* rising out of its block (E12): hidden until it has risen 5 px, then
         * only the part above the block's top shows; aux = pixels risen */
        int32_t top = scr_y((int32_t)e->b.y + e->aux + 8);
        if (e->aux < 5u) return;
        blit(g_sprite_art[id], scr_x(s, e->b.x), scr_y(y), flags, from, to, top, 0);
        return;
    }
    blit(g_sprite_art[id], scr_x(s, e->b.x), scr_y(y), flags, from, to, SCR_H, 0);
}

static void draw_frame(const GameState *s)
{
    uint32_t i;
    draw_background(s);

    for (i = 0; i < 2u; i++) {
        const Bounce *bo = &s->bounce[i];
        if (bo->active)
            blit((const uint8_t *)(s->lvl->sky ? g_tile_art[1][bo->final_tile] : g_tile_art[0][bo->final_tile]),
                 scr_x(s, bo->b.x), scr_y(bo->b.y), 0, 0, 0, SCR_H, 1);
    }
    for (i = 0; i < 6u; i++)   /* a spring object is drawn by its tile */
        if (s->e[i].type != E_NONE && s->e[i].type != E_SPRING && s->e[i].type != E_PART)
            draw_enemy(s, &s->e[i]);
    for (i = 0; i < 2u; i++) {
        const Flame *f = &s->fl[i];
        if (!f->active) continue;
        {
            uint32_t fl = f->b.vx > 0 ? FLIP_H : 0u;
            uint8_t l = (s->fc & 4u) ? SPR_JET_B_L : SPR_JET_A_L;
            uint8_t r = (s->fc & 4u) ? SPR_JET_B_R : SPR_JET_A_R;
            sprite(s, fl ? r : l, f->b.x, f->b.y, fl, 0, 0);
            sprite(s, fl ? l : r, (uint16_t)(f->b.x + 16u), f->b.y, fl, 0, 0);
        }
    }
    for (i = 0; i < 4u; i++)
        if (s->coin[i].active) sprite(s, SPR_NUT, (uint16_t)(s->coin[i].b.x - 5u), s->coin[i].b.y, 0, 0, 0);
    for (i = 0; i < 2u; i++) {
        const Fireball *f = &s->fb[i];
        if (f->state) sprite(s, f->state == 1u ? SPR_SPARK : SPR_PUFF,
                             (uint16_t)(f->b.x - 4u), (int32_t)f->b.y - 4, 0, 0, 0);
    }
    draw_player(s);

    for (i = 0; i < 10u; i++) {
        const Popup *q = i < 4u ? &s->pop[i] : &s->sc[i - 4u];
        if (!q->timer) continue;
        if (q->code >= 11u) sprite(s, SPR_HUD_HEART, q->x, q->y, 0, 0, 0);
        else number(k_popup_points[q->code], q->code >= 6u ? 4u : 3u, scr_x(s, q->x), scr_y(q->y));
    }

    draw_hud(s);
}

static uint8_t read_buttons(void)
{
    uint32_t k = REG_KEYS;
    uint8_t b = 0;
    if (k & 0x01u) b |= BTN_UP | BTN_RUN;
    if (k & 0x02u) b |= BTN_DOWN;
    if (k & 0x04u) b |= BTN_LEFT;
    if (k & 0x08u) b |= BTN_RIGHT;
    if (k & 0x10u) b |= BTN_JUMP;
    return b;
}

#ifndef HOST_PREVIEW
volatile uint8_t g_start_y;
volatile uint16_t g_start_x;
volatile uint8_t g_start_level;   /* 0 = first level; the playground's data field can set it */

int main(void)
{
    uint32_t v;
    game_reset(&g_state);
    if (g_start_level >= 2u) {   /* RAM byte set before the run: start on this level (1-based) */
        g_state.level = (uint8_t)(g_start_level - 2u);
        g_state.restart = 2;
        game_step(&g_state, 0);
        if (g_start_x != 0u) {   /* optional: stand at level X g_start_x, row-pixel g_start_y */
            g_state.p.b.x = g_start_x;
            g_state.p.b.y = g_start_y;
            g_state.cam = (uint16_t)(g_start_x > 120u ? g_start_x - 120u : 0u);
            if (g_state.cam > g_state.cam_max) g_state.cam = g_state.cam_max;
            g_state.p.prevrelx = (uint8_t)(g_state.p.b.x - g_state.cam);
        }
    }
#ifdef START_LEVEL   /* measurement builds: start on level START_LEVEL (1-based) */
    g_state.level = (uint8_t)(START_LEVEL - 2);
    g_state.restart = 2;
    game_step(&g_state, 0);
#endif
    v = REG_VSYNC;
    for (;;) {
        game_step(&g_state, read_buttons());
        draw_frame(&g_state);
        REG_PRESENT = 1u;
        while (REG_VSYNC == v) { }
        v = REG_VSYNC;
    }
}
#endif
