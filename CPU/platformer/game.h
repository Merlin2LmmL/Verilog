/*
 * game.h - deterministic game logic for the clean-room platformer.
 *
 * Freestanding C99. Only <stdint.h> and <stddef.h>. No I/O in this layer.
 * Coordinates and units follow SPEC.md exactly:
 *   X      16-bit level pixels, Xsub = sub-pixel byte (top nibble = 1/16 px)
 *   Yh:Y   16-bit vertical position (Yh 1 = visible screen), Ys = 1/256 px
 *   Vx     signed 1/16 px per frame, Vxf = 1/256 of a Vx unit
 *   Vy:Vyf signed 8.8 px per frame
 */
#ifndef GAME_H
#define GAME_H

#include <stdint.h>
#include <stddef.h>

/* ---- buttons passed to game_step (task-defined bit layout) ---- */
#define BTN_UP    0x01u
#define BTN_DOWN  0x02u
#define BTN_LEFT  0x04u
#define BTN_RIGHT 0x08u
#define BTN_JUMP  0x10u   /* spec button A */
#define BTN_RUN   0x20u   /* spec button B (run, fireball) */

/* ---- internal pad word (spec section "Notation") ---- */
#define PAD_A     0x80u
#define PAD_B     0x40u
#define PAD_UP    0x08u
#define PAD_DOWN  0x04u
#define PAD_LEFT  0x02u
#define PAD_RIGHT 0x01u

/* ---- level grid ---- */
#define MAP_ROWS 13u          /* rows 0..12 cover screen y 32..239 */
#define MAP_COLS 256u         /* fixed stride; column index wraps at 256 */

/* tile ids (own numbering; behaviour class via table in game.c) */
enum {
    T_SKY = 0, T_GROUND, T_DIRT, T_BRICK, T_BRICK_MULTI,
    T_QCOIN, T_QPOWER, T_QSTAR, T_Q1UP, T_USED,
    T_HIDDEN_COIN, T_HIDDEN_1UP, T_COIN, T_BUMPED, T_STONE,
    T_PIPE_TL, T_PIPE_TR, T_PIPE_L, T_PIPE_R, T_VINE,
    T_POLE, T_SPRING, T_GOAL, T_CLOUD, T_BUSH,
    T_WATER, T_WATERTOP,
    T_TREE_L, T_TREE_M, T_TREE_R, T_TRUNK,   /* mushroom platform: solid cap, background trunk */
    NUM_TILES
};

/* tile behaviour classes (SPEC 4.1) */
enum {
    C_EMPTY = 0, C_SOLID, C_HITTABLE, C_HIDDEN, C_COIN, C_CLIMB,
    C_SPRING, C_BUMPED, C_PIPE_DL, C_PIPE_DR, C_PIPE_ST, C_PIPE_SB,
    C_LEVEL_END
};

/* player states (pstate) */
#define PS_GROUND 0u
#define PS_RISE   1u
#define PS_FALL   2u
#define PS_CLIMB  3u

/* player modes (own coding of the spec's "player routine modes") */
enum { PM_NORMAL = 0, PM_GROW, PM_FIREUP, PM_INJURY, PM_DYING, PM_CLEAR };

/* object types in slots 0..5 */
enum {
    E_NONE = 0,
    E_SQUAT,      /* squat walker */
    E_SHELL,      /* shell walker */
    E_LEDGE,      /* ledge-aware shell walker */
    E_ARMOR,      /* armored walker (fireproof shell walker) */
    E_HOPPER,     /* winged shell walker, jumping */
    E_ITEM_GROW,  /* growth item */
    E_ITEM_FIRE,  /* fire item */
    E_ITEM_STAR,  /* invincibility item */
    E_ITEM_1UP,   /* extra-life item */
    E_SPRING,     /* spring object (E15): runs the spring animation in its slot */
    E_SPIKE,      /* spike walker (LE_EGG: starts as a falling spike egg) */
    E_PLANT,      /* pipe plant; entry col = left pipe column, row = pipe top row */
    E_LAVA,       /* lava ball; waits below the screen, leaps up */
    E_FISH,       /* swimming fish, slow */
    E_FISH_FAST,  /* swimming fish, fast */
    E_SQUID,      /* squid swimmer */
    E_MISSILE,    /* free-flying missile */
    E_CHAIN,      /* fire chain, short (6 segments); entry = pivot block */
    E_CHAIN_LONG, /* fire chain, long (12 segments), two slots */
    E_BOSS,       /* boss, two slots; entry row = row it stands on */
    E_PART        /* second slot of a two-slot object (owned by the slot below) */
};

/* enemy state byte: low 3 bits = state, high bits = flags (SPEC 6.2) */
#define ES_WALK    0u
#define ES_FALL    1u
#define ES_KNOCK   2u
#define ES_LANDED  3u
#define ES_STOMPED 4u
#define ES_EGG     5u
#define ES_EMERGE  6u   /* own: item still rising out of its block */
#define ES_LOW     0x07u
#define ESF_D      0x80u /* defeated: falls through everything */
#define ESF_S      0x40u /* sliding shell / emerged moving item */
#define ESF_A      0x20u /* sliding shell or item that is airborne */

/* frame timers (tick every frame, SPEC 2.5) */
enum { FT_RUN = 0, FT_JUMP, FT_SIDE, FT_BLOCK, FT_CLIMB, FT_STOMP, FT_COUNT };
/* interval timers (tick every 21 frames) */
enum { IT_INJURY = 0, IT_STAR, IT_MULTI, IT_E0, IT_COUNT = IT_E0 + 6 };

/* Position and speed of anything that moves (SPEC 2.1 - 2.4). */
typedef struct {
    uint16_t x;    /* level X, whole px */
    uint8_t  xs;   /* X sub-pixel byte, top nibble used (1/16 px) */
    uint8_t  yh;   /* vertical screen number: 0 above, 1 visible, >=2 below */
    uint8_t  y;    /* screen row of reference point */
    uint8_t  ys;   /* Y sub-pixel, 1/256 px */
    int8_t   vx;   /* X speed, 1/16 px per frame */
    uint8_t  vxf;  /* fraction of a Vx unit, 1/256 (player acceleration only) */
    int8_t   vy;   /* Y speed, whole px per frame */
    uint8_t  vyf;  /* Y speed fraction, 1/256 px per frame */
    uint8_t  rsv[2]; /* padding: keeps object structs at power-of-two sizes */
} Body;

typedef struct {
    Body    b;
    uint8_t ax;        /* |Vx| stored by the acceleration step */
    uint8_t face;      /* facing direction 1 right, 2 left (3 = both held) */
    uint8_t mdir;      /* moving direction 1/2 */
    uint8_t pstate;    /* PS_* */
    uint8_t gcur;      /* gravity used this frame, 1/256 px/f^2 */
    uint8_t gfall;     /* fall gravity from last jump start (40 at level start) */
    uint8_t y0;        /* Y at jump start */
    uint8_t runflag;   /* non-zero once high ground speed was reached */
    uint8_t blocked;   /* bit0 right allowed, bit1 left allowed */
    uint8_t prevab;    /* A/B bits of the previous frame (E3: as last processed) */
    uint8_t abproc;    /* A/B bits as last processed by the input step (3.2) */
    uint8_t boxy;      /* Y when the box was computed (5.1, before the tile pass) */
    uint8_t big;       /* collision/draw size: 0 small, 1 big */
    uint8_t power;     /* 0 small, 1 big, 2 fire */
    uint8_t crouch;    /* crouch flag */
    uint8_t mode;      /* PM_* */
    int8_t  moved;     /* whole px moved by this frame's position update */
    uint8_t lr;        /* processed left/right bits of this frame */
    uint8_t prevrelx;  /* screen-relative X recorded at end of previous frame */
    uint8_t relx;      /* screen-relative X when the box was computed (5.1) */
    uint8_t box;       /* bounding box index (0, 1 or 2) */
    uint8_t capr;      /* speed cap selected this frame (1/16 px/f) */
    uint16_t acc;      /* acceleration selected this frame (9 bit) */
    uint8_t spring;    /* spring frame to run next in the object pass, 1..13; 0 = idle (5.8) */
    uint8_t spring_hi; /* strong spring launch selected */
    uint8_t stomp_chain; /* stomp chain counter (5.6) */
    uint8_t jingle;    /* own: frames left of the death jingle */
    uint8_t pit;       /* own: pit fall already noticed */
    uint8_t mode_timer;/* own: frames left in the level-clear sequence */
} Player;

typedef struct {
    Body    b;
    uint8_t type;      /* E_* */
    uint8_t state;     /* ES_* | ESF_* */
    uint8_t dir;       /* 1 right, 2 left */
    uint8_t touch;     /* "touching the player" memory bit */
    uint8_t pairs;     /* bit j: overlapping enemy slot j last odd frame */
    uint8_t chain;     /* sliding-shell chain count */
    uint8_t aux;       /* per type: item emerge counter */
    uint8_t onscreen;  /* on screen for collisions this frame (E8) */
    int16_t boxx;      /* E14: screen-relative X stored at the start of its routine */
    uint8_t boxy;      /* E14: Y stored at the start of its routine */
    uint8_t t0, t1, t2, t3; /* per type: private counters (see game.c) */
    uint8_t hy;        /* per type: spawn Y (plant bottom, fish centre, boss floor) */
    uint8_t hp;        /* boss hit points */
    uint16_t hx;       /* per type: spawn X (boss) */
} Enemy;              /* 32 bytes: slot index -> shift, no multiply */

typedef struct {
    Body    b;
    uint8_t active;
    uint8_t col, row;    /* grid cell being bounced */
    uint8_t final_tile;  /* tile written when the bounce ends */
} Bounce;

typedef struct {
    Body    b;
    uint8_t state;       /* 0 free, 1 flying, 2 exploding */
    uint8_t bounced;     /* bounced on the previous frame */
    uint8_t timer;       /* explosion frames left */
    uint8_t rsv;         /* padding to 16 bytes */
} Fireball;

typedef struct {
    Body    b;
    uint8_t active;      /* jumping coin from a block */
    uint8_t rsv[3];      /* padding to 16 bytes */
} CoinObj;

typedef struct {
    Body    b;
    uint8_t active;      /* boss flame in flight */
    uint8_t ty;          /* target Y it drifts toward */
    uint8_t rsv[2];      /* padding to 16 bytes */
} Flame;

typedef struct {
    uint16_t x;          /* level X */
    uint8_t  y;          /* screen Y */
    uint8_t  code;       /* score code 1..11 */
    uint8_t  timer;      /* frames left, 0 = free (pending scores: 48, award at 43) */
    uint8_t  rsv[3];     /* padding to 8 bytes */
} Popup;

/* compile-time size checks (array of size -1 fails to compile) */
typedef char check_body_size[sizeof(Body) == 12 ? 1 : -1];
typedef char check_enemy_size[sizeof(Enemy) == 32 ? 1 : -1];
typedef char check_bounce_size[sizeof(Bounce) == 16 ? 1 : -1];
typedef char check_fireball_size[sizeof(Fireball) == 16 ? 1 : -1];
typedef char check_coin_size[sizeof(CoinObj) == 16 ? 1 : -1];
typedef char check_flame_size[sizeof(Flame) == 16 ? 1 : -1];
typedef char check_popup_size[sizeof(Popup) == 8 ? 1 : -1];

/* level description (data in levels.c) */
typedef struct { uint8_t id, col, row, w, h; } LevelRect;  /* fill rectangle */
typedef struct { uint8_t col, row, type, flags; } LevelEnemy; /* row = grid row stood on */
#define LE_HARD_B 0x01u   /* entry only present in hard mode B */
#define LE_EGG    0x02u   /* E_SPIKE: spawn as a falling spike egg */
#define LE_CCW    0x04u   /* E_CHAIN*: spin the other way (angle counts down) */
typedef struct {
    const LevelRect  *rects;
    const LevelEnemy *enemies;
    uint8_t  nrects;
    uint8_t  nenemies;
    uint16_t cols;       /* level width in columns (1..256) */
    uint8_t  water;      /* water level flag */
    uint8_t  start_y;    /* player start Y */
    uint16_t start_x;    /* player start X */
    uint16_t time;       /* level timer start, 0 = no timer */
    uint8_t  sky;        /* drawing only: background set, 0 open air, 1 water */
} LevelDef;

extern const LevelDef g_levels[];
extern const uint8_t  g_num_levels;

struct GameState {
    union {
        uint8_t  map[MAP_ROWS * MAP_COLS];   /* tile ids, index (row << 8) | col */
        uint32_t map_w[MAP_ROWS * MAP_COLS / 4u]; /* same bytes, for word-wise clearing */
    } m;
    Player   p;
    Enemy    e[6];        /* object slots 0..4 enemies, 5 items */
    Bounce   bounce[2];
    Fireball fb[2];
    CoinObj  coin[4];
    Flame    fl[2];       /* boss flames */
    Popup    pop[4];      /* cosmetic floating numbers (jumping coins) */
    Popup    sc[6];       /* E6: one pending floating score per object slot */
    uint8_t  ft[FT_COUNT];   /* frame timers */
    uint8_t  it[IT_COUNT];   /* interval timers */
    uint8_t  rng[7];         /* 56-bit shift register R0..R6 */
    uint16_t cam;            /* camera X (left screen edge, level px) */
    uint16_t cam_max;        /* own: right end of the level */
    uint8_t  pad;            /* this frame's pad word (PAD_*) */
    uint8_t  fc;             /* 8-bit frame counter */
    uint8_t  freeze;         /* global freeze counter */
    uint8_t  divider;        /* interval divider (0..20) */
    uint8_t  water;          /* water level */
    uint8_t  whirl;          /* inside a whirlpool (never set: no whirlpools) */
    uint8_t  hard_a, hard_b; /* progression flags */
    uint8_t  scroll_lock;
    uint8_t  level;          /* index into g_levels */
    uint8_t  next_enemy;     /* next pending level-object entry */
    uint8_t  fb_sel;         /* fireball slot used by the next throw */
    uint8_t  bounce_sel;     /* bounce slot used by the next block hit */
    uint8_t  multi_on;       /* multi-coin brick sequence started */
    uint8_t  brk_n;          /* number of pending brick removals */
    uint8_t  brk_col[2], brk_row[2];
    uint8_t  lives;
    uint8_t  coins;
    uint8_t  restart;        /* own: 1 = life lost, 2 = level cleared */
    uint8_t  time_div;       /* own: level-timer frame divider */
    uint16_t time;           /* own: level timer, 0 = disabled */
    uint32_t score;
    const LevelDef *lvl;
};
typedef struct GameState GameState;

void game_reset(GameState *s);
void game_step(GameState *s, uint8_t buttons);   /* exactly one frame */

/* helpers shared with the platform layer */
uint8_t game_tile_class(uint8_t id);
/* fire chain segment n (0..11): offset from the pivot in level px */
void game_chain_offset(const Enemy *e, uint8_t n, int8_t *dx, int8_t *dy);
/* fire chain pivot: level X and screen Y of segment 0's top-left corner */
#define CHAIN_PX(e) ((uint16_t)((e)->b.x + 4u))
#define CHAIN_PY(e) ((uint8_t)((e)->b.y + 36u))

#endif
