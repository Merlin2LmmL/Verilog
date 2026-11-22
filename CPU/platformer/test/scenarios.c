/*
 * Host-side scenario checks for the parts the spec vectors do not cover:
 * blocks, items, enemies, shells, fireballs, climbing, springs, goal, water,
 * death. Each scenario teleports the player inside the real level, feeds
 * inputs, and checks the outcome. Prints one line per check.
 */
#include <stdio.h>
#include <string.h>
#include "../game.h"

static GameState g;
static int fails, checks;

#define CHECK(cond, msg) do { checks++; if (!(cond)) { fails++; printf("FAIL %s (line %d)\n", msg, __LINE__); } \
                              else printf("ok   %s\n", msg); } while (0)

static void run(uint8_t b, int n) { while (n-- > 0) game_step(&g, b); }

static void place(uint16_t x, uint8_t y)
{
    g.p.b.x = x; g.p.b.y = y; g.p.b.xs = 0; g.p.b.ys = 0;
    g.p.b.vx = 0; g.p.b.vxf = 0; g.p.b.vy = 0; g.p.b.vyf = 0;
    g.p.pstate = PS_FALL; g.p.ax = 0;
    if (x > 112) g.cam = (uint16_t)(x - 112);
    g.p.prevrelx = (uint8_t)(g.p.b.x - g.cam);
}

static int find_enemy(uint8_t type)
{
    int i;
    for (i = 0; i < 6; i++) if (g.e[i].type == type) return i;
    return -1;
}

static void clear_enemies(void)
{
    memset(g.e, 0, sizeof g.e);
    g.next_enemy = 255;   /* no more spawns */
}

static void put_enemy(int slot, uint8_t type, uint16_t x, uint8_t ground_row)
{
    Enemy *e = &g.e[slot];
    memset(e, 0, sizeof *e);
    e->type = type;
    e->b.x = x; e->b.yh = 1; e->b.y = (uint8_t)(ground_row * 16 + 8);
    e->dir = 2; e->b.vx = -8;
}

static uint8_t tile(int col, int row) { return g.m.map[(row << 8) | col]; }

int main(void)
{
    int i, k;

    /* 1. small player bumps the power crate set into the walkway (col 35 row 7) */
    game_reset(&g); clear_enemies();
    place(35 * 16, 176); run(0, 2);
    run(BTN_JUMP, 30);
    CHECK(tile(35, 7) == T_USED || g.bounce[0].active || g.bounce[1].active, "power crate bumped");
    run(0, 60);
    CHECK(tile(35, 7) == T_USED, "power crate becomes used block");
    k = find_enemy(E_ITEM_GROW);
    CHECK(k == 5, "growth item released into slot 5");
    CHECK(k >= 0 && (g.e[5].state & ESF_S), "growth item slides after emerging");
    run(0, 60);
    CHECK(g.e[5].type == E_ITEM_GROW && g.e[5].b.vx < 0, "the stop on the walkway turns the item back");
    /* stand on the walkway and let it come */
    place(32 * 16, 112);
    for (i = 0; i < 300 && g.p.power == 0; i++) game_step(&g, 0);
    CHECK(g.p.power == 1 && g.p.mode == PM_GROW, "growth item collected: grow sequence");
    run(0, 70);
    CHECK(g.p.big == 1 && g.p.mode == PM_NORMAL && g.freeze == 0, "grow sequence ends big, control back");

    /* 2. big player breaks a plain brick (col 70 row 7) */
    clear_enemies();
    place(70 * 16, 176); run(0, 2);
    { uint32_t sc = g.score; run(BTN_JUMP, 20);
      CHECK(tile(70, 7) == T_SKY && g.score == sc + 50, "big player breaks brick for 50 points"); }

    /* 3. stomp a squat walker, it is erased two ticks later */
    game_reset(&g); clear_enemies();
    place(1200, 150); g.p.pstate = PS_FALL;
    put_enemy(0, E_SQUAT, 1206, 11);
    for (i = 0; i < 40 && g.e[0].state != ES_STOMPED; i++) game_step(&g, 0);
    CHECK(g.e[0].state == ES_STOMPED && g.p.b.vy < 0, "squat walker stomped, player bounces");
    CHECK(g.score == 0 && g.sc[0].code == 1, "stomp score is pending (E6)");
    run(0, 4);
    CHECK(g.score == 0, "no points on the 4 frames after the stomp (E13)");
    run(0, 1);
    CHECK(g.score == 100, "first stomp pays 100 on the 5th frame after it (E13)");
    run(0, 60);
    CHECK(g.e[0].type == E_NONE, "flattened squat walker removed after 2 interval ticks");

    /* 4. shell: stomp, kick, slide into another walker */
    game_reset(&g); clear_enemies();
    place(1200, 150);
    put_enemy(0, E_SHELL, 1206, 11);
    put_enemy(1, E_SQUAT, 1320, 11);
    for (i = 0; i < 40 && g.e[0].state != ES_STOMPED; i++) game_step(&g, 0);
    CHECK(g.e[0].state == ES_STOMPED, "shell walker stomped into a resting shell");
    /* the stomp bounce uses the level-start fall gravity 40: a long hop.
       Wait for the landing, then walk into the shell from the left. */
    for (i = 0; i < 200 && (g.p.pstate != PS_GROUND || g.p.b.vy != 0); i++) game_step(&g, 0);
    if (g.e[0].state & ESF_S) { g.e[0].state = ES_STOMPED; g.e[0].b.vx = 0; g.e[0].b.x = 1200; }
    g.p.b.x = (uint16_t)(g.e[0].b.x - 24); g.p.b.vx = 0; g.p.pstate = PS_GROUND; g.p.b.y = 176;
    run(0, 2);
    for (i = 0; i < 60 && !(g.e[0].state & ESF_S); i++) game_step(&g, BTN_RIGHT);
    CHECK((g.e[0].state & ESF_S) && g.e[0].b.vx == 48, "resting shell kicked to +48");
    for (i = 0; i < 120 && !(g.e[1].state & ESF_D); i++) game_step(&g, 0);
    CHECK(g.e[1].state & ESF_D, "sliding shell defeats the walker it hits");

    /* 5. fire power: fireball defeats a walker */
    game_reset(&g); clear_enemies();
    g.p.power = 2; g.p.big = 1;
    place(1100, 176); run(0, 3);
    put_enemy(0, E_SQUAT, 1150, 11);   /* inside the low part of the bounce arc */
    run(0, 2);
    for (i = 0; i < 60 && !(g.e[0].state & ESF_D); i++) game_step(&g, (i & 1) ? 0 : BTN_RUN);
    CHECK(g.e[0].state & ESF_D, "fireball defeats squat walker");

    /* 6. climb the cable at col 96 */
    game_reset(&g); clear_enemies();
    place(96 * 16 - 16, 176); g.p.pstate = PS_GROUND; run(0, 2);
    for (i = 0; i < 40 && g.p.pstate != PS_CLIMB; i++) game_step(&g, BTN_RIGHT);
    CHECK(g.p.pstate == PS_CLIMB, "attached to the climbable cable");
    { uint8_t y0 = g.p.b.y; run(BTN_UP, 40);
      CHECK(g.p.pstate == PS_CLIMB && g.p.b.y + 30 < y0, "climbs up at about 0.875 px/f"); }

    /* 7. spring at col 112 row 10 (E4: 13 frames, net 6 px lower, frame 13 launches) */
    game_reset(&g); clear_enemies();
    place(112 * 16, 120); g.p.pstate = PS_FALL;
    for (i = 0; i < 60 && !g.p.spring; i++) game_step(&g, 0);
    CHECK(g.p.spring == 2 && g.p.b.y == 160 + 2, "landing on the spring: frame 1 snaps then +2");
    { int n = 1; uint8_t cam0;
      while (g.p.spring && n < 40) { game_step(&g, 0); n++; }
      CHECK(n == 13 && g.p.b.y == 166 && g.p.b.vy == -7, "spring runs 13 frames, ends 6 px low, weak launch -7");
      game_step(&g, 0);
      CHECK(g.p.pstate == PS_FALL && g.p.b.y == 166, "frame after launch: no vertical move, pass switches to falling");
      (void)cam0; }
    game_reset(&g); clear_enemies();
    place(112 * 16, 120); g.p.pstate = PS_FALL;
    for (i = 0; i < 60 && !g.p.spring; i++) game_step(&g, 0);
    for (i = 0; i < 30 && g.p.spring; i++) game_step(&g, i == 6 ? BTN_JUMP : 0);
    CHECK(g.p.b.vy == -12 && g.p.b.vyf == 0, "A during the animation gives the strong launch (-12)");
    { uint8_t miny = 255; for (i = 0; i < 40; i++) { game_step(&g, 0); if (g.p.b.y < miny) miny = g.p.b.y; }
      CHECK(miny < 80, "strong spring launch goes high"); }

    /* 8. goal pad (col 190 row 8) ends the level, next is the water level */
    game_reset(&g); clear_enemies();
    place(190 * 16, 60);
    run(0, 160);
    CHECK(g.level == 1 && g.water == 1, "landing on the goal pad loads level 2 (water)");
    run(BTN_JUMP, 1); run(0, 1);
    CHECK(g.p.pstate == PS_RISE && g.p.gfall == 10, "swimming uses the stroke table");

    /* 9. small player touching a walker dies, life lost after the fall */
    game_reset(&g); clear_enemies();
    place(1200, 176); g.p.pstate = PS_GROUND;
    put_enemy(0, E_SQUAT, 1220, 11);
    for (i = 0; i < 40 && g.p.mode != PM_DYING; i++) game_step(&g, 0);
    CHECK(g.p.mode == PM_DYING && g.freeze == 255, "touching a walker kills the small player");
    for (i = 0; i < 600 && g.lives == 3; i++) game_step(&g, 0);
    CHECK(g.lives == 2 && g.p.mode == PM_NORMAL && g.p.b.x == 40, "life lost, level restarted");

    /* 10. big player hurt: shrinks, invincible, keeps playing */
    game_reset(&g); clear_enemies();
    g.p.power = 1; g.p.big = 1;
    place(1200, 176); g.p.pstate = PS_GROUND;
    put_enemy(0, E_SQUAT, 1220, 11);
    for (i = 0; i < 40 && g.p.mode != PM_INJURY; i++) game_step(&g, 0);
    CHECK(g.p.mode == PM_INJURY && g.p.power == 0 && g.it[IT_INJURY] == 8, "big player hurt: injury sequence");
    run(0, 60);
    CHECK(g.p.big == 0 && g.p.mode == PM_NORMAL, "injury ends small and in control");

    /* 11. falling in a pit (cols 41-44, away from the stepping stone at 43) costs a life */
    game_reset(&g); clear_enemies();
    place(41 * 16 + 2, 150);
    for (i = 0; i < 1500 && g.lives == 3; i++) game_step(&g, 0);
    CHECK(g.lives == 2, "pit fall costs a life");

    /* 12. hard modes after a full loop: squat walkers become armored */
    game_reset(&g);
    g.restart = 2; g.level = (uint8_t)(g_num_levels - 1u); game_step(&g, 0);
    CHECK(g.hard_a == 1 && g.level == 0, "clearing the last level sets hard mode A");
    g.cam = 64;
    for (i = 0; i < 5; i++) game_step(&g, 0);
    CHECK(find_enemy(E_ARMOR) >= 0 && find_enemy(E_SQUAT) < 0, "hard mode A spawns armored walkers");

    /* 14. E3: A pressed during the grow freeze and still held jumps at once */
    game_reset(&g); clear_enemies();
    place(1200, 176); g.p.pstate = PS_GROUND; run(0, 2);
    g.p.mode = PM_GROW; g.p.power = 1; g.freeze = 255;
    for (i = 0; i < 80 && g.p.mode != PM_NORMAL; i++) game_step(&g, BTN_JUMP);
    CHECK(g.p.prevab == 0, "previous A/B not refreshed during the grow (E3)");
    game_step(&g, BTN_JUMP);
    CHECK(g.p.pstate == PS_RISE && g.p.b.vy < 0, "A held from the grow starts a jump on the first control frame");
    game_reset(&g); clear_enemies();
    place(1200, 176); g.p.pstate = PS_GROUND; run(BTN_JUMP, 1); run(BTN_JUMP, 70);   /* jump, land, A still held */
    g.p.mode = PM_GROW; g.p.power = 1; g.freeze = 255;
    for (i = 0; i < 80 && g.p.mode != PM_NORMAL; i++) game_step(&g, BTN_JUMP);
    game_step(&g, BTN_JUMP);
    CHECK(g.p.pstate == PS_GROUND, "A held before and after the grow: no jump");

    /* 15. E7: squat walker knocked from below ends 4 px higher, Vy -3 */
    game_reset(&g); clear_enemies();
    put_enemy(0, E_SQUAT, 70 * 16, 7);         /* standing on the brick row (row 7) */
    g.m.map[(7 << 8) | 70] = T_BUMPED; g.cam = 70 * 16 - 100; place(60 * 16, 176);
    g.cam = 70 * 16 - 100;
    { uint8_t y0 = g.e[0].b.y; game_step(&g, 0); if (!(g.fc & 1)) game_step(&g, 0);
      CHECK((g.e[0].state & ESF_D) && g.e[0].b.vy <= -2, "squat walker on a bumped block is defeated");
      (void)y0; }
    game_reset(&g); clear_enemies();
    put_enemy(0, E_SQUAT, 70 * 16, 7);
    g.m.map[(7 << 8) | 70] = T_BUMPED; g.cam = 70 * 16 - 100; g.freeze = 2;   /* no movement this frame */
    { uint8_t y0 = g.e[0].b.y; game_step(&g, 0);
      CHECK(g.e[0].b.y == (uint8_t)(y0 - 4) && g.e[0].b.vy == -3, "knock lifts the squat walker 4 px with Vy -3 (E7)"); }

    /* 16. E10: a hopper lands on a bumped block like ordinary ground */
    game_reset(&g); clear_enemies();
    put_enemy(0, E_HOPPER, 70 * 16, 7);
    g.e[0].b.vy = 2; g.m.map[(7 << 8) | 70] = T_BUMPED; g.cam = 70 * 16 - 100; g.freeze = 2;
    game_step(&g, 0);
    CHECK(!(g.e[0].state & ESF_D) && g.e[0].type == E_HOPPER && g.e[0].b.vy == -3, "hopper rebounds off a bumped block (E10)");

    /* 13. 30k frames of random input in the real game: no stuck state */
    game_reset(&g);
    { uint32_t r = 12345; int bad = 0;
      for (i = 0; i < 30000; i++) {
          r = r * 1103515245u + 12345u;
          game_step(&g, (uint8_t)((r >> 16) & 0x3F));
          if (g.p.b.yh == 1 && g.p.b.x > g.cam + 239u) bad++;
      }
      CHECK(bad == 0, "random play: player always inside the screen clamp");
    }

    /* 17. E15: the spring pauses while the freeze counter runs */
    game_reset(&g); clear_enemies();
    place(112 * 16, 120); g.p.pstate = PS_FALL;
    for (i = 0; i < 60 && !g.p.spring; i++) game_step(&g, 0);
    run(0, 3);
    { uint8_t n = g.p.spring, y = g.p.b.y;
      g.freeze = 30; run(0, 10);
      CHECK(g.p.spring == n && g.p.b.y == y, "spring animation frozen with the freeze counter (E15)");
      run(BTN_JUMP, 1);
      CHECK(g.p.pstate == PS_GROUND && g.p.b.vy == 0, "no jump start while the spring is animating (E15)"); }

    /* 18. E15: with the spring object in a slot the logic runs in that slot */
    game_reset(&g); clear_enemies();
    put_enemy(2, E_SPRING, 112 * 16, 10); g.e[2].b.vx = 0;
    place(112 * 16, 120); g.p.pstate = PS_FALL;
    for (i = 0; i < 60 && !g.p.spring; i++) game_step(&g, 0);
    { uint8_t y = g.p.b.y; run(0, 1);
      CHECK(g.p.b.y == (uint8_t)(y + 2) && g.e[2].type == E_SPRING, "spring object in slot 2 moves the player (E15)"); }

    /* 19. E12: emergence follows the frame counter, 17 px, not frozen */
    game_reset(&g); clear_enemies();
    place(35 * 16, 176); run(0, 2);
    for (i = 0; i < 30 && g.e[5].type == E_NONE; i++) game_step(&g, BTN_JUMP);
    { uint8_t y0 = g.e[5].b.y; int frames = 0; uint8_t frozen_ok = 1;
      g.freeze = 20;
      while (frames < 80 && (g.e[5].state & ES_LOW) == ES_EMERGE && !(g.e[5].state & ESF_S)) {
          uint8_t before = g.e[5].b.y; game_step(&g, 0); frames++;
          if ((g.fc & 3u) == 0 && g.e[5].b.y != (uint8_t)(before - 1)) frozen_ok = 0;
          if ((g.fc & 3u) != 0 && g.e[5].b.y != before) frozen_ok = 0;
      }
      CHECK(frozen_ok, "item rises 1 px exactly on frames with frame counter AND 3 = 0, also frozen (E12)");
      (void)y0;   /* the first rise can happen on the spawn frame itself */
      CHECK(g.e[5].b.y == (uint8_t)(32 + 16 * 7 - 25) && g.e[5].aux == 17,
            "item ends 25 px above the block's top after 17 rises (E12)"); }

    /* 20. E16: the invincibility item lands on a bumped block like ground */
    game_reset(&g); clear_enemies();
    put_enemy(5, E_ITEM_STAR, 300, 11); g.e[5].state = ESF_S; g.e[5].b.vx = 0; g.e[5].b.vy = 2;
    g.m.map[(11 << 8) | 19] = T_BUMPED;   /* tile under x = 300..315 */
    place(200, 176);
    run(0, 2);
    CHECK(g.e[5].type == E_ITEM_STAR && g.e[5].b.vy == -3 && !(g.e[5].state & ESF_A),
          "invincibility item rebounds off a bumped block, not knocked (E16)");


    /* ---- special objects (6.4) ---- */

    /* 21. pipe plant: rises 24 px at 1 px every other frame, waits 64 */
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[0]; memset(e, 0, sizeof *e);
      e->type = E_PLANT; e->b.x = 200; e->b.yh = 1; e->b.y = e->hy = 168;
      run(0, 1);
      for (i = 0; i < 60 && e->aux != 2u; i++) game_step(&g, 0);
      CHECK(e->b.y == 144 && e->aux == 2 && i >= 46 && i <= 48, "plant rises 24 px in ~48 frames");
      run(0, 63);
      CHECK(e->b.y == 144, "plant waits 64 frames at the top");
      run(0, 60);
      CHECK(e->b.y == 168 && e->aux == 0, "plant sinks back into its pipe");
      g.p.b.x = 180; e->t0 = 0; run(0, 100);
      CHECK(e->b.y == 168 && e->aux == 0, "plant stays hidden while the player is within 32 px"); }

    /* 22. lava ball: launch from below the screen, then waits for its timer */
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[1]; uint8_t miny = 255; memset(e, 0, sizeof *e);
      e->type = E_LAVA; e->b.x = 200; e->b.yh = 2; e->b.y = e->hy = 48; g.it[IT_E0 + 1] = 0;
      run(0, 1);
      CHECK(e->b.vy == -7 && (e->b.vyf & 0x80u) && g.it[IT_E0 + 1] >= 6 && g.it[IT_E0 + 1] <= 15,
            "lava ball launches with Vy -7, random Vyf >= 128, timer 6..15");
      for (i = 0; i < 300 && (i < 5 || e->aux); i++) {
          game_step(&g, 0);
          if (e->b.yh == 1 && e->b.y < miny) miny = e->b.y;
      }
      CHECK(miny >= 48 + 50 && miny <= 48 + 95 && e->type == E_LAVA, "lava ball peaks 50..95 px below its row and is kept"); }

    /* 23. fire chain geometry and spin */
    { Enemy c; int8_t dx, dy; memset(&c, 0, sizeof c); c.type = E_CHAIN_LONG;
      c.t1 = 0;  game_chain_offset(&c, 11, &dx, &dy); k = (dx == 0 && dy == -88);
      c.t1 = 8;  game_chain_offset(&c, 11, &dx, &dy); k &= (dx == 88 && dy == 0);
      c.t1 = 16; game_chain_offset(&c, 11, &dx, &dy); k &= (dx == 0 && dy == 88);
      c.t1 = 28; game_chain_offset(&c, 3, &dx, &dy);  k &= (dx == -16 && dy == -16);
      c.t1 = 12; game_chain_offset(&c, 0, &dx, &dy);  k &= (dx == 0 && dy == 0);
      CHECK(k, "fire chain offsets: up, right, down, up-left, pivot"); }
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[0]; memset(e, 0, sizeof *e);
      e->type = E_CHAIN_LONG; e->b.x = 600; e->b.yh = 1; e->b.y = 64; e->dir = 2;
      e->t1 = 7; e->t0 = 250; run(0, 1);
      CHECK(e->t1 == 9 && e->t0 == (uint8_t)(250 + 56), "long chain spins +56 and skips angle 8"); }

    /* 24. fire chain contact hurts (big player shrinks) */
    game_reset_test(&g, W_FLAT, 480, 116, PS_FALL, 1); clear_enemies();
    g.p.power = 1;
    { Enemy *e = &g.e[0]; memset(e, 0, sizeof *e);
      e->type = E_CHAIN; e->b.x = 480; e->b.yh = 1; e->b.y = 64; e->dir = 2; e->t1 = 16;
      g.cam = 300; run(0, 1);
      CHECK(g.p.power == 0 && g.p.mode == PM_INJURY, "fire chain segment hurts the player"); }

    /* 25. spike walker cannot be stomped */
    game_reset_test(&g, W_FLAT, 100, 165, PS_FALL, 1); clear_enemies();
    g.p.power = 1; g.p.b.vy = 2;
    put_enemy(0, E_SPIKE, 100, 11); g.e[0].b.vx = 0;
    run(0, 2);
    CHECK(g.p.power == 0 && g.e[0].type == E_SPIKE && !(g.e[0].state & ESF_D), "stomping a spike walker hurts");

    /* 26. spike egg falls, hatches walking right at +8 (or toward the player) */
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    put_enemy(0, E_SPIKE, 200, 11); g.e[0].b.y = 40; g.e[0].state = ES_EGG; g.e[0].b.vx = 0; g.e[0].b.vy = -3;
    for (i = 0; i < 200 && g.e[0].state == ES_EGG; i++) game_step(&g, 0);
    CHECK(g.e[0].state == ES_WALK && g.e[0].b.y == 11 * 16 + 8 && (g.e[0].b.vx == 8 || g.e[0].b.vx == -8),
          "spike egg lands and hatches into a walker");

    /* 27. missile: stomped from above (flier rule), falls off, player Vy -3 */
    game_reset_test(&g, W_FLAT, 100, 140, PS_FALL, 0); clear_enemies();
    { Enemy *e = &g.e[0]; memset(e, 0, sizeof *e);
      e->type = E_MISSILE; e->b.x = 100; e->b.yh = 1; e->b.y = 150; e->dir = 2;
      g.p.b.vy = 2; run(0, 2);
      CHECK((e->state & ESF_D) && g.p.b.vy == -3 && g.p.mode == PM_NORMAL, "missile stomped: defeated, player Vy -3"); }

    /* 28. swimming fish drifts 0.25 px/f */
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[0]; memset(e, 0, sizeof *e);
      e->type = E_FISH; e->b.x = 240; e->b.yh = 1; e->b.y = e->hy = 100; e->b.vx = -4; e->dir = 2;
      run(0, 64);
      CHECK(e->b.x == 224 && e->b.y == 100, "slow fish drifts 16 px in 64 frames (slot 0: no bob)"); }

    /* 29. squid rises 32 px per stroke, never above Y 32 */
    game_reset_test(&g, W_WATER, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[0]; uint8_t y0; memset(e, 0, sizeof *e);
      e->type = E_SQUID; e->b.x = 160; e->b.yh = 1; e->b.y = 120; e->dir = 2;
      while ((g.fc & 7u) != 7u) game_step(&g, 0);
      y0 = e->b.y;
      for (i = 0; i < 60 && e->aux != 2u; i++) game_step(&g, 0);
      CHECK(e->aux == 2 && e->b.y == (uint8_t)(y0 - 32), "squid stroke rises 32 px then sinks"); }

    /* 30. boss: five fireball hits, then defeated for 5000 */
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[0]; int hits = 0; memset(e, 0, sizeof *e);
      e->type = E_BOSS; e->b.x = 200; e->hx = 200; e->b.yh = 1; e->b.y = e->hy = 176;
      e->hp = 5; e->b.vx = -1; e->t0 = 200; e->t1 = 191; e->t2 = 33; e->dir = 2;
      g.e[1].type = E_PART;
      for (i = 0; i < 400 && !(e->state & ESF_D); i++) {
          if (g.fb[0].state == 0) {
              memset(&g.fb[0], 0, sizeof g.fb[0]);
              g.fb[0].state = 1; g.fb[0].b.yh = 1; g.fb[0].b.x = (uint16_t)(e->b.x + 20); g.fb[0].b.y = 180;
              hits++;
          }
          game_step(&g, 0);
      }
      CHECK((e->state & ESF_D) && hits == 5 && g.sc[0].code == 9, "boss takes 5 fireball hits, 5000 points");
      run(0, 200);
      CHECK(g.e[0].type == E_NONE && g.e[1].type == E_NONE, "defeated boss falls off and frees both slots"); }

    /* 31. boss breathes a flame on its timer; the flame flies left */
    game_reset_test(&g, W_FLAT, 40, 176, PS_GROUND, 0); clear_enemies();
    { Enemy *e = &g.e[0]; memset(e, 0, sizeof *e);
      e->type = E_BOSS; e->b.x = 200; e->hx = 200; e->b.yh = 1; e->b.y = e->hy = 176;
      e->hp = 5; e->b.vx = -1; e->t0 = 33; e->t1 = 10; e->t2 = 33; e->dir = 2;
      g.e[1].type = E_PART;
      run(0, 10);
      CHECK(g.fl[0].active && g.fl[0].b.vx == -16 && e->t1 == 191 && e->chain == 1, "boss flame on the timer; next gap from the pattern");
      { uint16_t x0 = g.fl[0].b.x; run(0, 16); CHECK(g.fl[0].b.x == x0 - 16, "flame flies 1 px/f"); } }

    /* 32. two-slot spawn from the level list (level 3 boss) */
    game_reset(&g);
    g.restart = 2; g.level = 1; game_step(&g, 0);
    CHECK(g.level == 2, "level 3 loads after level 2");
    for (k = 0; k < g.lvl->nenemies && g.lvl->enemies[k].type != E_BOSS; k++) { }
    memset(g.e, 0, sizeof g.e);
    g.next_enemy = (uint8_t)k; g.cam = (uint16_t)(132 * 16 - 255 - 40);
    g.p.b.x = (uint16_t)(g.cam + 40);
    run(0, 1);
    CHECK(g.e[0].type == E_BOSS && g.e[1].type == E_PART && g.e[0].b.y == 176 && g.e[0].hp == 5,
          "boss spawns into two slots, standing on row 11");

    printf("%d/%d checks pass\n", checks - fails, checks);
    return fails != 0;
}
