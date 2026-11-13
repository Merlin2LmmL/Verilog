// CPU Playground: hex editor, run/step controls and the data path diagram.
// The CPU itself is in emu.js.
(function () {
  'use strict';

  const E = CPU32;
  const { hex8, regName, disasm, decode, u32 } = E;

  const COLORS = { p1: '#1565c0', p2: '#e65100', imm: '#6a1b9a', wb: '#2e7d32', pc: '#444', off: '#c8c8c8' };

  const EXAMPLES = [
    {
      name: 'Add and multiply',
      text: `; Adds 5 and 7, then multiplies the sum by 7.
; Step through it and watch r1 to r4 fill up.

11100005   ; addi r1, r0, 5
11200007   ; addi r2, r0, 7
01312000   ; add  r3, r1, r2      r3 = 12
20432000   ; mul  r4, r3, r2      r4 = 84
ff000000   ; halt`,
      data: '',
    },
    {
      name: 'Sum of 1 to 10',
      text: `; Adds up the numbers from 1 to 10 in a loop and
; stores the result, 55, at address 0.

11100000   ; addi r1, r0, 0     sum = 0
11200001   ; addi r2, r0, 1     i = 1
1130000a   ; addi r3, r0, 10    last = 10
01112000   ; loop: add r1, r1, r2    sum += i
11220001   ; addi r2, r2, 1     i++
4332fffe   ; bge  r3, r2, loop  while last >= i
38100000   ; st   r1, [r0+0]    save the sum in memory
ff000000   ; halt`,
      data: '',
    },
    {
      name: 'Fibonacci',
      text: `; Prints the first 20 Fibonacci numbers to the console.
; Assembled from programs/fib.asm.

1fa0ffff
11100000
11200001
11300014
381a0004
1140000a
384a0000
01412000
01120000
01240000
1133ffff
4130fff9
ff000000`,
      data: '',
    },
    {
      name: 'Hello World',
      text: `; Prints "Hello, World!" with a function that prints a string.
; The string is in the data memory field below.
; Assembled from programs/hello.asm.

1fe00004
1f100000
14110000
50f00002
ff000000
1f60ffff
32510000
40500004
38560000
11110001
500ffffc
510f0000`,
      data: `6c6c6548
57202c6f
646c726f
00000a21`,
    },
    {
      name: 'Every kind of instruction',
      text: `; Uses each kind of instruction once: lui, ori, addi,
; a word and a byte store and load, a branch and a jal.

1f100001   ; lui  r1, 1          r1 = 0x00010000
14110234   ; ori  r1, r1, 0x234  r1 = 0x00010234
11200004   ; addi r2, r0, 4
38120000   ; st   r1, [r2+0]     memory[4] = r1
30320000   ; ld   r3, [r2+0]     r3 = memory[4]
39120008   ; stb  r1, [r2+8]     one byte
32420008   ; ldbu r4, [r2+8]
4113fffe   ; bne  r1, r3, -2     not taken
50f00002   ; jal  lr, +2         lr = return address
11500063   ; addi r5, r0, 99     the jal skips this one
ff000000   ; halt`,
      data: '',
    },
    {
      name: 'Bouncing square',
      text: `; Draws a color gradient and all 256 colors on the screen,
; then bounces a yellow square around for 5 seconds.
; Assembled from programs/pixels.asm.

1fe00004
11b00000
011b0000
50f0005c
1f500101
14550101
20115000
165b0007
1f60fffd
01556000
11650080
38150000
11550004
4156fffe
11bb0001
11500058
41b5fff2
115bffa8
17550002
16550007
1f600101
14660101
20756000
1f600302
14660100
01776000
1f800404
14880404
165b0007
1f60fffd
01556000
11650080
38750000
01778000
11550004
4156fffd
11bb0001
11500060
41b5ffeb
11a00014
11b0000a
11c00002
11d00001
1150012c
11eefffc
385e0000
011a0000
012b0000
1130ffff
50f00019
01aac000
430a0003
11500076
42a50002
02c0c000
01bbd000
430b0003
1150004e
42b50002
02d0d000
011a0000
012b0000
113000fc
50f0000b
1f50ffff
38050020
30650024
30750024
4076ffff
305e0000
1155ffff
385e0000
4150ffe6
ff000000
11eefffc
38fe0000
01410000
1192000a
01130000
43300003
01120000
50f0000e
16720007
01774000
1f80fffd
01778000
1187000a
39170000
11770001
4178fffe
11220001
4129fff3
30fe0000
11ee0004
510f0000
17510005
17610004
16660005
14660004
11100003
02115000
04116000
510f0000`,
      data: '',
      speed: '2500000',
    },
    {
      name: 'Drawing with the keyboard',
      text: `; A small drawing program. Press Run, click the screen and
; move the pen with the arrow keys or WASD. Space changes the
; color, c clears the screen and q quits.
; Assembled from programs/draw.asm.

1fe00004
1fd0ffff
11a00040
11b00030
11c00000
50f0005a
50f00041
1f100000
14110007
50f0005d
305d0008
4050ffff
305d000c
11eefffc
385e0000
011a0000
012b0000
50f00040
50f00044
305e0000
11ee0004
11600080
40560016
11600077
40560014
11600081
40560016
11600073
40560014
11600082
40560017
11600061
40560015
11600083
40560017
11600064
40560015
11600020
40560018
11600063
4056001b
11600071
4056001c
50000019
11bbfffe
43b00017
11bb0002
50000015
11bb0002
1160005e
436b0012
11bbfffe
50000010
11aafffe
43a0000e
11aa0002
5000000c
11aa0002
1160007e
436a0009
11aafffe
50000007
11cc0001
11600007
42c60004
11c00000
50000002
50f0001c
50f00003
500fffc5
ff000000
11eefffc
38fe0000
011a0000
012b0000
113000ff
50f0000a
380d0020
30fe0000
11ee0004
510f0000
1f600000
14660000
0166c000
32360000
510f0000
16620007
01661000
1f70fffd
01667000
39360000
39360001
39360080
39360081
510f0000
1f60fffd
1f70fffd
14773000
38060000
11660004
4167fffe
510f0000
32610000
40600004
386d0000
11110001
500ffffc
510f0000`,
      data: `1cfcf4e0
61e3031f
776f7272
726f2073
53415720
6d203a44
2c65766f
61707320
203a6563
6f6c6f63
63202c72
6c63203a
2c726165
203a7120
74697571
0000000a`,
      speed: '2500000',
    },
    {
      name: 'Video',
      text: `; Plays a 26 second black-and-white video at 12 frames per second.
; The video is compressed in data memory: every frame only stores
; which pixels flip between black and white. tools/video.py makes
; the data from any video. Assembled from programs/video.asm.

1fe00004
1fd0ffff
1fa00000
14aa0000
30ca0000
305a0004
11eefffc
385e0000
11aa0008
305d0024
11eefffc
385e0000
1fb0fffd
50f00026
01bb1000
50f00024
40100018
015b1000
1190ffff
40b5fffa
136b0003
40600006
326b0000
156600ff
396b0000
11bb0001
500ffff9
1175fffc
447b0006
306b0000
05669000
386b0000
11bb0004
500ffffb
40b5ffeb
326b0000
156600ff
396b0000
11bb0001
500ffffb
380d0020
305e0000
306e0004
01556000
307d0024
02875000
4280fffe
385e0000
11ccffff
41c0ffdb
ff000000
11100000
11700000
326a0000
11aa0001
1386007f
06887000
04118000
11770007
13660080
4160fff9
510f0000`,
      dataScript: 'video-data.js',      // 89 KB, only loaded when this example is picked
      dataVar: 'CPU_VIDEO_DATA',
      speed: '2500000',
    },
  ];

  const $ = (id) => document.getElementById(id);
  const SVGNS = 'http://www.w3.org/2000/svg';

  const m = new E.Machine();
  let consoleText = '';
  let words = [];            // parsed program
  let timer = null;          // running?
  let lastTrace = null;
  const MAX_CYCLES = 20000000;

  m.onOutput = (s) => { consoleText += s; };

  // ---------- helpers ----------
  function el(tag, attrs, text) {
    const e = document.createElementNS(SVGNS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  }

  function fmt(v) {                       // small numbers as signed decimal, big ones as hex
    v = u32(v);
    const s = v | 0;
    return Math.abs(s) < 10000 ? String(s) : '0x' + v.toString(16).toUpperCase();
  }
  function fmtBoth(v) {
    v = u32(v);
    const s = v | 0;
    return Math.abs(s) < 10000 ? String(s) : '0x' + v.toString(16).toUpperCase() + ' (' + s + ')';
  }
  function html(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // ---------- program ----------
  function loadFromText() {
    stop();
    const prog = E.parseHex($('hex').value);
    const data = E.parseHex($('datahex').value);
    const errs = prog.errors.map((e) => `program line ${e.line + 1}: ${e.message}`)
      .concat(data.errors.map((e) => `data line ${e.line + 1}: ${e.message}`));
    if (prog.words.length > E.IMEM_WORDS) errs.push(`only the first ${E.IMEM_WORDS} instructions fit in instruction memory`);
    $('errors').innerHTML = errs.map((e) => `<div>${html(e)}</div>`).join('');
    words = prog.words.map((w) => w.value);
    m.loadProgram(words, data.words.map((w) => w.value));
    consoleText = '';
    autoOpened = false;
    buildListing();
    try { localStorage.setItem('cpu-playground', JSON.stringify({ text: $('hex').value, data: $('datahex').value })); } catch (e) { /* private window */ }
    refresh();
  }

  function resetMachine() {
    stop();
    m.reset();
    consoleText = '';
    autoOpened = false;
    refresh();
  }

  function buildListing() {
    const tb = $('listing');
    tb.innerHTML = '';
    words.forEach((w, i) => {
      const tr = document.createElement('tr');
      tr.id = 'row' + i;
      const addr = i * 4;
      tr.innerHTML = `<td>${hex8(addr).slice(4)}</td><td>${hex8(w)}</td><td>${html(disasm(w, addr))}</td>`;
      tb.appendChild(tr);
    });
  }

  // ---------- running ----------
  function doStep() {
    if (m.halted) return;
    lastTrace = m.step();
    refresh();
  }

  function stop() {
    if (timer !== null) { clearTimeout(timer); cancelAnimationFrame(timer); timer = null; }
    $('run').textContent = 'Run';
  }

  function toggleRun() {
    if (timer !== null) { stop(); refresh(); return; }
    if (m.halted) return;
    $('run').textContent = 'Pause';
    const perSecond = Number($('speed').value);
    const realTime = perSecond === E.CLOCK_HZ;
    const batched = perSecond === 0 || realTime;     // many instructions per animation frame
    let lastTs = null, owed = 0;
    const tick = (ts) => {
      if (m.halted) { stop(); refresh(); return; }
      if (batched) {
        // Run for at most 12 ms per animation frame, so the page stays smooth.
        // Real time is locked to the monitor like a game console: every animation frame runs
        // the CPU up to exactly the start of a screen refresh (VSYNC), so a program that draws
        // one frame per refresh shows every frame once, without stutter. On a 60 Hz monitor
        // that is one refresh per animation frame; other monitors get as many as the time says.
        let goal = Infinity;
        if (realTime) {
          const dt = lastTs === null ? 1000 / 60 : ts - lastTs;
          lastTs = ts;
          let refreshes;
          if (Math.abs(dt - 1000 / 60) < 2) refreshes = 1;
          else { owed += dt * 60 / 1000; refreshes = Math.min(4, Math.floor(owed)); owed -= Math.floor(owed); }
          goal = m.cycles + refreshes * E.CYCLES_PER_REFRESH - m.refreshCycles;   // next refresh boundary
          if (refreshes === 0) goal = m.cycles;
        }
        const end = performance.now() + 12;
        const endless = () => m.frames > 0 || m.readsKeys;
        do {
          for (let i = 0; i < 2000 && !m.halted && m.cycles < goal; i++) lastTrace = m.step();
        } while (!m.halted && m.cycles < goal && performance.now() < end && (endless() || m.cycles < MAX_CYCLES));
        if (m.cycles >= MAX_CYCLES && !endless() && !m.halted) {
          stop();
          consoleText += `\n--- stopped after ${m.cycles} cycles, the program is still running ---\n`;
        }
        refresh();
        if (timer !== null) timer = requestAnimationFrame(tick);
      } else {
        lastTrace = m.step();
        refresh();
        if (timer !== null) timer = setTimeout(tick, 1000 / perSecond);
      }
    };
    timer = batched ? requestAnimationFrame(tick) : setTimeout(tick, 0);
    refresh();
  }

  // ---------- view ----------
  function refresh() {
    const t = m.peek();
    renderStatus();
    renderFields(t);
    renderExplain(t);
    renderDiagram(t);
    renderListing();
    renderBottom();
    renderScreen();
    $('step').disabled = m.halted;
    $('run').disabled = m.halted && timer === null;
  }

  function renderStatus() {
    let state = 'ready', cls = '';
    if (m.trapped) { state = 'stopped: illegal instruction'; cls = 'trapped'; }
    else if (m.halted) { state = 'halted'; cls = 'halted'; }
    else if (timer !== null) state = 'running';
    else if (m.cycles > 0) state = 'paused';
    $('status').innerHTML =
      `<span>PC <b>${hex8(m.pc)}</b></span><span>cycles <b>${m.cycles}</b></span>` +
      `<span class="state ${cls}">${state}</span>` +
      (m.warnings.length ? `<span style="color:#b00020">${html(m.warnings[m.warnings.length - 1])}</span>` : '');
  }

  function renderFields(t) {
    const d = t.d;
    const hx = hex8(d.instr);
    const box = (digits, color, name, role) =>
      `<div class="field" style="--c:${color}"><div class="digits">${digits.split('').map((c) => `<span>${c}</span>`).join('')}</div>` +
      `<div class="name">${name}</div><div class="role">${role}</div></div>`;
    let out = `<div id="asm">${html(m.halted && !m.trapped ? 'halt' : disasm(d.instr, t.pc))}<small>next instruction at ${hex8(t.pc)}</small></div>`;
    out += box(hx.slice(0, 2), '#555', 'opcode', d.illegal ? 'illegal' : d.name);
    if (d.kind === 'JAL') {
      out += box(hx[2], COLORS.wb, 'A', 'rd = PC+4') + box(hx.slice(3), COLORS.imm, 'imm20', 'jump offset');
    } else if (d.kind === 'HALT' || d.illegal) {
      out += box(hx.slice(2), '#999', '', 'unused');
    } else {
      // A
      let aRole = 'rd, result', aColor = COLORS.wb;
      if (d.kind === 'STORE') { aRole = 'data to store'; aColor = COLORS.p2; }
      if (d.kind === 'BRANCH') { aRole = 'ra, port 2'; aColor = COLORS.p2; }
      out += box(hx[2], aColor, 'A', aRole);
      // B
      if (d.kind === 'LUI') out += box(hx[3], '#999', 'B', 'unused');
      else out += box(hx[3], COLORS.p1, 'B', d.kind === 'LOAD' || d.kind === 'STORE' || d.kind === 'JALR' ? 'base, port 1' : 'port 1');
      // C or imm
      if (d.kind === 'R') out += box(hx[4], COLORS.p2, 'C', 'port 2') + box(hx.slice(5), '#999', '', 'unused');
      else out += box(hx.slice(4), COLORS.imm, 'imm16', 'immediate');
    }
    $('fields').innerHTML = out;
  }

  function renderExplain(t) {
    const d = t.d;
    const L = [];
    const rn = regName;
    const p1 = (x) => `<b class="p1">${x}</b>`, p2 = (x) => `<b class="p2">${x}</b>`;
    const im = (x) => `<b class="imm">${x}</b>`, wb = (x) => `<b class="wb">${x}</b>`;
    if (d.illegal) {
      L.push(`<b>${hex8(d.instr)}</b> is not an instruction, there is no opcode ${hex8(d.instr).slice(0, 2)}. The CPU stops here.`);
    } else if (d.halt) {
      L.push('<b>halt</b> stops the CPU.');
    } else {
      const sym = E.ALU_SYMBOLS[d.aluOp];
      const dest = wb(rn(d.rd));
      switch (d.kind) {
        case 'R':
          L.push(`${dest} = ${p1(rn(d.rs1))} ${sym} ${p2(rn(d.rs2))}`);
          L.push(`${wb(fmt(t.aluY))} = ${p1(fmt(t.aluA))} ${sym} ${p2(fmt(t.aluB))}`);
          break;
        case 'I':
          L.push(`${dest} = ${p1(rn(d.rs1))} ${sym} ${im(fmt(d.imm))}`);
          L.push(`${wb(fmt(t.aluY))} = ${p1(fmt(t.aluA))} ${sym} ${im(fmt(d.imm))}`);
          break;
        case 'LUI':
          L.push(`${dest} = ${im(fmt(d.imm))}, the immediate shifted left by 16`);
          break;
        case 'LOAD':
          L.push(`${dest} = memory[${p1(rn(d.rs1))} + ${im(fmt(d.imm))}], ${d.memByte ? (d.memSigned ? 'one byte, sign-extended' : 'one byte, zero-extended') : 'one word'}`);
          L.push(`address ${p1(fmt(t.aluA))} + ${im(fmt(d.imm))} = ${hex8(t.aluY)}, it holds ${wb(fmt(t.loadValue))}`);
          break;
        case 'STORE':
          L.push(`memory[${p1(rn(d.rs1))} + ${im(fmt(d.imm))}] = ${p2(rn(d.rs2))}, ${d.memByte ? 'only the low byte' : 'one word'}`);
          L.push(`address ${p1(fmt(t.aluA))} + ${im(fmt(d.imm))} = ${hex8(t.aluY)}, stores ${p2(fmt(t.memData))}`);
          if (t.aluY >= E.FB_BASE && t.aluY < E.FB_BASE + E.FB_W * E.FB_H) {
            const n = t.aluY - E.FB_BASE;
            const where = `x = ${n % E.FB_W}, y = ${Math.floor(n / E.FB_W)}`;
            L.push(d.memByte ? `That's the pixel at ${where} on the screen. It shows up after the next FB_SHOW.`
                             : `Those are 4 pixels from ${where} on the screen. They show up after the next FB_SHOW.`);
          } else if (t.aluY === 0xFFFF0020) {
            L.push('That\'s FB_SHOW, so the screen now shows everything drawn so far.');
          }
          break;
        case 'BRANCH': {
          const cmp = { beq: '==', bne: '!=', blt: '<', bge: '>=', bltu: '<u', bgeu: '>=u' }[d.name];
          L.push(`if ${p2(rn(d.rs2))} ${cmp} ${p1(rn(d.rs1))} then PC = PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)}`);
          L.push(`${p2(fmt(t.p2))} ${cmp} ${p1(fmt(t.p1))} is <b>${t.taken ? 'true: jump to ' + hex8(t.nextPc) : 'false: continue with ' + hex8(t.nextPc)}</b>`);
          break;
        }
        case 'JAL':
          L.push(`${dest} = PC + 4 = ${hex8(t.pc4)}, then PC = PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)} = ${hex8(t.nextPc)}`);
          break;
        case 'JALR':
          L.push(`${dest} = PC + 4 = ${hex8(t.pc4)}, then PC = ${p1(rn(d.rs1))} + ${im(fmt(d.imm))} = ${hex8(t.nextPc)}`);
          break;
      }
      if (d.regWrite && d.rd === 0) L.push('r0 is always 0, so the result gets thrown away.');
    }
    $('explain').innerHTML = L.map((l) => `<div class="line">${l}</div>`).join('') +
      (words.length === 0 ? '<div class="line">Type some hex on the left, or pick an example.</div>' : '');
  }

  function renderListing() {
    const idx = m.pc >>> 2;
    for (const tr of $('listing').children) tr.className = '';
    for (let i = 0; i < Math.min(idx, words.length); i++) {
      // only color rows when we've actually moved, not for the initial state
      if (m.cycles > 0) $('row' + i).className = 'past';
    }
    const cur = $('row' + idx);
    if (cur) {
      cur.className = 'cur';
      const wrap = $('listing-wrap');
      const top = cur.offsetTop, bottom = top + cur.offsetHeight;
      if (top < wrap.scrollTop + 24) wrap.scrollTop = Math.max(0, top - 24);
      else if (bottom > wrap.scrollTop + wrap.clientHeight) wrap.scrollTop = bottom - wrap.clientHeight + 4;
    }
  }

  function renderBottom() {
    const c = $('console');
    c.textContent = consoleText;
    c.scrollTop = c.scrollHeight;
    const keys = [...m.touched].sort((a, b) => a - b);
    let s = '';
    for (const k of keys.slice(0, 64)) {
      const a = k * 4;
      const v = m.readWord(a);
      const line = `${hex8(a)}: ${hex8(v)}  ${fmt(v)}`;
      s += (k === m.lastStore ? `<span class="last">${line}</span>` : line) + '\n';
    }
    if (keys.length > 64) s += `... and ${keys.length - 64} more\n`;
    $('mem').innerHTML = s || 'Nothing written yet';
    if (m.leds) $('mem').innerHTML += `\nLEDs: ${hex8(m.leds)}`;
  }

  // ---------- pixel screen ----------
  // The canvas is 128 x 96 real pixels, CSS scales it up. A lookup table turns each
  // RGB332 byte into 4 RGBA bytes at once, and the canvas is only drawn again when the
  // program has shown a new frame, at most once per animation frame (refresh).
  const screenCtx = $('screen').getContext('2d');
  const screenImage = screenCtx.createImageData(E.FB_W, E.FB_H);
  const screenPixels = new Uint32Array(screenImage.data.buffer);
  const paletteBytes = new Uint8Array(256 * 4);
  for (let c = 0; c < 256; c++) paletteBytes.set([...E.rgb332(c), 255], c * 4);
  const PALETTE = new Uint32Array(paletteBytes.buffer);  // same byte order as screenPixels
  let drawnFrames = -1;
  let autoOpened = false;      // opened the screen for this run already
  let screenInfo = '';

  function renderScreen() {
    if (!autoOpened && (m.frames > 0 || m.readsKeys)) { $('screen-details').open = true; autoOpened = true; }
    if (m.frames !== drawnFrames) {
      const src = m.fbShown;
      for (let i = 0; i < src.length; i++) screenPixels[i] = PALETTE[src[i]];
      screenCtx.putImageData(screenImage, 0, 0);
      drawnFrames = m.frames;
    }
    let info = m.frames ? `Frame ${m.frames}` : 'Empty. Programs draw at 0xFFFD0000 and show it with FB_SHOW at 0xFFFF0020.';
    if (document.activeElement === $('screen')) info += ' · Keys go to the program, Esc stops that';
    else if (m.readsKeys) info += ' · Click the screen to type';
    if (info !== screenInfo) $('screen-info').textContent = screenInfo = info;
  }

  // fullscreen: the box around the canvas goes fullscreen, the CSS makes the canvas
  // as big as fits. The canvas gets the focus, so the keys go to the program right away
  function toggleFullscreen() {
    if (document.fullscreenElement) { document.exitFullscreen(); return; }
    const box = $('screen-box');
    if (!box.requestFullscreen) return;
    $('screen-details').open = true;
    box.requestFullscreen().then(() => $('screen').focus()).catch(() => { /* not allowed here */ });
  }

  // keyboard: while the screen has focus, keys go to the program instead of the shortcuts
  const KEY_CODES = { ArrowUp: 0x80, ArrowDown: 0x81, ArrowLeft: 0x82, ArrowRight: 0x83, Enter: 10, Backspace: 8 };
  function keyForProgram(ev) {
    if (ev.ctrlKey || ev.metaKey || ev.altKey) return;
    if (ev.key === 'Escape') { $('screen').blur(); return; }
    let code = KEY_CODES[ev.key];
    if (code === undefined && ev.key.length === 1 && ev.key.charCodeAt(0) < 128) code = ev.key.charCodeAt(0);
    if (code === undefined) return;
    ev.preventDefault();       // no scrolling with the arrow keys or space
    m.pushKey(code);
  }

  // ---------- the diagram ----------
  // left to right: registers -> ALU -> data memory -> write-back multiplexer, and the write-back
  // bus runs along the bottom back into the registers. Wires only cross at right angles.
  const REG_X = 40, REG_W = 140, REG_H = 26;
  const REG_R = REG_X + REG_W;
  const regY = (i) => 30 + i * 30;
  const regMid = (i) => regY(i) + REG_H / 2;
  const ARROW = 10;
  const LANE1 = 205, LANE2 = 228;

  // polyline with rounded corners; the last segment is shortened by `shorten` for the arrow head
  function roundedPath(pts, radius, shorten) {
    pts = pts.map((q) => q.slice());
    if (shorten && pts.length >= 2) {
      const a = pts[pts.length - 2], b = pts[pts.length - 1];
      const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (len > shorten) { b[0] -= (b[0] - a[0]) / len * shorten; b[1] -= (b[1] - a[1]) / len * shorten; }
    }
    let out = `M${pts[0][0]},${pts[0][1]}`;
    for (let i = 1; i < pts.length - 1; i++) {
      const p = pts[i - 1], c = pts[i], n = pts[i + 1];
      const l1 = Math.hypot(c[0] - p[0], c[1] - p[1]), l2 = Math.hypot(n[0] - c[0], n[1] - c[1]);
      if (!l1 || !l2) continue;
      const r = Math.min(radius, l1 / 2, l2 / 2);
      out += ` L${c[0] - (c[0] - p[0]) / l1 * r},${c[1] - (c[1] - p[1]) / l1 * r}`;
      out += ` Q${c[0]},${c[1]} ${c[0] + (n[0] - c[0]) / l2 * r},${c[1] + (n[1] - c[1]) / l2 * r}`;
    }
    const last = pts[pts.length - 1];
    return out + ` L${last[0]},${last[1]}`;
  }

  function renderDiagram(t) {
    const svg = $('diagram');
    svg.textContent = '';
    const d = t.d;
    const live = !d.illegal && !d.halt;

    // arrow heads: the triangle starts where the wire ends, so its tip touches the target
    const defs = el('defs', {});
    for (const [name, color] of Object.entries(COLORS)) {
      const mk = el('marker', { id: 'ah-' + name, viewBox: '0 0 10 10', refX: 0, refY: 5, markerWidth: ARROW, markerHeight: 10, markerUnits: 'userSpaceOnUse', orient: 'auto' });
      mk.appendChild(el('path', { d: 'M0,0 L10,5 L0,10 z', fill: color }));
      defs.appendChild(mk);
    }
    svg.appendChild(defs);

    // wires are collected and drawn last: grey (unused) ones below, colored ones on top
    const pending = [];
    const dots = [];
    const wire = (pts, kind, on, opts) => { pending.push({ pts, kind, on, opts: opts || {} }); };
    const dot = (x, y, kind, on) => { if (on) dots.push({ x, y, kind }); };
    const flushWires = () => {
      for (const w of pending.filter((q) => !q.on).concat(pending.filter((q) => q.on))) {
        const arrow = w.opts.arrow !== false;
        svg.appendChild(el('path', {
          d: roundedPath(w.pts, 9, arrow ? ARROW : 0), fill: 'none',
          stroke: w.on ? COLORS[w.kind] : COLORS.off, 'stroke-width': w.on ? 3 : 1.5,
          'stroke-linecap': 'round', 'marker-end': arrow ? `url(#ah-${w.on ? w.kind : 'off'})` : '',
        }));
        if (w.on) svg.appendChild(el('circle', { cx: w.pts[0][0], cy: w.pts[0][1], r: 4, fill: COLORS[w.kind] }));
      }
      for (const q of dots) svg.appendChild(el('circle', { cx: q.x, cy: q.y, r: 4, fill: COLORS[q.kind] }));
    };
    const box = (x, y, w, h, opts) => {
      opts = opts || {};
      svg.appendChild(el('rect', {
        x, y, width: w, height: h, rx: opts.round || 0,
        fill: opts.fill || 'white', stroke: opts.stroke || '#000', 'stroke-width': opts.sw || 1.2,
        opacity: opts.dim ? 0.45 : 1,
      }));
    };
    const text = (x, y, s, opts) => {
      opts = opts || {};
      svg.appendChild(el('text', {
        x, y, 'font-size': opts.size || 12, 'text-anchor': opts.anchor || 'start',
        fill: opts.fill || '#000', 'font-weight': opts.bold ? 'bold' : 'normal',
        opacity: opts.dim ? 0.45 : 1,
      }, s));
    };

    const usesP1 = live && d.rs1 !== null;
    const usesP2 = live && d.rs2 !== null;
    const toAlu = live && d.usesAlu;
    const isBranch = live && d.branch;
    const isMemW = live && d.memWrite;
    const isMemR = live && d.memRead;
    const memOn = isMemR || isMemW;
    const writes = live && d.regWrite;
    const wbAlu = writes && d.wbSel === 'alu';
    const wbPc4 = writes && d.wbSel === 'pc4';

    // ---- registers
    text(REG_X, 18, 'Registers', { bold: true, size: 13 });
    for (let i = 0; i < 16; i++) {
      const isP1 = usesP1 && d.rs1 === i, isP2 = usesP2 && d.rs2 === i, isRd = writes && d.rd === i;
      let fill = 'white', stroke = '#000', sw = 1;
      if (isRd) { fill = '#e3f2e4'; stroke = COLORS.wb; sw = 2.5; }
      else if (isP1) { fill = '#e3eefa'; stroke = COLORS.p1; sw = 2.5; }
      else if (isP2) { fill = '#fdebdc'; stroke = COLORS.p2; sw = 2.5; }
      box(REG_X, regY(i), REG_W, REG_H, { fill, stroke, sw });
      text(REG_X + 6, regY(i) + 17, regName(i).padEnd(3), { bold: true });
      text(REG_X + REG_W - 6, regY(i) + 17, hex8(m.regs[i]), { anchor: 'end', fill: i === 0 ? '#999' : '#000' });
    }
    text(LANE1, 24, 'port 1', { size: 9, fill: COLORS.p1, anchor: 'middle' });
    text(LANE2 + 14, 24, 'port 2', { size: 9, fill: COLORS.p2, anchor: 'middle' });

    // ---- program counter row
    box(330, 20, 80, 36);
    text(370, 34, 'PC', { anchor: 'middle', size: 10, fill: '#555' });
    text(370, 49, hex8(t.pc), { anchor: 'middle', bold: true });
    box(450, 20, 80, 36);
    text(490, 34, 'PC + 4', { anchor: 'middle', size: 10, fill: '#555' });
    text(490, 49, hex8(t.pc4), { anchor: 'middle' });
    box(570, 20, 130, 36, { sw: 2 });
    let nextHow = 'PC + 4';
    if (live && d.branch) nextHow = t.taken ? `PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)}` : 'PC + 4';
    else if (live && d.jal) nextHow = `PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)}`;
    else if (live && d.jalr) nextHow = 'jump target';
    else if (!live) nextHow = 'stays';
    text(635, 34, 'next PC = ' + nextHow, { anchor: 'middle', size: 9, fill: '#555' });
    text(635, 49, hex8(t.nextPc), { anchor: 'middle', bold: true });
    wire([[410, 38], [450, 38]], 'pc', true);
    const defaultNext = live && !(d.jal || d.jalr || (d.branch && t.taken));
    wire([[530, 38], [570, 38]], 'pc', defaultNext);

    // ---- branch comparator
    const CMP = { x: 330, y: 76, w: 120, h: 60 };
    box(CMP.x, CMP.y, CMP.w, CMP.h, { fill: isBranch ? '#fffde7' : '#f5f5f5', stroke: isBranch ? '#000' : '#aaa', sw: isBranch ? 2 : 1, dim: !isBranch });
    text(CMP.x + CMP.w / 2, CMP.y + 17, 'Branch compare', { anchor: 'middle', size: 11, bold: true, dim: !isBranch });
    if (isBranch) {
      const cmp = { beq: '==', bne: '!=', blt: '<', bge: '>=', bltu: '<u', bgeu: '>=u' }[d.name];
      text(CMP.x + CMP.w / 2, CMP.y + 36, `${regName(d.rs2)} ${cmp} ${regName(d.rs1)}`, { anchor: 'middle', size: 12 });
      text(CMP.x + CMP.w / 2, CMP.y + 52, t.taken ? 'taken' : 'not taken', { anchor: 'middle', size: 12, bold: true, fill: t.taken ? COLORS.wb : '#b00020' });
    }
    wire([[CMP.x + CMP.w, 106], [635, 106], [635, 56]], 'wb', isBranch && t.taken);

    // ---- ALU, B input multiplexer, immediate
    const ALU = { x: 330, y: 165, w: 120, h: 170 };
    const A_Y = 240, B_Y = 300, OUT_Y = 250;
    box(ALU.x, ALU.y, ALU.w, ALU.h, { fill: toAlu ? '#fffde7' : '#f5f5f5', stroke: toAlu ? '#000' : '#aaa', sw: toAlu ? 2 : 1, dim: !toAlu });
    text(ALU.x + ALU.w / 2, ALU.y + 22, 'ALU', { anchor: 'middle', bold: true, size: 15, dim: !toAlu });
    if (toAlu) {
      text(ALU.x + ALU.w / 2, ALU.y + 42, `${E.ALU_NAMES[d.aluOp]} (${E.ALU_SYMBOLS[d.aluOp]})`, { anchor: 'middle', bold: true, size: 13 });
      if (d.memRead || d.memWrite) text(ALU.x + ALU.w / 2, ALU.y + 58, 'address', { anchor: 'middle', size: 11, fill: '#555' });
      if (d.jalr) text(ALU.x + ALU.w / 2, ALU.y + 58, 'jump target', { anchor: 'middle', size: 11, fill: '#555' });
      text(ALU.x + 8, A_Y + 4, 'a ' + hex8(t.aluA), { fill: usesP1 ? COLORS.p1 : '#999', bold: true });
      text(ALU.x + 8, B_Y + 4, 'b ' + hex8(t.aluB), { fill: d.aluBImm ? COLORS.imm : COLORS.p2, bold: true });
      text(ALU.x + ALU.w - 8, ALU.y + ALU.h - 10, 'y ' + hex8(t.aluY), { anchor: 'end', fill: COLORS.wb, bold: true });
    } else {
      text(ALU.x + ALU.w / 2, ALU.y + 60, 'not used', { anchor: 'middle', size: 12, dim: true });
    }

    const MUX = { x: 270, y: 265, w: 34, h: 70 };
    box(MUX.x, MUX.y, MUX.w, MUX.h, { fill: toAlu ? '#fff' : '#f5f5f5', dim: !toAlu });
    text(MUX.x + MUX.w / 2, MUX.y + 11, 'MUX', { anchor: 'middle', size: 9, dim: !toAlu });
    text(MUX.x + MUX.w - 3, MUX.y + 26, 'reg', { anchor: 'end', size: 9, dim: !toAlu });
    text(MUX.x + MUX.w / 2, MUX.y + MUX.h - 5, 'imm', { anchor: 'middle', size: 9, dim: !toAlu });
    const immShown = live && (d.aluBImm || d.branch || d.jal);
    const IMM = { x: 240, y: 360, w: 95, h: 32 };
    box(IMM.x, IMM.y, IMM.w, IMM.h, { fill: immShown ? '#f3e5f5' : '#f5f5f5', stroke: immShown ? COLORS.imm : '#aaa', sw: immShown ? 2 : 1, dim: !immShown });
    text(IMM.x + IMM.w / 2, IMM.y + 13, 'immediate', { anchor: 'middle', size: 9, dim: !immShown });
    text(IMM.x + IMM.w / 2, IMM.y + 26, immShown ? hex8(d.imm) : '', { anchor: 'middle', size: 11, fill: COLORS.imm, bold: true });

    // ---- data memory
    const MEM = { x: 600, y: 195, w: 140, h: 160 };
    box(MEM.x, MEM.y, MEM.w, MEM.h, { fill: memOn ? '#fffde7' : '#f5f5f5', stroke: memOn ? '#000' : '#aaa', sw: memOn ? 2 : 1, dim: !memOn });
    text(MEM.x + MEM.w / 2, MEM.y + 20, 'Data memory', { anchor: 'middle', bold: true, size: 13, dim: !memOn });
    if (memOn) {
      text(MEM.x + 8, OUT_Y - 6, 'address', { size: 10, fill: '#555' });
      text(MEM.x + 8, OUT_Y + 8, hex8(t.memAddr), { fill: COLORS.wb, bold: true });
      if (isMemW) {
        text(MEM.x + 8, 321, 'write data', { size: 10, fill: '#555' });
        text(MEM.x + 8, 335, hex8(t.memData), { fill: COLORS.p2, bold: true });
        text(MEM.x + MEM.w - 8, MEM.y + MEM.h - 8, d.memByte ? `byte ${t.memLane}` : 'whole word', { anchor: 'end', size: 10, fill: '#555' });
      } else {
        text(MEM.x + MEM.w - 8, 276, 'read data', { anchor: 'end', size: 10, fill: '#555' });
        text(MEM.x + MEM.w - 8, 290, hex8(t.loadValue), { anchor: 'end', fill: COLORS.wb, bold: true });
        text(MEM.x + MEM.w - 8, MEM.y + MEM.h - 8, d.memByte ? `byte ${t.memLane}` : 'whole word', { anchor: 'end', size: 10, fill: '#555' });
      }
    }

    // ---- write back multiplexer
    const WB = { x: 820, y: 200, w: 46, h: 140 };
    box(WB.x, WB.y, WB.w, WB.h, { fill: writes ? '#fff' : '#f5f5f5', dim: !writes });
    text(WB.x + WB.w / 2, WB.y + 14, 'WB', { anchor: 'middle', size: 10, dim: !writes });
    text(WB.x + WB.w - 4, 229, 'alu', { anchor: 'end', size: 9, dim: !writes });
    text(WB.x + WB.w - 4, 294, 'mem', { anchor: 'end', size: 9, dim: !writes });

    // ---- wires: registers -> comparator / ALU / multiplexer / memory
    const tapP1 = usesP1 ? regMid(d.rs1) : null, tapP2 = usesP2 ? regMid(d.rs2) : null;
    // port 1 and port 2 buses (grey when unused)
    wire([[LANE1, 40], [LANE1, A_Y], [ALU.x, A_Y]], 'p1', false, { arrow: false });
    wire([[LANE2, 40], [LANE2, MUX.y + 22], [MUX.x, MUX.y + 22]], 'p2', false, { arrow: false });
    if (usesP1 && toAlu) wire([[REG_R, tapP1], [LANE1, tapP1], [LANE1, A_Y], [ALU.x, A_Y]], 'p1', true);
    if (usesP1 && isBranch) wire([[REG_R, tapP1], [LANE1, tapP1], [LANE1, 96], [CMP.x, 96]], 'p1', true);
    if (usesP2 && isBranch) wire([[REG_R, tapP2], [LANE2, tapP2], [LANE2, 116], [CMP.x, 116]], 'p2', true);
    else if (usesP2 && isMemW) wire([[REG_R, tapP2], [LANE2, tapP2], [LANE2, 440], [575, 440], [575, 335], [MEM.x, 335]], 'p2', true);
    else if (usesP2 && !d.aluBImm) wire([[REG_R, tapP2], [LANE2, tapP2], [LANE2, MUX.y + 22], [MUX.x, MUX.y + 22]], 'p2', true);
    // store data path is always drawn (grey when idle), so the memory has both inputs
    wire([[LANE2, 40], [LANE2, 440], [575, 440], [575, 335], [MEM.x, 335]], 'p2', false);

    wire([[MUX.x + MUX.w, B_Y], [ALU.x, B_Y]], d.aluBImm ? 'imm' : 'p2', toAlu);
    wire([[MUX.x + MUX.w / 2, IMM.y], [MUX.x + MUX.w / 2, MUX.y + MUX.h]], 'imm', toAlu && d.aluBImm);

    // ---- wires: ALU -> memory address / write back / next PC, memory -> write back
    const aluOutOn = memOn || wbAlu || (live && d.jalr);
    wire([[ALU.x + ALU.w, OUT_Y], [480, OUT_Y]], 'wb', aluOutOn, { arrow: false });
    wire([[480, OUT_Y], [MEM.x, OUT_Y]], 'wb', memOn);
    wire([[480, OUT_Y], [480, 175], [790, 175], [790, 225], [WB.x, 225]], 'wb', wbAlu);
    wire([[MEM.x + MEM.w, 290], [WB.x, 290]], 'wb', isMemR);
    wire([[490, 20], [490, 8], [WB.x + WB.w / 2, 8], [WB.x + WB.w / 2, WB.y]], 'wb', wbPc4);
    if (live && d.jalr) wire([[480, OUT_Y], [480, 150], [600, 150], [600, 56]], 'wb', true);
    dot(480, OUT_Y, 'wb', aluOutOn);

    // ---- write back -> register file: along the bottom, then into the left side of the register
    const wbOut = [WB.x + WB.w, 265];
    if (writes) {
      const y = regMid(d.rd);
      wire([wbOut, [888, 265], [888, 572], [20, 572], [20, y], [REG_X, y]], 'wb', d.rd !== 0);
      if (d.rd === 0) text(40, 562, 'write to r0 is ignored', { size: 11, fill: '#b00020' });
      else text(560, 562, 'write ' + hex8(t.wbValue) + ' to ' + regName(d.rd), { size: 12, fill: COLORS.wb, bold: true });
    } else {
      wire([wbOut, [888, 265], [888, 572], [20, 572], [20, 40]], 'wb', false, { arrow: false });
    }

    if (d.illegal) text(390, 350, 'illegal instruction', { size: 14, fill: '#b00020', bold: true, anchor: 'middle' });
    if (d.halt) text(390, 350, 'halt', { size: 14, bold: true, anchor: 'middle' });

    flushWires();
  }

  // ---------- wiring ----------
  function fillExamples() {
    const sel = $('example');
    EXAMPLES.forEach((ex, i) => {
      const o = document.createElement('option');
      o.value = String(i); o.textContent = ex.name;
      sel.appendChild(o);
    });
    const custom = document.createElement('option');
    custom.value = 'custom'; custom.textContent = 'My own program';
    sel.appendChild(custom);
  }

  function chooseExample() {
    const v = $('example').value;
    if (v === 'custom') return;
    const ex = EXAMPLES[Number(v)];
    if (ex.dataScript && window[ex.dataVar] === undefined) {   // big data is only loaded when needed
      const s = document.createElement('script');
      s.src = ex.dataScript;
      s.onload = chooseExample;
      s.onerror = () => { $('errors').textContent = `Could not load ${ex.dataScript}`; };
      document.head.appendChild(s);
      return;
    }
    const data = ex.dataVar ? window[ex.dataVar] : ex.data;
    $('hex').value = ex.text;
    $('datahex').value = data;
    $('data-details').open = data.trim() !== '' && data.length < 2000;
    if (ex.speed) $('speed').value = ex.speed;
    loadFromText();
  }

  function init() {
    fillExamples();
    let saved = null;
    try { saved = JSON.parse(localStorage.getItem('cpu-playground') || 'null'); } catch (e) { /* ignore */ }
    if (saved && typeof saved.text === 'string' && saved.text.trim()) {
      $('hex').value = saved.text;
      $('datahex').value = saved.data || '';
      $('data-details').open = ($('datahex').value.trim() !== '');
      const idx = EXAMPLES.findIndex((ex) => ex.text === saved.text && (ex.dataVar || ex.data === (saved.data || '')));
      $('example').value = idx >= 0 ? String(idx) : 'custom';
      loadFromText();
    } else {
      $('example').value = '0';
      chooseExample();
    }

    $('example').addEventListener('change', chooseExample);
    const edited = () => { $('example').value = 'custom'; loadFromText(); };
    $('hex').addEventListener('input', edited);
    $('datahex').addEventListener('input', edited);
    $('step').addEventListener('click', () => { stop(); doStep(); });
    $('run').addEventListener('click', toggleRun);
    $('reset').addEventListener('click', resetMachine);
    $('speed').addEventListener('change', () => { if (timer !== null) { stop(); toggleRun(); } });
    $('screen').addEventListener('keydown', keyForProgram);
    $('screen').addEventListener('focus', renderScreen);
    $('screen').addEventListener('blur', renderScreen);
    $('screen').addEventListener('dblclick', toggleFullscreen);
    $('fullscreen').addEventListener('click', toggleFullscreen);
    document.addEventListener('fullscreenchange', () => {
      $('fullscreen').textContent = document.fullscreenElement ? 'Exit fullscreen' : 'Fullscreen';
    });
    document.addEventListener('keydown', (ev) => {
      if (ev.target.tagName === 'TEXTAREA' || ev.target.tagName === 'SELECT' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
      if (ev.target === $('screen')) return;      // those keys are for the program
      if (ev.key === 's' || ev.key === 'S') { stop(); doStep(); }
      else if (ev.key === 'r' || ev.key === 'R') toggleRun();
      else if (ev.key === 'Escape') resetMachine();
      else if (ev.key === 'f' || ev.key === 'F') toggleFullscreen();
    });
  }

  init();
})();
