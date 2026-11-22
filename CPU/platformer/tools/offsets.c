/* offsetof() values of GameState fields for the rv32 ABI, read by
 * tools/make_sim.py (order: x xs y ys vx vxf vy vyf pstate cam freeze fc
 * mode power level yh, then sizeof). Compiled with -S only. */
#include <stddef.h>
#include "game.h"
const unsigned offs[] = {
    offsetof(GameState, p.b.x), offsetof(GameState, p.b.xs), offsetof(GameState, p.b.y),
    offsetof(GameState, p.b.ys), offsetof(GameState, p.b.vx), offsetof(GameState, p.b.vxf),
    offsetof(GameState, p.b.vy), offsetof(GameState, p.b.vyf), offsetof(GameState, p.pstate),
    offsetof(GameState, cam), offsetof(GameState, freeze), offsetof(GameState, fc),
    offsetof(GameState, p.mode), offsetof(GameState, p.power), offsetof(GameState, level),
    offsetof(GameState, p.b.yh), sizeof(GameState)
};
