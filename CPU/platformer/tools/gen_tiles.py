#!/usr/bin/env python3
"""Generate tiles.c / tiles.h.

Tile and sprite art is cut from two sprite sheets (see the sprite-sheet input
section below), downscaled 2x to the game's 8x8 and quantised to RGB332.
Anything the sheets have no counterpart for (player, power-ups, particles,
spring, vine, font) keeps the ASCII art in this file.

Colours are RGB332 (RRRGGGBB). In tiles '.' / transparent sheet pixels become
the level's background colour baked in at generation time; in sprites they
become the transparent key.

Usage: gen_tiles.py OUTDIR [--assets DIR] [--ascii-only] [--extras] [--preview PNG]
Needs Pillow unless --ascii-only is given.
"""
import argparse
import os
import sys
from collections import Counter

PAL = {
    'k': (24, 20, 36),    'w': (250, 250, 250), 'g': (90, 200, 70),
    'G': (30, 110, 40),   'b': (150, 90, 40),   'B': (90, 50, 20),
    'o': (240, 140, 30),  'y': (250, 220, 40),  'Y': (180, 140, 0),
    'r': (220, 40, 40),   'R': (130, 10, 20),   'c': (80, 230, 240),
    'C': (20, 120, 140),  's': (190, 190, 200), 'S': (100, 100, 110),
    'p': (200, 90, 220),  'P': (110, 40, 130),  'u': (60, 110, 230),
    'U': (20, 40, 120),   'l': (120, 190, 250), 'L': (40, 90, 200),
    'e': (230, 200, 140),
}
SKY = (100, 180, 250)
BACKGROUNDS = [SKY, (40, 90, 200)]   # 0: open air, 1: water level (matches 'L')
TRANSPARENT = 0xE3     # magenta key, never produced by PAL


def rgb332(c):
    r, g, b = c
    v = ((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6)
    assert v != TRANSPARENT
    return v


def px(ch, bg):
    if ch == '.':
        return bg
    return rgb332(PAL[ch])


# ---------------- background tiles, order = tile ids in game.h ----------------
TILES = [
    ("T_SKY", ["........"] * 8),
    ("T_GROUND", ["gggggggg", "gGggGggg", "GbGbbGbG", "bbbbBbbb",
                  "bBbbbbbb", "bbbbbBbb", "bbBbbbbb", "bbbbbbBb"]),
    ("T_DIRT", ["bbbbBbbb", "bBbbbbbb", "bbbbbBbb", "bbBbbbbb",
                "bbbbbbBb", "Bbbbbbbb", "bbbBbbbb", "bbbbbbbB"]),
    ("T_BRICK", ["CCCkCCCk", "CoCkCCCk", "CoooCoCk", "kkkkkkkk",
                 "CkCCCkCC", "CkCooooC", "CkCCCkCC", "kkkkkkkk"]),
    ("T_BRICK_MULTI", None),          # same art as T_BRICK
    ("T_QCOIN", ["kkkkkkkk", "kYyyyyYk", "kyyywyyk", "kyywwyyk",
                 "kywwwwyk", "kyyywyyk", "kYyywyYk", "kkkkkkkk"]),
    ("T_QPOWER", None), ("T_QSTAR", None), ("T_Q1UP", None),
    ("T_USED", ["SSSSSSSS", "SsSSSSsS", "SSSSSSSS", "SSSkkSSS",
                "SSSkkSSS", "SSSSSSSS", "SsSSSSsS", "SSSSSSSS"]),
    ("T_HIDDEN_COIN", ["........"] * 8),
    ("T_HIDDEN_1UP", ["........"] * 8),
    ("T_COIN", ["........", "..ssss..", ".ssSSss.", ".sS..Ss.",
                ".sS..Ss.", ".ssSSss.", "..ssss..", "........"]),
    ("T_BUMPED", ["........"] * 8),
    ("T_STONE", ["sssssssS", "sSssssSS", "ssssssSS", "sssssSSS",
                 "ssssSSsS", "sssSSssS", "sSSSssSS", "SSSSSSSS"]),
    ("T_PIPE_TL", ["kkkkkkkk", "ksssssss", "kSSSSSSS", "kkkkkkkk",
                   ".kSsssss", ".kSsssss", ".kSsssss", ".kSsssss"]),
    ("T_PIPE_TR", ["kkkkkkkk", "sssssssk", "SSSSSSSk", "kkkkkkkk",
                   "sssSSSk.", "sssSSSk.", "sssSSSk.", "sssSSSk."]),
    ("T_PIPE_L", [".kSsssss", ".kSsssss", ".kSkkkkk", ".kSsssss",
                  ".kSsssss", ".kSsssss", ".kSkkkkk", ".kSsssss"]),
    ("T_PIPE_R", ["sssSSSk.", "sssSSSk.", "kkkSSSk.", "sssSSSk.",
                  "sssSSSk.", "sssSSSk.", "kkkSSSk.", "sssSSSk."]),
    ("T_VINE", ["...Gg...", "...gG...", "..gGg...", "...Gg...",
                "...gGg..", "...Gg...", "..gGg...", "...gG..."]),
    ("T_POLE", ["...ss...", "...sS...", "...sS...", "...sS...",
                "...sS...", "...sS...", "...sS...", "...sS..."]),
    ("T_SPRING", ["rrrrrrrr", "RRRRRRRR", ".s....s.", "..s..s..",
                  ".s....s.", "..s..s..", ".s....s.", "SSSSSSSS"]),
    ("T_GOAL", ["ykykykyk", "kykykyky", "SSSSSSSS", "SccSSccS",
                "SccSSccS", "SSSSSSSS", "SsSSSSsS", "SSSSSSSS"]),
    ("T_CLOUD", ["........", "...ww...", "..wwww..", ".wwwwww.",
                 "wwwwwwww", "wlwwwwlw", ".llllll.", "........"]),
    ("T_BUSH", ["........", "........", "...gg...", "..gggg..",
                ".ggGggg.", "gggggGgg", "gGgggggg", "gggGgggg"]),
    ("T_WATER", ["LLLLLLLL"] * 8),
    ("T_WATERTOP", ["llllllll", "lLlllLll", "LLLLLLLL", "LLLLLLLL",
                    "LLLLLLLL", "LLLLLLLL", "LLLLLLLL", "LLLLLLLL"]),
    # mushroom platform (SMB 1-3): solid cap left / middle / right, and the non-solid trunk
    ("T_TREE_L", ["........", ".ggggggg", "gggggggg", "gGggGggg",
                  "gggggggg", ".ggggggg", "........", "........"]),
    ("T_TREE_M", ["........", "gggggggg", "gggggggg", "gGggGggg",
                  "gggggggg", "gggggggg", "........", "........"]),
    ("T_TREE_R", ["........", "ggggggg.", "gggggggg", "gGggGggg",
                  "gggggggg", "ggggggg.", "........", "........"]),
    ("T_TRUNK", ["..bbbb..", "..bBbb..", "..bbbB..", "..bBbb..",
                 "..bbbb..", "..bbBb..", "..bbbb..", "..bBbb.."]),
    # ends of a cloud / bush that is 2 or more cells wide; the art comes from EDGE_TILES below
    ("T_CLOUD_L", None), ("T_CLOUD_R
]

# ---------------- sprites (8x8, '.' transparent) ----------------
SPRITES = [
    # player robot, small: stand / walk / jump, facing right
    ("SPR_SMALL_STAND", ["....y...", "....S...", ".ssssss.", ".sswscw.",
                         ".ssssss.", "..uuuu..", "..u..u..", ".kk..kk."]),
    ("SPR_SMALL_WALK", ["....y...", "....S...", ".ssssss.", ".sswscw.",
                        ".ssssss.", "..uuuu..", ".u....u.", "kk....kk"]),
    ("SPR_SMALL_JUMP", ["s...y..s", "s...S..s", ".ssssss.", ".sswscw.",
                        ".ssssss.", "..uuuu..", ".uu..uu.", ".k....k."]),
    # big robot: top/bottom halves
    ("SPR_BIG_TOP", ["....y...", "....S...", "..ssss..", ".ssssss.",
                     ".sswscw.", ".ssssss.", "..ssss..", ".uuuuuu."]),
    ("SPR_BIG_BOT", ["suuyyuus", "suuyyuus", "s.uuuu.s", "..uuuu..",
                     "..u..u..", "..u..u..", ".uu..uu.", ".kk..kk."]),
    ("SPR_BIG_BOT_WALK", ["suuyyuus", "suuyyuus", "s.uuuu.s", "..uuuu..",
                          ".u....u.", ".u....u.", "uu....uu", "kk....kk"]),
    ("SPR_BIG_CROUCH", ["....y...", ".ssssss.", ".sswscw.", ".ssssss.",
                        "suuyyuus", "suuuuuus", ".uu..uu.", ".kk..kk."]),
    ("SPR_DEAD", ["s......s", ".s.yy.s.", "..ssss..", ".skwswk.",
                  ".ssssss.", "..uuuu..", ".u.uu.u.", "k......k"]),
    # fuzz mite (squat walker): two walk frames and flattened
    ("SPR_MITE_A", [".p.pp.p.", "..pppp..", ".pwwwwp.", "ppwkkwpp",
                    "ppwwwwpp", ".pppppp.", "..p..p..", ".kk..kk."]),
    ("SPR_MITE_B", [".p.pp.p.", "..pppp..", ".pwwwwp.", "ppwkkwpp",
                    "ppwwwwpp", ".pppppp.", ".p....p.", "kk....kk"]),
    ("SPR_MITE_FLAT", ["........", "........", "........", "........",
                       "........", ".p.pp.p.", "pwkkkkwp", "pppppppp"]),
    # beetle (shell walker), facing left: two frames, shell, winged
    ("SPR_BEETLE_A", ["..rrrr..", ".rrkrrr.", "rrrrrkrr", "krkrrrrr",
                      "kkrrrrrr", "kkkkkkkk", ".k.k.k..", "k...k..."]),
    ("SPR_BEETLE_B", ["..rrrr..", ".rrkrrr.", "rrrrrkrr", "krkrrrrr",
                      "kkrrrrrr", "kkkkkkkk", "..k.k.k.", "...k...k"]),
    ("SPR_SHELL", ["........", "........", "........", "..rrrr..",
                   ".rkrrkr.", "rrrrrrrr", "rkrrrrkr", ".kkkkkk."]),
    ("SPR_BEETLE_WING", [".ww..ww.", "wwrrrrww", ".rrkrrr.", "rrrrrkrr",
                         "krkrrrrr", "kkrrrrrr", "kkkkkkkk", ".k.k.k.."]),
    # items
    ("SPR_BATTERY", ["...ss...", ".kkkkkk.", ".kggggk.", ".kgwwgk.",
                     ".kggggk.", ".kGGGGk.", ".kGGGGk.", ".kkkkkk."]),
    ("SPR_CORE", ["...rr...", "..rooR..", ".rooyoR.", "royywyoR",
                  "Royyyyor", ".Rooyor.", "..RoorR.", "...RR..."]),
    ("SPR_GEAR", ["..y..y..", ".yyyyyy.", "yyYyyYyy", ".yy..yy.",
                  ".yy..yy.", "yyYyyYyy", ".yyyyyy.", "..y..y.."]),
    ("SPR_HEART", ["........", ".cc..cc.", "cwcccccc", "cccccccc",
                   ".cccccc.", "..cccc..", "...cc...", "........"]),
    ("SPR_NUT", ["........", "..ssss..", ".ssSSss.", ".sS..Ss.",
                 ".sS..Ss.", ".ssSSss.", "..ssss..", "........"]),
    ("SPR_SPARK", ["........", "........", "...oy...", "..oyyo..",
                   "..oyyo..", "...yo...", "........", "........"]),
    ("SPR_PUFF", ["........", ".y....y.", "...ww...", "..w..w..",
                  "..w..w..", "...ww...", ".y....y.", "........"]),
    ("SPR_HUD_NUT", ["..ss....", ".sSSs...", ".sSSs...", "..ss....",
                     "........", "........", "........", "........"]),
    ("SPR_HUD_HEART", [".c.c....", "ccccc...", ".ccc....", "..c.....",
                       "........", "........", "........", "........"]),
]

# 3x5 digits, each row a 3-bit mask (bit 2 = leftmost)
FONT = [
    ["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
    ["###", "..#", "###", "#..", "###"], ["###", "..#", ".##", "..#", "###"],
    ["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
    ["###", "#..", "###", "#.#", "###"], ["###", "..#", ".#.", ".#.", ".#."],
    ["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]



# ======================= sprite-sheet input =======================
#
# Two ripped sheets supply the art. Neither is a plain 8x8 grid, so the
# geometry is described here instead of being guessed:
#
#  * Blocks sheet: 16x16 metatiles separated by a 1 px grid line (pitch 17).
#    Each palette group has its own origin (top-left pixel of tile 0,0), so a
#    tile is addressed as (group, row, col). Only the "Overworld" variant of
#    each group is used.
#  * Entities sheet: sprite cells sit on a 2 px gap (pitch 18) but vary in size
#    (16x16 walkers, 16x24 koopas, 16x8 squashed goomba, 32x32 bowser), so each
#    sprite is an explicit (x, y, w, h) rectangle.
#
# The game draws 8x8 tiles and sprites, the sheets are 16x16, so every cell is
# padded to 16x16 (bottom-aligned) and halved with half().
#
SHEET_FILES = {
    "B": "Custom_Tileset_Blocks.png",
    "E": "Custom_Tileset_Entities.png",
    "I": "Custom_Tileset_Items_Objects_and_NPCs.png",
    "P": "Custom_Tileset_Playable_Characters.png",
    "S": "Custom_Stage_Trees.png",       # four cells cut from the 1-3 stage map: tree cap L/M/R, trunk
}
BLOCK_PITCH = 17
BLOCK_GROUPS = {          # origin of tile (0,0) of the Overworld variant
    "P1": (0, 16),        # ground and stone: ground, brick, stair block, castle...
    "P0": (0, 196),       # pipes and scenery: pipes, bushes, hills, flagpole...
    "P2": (298, 16),      # water and sky: cloud, water surface, water fill
    "P3": (298, 78),      # coins: question block frames, used block, coins
}
SHEET_BG = (0, 41, 140)   # canvas colour of the sheets, never art
WATER_SRC = (99, 173, 255)
WATER = {WATER_SRC: BACKGROUNDS[1]}   # keep water identical to the water-level bg

# A source is either ("P1", row, col) on the blocks sheet (16x16 tiles, pitch 17,
# origin per palette group) or (sheet, x, y, w, h), an explicit rectangle on any sheet:
# B blocks, E entities, I items/objects/NPCs, P playable characters.
#
# game tile -> source; tiles not listed keep their ASCII art
TILE_SRC = {
    "T_GROUND": ("P1", 0, 0), "T_DIRT": ("P1", 0, 0),
    "T_BRICK": ("P1", 0, 1), "T_BRICK_MULTI": ("P1", 0, 1),
    "T_QCOIN": ("P3", 0, 0), "T_QPOWER": ("P3", 0, 0),
    "T_QSTAR": ("P3", 0, 0), "T_Q1UP": ("P3", 0, 0),
    "T_USED": ("P3", 0, 3),
    "T_COIN": ("P3", 1, 0),
    "T_STONE": ("P1", 1, 0),
    "T_PIPE_TL": ("P0", 0, 7), "T_PIPE_TR": ("P0", 0, 8),
    "T_PIPE_L": ("P0", 1, 7), "T_PIPE_R": ("P0", 1, 8),
    "T_VINE": ("I", 148, 90, 16, 16),       # climbing vine
    "T_POLE": ("P0", 3, 8), "T_GOAL": ("P0", 2, 8),
    "T_SPRING": ("I", 68, 91, 16, 15),      # springboard, fully compressed
    "T_CLOUD": ("P2", 0, 1),
    "T_BUSH": ("P0", 1, 1),
    "T_WATER": ("P2", 1, 3), "T_WATERTOP": ("P2", 0, 3),
    "T_TREE_L": ("S", 0, 0, 16, 16), "T_TREE_M": ("S", 16, 0, 16, 16),
    "T_TREE_R": ("S", 32, 0, 16, 16), "T_TRUNK": ("S", 48, 0, 16, 16),
}
TILE_RECOLOR = {"T_WATER": WATER, "T_WATERTOP": WATER}

# Sprites. Each row is (names, source, tiles_wide, tiles_high, options): the source cell
# is padded to that many 16x16 cells (centred, sitting on the floor), halved, and cut
# into 8x8 pieces in row-major order, one name per piece ("_" discards a piece).
# A name the ASCII list already has REPLACES that slot; a new name is APPENDED after the
# last existing sprite, in table order, so existing ids never move.
# options: valign="mid"/"top" (default: floor) places the cell in the padded area, squash=N resamples to N rows
# first, keyblack=True turns black that touches the cell edge transparent.
MID = {"valign": "mid"}
TOP = {"valign": "top"}
SHEET_SPRITES = [
    # ---- replaces placeholders ----
    (["SPR_SMALL_STAND"], ("P", 0, 8, 16, 16), 1, 1, {}),
    (["SPR_SMALL_WALK"], ("P", 20, 8, 16, 16), 1, 1, {}),
    (["SPR_SMALL_JUMP"], ("P", 96, 8, 16, 16), 1, 1, {}),
    (["SPR_BIG_TOP", "SPR_BIG_BOT"], ("P", 0, 32, 16, 32), 1, 2, {}),
    (["_", "SPR_BIG_BOT_WALK"], ("P", 20, 32, 16, 32), 1, 2, {}),
    (["SPR_BIG_CROUCH"], ("P", 116, 40, 16, 24), 1, 1, {"squash": 16}),
    (["SPR_DEAD"], ("P", 116, 8, 16, 16), 1, 1, {}),
    (["SPR_MITE_A"], ("E", 0, 16, 16, 16), 1, 1, {}),            # goomba
    (["SPR_MITE_B"], ("E", 18, 16, 16, 16), 1, 1, {}),
    (["SPR_MITE_FLAT"], ("E", 36, 24, 16, 8), 1, 1, {}),
    (["SPR_BEETLE_A"], ("E", 0, 34, 16, 16), 1, 1, {}),          # buzzy beetle, faces left
    (["SPR_BEETLE_B"], ("E", 18, 34, 16, 16), 1, 1, {}),
    (["SPR_SHELL"], ("E", 36, 34, 16, 16), 1, 1, {}),
    (["SPR_BATTERY"], ("I", 0, 8, 16, 16), 1, 1, {}),            # super mushroom
    (["SPR_CORE"], ("I", 32, 8, 16, 16), 1, 1, {}),              # fire flower
    (["SPR_GEAR"], ("I", 124, 8, 16, 16), 1, 1, {}),             # starman
    (["SPR_HEART"], ("I", 0, 26, 16, 16), 1, 1, {}),             # 1-up mushroom
    (["SPR_NUT"], ("P3", 1, 0), 1, 1, {}),                       # coin
    (["SPR_SPARK"], ("I", 180, 54, 8, 8), 1, 1, MID),            # fireball
    (["SPR_PUFF"], ("I", 198, 64, 16, 16), 1, 1, {}),            # fireball impact
    # ---- appended, in the order of the project's tiles.h (see NEW_ORDER) ----
    (["SPR_SLAG"], ("E", 90, 370, 16, 16), 1, 1, {}),                       # podoboo
    (["SPR_CLAW_A", "SPR_CLAW_ROD"], ("E", 0, 138, 16, 24), 1, 2, TOP),     # piranha head, stem
    (["SPR_CLAW_B", "_"], ("E", 18, 138, 16, 24), 1, 2, TOP),
    (["SPR_DRONE_A"], ("E", 0, 370, 16, 16), 1, 1, {}),                     # cheep cheep
    (["SPR_DRONE_B"], ("E", 18, 370, 16, 16), 1, 1, {}),
    (["SPR_JELLY_A"], ("E", 0, 52, 16, 24), 1, 1, {"squash": 16}),          # blooper
    (["SPR_JELLY_B"], ("E", 18, 52, 16, 16), 1, 1, {}),
    (["SPR_DART"], ("E", 54, 52, 16, 16), 1, 1, {}),                        # bullet bill
    (["SPR_CALTROP_A"], ("E", 72, 352, 16, 16), 1, 1, {}),                  # spiny
    (["SPR_CALTROP_B"], ("E", 90, 352, 16, 16), 1, 1, {}),
    (["SPR_CALTROP_EGG"], ("E", 36, 352, 16, 16), 1, 1, {}),                # spiny egg
    (["SPR_EMBER"], ("I", 200, 54, 8, 8), 1, 1, MID),                       # fireball frame
    (["SPR_BOSS_A_TL", "SPR_BOSS_A_TR", "SPR_BOSS_A_BL", "SPR_BOSS_A_BR"],  # bowser
     ("E", 0, 208, 32, 32), 2, 2, {}),
    (["SPR_BOSS_B_TL", "SPR_BOSS_B_TR", "SPR_BOSS_B_BL", "SPR_BOSS_B_BR"],
     ("E", 68, 208, 32, 32), 2, 2, {}),
    (["SPR_JET_A_L", "SPR_JET_A_R"], ("E", 102, 242, 24, 8), 2, 1, {}),     # bowser fire
    (["SPR_JET_B_L", "SPR_JET_B_R"], ("E", 102, 252, 24, 8), 2, 1, {}),
]
# enum order of the appended sprites; must match tiles.h in the project
NEW_ORDER = [
    "SPR_SLAG", "SPR_CLAW_A", "SPR_CLAW_B", "SPR_CLAW_ROD", "SPR_DRONE_A", "SPR_DRONE_B",
    "SPR_JELLY_A", "SPR_JELLY_B", "SPR_DART", "SPR_CALTROP_A", "SPR_CALTROP_B",
    "SPR_CALTROP_EGG", "SPR_EMBER",
    "SPR_BOSS_A_TL", "SPR_BOSS_A_TR", "SPR_BOSS_A_BL", "SPR_BOSS_A_BR",
    "SPR_BOSS_B_TL", "SPR_BOSS_B_TR", "SPR_BOSS_B_BL", "SPR_BOSS_B_BR",
    "SPR_JET_A_L", "SPR_JET_A_R", "SPR_JET_B_L", "SPR_JET_B_R",
]
# Optional extras, appended after NEW_ORDER only with --extras (not in the project's tiles.h)
EXTRA_SPRITES = [
    (["SPR_SMALL_WALK2"], ("P", 38, 8, 16, 16), 1, 1, {}),
    (["SPR_SMALL_WALK3"], ("P", 56, 8, 16, 16), 1, 1, {}),
    (["SPR_SMALL_SKID"], ("P", 76, 8, 16, 16), 1, 1, {}),
    (["SPR_BIG_SKID_TOP", "SPR_BIG_SKID_BOT"], ("P", 76, 32, 16, 32), 1, 2, {}),
    (["SPR_BIG_JUMP_TOP", "SPR_BIG_JUMP_BOT"], ("P", 96, 32, 16, 32), 1, 2, {}),
    (["SPR_SPINY_EGG_B"], ("E", 54, 352, 16, 16), 1, 1, {}),
    (["SPR_KOOPA_A_TOP", "SPR_KOOPA_A_BOT"], ("E", 0, 112, 16, 24), 1, 2, {}),
    (["SPR_KOOPA_B_TOP", "SPR_KOOPA_B_BOT"], ("E", 18, 112, 16, 24), 1, 2, {}),
    (["SPR_KOOPA_SHELL"], ("E", 72, 120, 16, 16), 1, 1, {}),
    (["SPR_FIREBALL_B"], ("I", 190, 54, 8, 8), 1, 1, MID),
    (["SPR_FIREBALL_D"], ("I", 210, 54, 8, 8), 1, 1, MID),
    (["SPR_PUFF_SMALL"], ("I", 180, 64, 16, 16), 1, 1, {}),
    (["SPR_PUFF_LARGE"], ("I", 216, 64, 16, 16), 1, 1, {}),
    (["SPR_BRICK_BIT_A"], ("I", 180, 26, 8, 8), 1, 1, MID),
    (["SPR_BRICK_BIT_B"], ("I", 190, 26, 8, 8), 1, 1, MID),
    (["SPR_COIN_SPIN_B"], ("I", 190, 36, 8, 16), 1, 1, {}),
    (["SPR_COIN_SPIN_C"], ("I", 200, 36, 8, 16), 1, 1, {}),
    (["SPR_COIN_SPIN_D"], ("I", 210, 36, 8, 16), 1, 1, {}),
    (["SPR_FLAG"], ("I", 110, 90, 16, 16), 1, 1, {}),
    (["SPR_CASTLE_FLAG"], ("I", 92, 90, 16, 16), 1, 1, {}),
    (["SPR_TOAD_TOP", "SPR_TOAD_BOT"], ("I", 0, 444, 16, 24), 1, 2, {"keyblack": True}),
    (["SPR_PEACH_TOP", "SPR_PEACH_BOT"], ("I", 18, 444, 16, 24), 1, 2, {"keyblack": True}),
]
PLAYER_SPRITES = ["SPR_SMALL_STAND", "SPR_SMALL_WALK", "SPR_SMALL_JUMP", "SPR_BIG_TOP",
                  "SPR_BIG_BOT", "SPR_BIG_BOT_WALK", "SPR_BIG_CROUCH", "SPR_DEAD"]
MARIO_RED, FIRE_CREAM = (181, 49, 33), (255, 206, 197)   # COL_BODY / COL_FIRE sources

# The 8x11 "?" of the question block halves into an unreadable smudge, so for these
# tiles the interior is repainted (sheet orange) and a 4x5 "?" drawn (sheet brown).
QMARK_TILES = {"T_QCOIN", "T_QPOWER", "T_QSTAR", "T_Q1UP"}
QMARK_FILL, QMARK_INK = (230, 156, 33), (156, 74, 0)
QMARK = [(3, 2), (4, 2), (2, 3), (5, 3), (4, 4), (4, 6)]   # (x, y) in the 8x8 tile
# the sheet has no winged beetle: draw wings on the walk frame where it is empty
WING_PIXELS = [(0, 0), (1, 0), (6, 0), (7, 0), (0, 1), (1, 1), (6, 1), (7, 1)]


def rgb332_nearest(c):
    """Nearest RGB332 value (rounding, not truncating, so sheet colours keep their hue)."""
    v = (round(c[0] * 7 / 255) << 5) | (round(c[1] * 7 / 255) << 2) | round(c[2] * 3 / 255)
    return v + 4 if v == TRANSPARENT else v    # nudge off the transparent key


def rgb_of(v):
    """Inverse of RGB332, for previews."""
    return (round((v >> 5) * 255 / 7), round(((v >> 2) & 7) * 255 / 7), round((v & 3) * 255 / 3))


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def half(grid):
    """2x2 -> 1 pixel. Most common colour wins; ties go to opaque, then to the darker
    colour, so 1 px outlines and mortar lines survive instead of vanishing."""
    out = []
    for y in range(len(grid) // 2):
        row = []
        for x in range(len(grid[0]) // 2):
            blk = [grid[2 * y][2 * x], grid[2 * y][2 * x + 1],
                   grid[2 * y + 1][2 * x], grid[2 * y + 1][2 * x + 1]]
            cnt = Counter(blk)
            row.append(max(cnt, key=lambda c: (cnt[c], c is not None, -lum(c) if c else 0)))
        out.append(row)
    return out


class Sheets:
    def __init__(self, folder):
        from PIL import Image          # only needed when reading sheets
        self.img = {}
        for k, f in SHEET_FILES.items():
            self.img[k] = Image.open(os.path.join(folder, f)).convert("RGB")

    @staticmethod
    def clear(p):
        """Sheet canvas or one of the lavender 'transparent' swatches (slightly different shades)."""
        return (p == SHEET_BG or p == (108, 106, 255)     # canvas, darker lavender (vine/flag cells)
                or (p[2] >= 250 and abs(p[0] - 147) <= 4 and abs(p[1] - 146) <= 4))

    def rect(self, spec):
        if spec[0] in BLOCK_GROUPS:                  # (group, row, col) on the blocks grid
            ox, oy = BLOCK_GROUPS[spec[0]]
            return "B", ox + spec[2] * BLOCK_PITCH, oy + spec[1] * BLOCK_PITCH, 16, 16
        return spec

    def cell(self, spec, keyblack=False):
        """Crop a source cell: rows of RGB tuples, None = transparent."""
        sheet, x, y, w, h = self.rect(spec)
        im = self.img[sheet]
        assert x + w <= im.width and y + h <= im.height, spec
        g = [[None if self.clear(p) else p for p in (im.getpixel((x + i, y + j)) for i in range(w))]
             for j in range(h)]
        if keyblack:       # some NPCs are drawn on black: flood the black that touches the edge
            todo = [(i, j) for j in range(h) for i in range(w) if i in (0, w - 1) or j in (0, h - 1)]
            while todo:
                i, j = todo.pop()
                if 0 <= i < w and 0 <= j < h and g[j][i] == (0, 0, 0):
                    g[j][i] = None
                    todo += [(i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)]
        return g

    def pieces(self, spec, tw=1, th=1, valign="floor", squash=None, keyblack=False, recolor=None):
        """Cut a source into tw*th 8x8 pieces (row-major): pad to the 16x16 grid, halve."""
        c = self.cell(spec, keyblack)
        if squash:                                   # drop rows evenly, e.g. 22 -> 16
            c = [c[int((i + 0.5) * len(c) / squash)] for i in range(squash)]
        h, w = len(c), len(c[0])
        W, H = 16 * tw, 16 * th
        assert w <= W and h <= H, (spec, "does not fit %dx%d" % (W, H))
        dx = (W - w) // 2
        dy = {"mid": (H - h) // 2, "top": 0}.get(valign, H - h)
        g = [[None] * W for _ in range(H)]
        for j in range(h):
            for i in range(w):
                g[dy + j][dx + i] = c[j][i]
        g = half(g)
        if recolor:
            g = [[recolor.get(p, p) if p else p for p in row] for row in g]
        return [[row[8 * tc:8 * tc + 8] for row in g[8 * tr:8 * tr + 8]]
                for tr in range(th) for tc in range(tw)]

    def grid8(self, spec, recolor=None):
        return self.pieces(spec, recolor=recolor)[0]


def to_pix(grid, clear):
    return [clear if c is None else rgb332_nearest(c) for row in grid for c in row]


def preview(path, sets, sprites, per_row=31):
    from PIL import Image
    S, pad = 6, 2
    cell = 8 * S + pad
    srows = -(-len(sprites) // per_row)
    im = Image.new("RGB", (per_row * cell + pad, (len(sets) + srows) * cell + pad), (40, 40, 40))
    def blit(p, cx, cy, key=None):
        for i, v in enumerate(p):
            col = (255, 0, 255) if v == key else rgb_of(v)
            for dy in range(S):
                for dx in range(S):
                    im.putpixel((pad + cx * cell + (i % 8) * S + dx,
                                 pad + cy * cell + (i // 8) * S + dy), col)
    for si, tiles in enumerate(sets):
        for ti, (_, p) in enumerate(tiles):
            blit(p, ti, si)
    for pi, (_, p) in enumerate(sprites):
        blit(p, pi % per_row, len(sets) + pi // per_row, key=TRANSPARENT)
    im.save(path)


def check(name, rows):
    assert len(rows) == 8, name
    for r in rows:
        assert len(r) == 8, (name, r)


def build(sheets, extras=False):
    sets = []
    for bgc in BACKGROUNDS:
        bg = rgb332(bgc)
        tiles, last = [], None
        for name, rows in TILES:
            rows = rows or last
            check(name, rows)
            pix = [px(c, bg) for r in rows for c in r]
            if sheets and name in TILE_SRC:
                grid = sheets.grid8(TILE_SRC[name], TILE_RECOLOR.get(name))
                if name in QMARK_TILES:
                    for y in range(1, 7):
                        for x in range(1, 7):
                            grid[y][x] = QMARK_FILL
                    for x, y in QMARK:
                        grid[y][x] = QMARK_INK
                pix = to_pix(grid, bg)
            tiles.append((name, pix))
            last = rows
        sets.append(tiles)

    sprites = []
    for name, rows in SPRITES:
        check(name, rows)
        sprites.append([name, [px(c, TRANSPARENT) for r in rows for c in r]])
    by = {n: p for n, p in sprites}

    body, fire, shell = rgb332(PAL['u']), rgb332(PAL['r']), rgb332(PAL['r'])
    if sheets:
        for names, spec, tw, th, opts in SHEET_SPRITES + (EXTRA_SPRITES if extras else []):
            for n, g8 in zip(names, sheets.pieces(spec, tw, th, **opts)):
                if n == "_":
                    continue
                pix = to_pix(g8, TRANSPARENT)
                if n in by:                      # replace a placeholder in place
                    by[n][:] = pix
                else:                            # new sprite: appended after the old ones
                    sprites.append([n, pix])
                    by[n] = pix
        # winged beetle = walk frame plus wings in the empty top corners
        w = list(by["SPR_BEETLE_A"])
        for x, y in WING_PIXELS:
            if w[y * 8 + x] == TRANSPARENT:
                w[y * 8 + x] = rgb332(PAL['w'])
        by["SPR_BEETLE_WING"][:] = w
        # HUD icons = the item sprites shrunk again into the top-left 4x4
        coin_o, coin_b = (230, 156, 33), (156, 74, 0)
        icon = [".oo.", "oBBo", "oBBo", "oBBo", ".oo."]       # readable on the black HUD
        hud = [[({"o": coin_o, "B": coin_b}.get(icon[y][x]) if y < 5 and x < 4 else None) for x in range(8)]
               for y in range(8)]
        by["SPR_HUD_NUT"][:] = to_pix(hud, TRANSPARENT)
        for hud_name, src in (("SPR_HUD_HEART", "SPR_HEART"),):
            spec = next(sp for ns, sp, *_ in SHEET_SPRITES if ns == [src])
            small = half(sheets.grid8(spec))
            hud = [[small[y][x] if x < 4 and y < 4 else None for x in range(8)] for y in range(8)]
            by[hud_name][:] = to_pix(hud, TRANSPARENT)
        # COL_BODY is the player colour the game swaps for the fire power, COL_SHELL the
        # beetle colour it swaps for the armored beetle; both must occur in their sprites
        body, fire = rgb332_nearest(MARIO_RED), rgb332_nearest(FIRE_CREAM)
        for n in PLAYER_SPRITES:
            assert body in by[n], (n, "lacks COL_BODY %02X" % body)
        shell = Counter(v for v in by["SPR_BEETLE_A"] if v != TRANSPARENT).most_common(1)[0][0]
        for n in ("SPR_BEETLE_A", "SPR_BEETLE_B", "SPR_SHELL", "SPR_BEETLE_WING"):
            assert shell in by[n], (n, "lacks COL_SHELL %02X" % shell)
        # enum order: ASCII sprites, then NEW_ORDER (the project's tiles.h), then extras
        ascii_n = [n for n, _ in SPRITES]
        extra_n = [n for ns, *_ in EXTRA_SPRITES for n in ns if n != "_"] if extras else []
        want = ascii_n + NEW_ORDER + extra_n
        made = [n for n, _ in sprites]
        assert sorted(made) == sorted(want), (set(made) ^ set(want))
        sprites = [[n, by[n]] for n in want]
    return sets, [(n, p) for n, p in sprites], (body, fire, shell)


def main():
    ap = argparse.ArgumentParser(description="Generate tiles.c / tiles.h")
    ap.add_argument("outdir")
    ap.add_argument("--assets", default=os.path.dirname(os.path.abspath(__file__)),
                    help="folder holding the two sheet PNGs (default: next to this script)")
    ap.add_argument("--ascii-only", action="store_true",
                    help="ignore the sheets and emit the original ASCII-art placeholders")
    ap.add_argument("--extras", action="store_true",
                    help="append EXTRA_SPRITES (koopa, toad, peach, flags, skids...) after the roster")
    ap.add_argument("--preview", metavar="PNG", help="also write a contact sheet of the result")
    a = ap.parse_args()
    out = a.outdir
    sky = rgb332(SKY)
    sets, sprites, (body, fire, shell) = build(None if a.ascii_only else Sheets(a.assets), a.extras)
    tiles = sets[0]
    if a.preview:
        preview(a.preview, sets, sprites)

    h = ["/* generated by tools/gen_tiles.py - do not edit */",
         "#ifndef TILES_H", "#define TILES_H", "#include <stdint.h>", "",
         "#define COL_TRANSPARENT 0x%02Xu" % TRANSPARENT,
         "#define COL_SKY 0x%02Xu" % sky,
         "#define COL_BODY 0x%02Xu   /* robot body colour, swapped for the fire power */" % body,
         "#define COL_FIRE 0x%02Xu" % fire,
         "#define COL_SHELL 0x%02Xu  /* beetle colour, swapped for the armored beetle */" % shell,
         "#define COL_ARMOR 0x%02Xu" % rgb332(PAL['S']),
         "#define COL_WHITE 0x%02Xu" % rgb332(PAL['w']),
         "#define COL_BLACK 0x%02Xu" % rgb332(PAL['k']),
         "", "enum {"]
    h += ["    %s," % n for n, _ in sprites]
    h += ["    NUM_SPRITES", "};", "",
          "/* [background set][tile id][word]: 8x8 RGB332, 4 px per word, little-endian */",
          "extern const uint32_t g_tile_art[%d][%d][16];" % (len(sets), len(tiles)),
          "extern const uint8_t  g_sprite_art[NUM_SPRITES][64];",
          "extern const uint8_t  g_font[10][5];",
          "", "#endif", ""]
    open(out + "/tiles.h", "w").write("\n".join(h))

    c = ["/* generated by tools/gen_tiles.py from its ASCII art - do not edit */",
         '#include "tiles.h"', "",
         "const uint32_t g_tile_art[%d][%d][16] = {" % (len(sets), len(tiles))]
    for si, tiles in enumerate(sets):
        c.append("  { /* background set %d */" % si)
        for name, p in tiles:
            words = []
            for i in range(0, 64, 4):
                words.append(p[i] | (p[i + 1] << 8) | (p[i + 2] << 16) | (p[i + 3] << 24))
            c.append("    /* %s */" % name)
            c.append("    { " + ", ".join("0x%08Xu" % w for w in words[:8]) + ",")
            c.append("      " + ", ".join("0x%08Xu" % w for w in words[8:]) + " },")
        c.append("  },")
    c.append("};")
    c.append("")
    c.append("const uint8_t g_sprite_art[NUM_SPRITES][64] = {")
    for name, p in sprites:
        c.append("    /* %s */ {" % name)
        for i in range(0, 64, 8):
            c.append("        " + ", ".join("0x%02X" % v for v in p[i:i + 8]) + ",")
        c.append("    },")
    c.append("};")
    c.append("")
    c.append("const uint8_t g_font[10][5] = {")
    for d in FONT:
        c.append("    { " + ", ".join(str(int(r.replace('#', '1').replace('.', '0'), 2)) for r in d) + " },")
    c.append("};")
    c.append("")
    open(out + "/tiles.c", "w").write("\n".join(c))
    print("tiles: %d, sprites: %d" % (len(tiles), len(sprites)))


if __name__ == "__main__":
    main()
