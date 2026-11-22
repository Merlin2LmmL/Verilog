#!/usr/bin/env python3
"""Build build/sim.html: a playable browser sim that runs the real rv32em
binary (build/game.bin, linked by `make elf`) on a small RV32IM interpreter
written in JavaScript, with the game's MMIO map (framebuffer, PRESENT, VSYNC,
KEYS_HELD).

usage: make_sim.py game.bin g_state_hex "off0 off1 ..." out.html
The offsets are offsetof() values in GameState for the rv32 ABI, in this
order: x xs y ys vx vxf vy vyf pstate cam freeze fc mode power level yh.
"""
import base64
import sys

TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scrap Garden on RV32EM</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;600&family=Silkscreen&display=swap" rel="stylesheet">
<style>
:root {
  /* one visual world: a dark electronics bench, amber from the robot's antenna */
  --bench: #121418;
  --panel: #1b1e24;
  --line: #2b3039;
  --ink: #e4e7ec;
  --mute: #8a93a3;
  --accent: #f0b429;
  --warn: #e5534b;
  --ok: #57b97a;
  --display: "Silkscreen", "IBM Plex Mono", monospace;
  --body: "IBM Plex Sans", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, monospace;
  /* layout: screen in a bezel on the left, CPU instruments on the right; stacks on phones */
  color-scheme: dark;
}
* { box-sizing: border-box; }
html, body { height: 100%; }
body { margin: 0; background: var(--bench); color: var(--ink); font: 15px/1.5 var(--body); }
.wrap { max-width: 1120px; margin: 0 auto; padding: 20px 16px 32px; display: grid; gap: 18px; }
header { display: flex; flex-wrap: wrap; align-items: baseline; gap: 6px 16px; }
h1 { font: 400 26px/1.1 var(--display); letter-spacing: 0.02em; margin: 0; color: var(--accent); text-wrap: balance; }
header p { margin: 0; color: var(--mute); max-width: 68ch; }
main { display: grid; grid-template-columns: minmax(0, 1fr) 320px; gap: 18px; align-items: start; }
@media (max-width: 860px) { main { grid-template-columns: 1fr; } }
.bezel { background: #0b0c0f; border: 1px solid var(--line); border-radius: 10px; padding: 14px; display: grid; gap: 10px; }
.screen { position: relative; outline: none; border-radius: 4px; }
.screen:focus-visible { box-shadow: 0 0 0 2px var(--accent); }
canvas#lcd { display: block; width: 100%; aspect-ratio: 4 / 3; image-rendering: pixelated; image-rendering: crisp-edges; background: #000; border-radius: 4px; }
.focushint { position: absolute; inset: auto 0 10px 0; margin: 0 auto; width: fit-content; padding: 4px 10px;
  background: rgba(11,12,15,0.85); border: 1px solid var(--line); border-radius: 999px; font: 12px var(--mono); color: var(--accent); }
.focushint[hidden] { display: none; }
.keys { display: flex; flex-wrap: wrap; gap: 6px 14px; font: 13px var(--mono); color: var(--mute); }
kbd { font: 12px var(--mono); color: var(--ink); background: var(--panel); border: 1px solid var(--line); border-bottom-width: 2px; border-radius: 4px; padding: 1px 6px; }
.pad { display: none; grid-template-columns: repeat(3, 52px) 1fr 76px 76px; grid-template-rows: 52px 52px; gap: 6px; user-select: none; touch-action: none; }
@media (pointer: coarse) { .pad { display: grid; } .keys { display: none; } }
.pad button { font: 600 14px var(--mono); }
.pad .up { grid-column: 2; grid-row: 1; } .pad .left { grid-column: 1; grid-row: 2; }
.pad .down { grid-column: 2; grid-row: 2; } .pad .right { grid-column: 3; grid-row: 2; }
.pad .run { grid-column: 5; grid-row: 1 / 3; } .pad .jump { grid-column: 6; grid-row: 1 / 3; color: var(--bench); background: var(--accent); }
aside { display: grid; gap: 14px; }
.card { background: var(--panel); border: 1px solid var(--line); border-radius: 10px; padding: 14px; display: grid; gap: 10px; }
.card h2 { margin: 0; font: 600 12px/1 var(--mono); letter-spacing: 0.08em; text-transform: uppercase; color: var(--mute); }
.big { font: 600 30px/1 var(--mono); font-variant-numeric: tabular-nums; }
.big small { font-size: 13px; color: var(--mute); font-weight: 400; }
.bar { height: 10px; background: var(--bench); border: 1px solid var(--line); border-radius: 999px; overflow: hidden; }
.bar > i { display: block; height: 100%; width: 0; background: var(--ok); }
.bar.hot > i { background: var(--warn); }
.stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; font: 13px var(--mono); font-variant-numeric: tabular-nums; }
.stats div { display: grid; } .stats span { color: var(--mute); font-size: 11px; }
canvas#spark { width: 100%; height: 56px; display: block; }
table { width: 100%; border-collapse: collapse; font: 13px var(--mono); font-variant-numeric: tabular-nums; }
td { padding: 3px 0; border-bottom: 1px solid var(--line); }
td:first-child { color: var(--mute); } td:last-child { text-align: right; }
.row { display: flex; flex-wrap: wrap; gap: 8px; }
button { font: 600 13px var(--mono); color: var(--ink); background: var(--bench); border: 1px solid var(--line); border-radius: 6px; padding: 7px 12px; cursor: pointer; }
button:hover { border-color: var(--mute); }
button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
button[aria-pressed="true"] { border-color: var(--accent); color: var(--accent); }
.note { margin: 0; color: var(--mute); font-size: 13px; max-width: 68ch; }
.err { color: var(--warn); font: 13px var(--mono); margin: 0; }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Scrap Garden</h1>
    <p>The real rv32em build of the clean-room platformer, running instruction by instruction on an RV32IM interpreter in this page: the same binary, framebuffer, VSYNC and key registers your CPU sees.</p>
  </header>
  <main>
    <section class="bezel" aria-label="Game screen">
      <div class="screen" id="screen" tabindex="0">
        <canvas id="lcd" width="128" height="96" aria-label="128 by 96 RGB332 framebuffer"></canvas>
        <div class="focushint" id="hint">Click the screen to play</div>
      </div>
      <div class="keys" aria-label="Keyboard controls">
        <span><kbd>&larr;</kbd> <kbd>&rarr;</kbd> walk</span>
        <span><kbd>&uarr;</kbd> or <kbd>X</kbd> run, fire, climb</span>
        <span><kbd>&darr;</kbd> crouch</span>
        <span><kbd>Space</kbd> or <kbd>Z</kbd> jump</span>
      </div>
      <div class="pad" aria-label="Touch controls">
        <button class="up" data-bit="1" aria-label="Up and run">&uarr;</button>
        <button class="left" data-bit="4" aria-label="Left">&larr;</button>
        <button class="down" data-bit="2" aria-label="Down">&darr;</button>
        <button class="right" data-bit="8" aria-label="Right">&rarr;</button>
        <button class="run" data-bit="1">RUN</button>
        <button class="jump" data-bit="16">JUMP</button>
      </div>
      <p class="note">Up is bit 0 of KEYS_HELD; the platform layer maps it to both Up and Run because the hardware has five keys for six buttons. Reach the checkered charging pad to clear a level.</p>
      <p class="err" id="err" hidden></p>
    </section>
    <aside>
      <section class="card" aria-label="Frame cost">
        <h2>Instructions per frame</h2>
        <div class="big" id="cost">0 <small>/ 41,000</small></div>
        <div class="bar" id="bar"><i></i></div>
        <canvas id="spark" width="584" height="112" aria-label="Last 240 frames"></canvas>
        <div class="stats">
          <div><span>average</span><b id="avg">0</b></div>
          <div><span>worst</span><b id="max">0</b></div>
          <div><span>frames</span><b id="frames">0</b></div>
        </div>
        <p class="note">Budget: 2.5 MHz at 60 fps, one instruction per cycle.</p>
      </section>
      <section class="card" aria-label="Player state">
        <h2>Player state in RAM</h2>
        <table>
          <tbody>
            <tr><td>X . Xsub/16</td><td id="sx">0</td></tr>
            <tr><td>Yh : Y . Ys</td><td id="sy">0</td></tr>
            <tr><td>Vx : Vxf</td><td id="svx">0</td></tr>
            <tr><td>Vy : Vyf</td><td id="svy">0</td></tr>
            <tr><td>pstate</td><td id="sst">0</td></tr>
            <tr><td>camera X</td><td id="scam">0</td></tr>
            <tr><td>freeze / frame</td><td id="sfr">0</td></tr>
            <tr><td>mode / power</td><td id="smode">0</td></tr>
          </tbody>
        </table>
      </section>
      <section class="card" aria-label="Run controls">
        <h2>Run</h2>
        <div class="row">
          <button id="pause" aria-pressed="false">Pause</button>
          <button id="step">Step 1 frame</button>
          <button id="reset">Power cycle</button>
        </div>
      </section>
    </aside>
  </main>
</div>
<script>
"use strict";
const IMAGE_B64 = "@@IMAGE@@";
const G_STATE = @@GSTATE@@;
const OFF = @@OFFS@@;
const BUDGET = 41000;

/* ---------- machine ---------- */
const RAM = new Uint8Array(1 << 20);
const R32 = new Uint32Array(RAM.buffer);
const FB = new Uint8Array(128 * 96);
const IMAGE = Uint8Array.from(atob(IMAGE_B64), c => c.charCodeAt(0));
const X = new Int32Array(32);
let pc = 0, vsync = 0, keys = 0, presented = false;

function powerOn() {
  RAM.fill(0); RAM.set(IMAGE, 0); FB.fill(0); X.fill(0);
  pc = 0; vsync = 0; presented = false;
}

function load(a, n, signed) {
  a >>>= 0;
  if (a >= 0xFFFD0000) {
    if (a < 0xFFFD0000 + 12288) {
      const o = a - 0xFFFD0000;
      let v = FB[o]; if (n > 1) v |= FB[o + 1] << 8; if (n > 2) v |= FB[o + 2] << 16 | FB[o + 3] << 24;
      return v | 0;
    }
    if (a === 0xFFFF0024) return vsync | 0;
    if (a === 0xFFFF0028) return keys;
    return 0;
  }
  if (a + n > RAM.length) throw new Error("load outside RAM at 0x" + a.toString(16));
  if (n === 4) return (a & 3) ? (RAM[a] | RAM[a + 1] << 8 | RAM[a + 2] << 16 | RAM[a + 3] << 24) : R32[a >>> 2] | 0;
  if (n === 2) { const v = RAM[a] | RAM[a + 1] << 8; return signed ? (v << 16) >> 16 : v; }
  const v = RAM[a]; return signed ? (v << 24) >> 24 : v;
}

function store(a, v, n) {
  a >>>= 0;
  if (a >= 0xFFFD0000) {
    if (a < 0xFFFD0000 + 12288) {
      const o = a - 0xFFFD0000;
      FB[o] = v; if (n > 1) FB[o + 1] = v >> 8; if (n > 2) { FB[o + 2] = v >> 16; FB[o + 3] = v >> 24; }
    } else if (a === 0xFFFF0020) presented = true;
    return;
  }
  if (a + n > RAM.length) throw new Error("store outside RAM at 0x" + a.toString(16));
  if (n === 4 && !(a & 3)) { R32[a >>> 2] = v; return; }
  RAM[a] = v; if (n > 1) RAM[a + 1] = v >> 8; if (n > 2) { RAM[a + 2] = v >> 16; RAM[a + 3] = v >> 24; }
}

function mulh(a, b) { return Number(BigInt.asIntN(32, (BigInt(a) * BigInt(b)) >> 32n)); }

/* run until the program writes PRESENT; returns instructions executed */
function runFrame() {
  let n = 0;
  presented = false;
  while (!presented) {
    if (++n > 3000000) throw new Error("no PRESENT within 3M instructions (pc 0x" + pc.toString(16) + ")");
    const ins = R32[pc >>> 2] | 0;
    const op = ins & 0x7f, rd = (ins >>> 7) & 31, f3 = (ins >>> 12) & 7;
    const rs1 = (ins >>> 15) & 31, rs2 = (ins >>> 20) & 31, f7 = ins >>> 25;
    let npc = (pc + 4) | 0, v = 0, w = true;
    switch (op) {
      case 0x37: v = ins & 0xFFFFF000; break;
      case 0x17: v = (pc + (ins & 0xFFFFF000)) | 0; break;
      case 0x6F: {
        const imm = ((ins >> 31) << 20) | (((ins >>> 12) & 0xff) << 12) | (((ins >>> 20) & 1) << 11) | (((ins >>> 21) & 0x3ff) << 1);
        v = npc; npc = (pc + imm) | 0; break;
      }
      case 0x67: v = npc; npc = (X[rs1] + (ins >> 20)) & ~1; break;
      case 0x63: {
        const imm = ((ins >> 31) << 12) | (((ins >>> 7) & 1) << 11) | (((ins >>> 25) & 0x3f) << 5) | (((ins >>> 8) & 0xf) << 1);
        const a = X[rs1], b = X[rs2]; let t;
        switch (f3) {
          case 0: t = a === b; break; case 1: t = a !== b; break;
          case 4: t = a < b; break;   case 5: t = a >= b; break;
          case 6: t = (a >>> 0) < (b >>> 0); break; case 7: t = (a >>> 0) >= (b >>> 0); break;
          default: throw new Error("bad branch at 0x" + pc.toString(16));
        }
        if (t) npc = (pc + imm) | 0;
        w = false; break;
      }
      case 0x03: {
        const a = X[rs1] + (ins >> 20);
        switch (f3) {
          case 0: v = load(a, 1, true); break; case 1: v = load(a, 2, true); break;
          case 2: v = load(a, 4, true); break; case 4: v = load(a, 1, false); break;
          case 5: v = load(a, 2, false); break; default: throw new Error("bad load at 0x" + pc.toString(16));
        }
        break;
      }
      case 0x23: store(X[rs1] + (((ins >> 25) << 5) | ((ins >>> 7) & 31)), X[rs2], f3 === 0 ? 1 : f3 === 1 ? 2 : 4); w = false; break;
      case 0x13: {
        const a = X[rs1], imm = ins >> 20, sh = rs2;
        switch (f3) {
          case 0: v = a + imm; break; case 2: v = a < imm ? 1 : 0; break;
          case 3: v = (a >>> 0) < (imm >>> 0) ? 1 : 0; break; case 4: v = a ^ imm; break;
          case 6: v = a | imm; break; case 7: v = a & imm; break;
          case 1: v = a << sh; break; default: v = (f7 & 0x20) ? a >> sh : a >>> sh; break;
        }
        break;
      }
      case 0x33: {
        const a = X[rs1], b = X[rs2];
        if (f7 === 1) {
          switch (f3) {
            case 0: v = Math.imul(a, b); break;
            case 1: v = mulh(a, b); break;
            case 2: v = mulh(a, b >>> 0); break;
            case 3: v = mulh(a >>> 0, b >>> 0); break;
            case 4: v = b === 0 ? -1 : (a === -2147483648 && b === -1 ? a : (a / b) | 0); break;
            case 5: v = b === 0 ? -1 : ((a >>> 0) / (b >>> 0)) | 0; break;
            case 6: v = b === 0 ? a : (a === -2147483648 && b === -1 ? 0 : a % b); break;
            default: v = b === 0 ? a : ((a >>> 0) % (b >>> 0)) | 0; break;
          }
        } else {
          switch (f3) {
            case 0: v = (f7 & 0x20) ? a - b : a + b; break; case 1: v = a << (b & 31); break;
            case 2: v = a < b ? 1 : 0; break; case 3: v = (a >>> 0) < (b >>> 0) ? 1 : 0; break;
            case 4: v = a ^ b; break; case 5: v = (f7 & 0x20) ? a >> (b & 31) : a >>> (b & 31); break;
            case 6: v = a | b; break; default: v = a & b; break;
          }
        }
        break;
      }
      case 0x0F: w = false; break;
      default: throw new Error("illegal instruction 0x" + (ins >>> 0).toString(16) + " at 0x" + pc.toString(16));
    }
    if (w && rd) X[rd] = v;
    pc = npc;
  }
  return n;
}

/* ---------- display ---------- */
const lcd = document.getElementById("lcd").getContext("2d");
const img = lcd.createImageData(128, 96);
const px32 = new Uint32Array(img.data.buffer);
const LUT = new Uint32Array(256);
for (let c = 0; c < 256; c++) {
  const r = Math.round(((c >> 5) & 7) * 255 / 7), g = Math.round(((c >> 2) & 7) * 255 / 7), b = Math.round((c & 3) * 255 / 3);
  LUT[c] = 0xFF000000 | b << 16 | g << 8 | r;
}
function blit() { for (let i = 0; i < FB.length; i++) px32[i] = LUT[FB[i]]; lcd.putImageData(img, 0, 0); }

/* ---------- instruments ---------- */
const $ = id => document.getElementById(id);
const hist = new Float32Array(240); let histPos = 0, frames = 0, total = 0, worst = 0;
const spark = $("spark").getContext("2d");
const fmt = n => n.toLocaleString("en-US");
function u8(o) { return RAM[G_STATE + o]; }
function s8(o) { return (RAM[G_STATE + o] << 24) >> 24; }
function u16(o) { return RAM[G_STATE + o] | RAM[G_STATE + o + 1] << 8; }
const MODES = ["normal", "grow", "fire-up", "injury", "dying", "clear"];
const PST = ["0 ground", "1 rising", "2 falling", "3 climbing"];

function instruments(n) {
  $("cost").firstChild.nodeValue = fmt(n) + " ";
  const pct = Math.min(100, n / BUDGET * 100);
  $("bar").firstElementChild.style.width = pct + "%";
  $("bar").classList.toggle("hot", n > BUDGET);
  $("avg").textContent = fmt(Math.round(total / Math.max(1, frames)));
  $("max").textContent = fmt(worst);
  $("frames").textContent = fmt(frames);
  const [ox, oxs, oy, oys, ovx, ovxf, ovy, ovyf, ost, ocam, ofr, ofc, omode, opow, , oyh] = OFF;
  $("sx").textContent = u16(ox) + " . " + (u8(oxs) >> 4);
  $("sy").textContent = u8(oyh) + " : " + u8(oy) + " . " + u8(oys);
  $("svx").textContent = s8(ovx) + " : " + u8(ovxf);
  $("svy").textContent = s8(ovy) + " : " + u8(ovyf);
  $("sst").textContent = PST[u8(ost)] || u8(ost);
  $("scam").textContent = u16(ocam);
  $("sfr").textContent = u8(ofr) + " / " + u8(ofc);
  $("smode").textContent = (MODES[u8(omode)] || u8(omode)) + " / " + ["small", "big", "fire"][u8(opow)];
  drawSpark();
}

function drawSpark() {
  const W = 584, H = 112, c = spark;
  c.clearRect(0, 0, W, H);
  const y = v => H - 4 - (Math.min(v, 50000) / 50000) * (H - 8);
  c.strokeStyle = "#2b3039"; c.lineWidth = 1;
  for (const g of [10000, 20000, 30000]) { c.beginPath(); c.moveTo(0, y(g)); c.lineTo(W, y(g)); c.stroke(); }
  c.strokeStyle = "#e5534b"; c.setLineDash([6, 6]); c.beginPath(); c.moveTo(0, y(BUDGET)); c.lineTo(W, y(BUDGET)); c.stroke(); c.setLineDash([]);
  c.fillStyle = "#8a93a3"; c.font = "18px IBM Plex Mono, monospace"; c.fillText("budget 41k", 6, y(BUDGET) - 6);
  c.beginPath();
  for (let i = 0; i < 240; i++) {
    const v = hist[(histPos + i) % 240], xx = i * (W / 239);
    if (i === 0) c.moveTo(xx, y(v)); else c.lineTo(xx, y(v));
  }
  c.lineTo(W, H); c.lineTo(0, H); c.closePath();
  c.fillStyle = "rgba(240,180,41,0.18)"; c.fill();
  c.beginPath();
  for (let i = 0; i < 240; i++) {
    const v = hist[(histPos + i) % 240], xx = i * (W / 239);
    if (i === 0) c.moveTo(xx, y(v)); else c.lineTo(xx, y(v));
  }
  c.strokeStyle = "#f0b429"; c.lineWidth = 2; c.stroke();
}

/* ---------- frame loop ---------- */
let paused = false, failed = false, last = 0, acc = 0;
function oneFrame() {
  vsync = (vsync + 1) | 0;              /* releases the program's VSYNC wait */
  const n = runFrame();
  frames++; total += n; if (frames > 1 && n > worst) worst = n;
  hist[histPos] = n; histPos = (histPos + 1) % 240;
  return n;
}
function tick(t) {
  requestAnimationFrame(tick);
  if (failed) return;
  if (!last) last = t;
  acc += Math.min(100, t - last); last = t;
  if (paused) { acc = 0; return; }
  let n = -1, k = 0;
  try {
    while (acc >= 1000 / 60 && k < 3) { n = oneFrame(); acc -= 1000 / 60; k++; }
  } catch (e) { fail(e); return; }
  if (k === 3) acc = 0;
  if (n >= 0) { blit(); instruments(n); }
}
function fail(e) { failed = true; const el = $("err"); el.hidden = false; el.textContent = "CPU stopped: " + e.message; }

/* ---------- input ---------- */
const KEYMAP = { ArrowUp: 1, KeyX: 1, ArrowDown: 2, ArrowLeft: 4, ArrowRight: 8, Space: 16, KeyZ: 16 };
const screenEl = $("screen");
const held = new Set();
function recompute() { keys = 0; for (const b of held) keys |= b; }
window.addEventListener("keydown", e => {
  const b = KEYMAP[e.code]; if (b === undefined) return;
  if (document.activeElement && document.activeElement.tagName === "BUTTON" && e.code === "Space") return;
  e.preventDefault(); held.add(b); recompute();
});
window.addEventListener("keyup", e => { const b = KEYMAP[e.code]; if (b === undefined) return; held.delete(b); recompute(); });
window.addEventListener("blur", () => { held.clear(); padHeld.clear(); keys = 0; });
function showHint() { $("hint").hidden = document.activeElement === screenEl; }
screenEl.addEventListener("focus", showHint); screenEl.addEventListener("blur", showHint);
screenEl.addEventListener("pointerdown", () => screenEl.focus());

const padHeld = new Map();
for (const btn of document.querySelectorAll(".pad button")) {
  const bit = Number(btn.dataset.bit);
  btn.addEventListener("pointerdown", e => { e.preventDefault(); btn.setPointerCapture(e.pointerId); padHeld.set(e.pointerId, bit); padKeys(); });
  const up = e => { padHeld.delete(e.pointerId); padKeys(); };
  btn.addEventListener("pointerup", up); btn.addEventListener("pointercancel", up);
}
function padKeys() { recompute(); for (const b of padHeld.values()) keys |= b; }

$("pause").addEventListener("click", () => { paused = !paused; $("pause").setAttribute("aria-pressed", String(paused)); $("pause").textContent = paused ? "Resume" : "Pause"; screenEl.focus(); });
$("step").addEventListener("click", () => {
  if (failed) return;
  paused = true; $("pause").setAttribute("aria-pressed", "true"); $("pause").textContent = "Resume";
  try { const n = oneFrame(); blit(); instruments(n); } catch (e) { fail(e); }
});
$("reset").addEventListener("click", () => {
  powerOn(); failed = false; $("err").hidden = true;
  frames = 0; total = 0; worst = 0; hist.fill(0); screenEl.focus();
});

/* power on and show the first frame at once */
powerOn();
try { const n = oneFrame(); blit(); instruments(n); } catch (e) { fail(e); }
showHint();
requestAnimationFrame(tick);
</script>
</body>
</html>
"""


def main():
    img, gstate, offs, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    data = open(img, "rb").read()
    html = (TEMPLATE.replace("@@IMAGE@@", base64.b64encode(data).decode())
            .replace("@@GSTATE@@", "0x" + gstate.lower().lstrip("0x").rjust(1, "0"))
            .replace("@@OFFS@@", "[" + ", ".join(offs.split()) + "]"))
    open(out, "w").write(html)
    print("wrote %s (%d bytes, image %d bytes)" % (out, len(html), len(data)))


if __name__ == "__main__":
    main()
