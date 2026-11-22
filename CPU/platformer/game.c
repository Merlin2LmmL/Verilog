/*
 * game.c - game logic, written from SPEC.md only.
 * Section numbers in comments refer to SPEC.md.
 *
 * Rules for this file: freestanding C99, fixed-width types, static memory,
 * no floating point, no 64-bit types, no * or / on variables in loops.
 * Signed reinterpretation of bytes goes through s8()/rel16() so nothing
 * depends on implementation-defined conversions or shifts of negatives.
 */
#include "game.h"

/* ------------------------------------------------------------------ */
/* small integer helpers                                               */
/* ------------------------------------------------------------------ */

/* low 8 bits of v as signed two's-complement (spec notation s8) */
static int8_t s8(uint32_t v)
{
    v &= 0xFFu;
    return (int8_t)(v >= 0x80u ? (int32_t)v - 256 : (int32_t)v);
}

/* a - b of two 16-bit level coordinates as a signed distance */
static int32_t rel16(uint16_t a, uint16_t b)
{
    uint32_t d = (uint32_t)(uint16_t)(a - b);
    return d >= 0x8000u ? (int32_t)d - 65536 : (int32_t)d;
}

static uint8_t abs8(int8_t v) { return (uint8_t)(v < 0 ? -v : v); }

/* ------------------------------------------------------------------ */
/* tiles                                                               */
/* ------------------------------------------------------------------ */

static const uint8_t k_tile_class[NUM_TILES] = {
    C_EMPTY,    /* T_SKY */
    C_SOLID,    /* T_GROUND */
    C_SOLID,    /* T_DIRT */
    C_HITTABLE, /* T_BRICK */
    C_HITTABLE, /* T_BRICK_MULTI */
    C_HITTABLE, /* T_QCOIN */
    C_HITTABLE, /* T_QPOWER */
    C_HITTABLE, /* T_QSTAR */
    C_HITTABLE, /* T_Q1UP */
    C_SOLID,    /* T_USED */
    C_HIDDEN,   /* T_HIDDEN_COIN */
    C_HIDDEN,   /* T_HIDDEN_1UP */
    C_COIN,     /* T_COIN */
    C_BUMPED,   /* T_BUMPED */
    C_SOLID,    /* T_STONE */
    C_PIPE_DL,  /* T_PIPE_TL */
    C_PIPE_DR,  /* T_PIPE_TR */
    C_SOLID,    /* T_PIPE_L */
    C_SOLID,    /* T_PIPE_R */
    C_CLIMB,    /* T_VINE (non-solid for enemies) */
    C_LEVEL_END,/* T_POLE: touching the flagpole ends the level */
    C_SPRING,   /* T_SPRING */
    C_LEVEL_END,/* T_GOAL */
    C_EMPTY,    /* T_CLOUD */
    C_EMPTY,    /* T_BUSH */
    C_EMPTY,    /* T_WATER */
    C_EMPTY,    /* T_WATERTOP */
    C_SOLID,    /* T_TREE_L */
    C_SOLID,    /* T_TREE_M */
    C_SOLID,    /* T_TREE_R */
    C_EMPTY     /* T_TRUNK: background only, walk through it */
};

uint8_t game_tile_class(uint8_t id)
{
    return id < NUM_TILES ? k_tile_class[id] : C_EMPTY;
}

/* grid column of level x; columns past 255 repeat column 255 (own choice) */
static uint32_t map_col(uint16_t px)
{
    uint32_t c = (uint32_t)px >> 4;
    return c > 255u ? 255u : c;
}

/* tile id at probe point (px, py); py is taken modulo 256 (4.1) */
static uint8_t tile_id(const GameState *s, uint16_t px, uint8_t py)
{
    uint8_t r = (uint8_t)(py & 0xF0u);
    if (r < 32u) return T_SKY;
    r = (uint8_t)((r - 32u) >> 4);
    if (r >= MAP_ROWS) return T_SKY;
    return s->m.map[((uint16_t)r << 8) | map_col(px)];
}

static uint16_t cell_index(uint16_t px, uint8_t py)
{
    return (uint16_t)(((uint16_t)(((py & 0xF0u) - 32u) >> 4) << 8) | map_col(px));
}

/* solid for enemies, fireballs and items: not EMPTY, vine, COIN, HIDDEN */
static uint8_t enemy_solid(uint8_t id)
{
    uint8_t c = game_tile_class(id);
    if (c == C_EMPTY || c == C_COIN || c == C_HIDDEN) return 0;
    if (id == T_VINE) return 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/* movement primitives (2.2, 2.4)                                      */
/* ------------------------------------------------------------------ */

/* X += Vx/16 with sub-pixel carry; returns whole pixels moved */
static int8_t body_move_x(Body *b)
{
    uint8_t v  = (uint8_t)b->vx;
    uint8_t lo = (uint8_t)(v << 4);
    int32_t hi = (int32_t)(v >> 4) - ((v & 0x80u) ? 16 : 0);
    uint32_t t = (uint32_t)b->xs + lo;
    int32_t moved = hi + (int32_t)(t >> 8);
    b->xs = (uint8_t)t;
    b->x  = (uint16_t)((int32_t)b->x + moved);
    return (int8_t)moved;
}

/* vertical integration with gravity g and terminal speed vmax */
static void body_move_y(Body *b, uint8_t g, int8_t vmax)
{
    uint32_t t = (uint32_t)b->ys + b->vyf;
    uint16_t pos = (uint16_t)(((uint16_t)b->yh << 8) | b->y);
    b->ys = (uint8_t)t;
    pos = (uint16_t)((int32_t)pos + b->vy + (int32_t)(t >> 8));
    b->yh = (uint8_t)(pos >> 8);
    b->y  = (uint8_t)pos;
    t = (uint32_t)b->vyf + g;
    b->vyf = (uint8_t)t;
    b->vy  = s8((uint32_t)(uint8_t)b->vy + (t >> 8));
    if (s8((uint32_t)(uint8_t)b->vy - (uint8_t)vmax) >= 0 && b->vyf >= 128u) {
        b->vy = vmax;
        b->vyf = 0;
    }
}

/* ------------------------------------------------------------------ */
/* score, coins, lives                                                  */
/* ------------------------------------------------------------------ */

static const uint16_t k_code_points[11] = {
    0, 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000
};

static void add_life(GameState *s) { if (s->lives < 99u) s->lives++; }

static void popup(GameState *s, uint8_t code, uint16_t x, uint8_t y)
{
    uint8_t i;
    for (i = 0; i < 4u; i++) {
        Popup *q = &s->pop[i];
        if (q->timer == 0) { q->x = x; q->y = y; q->code = code; q->timer = 40; return; }
    }
}

/* E6: a score code (capped at 11 = extra life) waits in its object slot;
 * the points or the life are added when its 48-frame timer reaches 43.
 * A second score set in the same slot before that replaces the first. */
static void award(GameState *s, uint8_t slot, uint8_t code, uint16_t x, uint8_t y)
{
    Popup *q = &s->sc[slot];
    if (code == 0) return;
    if (code > 11u) code = 11;
    q->x = x; q->y = y; q->code = code; q->timer = 48;
}

/* E13: a slot's pending score advances in the object pass, right after
 * that slot's own routine: timer 0 = no score; otherwise pay when the value
 * before counting down is 43, then count down. Not paused by the freeze. */
static void score_advance(GameState *s, uint8_t slot)
{
    Popup *q = &s->sc[slot];
    if (!q->timer) return;
    if (q->timer == 43u) {
        if (q->code >= 11u) add_life(s);
        else s->score += k_code_points[q->code];
    }
    q->timer--;
    if (q->timer & 1u) q->y--;   /* drawing only: the number floats up */
}

static void add_coin(GameState *s)
{
    s->score += 200u;
    if (++s->coins >= 100u) { s->coins = 0; add_life(s); }
}

/* ------------------------------------------------------------------ */
/* object helpers                                                       */
/* ------------------------------------------------------------------ */

static uint8_t is_item(uint8_t t) { return t >= E_ITEM_GROW && t <= E_ITEM_1UP; }
/* ordinary walkers: tile collision, enemy-vs-enemy contact, turnable (6.2) */
static uint8_t is_walker(uint8_t t) { return (t >= E_SQUAT && t <= E_HOPPER) || t == E_SPIKE; }
/* everything a fireball can hit (fire chains and second slots are not) */
static uint8_t is_enemy(uint8_t t)
{
    return (t >= E_SQUAT && t <= E_HOPPER) || (t >= E_SPIKE && t <= E_MISSILE) || t == E_BOSS;
}
static uint8_t is_two_slot(uint8_t t) { return t == E_BOSS || t == E_CHAIN_LONG; }
/* 5.2 step 6: not ground walkers, stomped when the player is 12 px higher */
static uint8_t is_flier(uint8_t t) { return t == E_HOPPER || (t >= E_FISH && t <= E_MISSILE); }
static uint8_t slot_of(const GameState *s, const Enemy *e) { return (uint8_t)(e - s->e); }
static uint8_t is_shell_type(uint8_t t) { return t == E_SHELL || t == E_LEDGE || t == E_ARMOR; }
static uint8_t is_sliding(const Enemy *e)
{
    return is_shell_type(e->type) && (e->state & ESF_S) && !(e->state & ESF_D);
}

static int8_t walk_speed(const GameState *s) { return s->hard_a ? 12 : 8; }

static void set_dir_speed(Enemy *e, uint8_t dir, int8_t mag)
{
    e->dir = dir;
    e->b.vx = (int8_t)(dir == 1u ? mag : -mag);
}

static void face_player(GameState *s, Enemy *e)
{
    int8_t mag = (int8_t)abs8(e->b.vx);
    if (mag == 0) mag = walk_speed(s);
    set_dir_speed(e, s->p.b.x < e->b.x ? 2u : 1u, mag);
}

static void turn_around(Enemy *e)
{
    e->b.vx = (int8_t)-e->b.vx;
    e->dir ^= 3u;
}

static void erase(GameState *s, uint8_t slot)
{
    uint8_t j;
    /* a two-slot object takes its second slot with it */
    if (is_two_slot(s->e[slot].type) && slot < 5u && s->e[slot + 1u].type == E_PART)
        s->e[slot + 1u].type = E_NONE;
    s->e[slot].type = E_NONE;
    for (j = 0; j < 6u; j++) s->e[j].pairs &= (uint8_t)~(1u << slot);
}

/* knock common part (6.3): state 2, Y-2, Vy -3 (-1 water), X speed +-16 */
static void knock(GameState *s, Enemy *e)
{
    if (e->type == E_HOPPER) e->type = E_SHELL;
    e->state = ES_KNOCK;
    e->b.y = (uint8_t)(e->b.y - 2u);
    e->b.vy = (s->water || e->type == E_SQUID) ? -1 : -3;
    e->b.vyf = 0;
    if (e->type == E_MISSILE) set_dir_speed(e, e->dir, 16);   /* keeps its direction */
    else set_dir_speed(e, e->b.x >= s->p.b.x ? 1u : 2u, 16);
}

/* defeated by sliding shell, fireball or invincible player (6.3) */
static void defeat(GameState *s, Enemy *e, uint8_t code)
{
    if (e->type == E_PLANT) e->b.y = (uint8_t)(e->b.y + 24u);   /* 6.3 */
    knock(s, e);
    e->state |= ESF_D;
    award(s, slot_of(s, e), code, e->b.x, e->b.y);
}

static uint8_t defeat_code(const Enemy *e) { return e->type == E_SQUAT ? 1u : 2u; }

/* overlap of two inclusive boxes given as screen x and y origins;
 * B12 is own: the boss flame (not in the spec's table) */
#define BOX_FLAME 12u
static const uint8_t k_box[13][4] = {
    {2, 8, 14, 32}, {3, 20, 13, 32}, {2, 20, 14, 32}, {2, 9, 14, 21},
    {0, 0, 24, 6},  {0, 0, 32, 13},  {0, 0, 48, 13},  {0, 0, 8, 8},
    {6, 4, 10, 8},  {3, 14, 13, 20}, {0, 2, 16, 21},  {4, 4, 12, 28},
    {2, 4, 30, 12}
};

/* E8: box edges are clipped to 0..255; a box entirely beyond an edge
 * never collides. Inclusive bounds. */
static uint8_t clip_span(int32_t lo, int32_t hi, int32_t *clo, int32_t *chi)
{
    if (hi < 0 || lo > 255) return 0;
    *clo = lo < 0 ? 0 : lo;
    *chi = hi > 255 ? 255 : hi;
    return 1;
}

static uint8_t boxes_overlap(int32_t ax, int32_t ay, uint8_t abox,
                             int32_t bx, int32_t by, uint8_t bbox)
{
    const uint8_t *a = k_box[abox], *b = k_box[bbox];
    int32_t al, ar, at, ab, bl, br, bt, bb;
    if (!clip_span(ax + a[0], ax + a[2], &al, &ar) || !clip_span(bx + b[0], bx + b[2], &bl, &br))
        return 0;
    if (!clip_span(ay + a[1], ay + a[3], &at, &ab) || !clip_span(by + b[1], by + b[3], &bt, &bb))
        return 0;
    if (al > br || bl > ar) return 0;
    if (at > bb || bt > ab) return 0;
    return 1;
}

static uint8_t enemy_box(const Enemy *e)
{
    uint8_t t = e->type;
    if (t == E_BOSS) return 10u;                       /* per half */
    if (t == E_SQUAT || (t >= E_PLANT && t <= E_MISSILE) ||
        (t == E_SPIKE && (e->state & ES_LOW) == ES_EGG)) return 9u;
    return 3u;
}

/* ------------------------------------------------------------------ */
/* level loading                                                        */
/* ------------------------------------------------------------------ */

static void clear_bytes(void *p, size_t n)
{
    uint8_t *q = (uint8_t *)p;
    while (n--) *q++ = 0;
}

static void build_map(GameState *s, const LevelDef *d)
{
    uint16_t i;
    uint8_t r, c, k;
    for (i = 0; i < MAP_ROWS * MAP_COLS / 4u; i++) s->m.map_w[i] = 0;   /* T_SKY is 0 */
    for (k = 0; k < d->nrects; k++) {
        const LevelRect *q = &d->rects[k];
        for (r = 0; r < q->h; r++) {
            uint8_t row = (uint8_t)(q->row + r);
            if (row >= MAP_ROWS) break;
            for (c = 0; c < q->w; c++)
                s->m.map[((uint16_t)row << 8) | (uint8_t)(q->col + c)] = q->id;
        }
    }
}

/* start state of a new level (9.2) */
static void load_level(GameState *s, const LevelDef *d)
{
    Player *p = &s->p;
    uint8_t keep_power = p->power;
    s->lvl = d;
    build_map(s, d);
    clear_bytes(p, sizeof *p);
    clear_bytes(s->e, sizeof s->e);
    clear_bytes(s->bounce, sizeof s->bounce);
    clear_bytes(s->fb, sizeof s->fb);
    clear_bytes(s->coin, sizeof s->coin);
    clear_bytes(s->pop, sizeof s->pop);
    clear_bytes(s->sc, sizeof s->sc);
    clear_bytes(s->ft, sizeof s->ft);
    clear_bytes(s->it, sizeof s->it);
    p->power = keep_power;
    p->big = keep_power ? 1u : 0u;
    p->b.x = d->start_x;
    p->b.y = d->start_y;
    p->b.yh = 1;
    p->face = p->mdir = 1;
    p->gfall = 40;            /* 3.1: Gfall is 40 at the start of each level */
    p->gcur = 40;
    p->blocked = 3;
    p->mode = PM_NORMAL;
    s->cam = 0;
    s->cam_max = (uint16_t)(d->cols >= 16u ? (d->cols << 4) - 256u : 0u);
    p->prevrelx = (uint8_t)(p->b.x - s->cam);
    s->water = d->water;
    s->whirl = 0;
    s->scroll_lock = 0;
    s->next_enemy = 0;
    s->freeze = 0;
    s->multi_on = 0;
    s->brk_n = 0;
    s->restart = 0;
    s->time = d->time;
    s->time_div = 0;
}

static void reset_globals(GameState *s)
{
    uint8_t i;
    clear_bytes(&s->p, sizeof s->p);
    for (i = 0; i < 7u; i++) s->rng[i] = 0;
    s->rng[0] = 0xA5;
    s->fc = 0;
    s->divider = 0;           /* E2: 0 at power-on, never reloaded by a level start */
    s->hard_a = s->hard_b = 0;
    s->fb_sel = s->bounce_sel = 0;
    s->lives = 3;
    s->coins = 0;
    s->score = 0;
    s->level = 0;
}

void game_reset(GameState *s)
{
    reset_globals(s);
    load_level(s, &g_levels[0]);
}

/* ------------------------------------------------------------------ */
/* block hits and their objects (5.5, 5.6)                              */
/* ------------------------------------------------------------------ */

static void spawn_jump_coin(GameState *s, uint16_t x, uint8_t y)
{
    uint8_t i;
    add_coin(s);
    for (i = 0; i < 4u; i++) {
        CoinObj *c = &s->coin[i];
        if (!c->active) {
            clear_bytes(c, sizeof *c);
            c->active = 1;
            c->b.x = (uint16_t)(x + 5u);
            c->b.yh = 1;
            c->b.y = (uint8_t)(y - 16u);
            c->b.vy = -5;
            return;
        }
    }
}

static void spawn_item(GameState *s, uint8_t type, uint16_t x, uint8_t top)
{
    Enemy *e = &s->e[5];
    erase(s, 5);
    clear_bytes(e, sizeof *e);
    e->type = type;
    e->state = ES_EMERGE;
    e->dir = 1;
    e->b.x = x;
    e->b.yh = 1;
    e->b.y = (uint8_t)(top - 8u);   /* 8 px above the block's top */
}

static void block_hit(GameState *s, uint16_t px, uint8_t py, uint8_t id)
{
    Player *p = &s->p;
    uint16_t ci = cell_index(px, py);
    uint8_t col = (uint8_t)ci, row = (uint8_t)(ci >> 8);
    uint16_t bx = (uint16_t)(px & 0xFFF0u);
    uint8_t  by = (uint8_t)(py & 0xF0u);
    uint8_t  final_tile = T_USED;
    Bounce *bo;

    s->m.map[ci] = T_BUMPED;
    s->ft[FT_BLOCK] = 16;

    /* a coin directly above is collected as a jumping coin */
    if (row > 0u) {
        uint16_t above = (uint16_t)(ci - 256u);
        if (game_tile_class(s->m.map[above]) == C_COIN) {
            s->m.map[above] = T_SKY;
            spawn_jump_coin(s, bx, (uint8_t)(by - 16u));
        }
    }

    if (id == T_BRICK && p->big) {
        /* break */
        p->b.vy = -2;
        s->score += 50u;
        if (s->brk_n < 2u) { s->brk_col[s->brk_n] = col; s->brk_row[s->brk_n] = row; s->brk_n++; }
        return;
    }

    /* bump */
    p->b.vy = 0;
    switch (id) {
    case T_BRICK:
        final_tile = T_BRICK;
        break;
    case T_BRICK_MULTI:
        spawn_jump_coin(s, bx, by);
        if (!s->multi_on) { s->multi_on = 1; s->it[IT_MULTI] = 11; final_tile = T_BRICK_MULTI; }
        else if (s->it[IT_MULTI]) final_tile = T_BRICK_MULTI;
        else { s->multi_on = 0; final_tile = T_USED; }
        break;
    case T_QCOIN: case T_HIDDEN_COIN:
        spawn_jump_coin(s, bx, by);
        break;
    case T_QPOWER:
        spawn_item(s, p->power ? E_ITEM_FIRE : E_ITEM_GROW, bx, by);
        break;
    case T_QSTAR:
        spawn_item(s, E_ITEM_STAR, bx, by);
        break;
    default: /* T_Q1UP, T_HIDDEN_1UP */
        spawn_item(s, E_ITEM_1UP, bx, by);
        break;
    }

    bo = &s->bounce[s->bounce_sel];
    s->bounce_sel ^= 1u;
    if (bo->active) s->m.map[((uint16_t)bo->row << 8) | bo->col] = bo->final_tile;
    clear_bytes(bo, sizeof *bo);
    bo->active = 1;
    bo->col = col;
    bo->row = row;
    bo->final_tile = final_tile;
    bo->b.x = bx;
    bo->b.yh = 1;
    bo->b.y = by;
    bo->b.vy = -2;
}

static void bounces_step(GameState *s)
{
    int8_t i;
    for (i = 1; i >= 0; i--) {
        Bounce *bo = &s->bounce[i];
        if (!bo->active) continue;
        body_move_y(&bo->b, 80, 8);
        if ((bo->b.y & 15u) < 5u) {
            s->m.map[((uint16_t)bo->row << 8) | bo->col] = bo->final_tile;
            bo->active = 0;
        }
    }
    while (s->brk_n) {
        s->brk_n--;
        s->m.map[((uint16_t)s->brk_row[s->brk_n] << 8) | s->brk_col[s->brk_n]] = T_SKY;
    }
}

static void collect_coin_at(GameState *s, uint16_t px, uint8_t py)
{
    s->m.map[cell_index(px, py)] = T_SKY;
    add_coin(s);
}

/* ------------------------------------------------------------------ */
/* player: damage and power (3.14, 5.3, 5.4)                            */
/* ------------------------------------------------------------------ */

#define JINGLE_FRAMES 150u   /* own: length of the (silent) death jingle */

static void player_die(GameState *s)
{
    Player *p = &s->p;
    p->b.vx = 0;
    p->b.vy = -4;
    p->b.vyf = 0;
    p->pstate = PS_RISE;
    p->mode = PM_DYING;
    p->jingle = JINGLE_FRAMES;
    p->spring = 0;
    s->freeze = 255;
}

static void player_hurt(GameState *s)
{
    Player *p = &s->p;
    if (s->it[IT_INJURY]) return;
    if (p->power == 0) { player_die(s); return; }
    p->power = 0;
    s->it[IT_INJURY] = 8;
    s->freeze = 255;
    p->pstate = PS_RISE;
    p->mode = PM_INJURY;
    p->spring = 0;
}

static void collect_item(GameState *s, Enemy *e)
{
    Player *p = &s->p;
    switch (e->type) {
    case E_ITEM_GROW: case E_ITEM_FIRE:
        if (p->power == 0) {
            p->power = 1; p->mode = PM_GROW; s->freeze = 255; p->pstate = PS_GROUND;
        } else if (p->power == 1) {
            p->power = 2; p->mode = PM_FIREUP; s->freeze = 255; p->pstate = PS_GROUND;
        }
        award(s, slot_of(s, e), 6, e->b.x, e->b.y);
        break;
    case E_ITEM_STAR:
        s->it[IT_STAR] = 35;
        award(s, slot_of(s, e), 6, e->b.x, e->b.y);
        break;
    default:
        award(s, slot_of(s, e), 11, e->b.x, e->b.y);
        break;
    }
}

/* ------------------------------------------------------------------ */
/* player: movement (3.2 - 3.13)                                        */
/* ------------------------------------------------------------------ */

static const uint8_t  k_cap[3] = {40, 24, 16};
static const uint8_t  k_acc[3] = {228, 152, 208};
static const uint8_t  k_jump_hold[7] = {32, 32, 30, 40, 40, 13, 4};
static const uint8_t  k_jump_fall[7] = {112, 112, 96, 144, 144, 10, 9};
static const int8_t   k_jump_vy[7]   = {-4, -4, -4, -5, -5, -2, -1};
static const uint8_t  k_jump_vyf[7]  = {0, 0, 0, 0, 0, 128, 0};

static void jump_start(GameState *s)
{
    Player *p = &s->p;
    uint8_t j, a = p->ax;
    s->ft[FT_JUMP] = 32;
    p->b.ys = 0;
    p->b.vyf = 0;
    p->y0 = p->b.y;
    p->pstate = PS_RISE;
    if (s->water) j = s->whirl ? 6u : 5u;
    else if (a < 9u) j = 0;
    else if (a < 16u) j = 1;
    else if (a < 25u) j = 2;
    else if (a < 28u) j = 3;
    else j = 4;
    p->gcur  = k_jump_hold[j];
    p->gfall = k_jump_fall[j];
    p->b.vy  = k_jump_vy[j];
    p->b.vyf = k_jump_vyf[j];
    if (s->water && p->b.y < 20u) p->b.vy = 0;
}

/* 3.3: cap index k, acceleration index f */
static void select_params(GameState *s, uint8_t lr, uint8_t ab)
{
    Player *p = &s->p;
    uint8_t k = 0, f = 0;
    uint16_t acc;
    if (p->pstate == PS_GROUND) {
        if (s->water) { k = 1; goto step4; }
        if (lr == p->mdir && (ab & PAD_B)) { s->ft[FT_RUN] = 10; goto step5; }
        if (lr == p->mdir && s->ft[FT_RUN]) goto step5;
        goto step4;
    }
    if (p->ax >= 25u) goto step5;
step4:
    k++;
    f = 1;
    if (p->runflag || p->ax >= 33u) f = 2;
step5:
    p->capr = k_cap[k];
    acc = k_acc[f];
    if (p->face != p->mdir) acc = (uint16_t)(acc << 1);
    p->acc = acc;
}

/* 3.4 acceleration step */
static void accel(GameState *s, uint8_t lr)
{
    Player *p = &s->p;
    uint8_t m = (uint8_t)(lr & p->blocked);
    uint16_t v = (uint16_t)(((uint16_t)(uint8_t)p->b.vx << 8) | p->b.vxf);
    uint8_t add;
    if (m == 0) {
        if (p->b.vx == 0) { p->ax = 0; return; }
        add = p->b.vx < 0;
    } else {
        add = (m & 1u) != 0;
    }
    if (add) {
        v = (uint16_t)(v + p->acc);
        p->b.vx = s8(v >> 8);
        p->b.vxf = (uint8_t)v;
        if (s8((uint32_t)(uint8_t)p->b.vx - p->capr) >= 0) p->b.vx = (int8_t)p->capr;
    } else {
        v = (uint16_t)(v - p->acc);
        p->b.vx = s8(v >> 8);
        p->b.vxf = (uint8_t)v;
        if (s8((uint32_t)(uint8_t)p->b.vx + p->capr) < 0) p->b.vx = (int8_t)-(int8_t)p->capr;
    }
    p->ax = abs8(p->b.vx);
}

/* 3.8 step 1 */
static void skid_check(GameState *s, uint8_t raw)
{
    Player *p = &s->p;
    if (p->ax >= 28u) p->runflag = p->ax;
    else if ((raw & 0x7Fu) == 0) { /* only A (or nothing) held */ }
    else if ((raw & 3u) == p->mdir) p->runflag = 0;
    else if (p->ax < 11u) { p->mdir = p->face; p->b.vx = 0; p->b.vxf = 0; }
}

static void ground_step(GameState *s, uint8_t raw, uint8_t lr)
{
    Player *p = &s->p;
    skid_check(s, raw);
    if (lr) p->face = lr;
    accel(s, lr);
    if (p->spring) {
        /* E4: no position update while the spring animates; the scroll logic
         * gets the animation step number 1..4 of the coming spring frame */
        p->moved = (int8_t)(((p->spring - 1u) >> 2) + 1u);
    } else {
        p->moved = body_move_x(&p->b);
    }
}

static void air_step(GameState *s, uint8_t raw, uint8_t lr, uint8_t ab, uint8_t dying)
{
    Player *p = &s->p;
    if (p->pstate == PS_FALL) {
        p->gcur = p->gfall;
    } else if (p->pstate == PS_RISE) {
        if (p->b.vy >= 0) p->gcur = p->gfall;
        else if ((ab & PAD_A) && (p->prevab & PAD_A)) { /* keep hold gravity */ }
        else if ((uint8_t)(p->y0 - p->b.y) != 0) p->gcur = p->gfall;
    }
    if (s->water && p->pstate == PS_RISE) {
        skid_check(s, raw);
        if (p->b.y < 20u) p->gcur = 24;
        if (lr) p->face = lr;
    }
    if (lr) accel(s, lr);
    p->moved = body_move_x(&p->b);
    if (dying) p->gcur = 40;
    body_move_y(&p->b, p->gcur, 4);
}

static void climb_step(GameState *s, uint8_t lr, uint8_t ud)
{
    Player *p = &s->p;
    uint8_t m;
    uint32_t t;
    uint16_t pos;
    if (ud & PAD_UP)        { p->b.vy = -1; p->b.vyf = 32; }
    else if (ud & PAD_DOWN) { p->b.vy = 1;  p->b.vyf = 255; }
    else                    { p->b.vy = 0;  p->b.vyf = 0; }
    t = (uint32_t)p->b.ys + p->b.vyf;
    p->b.ys = (uint8_t)t;
    pos = (uint16_t)(((uint16_t)p->b.yh << 8) | p->b.y);
    pos = (uint16_t)((int32_t)pos + p->b.vy + (int32_t)(t >> 8));
    p->b.yh = (uint8_t)(pos >> 8);
    p->b.y = (uint8_t)pos;

    m = (uint8_t)(lr & p->blocked);
    if (m == 0) {
        s->ft[FT_CLIMB] = 0;
    } else if (s->ft[FT_CLIMB] == 0) {
        if (m & 1u) { p->b.x = (uint16_t)(p->b.x + (p->face == 1u ? 14u : 4u)); p->face = 2; }
        else        { p->b.x = (uint16_t)(p->b.x - (p->face == 1u ? 4u : 14u)); p->face = 1; }
        s->ft[FT_CLIMB] = 24;
    }
}

/* 5.8 / E4 / E15: the spring logic runs in the spring object's slot turn
 * and does nothing at all while the freeze counter is non-zero (its step
 * counter included). Frame n = 1..13 (frame 1 is the landing frame): Y +2 on
 * frames 1-8, -2 on frames 9-13, an A press edge on frames 5-13 selects the
 * strong launch, frame 13 launches. */
static void spring_object(GameState *s)
{
    Player *p = &s->p;
    uint8_t n = p->spring;
    if (!n || s->freeze) return;
    if (n >= 5u && (p->abproc & PAD_A) && !(p->prevab & PAD_A)) p->spring_hi = 1;
    p->b.y = (uint8_t)(n <= 8u ? p->b.y + 2u : p->b.y - 2u);
    if (n >= 13u) {
        p->b.vy = p->spring_hi ? -12 : -7;   /* Vyf is still 0 from the landing */
        p->spring = 0;
        p->spring_hi = 0;
    } else {
        p->spring = (uint8_t)(n + 1u);
    }
}

/* ------------------------------------------------------------------ */
/* scrolling (7)                                                        */
/* ------------------------------------------------------------------ */

static void scroll_and_clamp(GameState *s, uint8_t lr)
{
    Player *p = &s->p;
    int8_t mv = p->moved;
    uint8_t amt = 0;
    int32_t rel;
    if (!s->scroll_lock && p->prevrelx >= 80u && !s->ft[FT_SIDE] && mv > 0) {
        if (mv >= 2 && p->prevrelx < 112u) amt = (uint8_t)(mv - 1);
        else amt = (uint8_t)mv;
    }
    if (amt) {
        uint16_t nc = (uint16_t)(s->cam + amt);
        if (nc > s->cam_max) nc = s->cam_max;   /* own: level end */
        if (nc > s->cam) s->cam = nc;
    }
    rel = rel16(p->b.x, s->cam);
    if (rel <= 0) {
        p->b.x = s->cam;
        if (lr != PAD_RIGHT) p->b.vx = 0;
    } else if (rel >= 240) {
        p->b.x = (uint16_t)(s->cam + 239u);
        if (lr != PAD_LEFT) p->b.vx = 0;
    }
}

/* ------------------------------------------------------------------ */
/* player vs tiles (4)                                                  */
/* ------------------------------------------------------------------ */

static const uint8_t k_head_dy[3] = {4, 2, 18};   /* big, big swimming, small/crouch */
static const uint8_t k_side_up[3] = {8, 8, 24};

/* 4.5 */
static void impede(GameState *s, uint8_t side)
{
    Player *p = &s->p;
    if (side == 1u) {
        if (p->b.vx >= 0) { p->b.x--; p->b.vx = 0; s->ft[FT_SIDE] = 16; }
        p->blocked &= (uint8_t)~1u;
    } else {
        if (p->b.vx < 1) { p->b.x++; p->b.vx = 0; s->ft[FT_SIDE] = 16; }
        p->blocked &= (uint8_t)~2u;
    }
}

static void level_end(GameState *s)
{
    Player *p = &s->p;
    p->mode = PM_CLEAR;
    p->mode_timer = 90;
    p->b.vx = 0;
    p->b.vy = 0;
    p->b.vyf = 0;
    p->b.y = (uint8_t)(p->b.y & 0xF0u);
}

static void side_contact(GameState *s, uint8_t id, uint16_t sx, uint8_t sy, uint8_t side)
{
    Player *p = &s->p;
    uint8_t c = game_tile_class(id);
    if (c == C_HIDDEN) return;
    if (c == C_CLIMB) {
        uint8_t f = (uint8_t)(p->b.x & 15u);
        if (f >= 6u && f <= 9u) {
            uint16_t colx = (uint16_t)(sx & 0xFFF0u);
            p->pstate = PS_CLIMB;
            p->b.vx = 0;
            p->b.vxf = 0;
            if ((uint8_t)(p->b.x - s->cam) < 16u) p->face = 2;
            p->b.x = (uint16_t)(p->face == 1u ? colx - 7u : colx + 7u);
        }
        return;
    }
    if (c == C_LEVEL_END) { level_end(s); return; }   /* flagpole and goal tiles end the level from the side too */
    if (c == C_COIN) { collect_coin_at(s, sx, sy); return; }
    if (c == C_SPRING && p->spring) return;
    /* PIPE_SIDE_BOTTOM entry: no warp areas in this game, so it impedes */
    impede(s, side);
}

static void tile_collision(GameState *s)
{
    Player *p = &s->p;
    uint8_t y, set, side;

    if (s->water) p->pstate = PS_RISE;
    else if (p->pstate == PS_GROUND || p->pstate == PS_CLIMB) p->pstate = PS_FALL;
    if (p->b.yh != 1u) return;
    p->blocked = 3;
    y = p->b.y;
    if (y >= 207u) return;
    set = (p->big && !p->crouch) ? (s->water ? 1u : 0u) : 2u;

    /* head */
    if (y >= (set != 2u ? 32u : 16u)) {
        uint16_t hx = (uint16_t)(p->b.x + 8u);
        uint8_t  hy = (uint8_t)(y + k_head_dy[set]);
        uint8_t  id = tile_id(s, hx, hy);
        uint8_t  c  = game_tile_class(id);
        if (c != C_EMPTY) {
            if (c == C_COIN) { collect_coin_at(s, hx, hy); return; }
            if (p->b.vy < 0 && (y & 15u) >= 4u) {
                if (c == C_HITTABLE || c == C_HIDDEN) {
                    if (s->water || s->ft[FT_BLOCK]) p->b.vy = 1;
                    else block_hit(s, hx, hy, id);
                } else {
                    p->b.vy = 1;   /* E1: LEVEL_END bumps too */
                }
            }
        }
    }

    /* feet */
    {
        uint8_t fy = (uint8_t)(y + 32u);
        uint16_t lx = (uint16_t)(p->b.x + 3u), rx = (uint16_t)(p->b.x + 12u);
        uint8_t lid = tile_id(s, lx, fy), rid = tile_id(s, rx, fy);
        uint8_t lc = game_tile_class(lid), rc = game_tile_class(rid);
        uint8_t t;
        if (lc == C_COIN) { collect_coin_at(s, lx, fy); return; }
        if (lc == C_EMPTY && rc == C_EMPTY) goto sides;
        if (lc == C_EMPTY && rc == C_COIN) { collect_coin_at(s, rx, fy); return; }
        t = lc != C_EMPTY ? lc : rc;
        if (t == C_CLIMB) goto sides;
        if (p->b.vy < 0) goto sides;
        if (t == C_LEVEL_END) { level_end(s); return; }
        if (t == C_HIDDEN) goto sides;
        if (p->spring) { p->pstate = PS_GROUND; goto sides; }
        if ((y & 15u) >= 5u) { impede(s, p->mdir); return; }
        if (t == C_SPRING) { p->spring = 1; p->spring_hi = 0; p->gcur = 112; }
        y = (uint8_t)(y & 0xF0u);
        p->b.y = y;
        /* down-pipe entry (Down, L on PIPE_DOWN_L, R on PIPE_DOWN_R):
         * no warp areas in this game, the check has no effect */
        p->b.vy = 0;
        p->b.vyf = 0;
        p->stomp_chain = 0;
        p->pstate = PS_GROUND;
    }

sides:
    for (side = 0; side < 2u; side++) {
        uint16_t sx = (uint16_t)(p->b.x + (side ? 13u : 2u));
        uint8_t dir = side ? 1u : 2u;
        uint8_t id, c;
        if (y >= 32u) {
            uint8_t sy = (uint8_t)(y + k_side_up[set]);
            if (y >= 228u) return;
            id = tile_id(s, sx, sy);
            c = game_tile_class(id);
            if (c != C_EMPTY && c != C_PIPE_ST && c != C_CLIMB) {
                side_contact(s, id, sx, sy, dir);
                return;
            }
        }
        if (y < 8u || y >= 208u) return;
        {
            uint8_t sy = (uint8_t)(y + 24u);
            id = tile_id(s, sx, sy);
            c = game_tile_class(id);
            if (c != C_EMPTY) { side_contact(s, id, sx, sy, dir); return; }
        }
    }
}

/* 3.15 */
static void pit_check(GameState *s)
{
    Player *p = &s->p;
    uint8_t yh = p->b.yh;
    if (yh < 2u || yh >= 0x80u) return;   /* 0x80.. = wrapped above the screen */
    s->scroll_lock = 1;
    if (p->mode != PM_DYING && !p->pit) { p->pit = 1; p->jingle = JINGLE_FRAMES; }
    if (yh >= (p->mode == PM_DYING ? 4u : 6u) && p->jingle == 0) s->restart = 1;
}

/* normal control (frame step 4.1 - 4.9) */
static void player_control(GameState *s)
{
    Player *p = &s->p;
    uint8_t raw = s->pad, ab, lr, ud;

    /* 3.2 input pre-processing */
    if (s->water && (p->b.yh != 1u || p->b.y >= 208u)) raw = 0;
    ab = raw & (PAD_A | PAD_B);
    lr = raw & (PAD_LEFT | PAD_RIGHT);
    ud = raw & (PAD_UP | PAD_DOWN);
    if ((raw & PAD_DOWN) && p->pstate == PS_GROUND && lr) { lr = 0; ud = 0; }
    p->lr = lr;
    p->abproc = ab;   /* E3: what step 11 stores as previous A/B */

    /* 3.11 crouch */
    if (!p->big) p->crouch = 0;
    else if (p->pstate == PS_GROUND) p->crouch = (ud & PAD_DOWN) ? 1u : 0u;

    /* 3.6 jump start */
    if (p->pstate != PS_CLIMB && !p->spring && (ab & PAD_A) && !(p->prevab & PAD_A)) {
        if (p->pstate == PS_GROUND) jump_start(s);
        else if (s->water && (s->ft[FT_JUMP] || p->b.vy >= 0)) jump_start(s);
    }
    select_params(s, lr, ab);

    /* movement step */
    p->moved = 0;
    if (p->spring || p->pstate == PS_GROUND) ground_step(s, raw, lr);
    else if (p->pstate == PS_CLIMB) climb_step(s, lr, ud);
    else air_step(s, raw, lr, ab, 0);
    if (p->pstate != PS_CLIMB) s->ft[FT_CLIMB] = 24;

    /* 3.5 */
    if (p->b.vx > 0) p->mdir = 1;
    else if (p->b.vx < 0) p->mdir = 2;

    scroll_and_clamp(s, lr);

    /* 5.1 box from the position at this point */
    p->relx = (uint8_t)(p->b.x - s->cam);
    p->boxy = p->b.y;
    p->box = p->big ? (p->crouch ? 2u : 0u) : 1u;

    tile_collision(s);
    pit_check(s);
}

static uint8_t player_in_control(const GameState *s)
{
    const Player *p = &s->p;
    if (p->mode == PM_NORMAL) return 1;
    return p->mode == PM_INJURY && s->freeze < 240u && s->freeze > 200u;
}

static void player_routine(GameState *s)
{
    Player *p = &s->p;
    if (p->jingle) p->jingle--;
    switch (p->mode) {
    case PM_NORMAL:
        player_control(s);
        break;
    case PM_GROW:
        if (s->freeze == 248u) p->big = 1;
        if (s->freeze <= 196u) { s->freeze = 0; p->mode = PM_NORMAL; }
        break;
    case PM_FIREUP:
        if (s->freeze <= 192u) { s->freeze = 0; p->mode = PM_NORMAL; }
        break;
    case PM_INJURY:
        if (s->freeze > 240u) break;
        if (s->freeze == 240u) { p->big = 0; p->crouch = 0; break; }
        if (s->freeze <= 200u) { s->freeze = 0; p->mode = PM_NORMAL; break; }   /* E9 */
        player_control(s);
        break;
    case PM_DYING:
        if (s->freeze >= 240u) break;
        p->lr = 0;
        p->moved = 0;
        air_step(s, 0, 0, 0, 1);
        pit_check(s);
        break;
    default: /* PM_CLEAR */
        {   /* slide down the pole until something solid is under the feet */
            uint8_t id = tile_id(s, (uint16_t)(p->b.x + 8u), (uint8_t)(p->b.y + 32u));
            if (p->b.y < 200u && (!enemy_solid(id) || id == T_POLE || id == T_GOAL))
                p->b.y = (uint8_t)(p->b.y + 2u);
        }
        if (p->mode_timer) p->mode_timer--;
        else s->restart = 2;
        break;
    }
    if (p->mode != PM_NORMAL && !player_in_control(s)) {
        p->box = p->big ? 0u : 1u;
        p->relx = (uint8_t)(p->b.x - s->cam);
        p->boxy = p->b.y;
    }
}

/* ------------------------------------------------------------------ */
/* fireballs (5.7)                                                      */
/* ------------------------------------------------------------------ */

static void fireballs_step(GameState *s)
{
    Player *p = &s->p;
    uint8_t i, j;
    if (player_in_control(s) && (p->abproc & PAD_B) && !(p->prevab & PAD_B) && p->power == 2u &&
        p->b.yh == 1u && !p->crouch && p->pstate != PS_CLIMB) {
        Fireball *f = &s->fb[s->fb_sel];
        if (f->state == 0) {
            clear_bytes(f, sizeof *f);
            f->state = 1;
            f->b.x = (uint16_t)(p->b.x + 4u);
            f->b.yh = 1;
            f->b.y = p->b.y;
            f->b.vx = p->face == 2u ? -64 : 64;
            f->b.vy = 4;
            s->fb_sel ^= 1u;
        }
    }
    for (i = 0; i < 2u; i++) {
        Fireball *f = &s->fb[i];
        int32_t rel;
        if (f->state == 2u) { if (--f->timer == 0) f->state = 0; continue; }
        if (f->state != 1u) continue;
        if (!s->freeze) {
            body_move_y(&f->b, 80, 3);
            body_move_x(&f->b);
        }
        rel = rel16(f->b.x, s->cam);
        if (rel < 0 || rel > 255 || f->b.yh != 1u) { f->state = 0; continue; }
        if (f->b.y >= 24u) {
            if (enemy_solid(tile_id(s, (uint16_t)(f->b.x + 4u), (uint8_t)(f->b.y + 8u)))) {
                if (f->b.vy < 0 || f->bounced) { f->state = 2; f->timer = 8; continue; }
                f->b.vy = -3;
                f->b.y &= 0xF8u;
                f->bounced = 1;
            } else {
                f->bounced = 0;
            }
        }
        if (s->fc & 1u) continue;
        for (j = 0; j < 5u; j++) {
            Enemy *e = &s->e[j];
            uint8_t t = e->type;
            int32_t ex;
            if (!is_enemy(t) || (e->state & ESF_D) || !e->onscreen) continue;
            ex = rel16(e->b.x, s->cam);
            if (!boxes_overlap(rel, f->b.y, 7, ex, e->b.y, enemy_box(e)) &&
                !(t == E_BOSS && boxes_overlap(rel, f->b.y, 7, ex + 16, e->b.y, 10)))
                continue;
            if (t == E_BOSS) {
                /* 6.4: five hit points; defeated: small jump, falls, 5000 */
                if (--e->hp == 0) {
                    e->state = ESF_D;
                    e->b.vy = -2;
                    e->b.vyf = 0;
                    award(s, j, 9, e->b.x, e->b.y);
                }
            } else if (t != E_ARMOR && t != E_MISSILE && t != E_LAVA) {
                defeat(s, e, defeat_code(e));
            }
            f->state = 2;
            f->timer = 8;
            break;
        }
    }
}

/* ------------------------------------------------------------------ */
/* enemies (6)                                                          */
/* ------------------------------------------------------------------ */

static void try_spawn(GameState *s, uint8_t slot)
{
    const LevelDef *d = s->lvl;
    const LevelEnemy *le;
    Enemy *e;
    uint32_t x, right;
    uint8_t type;
    if (s->next_enemy >= d->nenemies) return;
    le = &d->enemies[s->next_enemy];
    if ((le->flags & LE_HARD_B) && !s->hard_b) { s->next_enemy++; return; }
    x = (uint32_t)le->col << 4;
    right = (uint32_t)s->cam + 255u;
    if (x < right) { s->next_enemy++; return; }
    if (x > ((right + 48u) & ~15u)) return;
    type = le->type;
    /* own: a two-slot object waits until the slot above is free too */
    if (is_two_slot(type) && (slot >= 4u || s->e[slot + 1u].type != E_NONE)) return;
    s->next_enemy++;

    if (type == E_SQUAT && s->hard_a) type = E_ARMOR;
    erase(s, slot);
    e = &s->e[slot];
    clear_bytes(e, sizeof *e);
    e->type = type;
    e->b.x = (uint16_t)x;
    e->b.yh = 1;
    e->dir = 2;
    if (is_walker(type)) {                     /* ordinary enemies: Y = row * 16 + 8 */
        e->b.y = (uint8_t)((le->row << 4) + 8u);
        e->state = type == E_LEDGE ? ES_FALL : ES_WALK;
        set_dir_speed(e, 2, type == E_HOPPER || type == E_SPIKE ? 8 : walk_speed(s));
        if (type == E_SPIKE && (le->flags & LE_EGG)) {   /* 6.4 spike egg */
            e->state = ES_EGG;
            e->b.vx = 0;
            e->b.vy = -3;
        }
        return;
    }
    e->b.y = (uint8_t)(le->row << 4);          /* other objects: Y = row * 16 */
    e->hy = e->b.y;
    e->hx = e->b.x;
    switch (type) {
    case E_SPRING: e->dir = 1; break;
    case E_PLANT:                              /* own: centred on a 2-column pipe */
        e->b.x = (uint16_t)(x + 8u);
        e->b.y = (uint8_t)(e->b.y + 24u);      /* own: fully inside the pipe */
        e->hy = e->b.y;
        break;
    case E_LAVA: e->b.yh = 2; break;           /* waits below the screen */
    case E_FISH: case E_FISH_FAST:
        e->b.vx = type == E_FISH ? -4 : -8;    /* = 64 / 128 off the sub-pixel byte */
        if (slot >= 2u) e->t0 = (uint8_t)(1u + (s->rng[1] & 1u));   /* bob up / down */
        break;
    case E_MISSILE: e->b.vx = -24; break;
    case E_CHAIN: case E_CHAIN_LONG:
        if (le->flags & LE_CCW) e->dir = 1;
        break;
    case E_BOSS:
        e->hp = 5;
        e->b.vx = -1;
        e->t0 = 33;
        e->t1 = 191;
        e->t2 = 33;
        break;
    default: break;
    }
    if (is_two_slot(type)) {
        clear_bytes(&s->e[slot + 1u], sizeof(Enemy));
        s->e[slot + 1u].type = E_PART;
    }
}

static void wall_test(GameState *s, Enemy *e)
{
    uint16_t px;
    if (e->b.y < 32u || e->b.vx == 0) return;
    px = e->b.vx < 0 ? e->b.x : (uint16_t)(e->b.x + 16u);
    if (enemy_solid(tile_id(s, px, (uint8_t)(e->b.y + 20u)))) turn_around(e);
}

static void knock_from_below(GameState *s, Enemy *e, uint16_t ci)
{
    s->m.map[ci] = T_SKY;    /* one bounce knocks one enemy */
    if (is_item(e->type)) {
        e->b.vy = -3;
        e->b.vyf = 0;
        e->state |= ESF_S | ESF_A;
        set_dir_speed(e, e->b.x >= s->p.b.x ? 1u : 2u, 16);
        return;
    }
    if (e->type == E_SQUAT) { defeat(s, e, 0); e->b.y = (uint8_t)(e->b.y - 2u); }
    else knock(s, e);
    award(s, slot_of(s, e), 1, e->b.x, e->b.y);
}

static void snap_land(Enemy *e)
{
    e->b.y = (uint8_t)((e->b.y & 0xF0u) | 8u);
    e->b.vy = 0;
    e->b.vyf = 0;
}

/* 6.2 ground test + wall test for walkers, shells and walking items */
static void walker_tiles(GameState *s, Enemy *e, uint8_t slot)
{
    uint8_t st = e->state, low = st & ES_LOW, id, f;
    uint16_t px;
    if ((uint8_t)(e->b.y + 62u) < 68u) return;
    if (e->type == E_SPIKE && e->b.y < 37u) return;
    px = (uint16_t)(e->b.x + 8u);
    id = tile_id(s, px, (uint8_t)(e->b.y + 24u));
    if (game_tile_class(id) == C_BUMPED) {
        knock_from_below(s, e, cell_index(px, (uint8_t)(e->b.y + 24u)));
        return;
    }
    f = (uint8_t)(e->b.y & 15u);
    if (enemy_solid(id) && f >= 8u && f <= 12u) {
        if (st & ESF_A) {
            e->state = (uint8_t)(st & ~ESF_A);
            snap_land(e);              /* E5: no wall test on a landing frame */
        } else if ((st & ESF_S) || low == ES_WALK) {
            wall_test(s, e);
        } else if (low == ES_KNOCK) {
            e->state = ES_LANDED;
            s->it[IT_E0 + slot] = e->type == E_SPIKE ? 0u : 16u;
            snap_land(e);
        } else if (low == ES_FALL || low == ES_EGG) {
            if (e->type == E_SPIKE) {          /* right at +8, usually re-aimed */
                set_dir_speed(e, 1, 8);
                if (s->fc & 7u) face_player(s, e);
            } else if (e->type != E_SQUAT) {
                face_player(s, e);
            }
            snap_land(e);
            e->state = ES_WALK;
        }
        return;
    }
    /* no ground */
    if (e->type == E_LEDGE && st == ES_WALK) { turn_around(e); return; }   /* E5 */
    if (st & ESF_S) e->state = (uint8_t)(st | ESF_A);
    else if (low <= ES_FALL) e->state = ES_FALL;
    else if (low <= ES_STOMPED) e->state = ES_KNOCK;
    wall_test(s, e);
}

/* hopper (6.4) landing rule, also used by the invincibility item. E10/E16:
 * a BUMPED tile is ordinary ground here, so neither is knocked by it. */
static void hopper_tiles(GameState *s, Enemy *e)
{
    uint8_t id = tile_id(s, (uint16_t)(e->b.x + 8u), (uint8_t)(e->b.y + 24u));
    if (e->b.vy >= 1 && enemy_solid(id)) {
        e->b.y = (uint8_t)((e->b.y & 0xF0u) | 8u);
        e->b.vy = -3;
        e->b.vyf = 0;
    }
    wall_test(s, e);
}

static void player_hurt(GameState *s);
static void stomp(GameState *s, Enemy *e, uint8_t slot)
{
    Player *p = &s->p;
    if (e->type == E_SPIKE) { player_hurt(s); return; }
    if (e->type >= E_FISH && e->type <= E_MISSILE) {
        /* 5.2: defeated, falls off; player Vy -3; squid 1000, others 200 */
        e->state = ESF_D;
        e->b.vx = 0;
        e->b.vy = 0;
        e->b.vyf = 0;
        award(s, slot, e->type == E_SQUID ? 6u : 2u, e->b.x, e->b.y);
        p->b.vy = -3;
        return;
    }
    if (e->type == E_HOPPER) {
        e->type = E_SHELL;
        e->state = ES_WALK;
        e->b.vy = 0;
        e->b.vyf = 0;
        set_dir_speed(e, e->b.x >= p->b.x ? 1u : 2u, 8);
        award(s, slot, 3, e->b.x, e->b.y);
        p->b.vy = -4;
        return;
    }
    e->state = ES_STOMPED;
    e->b.vx = 0;
    e->b.vy = 0;
    e->b.vyf = 0;
    p->stomp_chain++;
    award(s, slot, (uint8_t)(p->stomp_chain + s->ft[FT_STOMP]), e->b.x, e->b.y);
    s->ft[FT_STOMP]++;
    s->it[IT_E0 + slot] = s->hard_a ? 11u : 16u;
    p->b.vy = -4;
}

/* 5.2 */
static void player_vs_enemy(GameState *s, Enemy *e, uint8_t slot)
{
    Player *p = &s->p;
    uint8_t low, t = e->type;
    if (p->b.yh != 1u || p->boxy >= 208u || !e->onscreen || !player_in_control(s) ||
        (e->state & ESF_D))
        return;
    if (!boxes_overlap(p->relx, p->boxy, p->box, e->boxx, e->boxy, enemy_box(e)) &&
        !(t == E_BOSS && boxes_overlap(p->relx, p->boxy, p->box, e->boxx + 16, e->boxy, 10))) {
        e->touch = 0;
        return;
    }
    if (e->touch) return;
    e->touch = 1;

    if (is_item(e->type)) {
        collect_item(s, e);
        erase(s, slot);
        return;
    }
    if (s->it[IT_STAR]) {
        /* own: the boss and lava balls ignore an invincible player */
        if (t != E_BOSS && t != E_LAVA) defeat(s, e, defeat_code(e));
        return;
    }
    if (t == E_SPIKE) goto stomp_test;                         /* step 3 */
    if (s->water || t == E_PLANT || t == E_LAVA || t == E_BOSS) { player_hurt(s); return; }
    low = e->state & ES_LOW;
    if (is_shell_type(e->type) && !(e->state & ESF_S) && (low == ES_LANDED || low == ES_STOMPED)) {
        uint8_t t = s->it[IT_E0 + slot];
        uint8_t code = t >= 3u ? (uint8_t)(p->stomp_chain + 3u) : (t == 2u ? 4u : (t == 1u ? 6u : 10u));
        award(s, slot, code, e->b.x, e->b.y);
        e->state = ES_STOMPED | ESF_S;
        e->chain = 0;
        set_dir_speed(e, e->b.x >= p->b.x ? 1u : 2u, 48);
        return;
    }
    if (e->type == E_SQUAT && low == ES_STOMPED) return;

stomp_test:
    if (p->b.vy > 0) { stomp(s, e, slot); return; }
    if (is_flier(t) && (uint32_t)p->b.y + 12u < e->b.y) { stomp(s, e, slot); return; }
    if (s->ft[FT_STOMP]) { stomp(s, e, slot); return; }
    if (s->it[IT_INJURY]) return;
    if (is_walker(t) && !(e->state & ESF_S) && e->b.vx != 0) {
        uint8_t away = (e->dir == 1u) ? (p->b.x < e->b.x) : (p->b.x >= e->b.x);
        if (away) turn_around(e);
    }
    player_hurt(s);
}

/* 6.3 / E7 / E14 enemy vs enemy, odd frames: run in the routine of the higher
 * slot i against slots i-1 down to 0. The "already acted" bit of a pair is
 * bit i of the lower enemy's `pairs`, cleared when the pair is tested
 * without overlap. */
static void enemy_vs_enemy(GameState *s, uint8_t i)
{
    Enemy *a = &s->e[i];
    uint8_t bit = (uint8_t)(1u << i);
    int8_t j;
    if (s->water || !a->onscreen || !(is_walker(a->type) || a->type == E_PLANT)) return;
    for (j = (int8_t)(i - 1u); j >= 0; j--) {
        Enemy *b = &s->e[j];
        if (!(is_walker(b->type) || b->type == E_PLANT) || !b->onscreen) continue;
        /* E14: both boxes as stored at the start of each enemy's own routine
         * this frame; the lower slot's has not followed its move */
        if (!boxes_overlap(a->boxx, a->boxy, enemy_box(a), b->boxx, b->boxy, enemy_box(b))) {
            b->pairs &= (uint8_t)~bit;
            continue;
        }
        if (b->pairs & bit) continue;
        b->pairs |= bit;
        if ((a->state & ESF_D) || (b->state & ESF_D)) continue;
        if (is_sliding(a) && is_sliding(b)) {
            defeat(s, a, 6);
            defeat(s, b, 0);
        } else if (is_sliding(a)) {
            defeat(s, b, (uint8_t)(4u + a->chain));
            a->chain++;
        } else if (is_sliding(b)) {
            defeat(s, a, (uint8_t)(4u + b->chain));
            b->chain++;
        } else if (a->type != E_PLANT && b->type != E_PLANT) {
            turn_around(a);
            turn_around(b);
        }
    }
}

static void enemy_move(GameState *s, Enemy *e, uint8_t slot)
{
    uint8_t st = e->state, low = st & ES_LOW;
    if (e->type == E_HOPPER && !(st & ESF_D)) {
        body_move_y(&e->b, 28, 3);
        body_move_x(&e->b);
        return;
    }
    if (st & ESF_D) {
        body_move_y(&e->b, 61, 3);
        body_move_x(&e->b);
    } else if (st & ESF_A) {
        int8_t keep = e->b.vx;
        body_move_y(&e->b, 61, 3);
        if (!is_item(e->type)) {
            if (keep > 0) e->b.vx = (int8_t)(keep > 24 ? keep - 24 : 0);
            else if (keep < 0) e->b.vx = (int8_t)(keep < -24 ? keep + 24 : 0);
        }
        body_move_x(&e->b);
        e->b.vx = keep;
    } else if (st & ESF_S) {
        body_move_x(&e->b);
    } else if (low == ES_WALK) {
        body_move_x(&e->b);
    } else if (low == ES_EGG) {
        body_move_y(&e->b, 32, 3);
        body_move_x(&e->b);
    } else if (low == ES_FALL || low == ES_KNOCK) {
        body_move_y(&e->b, 61, 3);
        body_move_x(&e->b);
    } else if (low == ES_LANDED || low == ES_STOMPED) {
        uint8_t t = s->it[IT_E0 + slot];
        if (e->type == E_SQUAT) {
            if (t <= 14u) erase(s, slot);
        } else if (t == 0) {
            e->state = ES_WALK;
            set_dir_speed(e, (s->fc & 1u) ? 2u : 1u, walk_speed(s));
        }
    }
}

static void despawn_check(GameState *s, uint8_t slot)
{
    Enemy *e = &s->e[slot];
    int32_t rel;
    if (e->type == E_NONE) return;
    rel = rel16(e->b.x, s->cam);
    if (rel < (e->type == E_PLANT ? -16 : -73)) { erase(s, slot); return; }
    if (rel >= 255 + 73 && e->type != E_SPRING && e->type != E_PLANT &&
        !(e->type == E_SPIKE && (e->state & ES_LOW) == ES_EGG)) { erase(s, slot); return; }
    if (e->b.yh >= 2u && e->b.yh < 0x80u && e->type != E_LAVA) erase(s, slot);
}

/* start of an object's routine: on-screen test (E8) and the stored box
 * position used by every collision test of this frame (E14) */
static void update_onscreen(GameState *s, Enemy *e)
{
    int32_t rel = rel16(e->b.x, s->cam);
    e->onscreen = (uint8_t)(rel >= -7 && rel <= 255 && e->b.yh == 1u && e->b.y <= 224u);
    e->boxx = (int16_t)(rel < -32768 ? -32768 : (rel > 32767 ? 32767 : rel));
    e->boxy = e->b.y;
}

/* ---- special objects (6.4). Field use:
 *   plant   aux phase (0 wait low, 1 rise, 2 wait high, 3 sink), t0 wait, hy low Y
 *   lava    aux 1 in flight, hy launch Y, slot interval timer = relaunch delay
 *   fish    t0 bob (0 none, 1 up, 2 down), hy spawn Y
 *   squid   aux phase 0..2, t0 speed (whole px)
 *   chain   t1:t0 spin state, dir 1 angle counts up, 2 down
 *   boss    aux step frame, t0 jump timer, t1 flame timer, t2 range, t3 approach
 *           timer, hp, chain = flame pattern step, hx/hy spawn X / floor Y,
 *           vx = whole px per 4th frame                                      */

static void defeated_fall(Enemy *e, uint8_t g, int8_t vmax)
{
    body_move_y(&e->b, g, vmax);
    body_move_x(&e->b);
}

static void plant_move(GameState *s, Enemy *e)
{
    uint8_t ph = e->aux;
    if (!(ph & 1u)) {                                  /* waiting at an end */
        if (e->t0) { e->t0--; return; }
        if (ph == 0) {                                 /* stays hidden near the player */
            int32_t d = (int32_t)s->p.b.x - (int32_t)e->b.x;
            if (d < 0) d = -d;
            if (d < 33) return;
        }
        e->aux = (uint8_t)(ph + 1u);
        return;
    }
    if (s->fc & 1u) return;                            /* 1 px every other frame */
    if (ph == 1u) {
        if (--e->b.y == (uint8_t)(e->hy - 24u)) { e->aux = 2; e->t0 = 64; }
    } else {
        if (++e->b.y == e->hy) { e->aux = 0; e->t0 = 64; }
    }
}

static void lava_move(GameState *s, Enemy *e, uint8_t slot)
{
    if (!e->aux) {                                     /* waiting below the screen */
        if (s->it[IT_E0 + slot]) return;
        e->aux = 1;
        e->b.yh = 2;                                   /* launch (own: from its spawn Y) */
        e->b.y = e->hy;
        e->b.ys = 0;
        e->b.vy = -7;
        e->b.vyf = (uint8_t)(s->rng[1] | 0x80u);
        s->it[IT_E0 + slot] = (uint8_t)((s->rng[2] & 15u) | 6u);
        return;
    }
    body_move_y(&e->b, 28, 3);
    if (e->b.vy > 0 && e->b.yh >= 2u && e->b.yh < 0x80u) e->aux = 0;   /* back below */
}

static void fish_move(Enemy *e)
{
    body_move_x(&e->b);
    if (e->t0) {
        uint16_t pos = (uint16_t)(((uint16_t)e->b.y << 8) | e->b.ys);
        uint8_t d;
        pos = (uint16_t)(e->t0 == 2u ? pos + 32u : pos - 32u);
        e->b.y = (uint8_t)(pos >> 8);
        e->b.ys = (uint8_t)pos;
        d = (uint8_t)(e->b.y >= e->hy ? e->b.y - e->hy : e->hy - e->b.y);
        if (d >= 15u) e->t0 = e->b.y < e->hy ? 2u : 1u;
    }
}

static void squid_move(GameState *s, Enemy *e, uint8_t slot)
{
    Player *p = &s->p;
    if ((s->rng[3] & (s->hard_b ? 0x03u : 0x3Fu)) == 0)
        e->dir = (slot & 1u) ? p->mdir : (p->b.x < e->b.x ? 2u : 1u);
    if (e->aux == 2u) {                                /* sinking */
        if (s->it[IT_E0 + slot]) { if (s->fc & 1u) e->b.y++; }
        else if ((uint32_t)e->b.y + 16u < p->b.y) { if (s->fc & 1u) e->b.y++; }
        else e->aux = 0;
        return;
    }
    if ((s->fc & 7u) == 0) {
        if (e->aux == 0) { if (++e->t0 >= 2u) e->aux = 1; }
        else if (e->t0 == 0 || --e->t0 == 0) { e->aux = 2; s->it[IT_E0 + slot] = 2; }
    }
    e->b.y = (uint8_t)(e->b.y < 32u + e->t0 ? 32u : e->b.y - e->t0);
    e->b.x = (uint16_t)(e->dir == 1u ? e->b.x + e->t0 : e->b.x - e->t0);
}

/* fire chain geometry: R[n][i] for segments 1..11 (segment 0 is the pivot) */
static const uint8_t k_chain_r[11][9] = {
    {0, 1, 3, 4, 5, 6, 7, 7, 8},         {0, 3, 6, 9, 11, 13, 14, 15, 16},
    {0, 4, 9, 13, 16, 19, 22, 23, 24},   {0, 6, 12, 18, 22, 26, 29, 31, 32},
    {0, 7, 15, 22, 28, 33, 37, 39, 40},  {0, 9, 18, 27, 33, 39, 44, 47, 48},
    {0, 11, 21, 31, 39, 46, 51, 55, 56}, {0, 12, 24, 36, 45, 53, 59, 62, 64},
    {0, 14, 27, 40, 50, 59, 66, 70, 72}, {0, 15, 31, 45, 56, 66, 74, 78, 80},
    {0, 17, 34, 49, 62, 73, 81, 86, 88}
};

void game_chain_offset(const Enemy *e, uint8_t n, int8_t *dx, int8_t *dy)
{
    uint8_t ang = (uint8_t)(e->t1 & 31u), a = (uint8_t)(ang & 15u);
    uint8_t b = (uint8_t)((ang + 8u) & 15u), q = (uint8_t)(ang >> 3);
    int8_t x, y;
    if (n == 0) { *dx = 0; *dy = 0; return; }
    x = (int8_t)k_chain_r[n - 1u][a <= 8u ? a : 16u - a];
    y = (int8_t)k_chain_r[n - 1u][b <= 8u ? b : 16u - b];
    *dx = q >= 2u ? (int8_t)-x : x;                 /* q0 (+,-) q1 (+,+) q2 (-,+) q3 (-,-) */
    *dy = (q == 0 || q == 3u) ? (int8_t)-y : y;
}

static void chain_routine(GameState *s, Enemy *e)
{
    Player *p = &s->p;
    uint8_t n, segs = e->type == E_CHAIN ? 6u : 12u;
    if (!s->freeze) {
        uint16_t spin = (uint16_t)(((uint16_t)e->t1 << 8) | e->t0);
        uint8_t v = e->type == E_CHAIN ? 40u : 56u;
        spin = (uint16_t)(e->dir == 1u ? spin - v : spin + v);
        e->t0 = (uint8_t)spin;
        e->t1 = (uint8_t)(spin >> 8);
        if (e->type == E_CHAIN_LONG && ((e->t1 & 15u) == 8u)) e->t1++;   /* skips 8 and 24 */
    }
    /* contact, every frame (6.4) */
    if (s->it[IT_STAR] || s->freeze || p->b.yh != 1u || !player_in_control(s)) return;
    for (n = 0; n < segs; n++) {
        int8_t dx, dy;
        int32_t sx, d;
        uint8_t sy, hy, k, hit = 0;
        game_chain_offset(e, n, &dx, &dy);
        sx = rel16((uint16_t)(CHAIN_PX(e) + dx), s->cam);
        if (sx < 0 || sx >= 240) continue;
        d = (int32_t)(uint8_t)(p->b.x - s->cam) + 4 - sx;
        if (d < -7 || d > 7) continue;
        sy = (uint8_t)(CHAIN_PY(e) + dy);
        k = (p->big && !p->crouch) ? 3u : 1u;          /* heights Y, Y+12, Y+24 or Y+24 */
        hy = (uint8_t)(p->b.y + (k == 3u ? 0u : 24u));
        for (; k > 0; k--, hy = (uint8_t)(hy + 12u)) {
            d = (int32_t)hy - sy;
            if (d >= -7 && d <= 7) hit = 1;
        }
        if (hit) { player_hurt(s); return; }
    }
}

static const uint8_t k_boss_four[4] = {33, 65, 17, 49};
/* own order of the spec's 8-step pattern of 191 and 64 frames */
static const uint8_t k_boss_flame[8] = {191, 64, 64, 191, 191, 64, 191, 64};
static const uint8_t k_flame_dy[4] = {4, 12, 20, 12};   /* own: target heights */

static void boss_flame(GameState *s, Enemy *e)
{
    uint8_t i;
    for (i = 0; i < 2u; i++) {
        Flame *f = &s->fl[i];
        if (f->active) continue;
        clear_bytes(f, sizeof *f);
        f->active = 1;
        f->b.yh = 1;
        f->b.x = (uint16_t)(e->dir == 1u ? e->b.x + 24u : e->b.x - 24u);
        f->b.y = (uint8_t)(e->b.y + 2u);
        f->b.vx = e->dir == 1u ? 16 : -16;
        f->ty = (uint8_t)(e->hy + k_flame_dy[s->rng[4] & 3u]);
        return;
    }
}

static void boss_move(GameState *s, Enemy *e)
{
    Player *p = &s->p;
    uint8_t right = (uint8_t)((uint32_t)p->b.x >= (uint32_t)e->b.x + 32u), chase;
    if ((s->fc & 31u) == 0) e->aux ^= 1u;
    if ((s->fc & 15u) == 0) e->dir = 2;
    /* own: the approach timer is kept running while the player is past it */
    if (right) e->t3 = 32;
    else if (e->t3) e->t3--;
    chase = (uint8_t)(e->t3 && right);
    if (chase) { e->dir = 1; e->t1 = 32; }
    if ((s->fc & 3u) == 0) {
        if (chase) {
            e->b.x = (uint16_t)(e->b.x + 2u);
        } else {
            int32_t d = (int32_t)e->b.x - (int32_t)e->hx;
            e->b.x = (uint16_t)(e->b.x + e->b.vx);
            if ((e->b.vx > 0 && d > e->t2) || (e->b.vx < 0 && -d > e->t2)) {
                e->b.vx = (int8_t)-e->b.vx;
                e->t2 = k_boss_four[s->rng[2] & 3u];
            }
        }
    }
    /* hop: jumps one frame before the timer runs out, then falls */
    if (e->t0) {
        if (--e->t0 == 1u) { e->b.vy = -2; e->b.vyf = 0; }
    } else {
        body_move_y(&e->b, 15, 2);
        if (e->b.vy >= 0 && e->b.yh == 1u && e->b.y >= e->hy) {
            e->b.y = e->hy;
            e->b.ys = 0;
            e->b.vy = 0;
            e->b.vyf = 0;
            e->t0 = k_boss_four[s->rng[5] & 3u];
        }
    }
    if (e->t1 && --e->t1) return;
    if (e->onscreen) boss_flame(s, e);
    e->t1 = (uint8_t)(k_boss_flame[e->chain & 7u] - (s->hard_b ? 16u : 0u));
    e->chain++;
}

/* boss flames: fly straight, drift toward their target height, hurt */
static void flames_step(GameState *s)
{
    Player *p = &s->p;
    uint8_t i;
    for (i = 0; i < 2u; i++) {
        Flame *f = &s->fl[i];
        int32_t rel;
        if (!f->active) continue;
        if (!s->freeze) {
            body_move_x(&f->b);
            if (!(s->fc & 1u) && f->b.y != f->ty) f->b.y = (uint8_t)(f->b.y < f->ty ? f->b.y + 1u : f->b.y - 1u);
        }
        rel = rel16(f->b.x, s->cam);
        if (rel < -32 || rel > 255) { f->active = 0; continue; }
        if ((s->fc & 1u) && !s->it[IT_STAR] && p->b.yh == 1u && player_in_control(s) &&
            boxes_overlap(p->relx, p->boxy, p->box, rel, f->b.y, BOX_FLAME))
            player_hurt(s);
    }
}

static void special_routine(GameState *s, Enemy *e, uint8_t slot)
{
    uint8_t t = e->type;
    if (t == E_CHAIN || t == E_CHAIN_LONG) { chain_routine(s, e); return; }
    if (!(s->fc & 1u)) player_vs_enemy(s, e, slot);
    if (e->type == E_NONE || s->freeze) return;
    if (e->state & ESF_D) {                          /* defeated: falls off */
        if (t == E_FISH || t == E_FISH_FAST || t == E_SQUID || t == E_BOSS) defeated_fall(e, 15, 2);
        else defeated_fall(e, 61, 3);
        return;
    }
    switch (t) {
    case E_PLANT:   plant_move(s, e); break;
    case E_LAVA:    lava_move(s, e, slot); break;
    case E_SQUID:   squid_move(s, e, slot); break;
    case E_MISSILE: body_move_x(&e->b); break;
    case E_BOSS:    boss_move(s, e); break;
    default:        fish_move(e); break;
    }
}

static void enemy_routine(GameState *s, uint8_t slot)
{
    Enemy *e = &s->e[slot];
    update_onscreen(s, e);
    if (!is_walker(e->type)) {
        special_routine(s, e, slot);
        despawn_check(s, slot);
        return;
    }
    if (!(e->state & ESF_D)) {
        if (e->type == E_HOPPER) hopper_tiles(s, e);
        else walker_tiles(s, e, slot);
    }
    if (s->fc & 1u) enemy_vs_enemy(s, slot);
    else player_vs_enemy(s, e, slot);
    if (e->type != E_NONE && !s->freeze) enemy_move(s, e, slot);
    despawn_check(s, slot);
}

/* items released from blocks (6.4) */
static void item_routine(GameState *s, uint8_t slot)
{
    Enemy *e = &s->e[slot];
    update_onscreen(s, e);
    if ((e->state & ES_LOW) == ES_EMERGE) {
        /* E12: 1 px on every frame with frame counter AND 3 = 0, also during
         * a freeze; after 17 rises (25 px above the block's top) it starts
         * moving. aux counts the rises. Drawn, collidable and despawn-checked
         * only once it has risen 5 px. */
        if ((s->fc & 3u) == 0) {
            e->b.y--;
            e->aux++;
            if (e->aux >= 17u) {
                if (e->type == E_ITEM_FIRE) e->state = ES_WALK;
                else { e->state = ESF_S; set_dir_speed(e, 1, 16); }
                e->b.vy = 0;
                e->b.vyf = 0;
            }
        }
        if (e->aux >= 5u) {
            if (!(s->fc & 1u)) player_vs_enemy(s, e, slot);
            despawn_check(s, slot);
        }
        return;
    }
    if (e->type == E_ITEM_STAR) {
        hopper_tiles(s, e);
    } else if (e->type != E_ITEM_FIRE) {
        walker_tiles(s, e, slot);
    }
    if (!(s->fc & 1u)) player_vs_enemy(s, e, slot);
    if (e->type == E_NONE) return;
    if (!s->freeze && e->type != E_ITEM_FIRE) {
        if (e->type == E_ITEM_STAR) { body_move_y(&e->b, 28, 3); body_move_x(&e->b); }
        else enemy_move(s, e, slot);
    }
    despawn_check(s, slot);
}

static void objects_step(GameState *s)
{
    uint8_t i, spring_ran = 0;
    for (i = 0; i < 6u; i++) {
        uint8_t t = s->e[i].type;
        if (t == E_NONE) { if (i < 5u) try_spawn(s, i); }
        else if (t == E_PART) { }   /* run by the slot below */
        else if (t == E_SPRING) {
            /* E15: the spring logic runs in the spring object's own turn */
            update_onscreen(s, &s->e[i]);
            spring_object(s);
            spring_ran = 1;
            despawn_check(s, i);
        }
        else if (is_item(t)) item_routine(s, i);
        else enemy_routine(s, i);
        score_advance(s, i);   /* E13 */
    }
    /* own fallback: a spring tile without a spring object in any slot */
    if (!spring_ran) spring_object(s);
}

/* ------------------------------------------------------------------ */
/* misc objects, popups, level timer                                    */
/* ------------------------------------------------------------------ */

static void misc_step(GameState *s)
{
    int8_t i;
    for (i = 3; i >= 0; i--) {
        CoinObj *c = &s->coin[i];
        if (!c->active || s->freeze) continue;
        body_move_y(&c->b, 80, 6);
        if (c->b.vy >= 5) { popup(s, 2, c->b.x, c->b.y); c->active = 0; }
    }
}

static void popups_step(GameState *s)
{
    uint8_t i;
    for (i = 0; i < 4u; i++) {
        Popup *q = &s->pop[i];
        if (!q->timer) continue;
        q->timer--;
        if (q->timer & 1u) q->y--;
    }
}

static void level_timer(GameState *s)
{
    if (!s->time || s->p.mode != PM_NORMAL) return;
    if (++s->time_div < 24u) return;
    s->time_div = 0;
    if (--s->time == 0) {
        s->p.power = 0;
        s->it[IT_INJURY] = 0;
        player_die(s);
    }
}

/* own: what happens after a life is lost or a level is cleared */
static void handle_restart(GameState *s)
{
    uint8_t why = s->restart;
    s->restart = 0;
    if (why == 2u) {
        s->score += (uint32_t)s->time * 50u;   /* time bonus, no multiply in a loop */
        s->level = (uint8_t)(s->level + 1u);
        if (s->level >= g_num_levels) s->level = 0;
        if (s->level == 0) { if (s->hard_a) s->hard_b = 1; s->hard_a = 1; }
    } else {
        s->p.power = 0;
        if (s->lives <= 1u) { game_reset(s); return; }
        s->lives--;
    }
    load_level(s, &g_levels[s->level]);
}

/* ------------------------------------------------------------------ */
/* one frame (1)                                                        */
/* ------------------------------------------------------------------ */

static uint8_t map_buttons(uint8_t b)
{
    uint8_t pad = 0;
    if (b & BTN_UP)    pad |= PAD_UP;
    if (b & BTN_DOWN)  pad |= PAD_DOWN;
    if (b & BTN_LEFT)  pad |= PAD_LEFT;
    if (b & BTN_RIGHT) pad |= PAD_RIGHT;
    if (b & BTN_JUMP)  pad |= PAD_A;
    if (b & BTN_RUN)   pad |= PAD_B;
    return pad;
}

void game_step(GameState *s, uint8_t buttons)
{
    Player *p = &s->p;
    uint8_t i, timers = 1;

    /* 1 sample input */
    s->pad = map_buttons(buttons);

    /* 2 freeze and timers */
    if (s->freeze) { s->freeze--; if (s->freeze) timers = 0; }
    if (timers) {
        for (i = 0; i < FT_COUNT; i++) if (s->ft[i]) s->ft[i]--;
        if (s->divider == 0) {
            s->divider = 20;
            for (i = 0; i < IT_COUNT; i++) if (s->it[i]) s->it[i]--;
        } else {
            s->divider--;
        }
    }
    s->fc++;

    /* 3 pseudo-random step */
    {
        uint8_t nb = (uint8_t)(((s->rng[0] ^ s->rng[1]) >> 1) & 1u);
        for (i = 6; i > 0; i--)
            s->rng[i] = (uint8_t)((s->rng[i] >> 1) | (uint8_t)(s->rng[i - 1] << 7));
        s->rng[0] = (uint8_t)((s->rng[0] >> 1) | (uint8_t)(nb << 7));
    }

    /* 4 player */
    player_routine(s);

    /* 5 fireballs */
    fireballs_step(s);

    /* 6 objects */
    objects_step(s);

    /* 7 previous relative X (not refreshed on undrawn invincible frames);
     * pending scores advance in step 6 (E13) */
    if (!(s->it[IT_INJURY] && (s->fc & 1u)))
        p->prevrelx = (uint8_t)(p->b.x - s->cam);
    popups_step(s);   /* jumping-coin popups (drawing only) */

    /* 8 bouncing blocks, tile write-back */
    bounces_step(s);

    /* 9 misc objects */
    misc_step(s);
    flames_step(s);

    /* 10 level timer */
    level_timer(s);

    /* 11 previous A/B: as last processed by the input step (E3) */
    p->prevab = p->abproc;

    if (s->restart) handle_restart(s);
}
