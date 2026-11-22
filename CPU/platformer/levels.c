/*
 * levels.c - level data: the five NES stage maps (8-4, 8-2, 7-2, 1-3, 1-1).
 *
 * A level is a list of filled rectangles over the 13-row grid plus a list
 * of level objects sorted by column. Grid row r covers screen y 32+16r..47+16r;
 * the ground surface used throughout is row 11 (a standing player has Y=176).
 * Enemy entries give the grid row of the tile the enemy stands on.
 */
#include "game.h"

#define R(id, c, r, w, h) { (uint8_t)(id), (uint8_t)(c), (uint8_t)(r), (uint8_t)(w), (uint8_t)(h) }

/* ---------------- game levels (converted from the NES stage maps) ---------------- */
/* Grid cells are 16 px like the NES metatiles; map row r+2 = grid row r. Scenery without a tile (hills,
 * castles, trees, fences) is dropped. Enemy placements are not part of the maps and were set by hand. */

/* Level 1, World 1-1: 211 columns, three pits, pipes, brick/crate rows, the hidden 1-up, stairs and the flagpole. */
static const LevelRect k_l1_rects[] = {
    R(T_GROUND, 0, 11, 69, 1), R(T_GROUND, 71, 11, 15, 1), R(T_GROUND, 88, 11, 65, 1),
    R(T_GROUND, 155, 11, 56, 1), R(T_DIRT, 0, 12, 69, 1), R(T_DIRT, 71, 12, 15, 1),
    R(T_DIRT, 88, 12, 65, 1), R(T_DIRT, 155, 12, 56, 1), R(T_CLOUD, 19, 0, 2, 1),
    R(T_CLOUD, 37, 0, 2, 1), R(T_CLOUD, 67, 0, 2, 1), R(T_CLOUD, 85, 0, 2, 1),
    R(T_CLOUD, 115, 0, 2, 1), R(T_CLOUD, 133, 0, 2, 1), R(T_CLOUD, 163, 0, 2, 1),
    R(T_CLOUD, 181, 0, 2, 1), R(T_CLOUD, 8, 1, 2, 1), R(T_CLOUD, 28, 1, 2, 1),
    R(T_CLOUD, 56, 1, 2, 1), R(T_CLOUD, 76, 1, 2, 1), R(T_CLOUD, 104, 1, 2, 1),
    R(T_CLOUD, 124, 1, 2, 1), R(T_CLOUD, 152, 1, 2, 1), R(T_CLOUD, 172, 1, 2, 1),
    R(T_CLOUD, 200, 1, 2, 1), R(T_BUSH, 12, 10, 3, 1), R(T_BUSH, 23, 10, 2, 1),
    R(T_BUSH, 42, 10, 2, 1), R(T_BUSH, 60, 10, 3, 1), R(T_BUSH, 71, 10, 2, 1),
    R(T_BUSH, 90, 10, 2, 1), R(T_BUSH, 108, 10, 3, 1), R(T_BUSH, 119, 10, 2, 1),
    R(T_BUSH, 138, 10, 1, 1), R(T_BUSH, 159, 10, 1, 1), R(T_BUSH, 167, 10, 2, 1),
    R(T_BUSH, 207, 10, 1, 1), R(T_QCOIN, 16, 7, 1, 1), R(T_BRICK, 20, 7, 1, 1),
    R(T_QPOWER, 21, 7, 1, 1), R(T_QPOWER, 22, 3, 1, 1), R(T_BRICK, 22, 7, 1, 1),
    R(T_QCOIN, 23, 7, 1, 1), R(T_BRICK, 24, 7, 1, 1), R(T_PIPE_TL, 28, 9, 1, 1),
    R(T_PIPE_L, 28, 10, 1, 1), R(T_PIPE_TR, 29, 9, 1, 1), R(T_PIPE_R, 29, 10, 1, 1),
    R(T_PIPE_TL, 38, 8, 1, 1), R(T_PIPE_L, 38, 9, 1, 2), R(T_PIPE_TR, 39, 8, 1, 1),
    R(T_PIPE_R, 39, 9, 1, 2), R(T_PIPE_TL, 46, 7, 1, 1), R(T_PIPE_L, 46, 8, 1, 3),
    R(T_PIPE_TR, 47, 7, 1, 1), R(T_PIPE_R, 47, 8, 1, 3), R(T_PIPE_TL, 57, 7, 1, 1),
    R(T_PIPE_L, 57, 8, 1, 3), R(T_PIPE_TR, 58, 7, 1, 1), R(T_PIPE_R, 58, 8, 1, 3),
    R(T_HIDDEN_1UP, 64, 6, 1, 1), R(T_BRICK, 77, 7, 1, 1), R(T_QPOWER, 78, 7, 1, 1),
    R(T_BRICK, 79, 7, 1, 1), R(T_BRICK, 80, 3, 8, 1), R(T_BRICK, 91, 3, 3, 1),
    R(T_QCOIN, 94, 3, 1, 1), R(T_BRICK, 94, 7, 1, 1), R(T_BRICK, 100, 7, 2, 1),
    R(T_QCOIN, 106, 7, 1, 1), R(T_QPOWER, 109, 3, 1, 1), R(T_QCOIN, 109, 7, 1, 1),
    R(T_QCOIN, 112, 7, 1, 1), R(T_BRICK, 118, 7, 1, 1), R(T_BRICK, 121, 3, 3, 1),
    R(T_BRICK, 128, 3, 1, 1), R(T_QCOIN, 129, 3, 2, 1), R(T_BRICK, 129, 7, 2, 1),
    R(T_BRICK, 131, 3, 1, 1), R(T_STONE, 134, 10, 4, 1), R(T_STONE, 135, 9, 3, 1),
    R(T_STONE, 136, 8, 2, 1), R(T_STONE, 137, 7, 1, 1), R(T_STONE, 140, 7, 1, 1),
    R(T_STONE, 140, 8, 2, 1), R(T_STONE, 140, 9, 3, 1), R(T_STONE, 140, 10, 4, 1),
    R(T_STONE, 148, 10, 5, 1), R(T_STONE, 149, 9, 4, 1), R(T_STONE, 150, 8, 3, 1),
    R(T_STONE, 151, 7, 2, 1), R(T_STONE, 155, 7, 1, 1), R(T_STONE, 155, 8, 2, 1),
    R(T_STONE, 155, 9, 3, 1), R(T_STONE, 155, 10, 4, 1), R(T_PIPE_TL, 163, 9, 1, 1),
    R(T_PIPE_L, 163, 10, 1, 1), R(T_PIPE_TR, 164, 9, 1, 1), R(T_PIPE_R, 164, 10, 1, 1),
    R(T_BRICK, 168, 7, 2, 1), R(T_QCOIN, 170, 7, 1, 1), R(T_BRICK, 171, 7, 1, 1),
    R(T_PIPE_TL, 179, 9, 1, 1), R(T_PIPE_L, 179, 10, 1, 1), R(T_PIPE_TR, 180, 9, 1, 1),
    R(T_PIPE_R, 180, 10, 1, 1), R(T_STONE, 181, 10, 9, 1), R(T_STONE, 182, 9, 8, 1),
    R(T_STONE, 183, 8, 7, 1), R(T_STONE, 184, 7, 6, 1), R(T_STONE, 185, 6, 5, 1),
    R(T_STONE, 186, 5, 4, 1), R(T_STONE, 187, 4, 3, 1), R(T_STONE, 188, 3, 2, 1),
    R(T_GOAL, 198, 0, 1, 1), R(T_POLE, 198, 1, 1, 9), R(T_STONE, 198, 10, 1, 1)
};
static const LevelEnemy k_l1_enemies[] = {
    { 24, 7, E_SQUAT, 0 }, { 40, 11, E_SQUAT, 0 }, { 46, 7, E_PLANT, 0 }, { 51, 11, E_SQUAT, 0 },
    { 53, 11, E_SQUAT, 0 }, { 57, 7, E_PLANT, 0 }, { 80, 3, E_SQUAT, 0 }, { 82, 3, E_SQUAT, 0 },
    { 97, 11, E_SQUAT, 0 }, { 99, 11, E_SQUAT, 0 }, { 107, 11, E_SHELL, 0 }, { 114, 11, E_SQUAT, 0 },
    { 116, 11, E_SQUAT, 0 }, { 124, 11, E_SQUAT, 0 }, { 126, 11, E_SQUAT, 0 }, { 128, 3, E_SQUAT, 0 },
    { 131, 3, E_SQUAT, 0 }, { 174, 11, E_SQUAT, 0 }, { 176, 11, E_SQUAT, 0 }
};

/* Level 2, World 1-3 (mushroom platforms): 164 columns. Mushroom caps are solid (T_TREE_*), the trunks are background (T_TRUNK).
 * Lifts are not modelled; the moving platforms became static T_STONE bars. */
static const LevelRect k_l2_rects[] = {
    R(T_GROUND, 0, 11, 16, 1), R(T_GROUND, 129, 11, 35, 1), R(T_DIRT, 0, 12, 16, 1),
    R(T_DIRT, 129, 12, 35, 1), R(T_CLOUD, 19, 0, 2, 1), R(T_CLOUD, 67, 0, 2, 1),
    R(T_CLOUD, 115, 0, 2, 1), R(T_CLOUD, 162, 0, 1, 1), R(T_CLOUD, 4, 1, 2, 1),
    R(T_CLOUD, 52, 1, 2, 1), R(T_CLOUD, 100, 1, 2, 1), R(T_CLOUD, 148, 1, 2, 1),
    R(T_CLOUD, 37, 4, 2, 1), R(T_CLOUD, 85, 4, 2, 1), R(T_CLOUD, 133, 4, 2, 1),
    R(T_CLOUD, 9, 5, 2, 1), R(T_CLOUD, 57, 5, 2, 1), R(T_CLOUD, 153, 5, 1, 1),
    R(T_CLOUD, 46, 9, 2, 1), R(T_CLOUD, 76, 9, 1, 1), R(T_CLOUD, 94, 9, 2, 1),
    R(T_CLOUD, 125, 9, 1, 1), R(T_CLOUD, 144, 9, 1, 1), R(T_TREE_L, 18, 10, 1, 1),
    R(T_TREE_M, 19, 10, 2, 1), R(T_TRUNK, 19, 11, 2, 2), R(T_TREE_R, 21, 10, 1, 1),
    R(T_TREE_L, 24, 7, 1, 1), R(T_TREE_M, 25, 7, 6, 1), R(T_TRUNK, 25, 8, 6, 5),
    R(T_TREE_L, 26, 3, 1, 1), R(T_COIN, 27, 2, 3, 1), R(T_TREE_M, 27, 3, 3, 1),
    R(T_TRUNK, 27, 4, 3, 3), R(T_TREE_R, 30, 3, 1, 1), R(T_TREE_R, 31, 7, 1, 1),
    R(T_TREE_L, 32, 10, 1, 1), R(T_COIN, 33, 9, 1, 1), R(T_TREE_M, 33, 10, 1, 1),
    R(T_TRUNK, 33, 11, 1, 2), R(T_TREE_R, 34, 10, 1, 1), R(T_TREE_L, 35, 6, 1, 1),
    R(T_TREE_M, 36, 6, 3, 1), R(T_TRUNK, 36, 7, 3, 6), R(T_COIN, 37, 0, 2, 1),
    R(T_TREE_R, 39, 6, 1, 1), R(T_TREE_L, 40, 2, 1, 1), R(T_TREE_M, 41, 2, 5, 1),
    R(T_TRUNK, 41, 3, 5, 10), R(T_TREE_R, 46, 2, 1, 1), R(T_COIN, 50, 4, 2, 1),
    R(T_TREE_L, 50, 11, 1, 1), R(T_TREE_M, 51, 11, 2, 1), R(T_TRUNK, 51, 12, 2, 1),
    R(T_TREE_R, 53, 11, 1, 1), R(T_STONE, 55, 4, 3, 1), R(T_QPOWER, 59, 8, 1, 1),
    R(T_TREE_L, 59, 11, 1, 1), R(T_COIN, 60, 2, 4, 1), R(T_TREE_L, 60, 3, 1, 1),
    R(T_TREE_M, 60, 11, 3, 1), R(T_TRUNK, 60, 12, 3, 1), R(T_TREE_M, 61, 3, 2, 1),
    R(T_TRUNK, 61, 4, 2, 7), R(T_TREE_R, 63, 3, 1, 1), R(T_TREE_R, 63, 11, 1, 1),
    R(T_TREE_L, 65, 11, 1, 1), R(T_TREE_M, 66, 11, 3, 1), R(T_TRUNK, 66, 12, 3, 1),
    R(T_TREE_R, 69, 11, 1, 1), R(T_TREE_L, 70, 7, 1, 1), R(T_TREE_M, 71, 7, 1, 1),
    R(T_TRUNK, 71, 8, 1, 5), R(T_TREE_R, 72, 7, 1, 1), R(T_TREE_L, 76, 4, 1, 1),
    R(T_TREE_M, 77, 4, 4, 1), R(T_TRUNK, 77, 5, 4, 8), R(T_TREE_R, 81, 4, 1, 1),
    R(T_COIN, 85, 3, 2, 1), R(T_STONE, 86, 6, 3, 1), R(T_COIN, 93, 2, 2, 1),
    R(T_STONE, 94, 7, 3, 1), R(T_COIN, 97, 2, 2, 1), R(T_TREE_L, 98, 9, 1, 1),
    R(T_TREE_M, 99, 9, 2, 1), R(T_TRUNK, 99, 10, 2, 3), R(T_TREE_R, 101, 9, 1, 1),
    R(T_TREE_L, 104, 5, 1, 1), R(T_TREE_M, 105, 5, 6, 1), R(T_TRUNK, 105, 6, 6, 7),
    R(T_TREE_R, 111, 5, 1, 1), R(T_COIN, 113, 10, 3, 1), R(T_TREE_L, 113, 11, 1, 1),
    R(T_TREE_M, 114, 11, 1, 1), R(T_TRUNK, 114, 12, 1, 1), R(T_TREE_R, 115, 11, 1, 1),
    R(T_TREE_L, 116, 7, 1, 1), R(T_TREE_M, 117, 7, 2, 1), R(T_TRUNK, 117, 8, 2, 5),
    R(T_TREE_R, 119, 7, 1, 1), R(T_COIN, 120, 3, 2, 1), R(T_TREE_L, 122, 7, 1, 1),
    R(T_TREE_M, 123, 7, 2, 1), R(T_TRUNK, 123, 8, 2, 5), R(T_TREE_R, 125, 7, 1, 1),
    R(T_STONE, 131, 4, 3, 1), R(T_STONE, 138, 7, 6, 4), R(T_STONE, 140, 5, 4, 2),
    R(T_STONE, 142, 3, 2, 2), R(T_GOAL, 152, 0, 1, 1), R(T_POLE, 152, 1, 1, 9),
    R(T_STONE, 152, 10, 1, 1)
};
static const LevelEnemy k_l2_enemies[] = {
    { 62, 3, E_LEDGE, 0 }, { 78, 4, E_HOPPER, 0 }, { 107, 5, E_LEDGE, 0 }, { 118, 7, E_LEDGE, 0 }
};

/* Level 3, World 7-2 (underwater): 192 columns, water level. Coral rock is T_STONE, the sea floor T_DIRT. */
static const LevelRect k_l3_rects[] = {
    R(T_WATERTOP, 0, 0, 78, 1), R(T_WATERTOP, 80, 0, 51, 1), R(T_WATERTOP, 132, 0, 40, 1),
    R(T_WATERTOP, 173, 0, 15, 1), R(T_DIRT, 0, 11, 66, 2), R(T_DIRT, 71, 11, 60, 2),
    R(T_DIRT, 140, 11, 17, 2), R(T_DIRT, 164, 11, 28, 2), R(T_COIN, 14, 10, 2, 1),
    R(T_STONE, 18, 7, 3, 1), R(T_COIN, 27, 3, 3, 1), R(T_COIN, 36, 10, 3, 1),
    R(T_STONE, 42, 7, 2, 1), R(T_STONE, 64, 8, 2, 3), R(T_STONE, 65, 6, 1, 2),
    R(T_COIN, 67, 8, 3, 1), R(T_STONE, 71, 6, 1, 2), R(T_STONE, 71, 8, 2, 3),
    R(T_STONE, 78, 0, 2, 3), R(T_STONE, 78, 8, 2, 3), R(T_STONE, 82, 3, 3, 1),
    R(T_COIN, 101, 9, 3, 1), R(T_STONE, 102, 7, 2, 1), R(T_COIN, 113, 4, 3, 1),
    R(T_STONE, 115, 6, 2, 1), R(T_STONE, 129, 7, 1, 2), R(T_STONE, 129, 9, 2, 2),
    R(T_STONE, 131, 0, 1, 2), R(T_STONE, 131, 2, 9, 1), R(T_COIN, 133, 9, 1, 1),
    R(T_COIN, 134, 10, 3, 1), R(T_COIN, 137, 9, 1, 1), R(T_STONE, 140, 9, 2, 2),
    R(T_STONE, 141, 7, 1, 2), R(T_STONE, 156, 3, 3, 1), R(T_STONE, 156, 4, 1, 7),
    R(T_COIN, 159, 7, 3, 1), R(T_COIN, 159, 10, 3, 1), R(T_STONE, 162, 3, 3, 1),
    R(T_STONE, 164, 4, 1, 7), R(T_GOAL, 172, 1, 1, 1), R(T_POLE, 172, 2, 1, 8),
    R(T_STONE, 172, 10, 1, 1), R(T_STONE, 173, 3, 4, 1), R(T_STONE, 173, 7, 4, 1),
    R(T_STONE, 180, 3, 4, 1), R(T_STONE, 180, 7, 4, 1), R(T_STONE, 185, 10, 7, 1),
    R(T_STONE, 186, 9, 6, 1), R(T_STONE, 187, 8, 5, 1), R(T_STONE, 188, 0, 4, 4),
    R(T_STONE, 188, 7, 4, 1), R(T_STONE, 190, 4, 2, 3)
};
static const LevelEnemy k_l3_enemies[] = {
    { 20, 4, E_SQUID, 0 }, { 28, 7, E_FISH, 0 }, { 40, 3, E_FISH, 0 }, { 46, 6, E_SQUID, 0 },
    { 58, 8, E_FISH, 0 }, { 64, 4, E_FISH_FAST, 0 }, { 70, 3, E_SQUID, 0 }, { 82, 3, E_FISH, 0 },
    { 96, 5, E_SQUID, 0 }, { 104, 7, E_FISH, 0 }, { 112, 6, E_FISH_FAST, 0 }, { 120, 4, E_SQUID, 0 },
    { 130, 5, E_FISH, 0 }, { 140, 8, E_FISH, 0 }, { 150, 6, E_SQUID, 0 }, { 158, 3, E_FISH_FAST, 0 },
    { 168, 7, E_FISH_FAST, 0 }, { 176, 3, E_SQUID, 0 }
};

/* Level 4, World 8-2: 229 columns. Pits, stairs, pipes, bullet cannons (stone columns, E_MISSILE on top),
 * a long brick walkway, and the flagpole. */
static const LevelRect k_l4_rects[] = {
    R(T_GROUND, 0, 11, 15, 1), R(T_GROUND, 16, 11, 5, 1), R(T_GROUND, 22, 11, 14, 1),
    R(T_GROUND, 37, 11, 8, 1), R(T_GROUND, 46, 11, 4, 1), R(T_GROUND, 51, 11, 1, 1),
    R(T_GROUND, 53, 11, 3, 1), R(T_GROUND, 57, 11, 6, 1), R(T_GROUND, 64, 11, 14, 1),
    R(T_GROUND, 80, 11, 4, 1), R(T_GROUND, 85, 11, 53, 1), R(T_GROUND, 139, 11, 5, 1),
    R(T_GROUND, 145, 11, 1, 1), R(T_GROUND, 147, 11, 1, 1), R(T_GROUND, 154, 11, 20, 1),
    R(T_GROUND, 175, 11, 1, 1), R(T_GROUND, 179, 11, 23, 1), R(T_GROUND, 203, 11, 1, 1),
    R(T_GROUND, 206, 11, 23, 1), R(T_DIRT, 0, 12, 15, 1), R(T_DIRT, 16, 12, 5, 1),
    R(T_DIRT, 22, 12, 14, 1), R(T_DIRT, 37, 12, 8, 1), R(T_DIRT, 46, 12, 4, 1),
    R(T_DIRT, 51, 12, 1, 1), R(T_DIRT, 53, 12, 3, 1), R(T_DIRT, 57, 12, 6, 1),
    R(T_DIRT, 64, 12, 14, 1), R(T_DIRT, 80, 12, 4, 1), R(T_DIRT, 85, 12, 53, 1),
    R(T_DIRT, 139, 12, 5, 1), R(T_DIRT, 145, 12, 1, 1), R(T_DIRT, 147, 12, 1, 1),
    R(T_DIRT, 154, 12, 20, 1), R(T_DIRT, 175, 12, 1, 1), R(T_DIRT, 179, 12, 23, 1),
    R(T_DIRT, 203, 12, 1, 1), R(T_DIRT, 206, 12, 23, 1), R(T_CLOUD, 29, 0, 2, 1),
    R(T_CLOUD, 47, 0, 2, 1), R(T_CLOUD, 77, 0, 2, 1), R(T_CLOUD, 95, 0, 2, 1),
    R(T_CLOUD, 125, 0, 2, 1), R(T_CLOUD, 143, 0, 2, 1), R(T_CLOUD, 173, 0, 2, 1),
    R(T_CLOUD, 191, 0, 2, 1), R(T_CLOUD, 221, 0, 2, 1), R(T_CLOUD, 1, 1, 2, 1),
    R(T_CLOUD, 18, 1, 2, 1), R(T_CLOUD, 66, 1, 2, 1), R(T_CLOUD, 114, 1, 2, 1),
    R(T_CLOUD, 162, 1, 2, 1), R(T_CLOUD, 210, 1, 2, 1), R(T_STONE, 17, 10, 4, 1),
    R(T_STONE, 18, 9, 3, 1), R(T_STONE, 19, 8, 2, 1), R(T_STONE, 20, 7, 1, 1),
    R(T_STONE, 22, 5, 4, 6), R(T_STONE, 23, 4, 3, 1), R(T_STONE, 24, 3, 2, 1),
    R(T_QCOIN, 29, 7, 1, 1), R(T_QPOWER, 30, 7, 1, 1), R(T_QCOIN, 31, 7, 2, 1),
    R(T_BRICK, 43, 3, 33, 1), R(T_STONE, 44, 9, 1, 1), R(T_BRICK, 44, 10, 1, 1),
    R(T_BRICK, 77, 7, 2, 1), R(T_STONE, 85, 9, 1, 2), R(T_STONE, 93, 8, 1, 3),
    R(T_BRICK, 99, 7, 2, 1), R(T_STONE, 105, 9, 1, 2), R(T_BRICK, 110, 7, 2, 1),
    R(T_STONE, 115, 10, 1, 1), R(T_BRICK, 118, 7, 1, 1), R(T_STONE, 119, 6, 1, 2),
    R(T_BRICK, 120, 7, 1, 1), R(T_STONE, 125, 8, 1, 2), R(T_PIPE_TL, 131, 9, 1, 1),
    R(T_PIPE_L, 131, 10, 1, 1), R(T_PIPE_TR, 132, 9, 1, 1), R(T_PIPE_R, 132, 10, 1, 1),
    R(T_PIPE_TL, 142, 9, 1, 1), R(T_PIPE_L, 142, 10, 1, 1), R(T_PIPE_TR, 143, 9, 1, 1),
    R(T_PIPE_R, 143, 10, 1, 1), R(T_PIPE_TL, 156, 7, 1, 1), R(T_PIPE_L, 156, 8, 1, 3),
    R(T_PIPE_TR, 157, 7, 1, 1), R(T_PIPE_R, 157, 8, 1, 3), R(T_PIPE_TL, 163, 9, 1, 1),
    R(T_PIPE_L, 163, 10, 1, 1), R(T_PIPE_TR, 164, 9, 1, 1), R(T_PIPE_R, 164, 10, 1, 1),
    R(T_STONE, 175, 9, 1, 2), R(T_STONE, 182, 10, 5, 1), R(T_STONE, 183, 9, 4, 1),
    R(T_STONE, 184, 8, 3, 1), R(T_STONE, 185, 7, 2, 1), R(T_STONE, 186, 6, 1, 1),
    R(T_STONE, 191, 8, 1, 3), R(T_STONE, 199, 10, 3, 1), R(T_STONE, 200, 9, 2, 1),
    R(T_STONE, 201, 8, 1, 1), R(T_STONE, 203, 6, 1, 5), R(T_STONE, 206, 3, 2, 8),
    R(T_GOAL, 216, 0, 1, 1), R(T_POLE, 216, 1, 1, 9), R(T_STONE, 216, 10, 1, 1)
};
static const LevelEnemy k_l4_enemies[] = {
    { 24, 3, E_SQUAT, 0 }, { 33, 11, E_SHELL, 0 }, { 40, 11, E_SQUAT, 0 }, { 44, 11, E_MISSILE, 0 },
    { 48, 3, E_HOPPER, 0 }, { 55, 3, E_SQUAT, 0 }, { 70, 3, E_SQUAT, 0 }, { 76, 11, E_SHELL, 0 },
    { 85, 11, E_MISSILE, 0 }, { 93, 10, E_MISSILE, 0 }, { 100, 7, E_SQUAT, 0 }, { 104, 11, E_SHELL, 0 },
    { 105, 11, E_MISSILE, 0 }, { 112, 11, E_SQUAT, 0 }, { 115, 12, E_MISSILE, 0 }, { 119, 8, E_MISSILE, 0 },
    { 120, 7, E_HOPPER, 0 }, { 125, 10, E_MISSILE, 0 }, { 130, 11, E_SQUAT, 0 }, { 136, 11, E_SHELL, 0 },
    { 147, 11, E_SQUAT, 0 }, { 162, 11, E_SHELL, 0 }, { 170, 11, E_SQUAT, 0 }, { 172, 11, E_HOPPER, 0 },
    { 175, 11, E_MISSILE, 0 }, { 185, 7, E_SQUAT, 0 }, { 188, 11, E_SHELL, 0 }, { 191, 10, E_MISSILE, 0 },
    { 196, 11, E_SQUAT, 0 }
};

/* Level 5, World 8-4 (castle): 256 columns (the NES map is 320; the plain stretch at columns 100-163 is cut so the level fits
 * the uint8_t column fields). Stone hull, white pipes with stack plants, four lava pits with podoboos, firebars on T_USED
 * hubs, and the bridge arena with Bowser before the goal pad. Spawns on top of the start block. Castle gray is T_STONE;
 * lava is a bare pit (no lava tile exists). */
static const LevelRect k_l5_rects[] = {
    R(T_STONE, 0, 0, 246, 1), R(T_STONE, 0, 5, 3, 1), R(T_STONE, 0, 6, 4, 1),
    R(T_STONE, 0, 7, 5, 1), R(T_STONE, 0, 8, 6, 5), R(T_STONE, 11, 11, 8, 2),
    R(T_PIPE_TL, 19, 9, 1, 1), R(T_PIPE_L, 19, 10, 1, 3), R(T_PIPE_TR, 20, 9, 1, 1),
    R(T_PIPE_R, 20, 10, 1, 3), R(T_STONE, 21, 11, 30, 2), R(T_USED, 30, 7, 1, 1),
    R(T_PIPE_TL, 51, 9, 1, 1), R(T_PIPE_L, 51, 10, 1, 3), R(T_PIPE_TR, 52, 9, 1, 1),
    R(T_PIPE_R, 52, 10, 1, 3), R(T_STONE, 53, 11, 13, 2), R(T_USED, 58, 6, 1, 1),
    R(T_STONE, 62, 8, 4, 3), R(T_STONE, 75, 8, 6, 5), R(T_STONE, 76, 4, 4, 1),
    R(T_PIPE_TL, 81, 6, 1, 1), R(T_PIPE_L, 81, 7, 1, 6), R(T_PIPE_TR, 82, 6, 1, 1),
    R(T_PIPE_R, 82, 7, 1, 6), R(T_STONE, 83, 8, 7, 5), R(T_PIPE_TL, 90, 5, 1, 1),
    R(T_PIPE_L, 90, 6, 1, 7), R(T_PIPE_TR, 91, 5, 1, 1), R(T_PIPE_R, 91, 6, 1, 7),
    R(T_STONE, 92, 8, 4, 3), R(T_STONE, 92, 11, 39, 2), R(T_USED, 98, 7, 1, 1),
    R(T_USED, 106, 7, 1, 1), R(T_PIPE_TL, 131, 9, 1, 1), R(T_PIPE_L, 131, 10, 1, 3),
    R(T_PIPE_TR, 132, 9, 1, 1), R(T_PIPE_R, 132, 10, 1, 3), R(T_STONE, 133, 11, 7, 2),
    R(T_STONE, 134, 8, 6, 3), R(T_PIPE_TL, 140, 6, 1, 1), R(T_PIPE_L, 140, 7, 1, 6),
    R(T_PIPE_TR, 141, 6, 1, 1), R(T_PIPE_R, 141, 7, 1, 6), R(T_STONE, 142, 8, 6, 5),
    R(T_PIPE_TL, 148, 5, 1, 1), R(T_PIPE_L, 148, 6, 1, 7), R(T_PIPE_TR, 149, 5, 1, 1),
    R(T_PIPE_R, 149, 6, 1, 7), R(T_STONE, 150, 8, 6, 5), R(T_STONE, 160, 8, 4, 5),
    R(T_PIPE_TL, 164, 6, 1, 1), R(T_PIPE_L, 164, 7, 1, 6), R(T_PIPE_TR, 165, 6, 1, 1),
    R(T_PIPE_R, 165, 7, 1, 6), R(T_STONE, 166, 8, 26, 3), R(T_STONE, 166, 11, 29, 2),
    R(T_USED, 172, 7, 1, 1), R(T_PIPE_TL, 195, 9, 1, 1), R(T_PIPE_L, 195, 10, 1, 3),
    R(T_PIPE_TR, 196, 9, 1, 1), R(T_PIPE_R, 196, 10, 1, 3), R(T_STONE, 197, 11, 5, 2),
    R(T_USED, 198, 7, 1, 1), R(T_PIPE_TL, 202, 9, 1, 1), R(T_PIPE_L, 202, 10, 1, 3),
    R(T_PIPE_TR, 203, 9, 1, 1), R(T_PIPE_R, 203, 10, 1, 3), R(T_STONE, 204, 11, 9, 2),
    R(T_STONE, 218, 1, 6, 2), R(T_STONE, 218, 8, 22, 1), R(T_STONE, 218, 9, 6, 4),
    R(T_STONE, 237, 7, 3, 1), R(T_STONE, 237, 9, 3, 2), R(T_STONE, 237, 11, 19, 2),
    R(T_STONE, 238, 1, 2, 3), R(T_GOAL, 246, 1, 1, 1), R(T_POLE, 246, 2, 1, 8),
    R(T_STONE, 246, 10, 1, 1), R(T_STONE, 247, 0, 9, 1)
};
static const LevelEnemy k_l5_enemies[] = {
    { 8, 3, E_LAVA, 0 }, { 30, 7, E_CHAIN, 0 }, { 51, 9, E_PLANT, 0 }, { 58, 6, E_CHAIN, 0 },
    { 70, 3, E_LAVA, 0 }, { 90, 5, E_PLANT, 0 }, { 98, 7, E_CHAIN, 0 }, { 106, 7, E_CHAIN_LONG, 0 },
    { 140, 6, E_PLANT, 0 }, { 158, 3, E_LAVA, 0 }, { 164, 6, E_PLANT, 0 }, { 172, 7, E_CHAIN, 0 },
    { 195, 9, E_PLANT, 0 }, { 198, 7, E_CHAIN_LONG, LE_CCW }, { 215, 3, E_LAVA, 0 }, { 232, 8, E_BOSS, 0 }
};

#define LV(rects, en, cols, water, time, bg) \
    { rects, en, (uint8_t)(sizeof rects / sizeof rects[0]), (uint8_t)(sizeof en / sizeof en[0]), \
      cols, water, 176, 40, time, bg }
#define LVS(rects, en, cols, water, time, bg, sx, sy) \
    { rects, en, (uint8_t)(sizeof rects / sizeof rects[0]), (uint8_t)(sizeof en / sizeof en[0]), \
      cols, water, sy, sx, time, bg }

const LevelDef g_levels[] = {
    LV(k_l1_rects, k_l1_enemies, 211, 0, 400, 0),
    LV(k_l2_rects, k_l2_enemies, 164, 0, 300, 0),
    LV(k_l3_rects, k_l3_enemies, 192, 1, 400, 1),
    LV(k_l4_rects, k_l4_enemies, 229, 0, 400, 0),
    LVS(k_l5_rects, k_l5_enemies, 256, 0, 400, 0, 40, 80)
};
const uint8_t g_num_levels = (uint8_t)(sizeof g_levels / sizeof g_levels[0]);
