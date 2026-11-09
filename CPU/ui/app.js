// CPU Playground: hex editor, run/step controls and the data path diagram.
// The CPU itself is in emu.js.
(function () {
  'use strict';

  const E = CPU32;
  const { hex8, regName, disasm, decode, u32 } = E;

  const COLORS = { p1: '#1565c0', p2: '#e65100', imm: '#6a1b9a', wb: '#2e7d32', pc: '#444', off: '#c8c8c8' };

  const EXAMPLES = [
    {
      name: 'Add and multiply (4 instructions)',
      text: `11100005   ; addi r1, r0, 5
11200007   ; addi r2, r0, 7
01312000   ; add  r3, r1, r2      r3 = 12
20432000   ; mul  r4, r3, r2      r4 = 84
ff000000   ; halt`,
      data: '',
    },
    {
      name: 'Sum of 1 to 10 (a loop)',
      text: `11100000   ; addi r1, r0, 0     sum = 0
11200001   ; addi r2, r0, 1     i = 1
1130000a   ; addi r3, r0, 10    last = 10
01112000   ; loop: add r1, r1, r2    sum += i
11220001   ; addi r2, r2, 1     i++
4332fffe   ; bge  r3, r2, loop  while last >= i
38100000   ; st   r1, [r0+0]    save the sum (55) in memory
ff000000   ; halt`,
      data: '',
    },
    {
      name: 'Fibonacci (prints 20 numbers)',
      text: `1fa0ffff
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
      name: 'Hello, World! (function call, needs data)',
      text: `1fe00004
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
      name: 'Every kind of instruction (store, load, branch, jal)',
      text: `1f100001   ; lui  r1, 1          r1 = 0x00010000
14110234   ; ori  r1, r1, 0x234  r1 = 0x00010234
11200004   ; addi r2, r0, 4
38120000   ; st   r1, [r2+0]     memory[4] = r1
30320000   ; ld   r3, [r2+0]     r3 = memory[4]
39120008   ; stb  r1, [r2+8]     one byte
32420008   ; ldbu r4, [r2+8]
4113fffe   ; bne  r1, r3, -2     not taken
50f00002   ; jal  lr, +2         lr = return address
11500063   ; addi r5, r0, 99     (skipped)
ff000000   ; halt`,
      data: '',
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
    buildListing();
    try { localStorage.setItem('cpu-playground', JSON.stringify({ text: $('hex').value, data: $('datahex').value })); } catch (e) { /* private window */ }
    refresh();
  }

  function resetMachine() {
    stop();
    m.reset();
    consoleText = '';
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
    const tick = () => {
      if (m.halted) { stop(); refresh(); return; }
      if (perSecond === 0) {
        for (let i = 0; i < 50000 && !m.halted && m.cycles < MAX_CYCLES; i++) lastTrace = m.step();
        if (m.cycles >= MAX_CYCLES && !m.halted) {
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
    timer = perSecond === 0 ? requestAnimationFrame(tick) : setTimeout(tick, 0);
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
      out += box(hx[2], COLORS.wb, 'A', 'rd (gets PC+4)') + box(hx.slice(3), COLORS.imm, 'imm20', 'jump offset');
    } else if (d.kind === 'HALT' || d.illegal) {
      out += box(hx.slice(2), '#999', '', 'unused');
    } else {
      // A
      let aRole = 'rd (result)', aColor = COLORS.wb;
      if (d.kind === 'STORE') { aRole = 'data to store'; aColor = COLORS.p2; }
      if (d.kind === 'BRANCH') { aRole = 'ra (port 2)'; aColor = COLORS.p2; }
      out += box(hx[2], aColor, 'A', aRole);
      // B
      if (d.kind === 'LUI') out += box(hx[3], '#999', 'B', 'unused (0)');
      else out += box(hx[3], COLORS.p1, 'B', d.kind === 'LOAD' || d.kind === 'STORE' || d.kind === 'JALR' ? 'base (port 1)' : 'port 1');
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
      L.push(`<b>${hex8(d.instr)}</b> is not an instruction (opcode ${hex8(d.instr).slice(0, 2)}). The CPU stops here.`);
    } else if (d.halt) {
      L.push('<b>halt</b> stops the CPU.');
    } else {
      const sym = E.ALU_SYMBOLS[d.aluOp];
      const dest = d.rd === 0 ? `${wb('r0')} (always 0, the write is ignored)` : wb(rn(d.rd));
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
          L.push(`${dest} = ${im(fmt(d.imm))} (the immediate shifted left by 16)`);
          break;
        case 'LOAD':
          L.push(`${dest} = memory[${p1(rn(d.rs1))} + ${im(fmt(d.imm))}]  (${d.memByte ? (d.memSigned ? 'one byte, sign-extended' : 'one byte, zero-extended') : 'one word'})`);
          L.push(`address ${p1(fmt(t.aluA))} + ${im(fmt(d.imm))} = ${hex8(t.aluY)}, it holds ${wb(fmt(t.loadValue))}`);
          break;
        case 'STORE':
          L.push(`memory[${p1(rn(d.rs1))} + ${im(fmt(d.imm))}] = ${p2(rn(d.rs2))}  (${d.memByte ? 'low byte only' : 'one word'})`);
          L.push(`address ${p1(fmt(t.aluA))} + ${im(fmt(d.imm))} = ${hex8(t.aluY)}, stores ${p2(fmt(t.memData))}`);
          break;
        case 'BRANCH': {
          const cmp = { beq: '==', bne: '!=', blt: '<', bge: '>=', bltu: '<u', bgeu: '>=u' }[d.name];
          L.push(`if ${p2(rn(d.rs2))} ${cmp} ${p1(rn(d.rs1))} then PC = PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)}`);
          L.push(`${p2(fmt(t.p2))} ${cmp} ${p1(fmt(t.p1))} is <b>${t.taken ? 'true: jump to ' + hex8(t.nextPc) : 'false: continue with ' + hex8(t.nextPc)}</b>`);
          break;
        }
        case 'JAL':
          L.push(`${dest} = PC + 4 (${hex8(t.pc4)}), then PC = PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)} = ${hex8(t.nextPc)}`);
          break;
        case 'JALR':
          L.push(`${dest} = PC + 4 (${hex8(t.pc4)}), then PC = ${p1(rn(d.rs1))} + ${im(fmt(d.imm))} = ${hex8(t.nextPc)}`);
          break;
      }
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
    $('mem').innerHTML = s || '(nothing written yet)';
    if (m.leds) $('mem').innerHTML += `\nLEDs: ${hex8(m.leds)}`;
  }

  // ---------- the diagram ----------
  const REG_X = 12, REG_W = 140, REG_H = 26;
  const regY = (i) => 30 + i * 30;
  const regMid = (i) => regY(i) + REG_H / 2;

  function renderDiagram(t) {
    const svg = $('diagram');
    svg.textContent = '';
    const d = t.d;
    const live = !d.illegal && !d.halt;

    // arrow heads
    const defs = el('defs', {});
    for (const [name, color] of Object.entries(COLORS)) {
      const mk = el('marker', { id: 'ah-' + name, viewBox: '0 0 10 10', refX: 9, refY: 5, markerWidth: 11, markerHeight: 11, markerUnits: 'userSpaceOnUse', orient: 'auto-start-reverse' });
      mk.appendChild(el('path', { d: 'M0,0 L10,5 L0,10 z', fill: color }));
      defs.appendChild(mk);
    }
    svg.appendChild(defs);

    const wire = (pathD, kind, on, opts) => {
      opts = opts || {};
      svg.appendChild(el('path', {
        d: pathD, fill: 'none', stroke: on ? COLORS[kind] : COLORS.off,
        'stroke-width': on ? 3 : 1.5, 'stroke-linejoin': 'round',
        'stroke-dasharray': opts.dash ? '6 4' : '',
        'marker-end': opts.arrow === false ? '' : `url(#ah-${on ? kind : 'off'})`,
      }));
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
    const writes = live && d.regWrite;

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
      const v = m.regs[i];
      text(REG_X + REG_W - 6, regY(i) + 17, hex8(v), { anchor: 'end', fill: i === 0 ? '#999' : '#000' });
      // role markers
      if (isRd) svg.appendChild(el('rect', { x: REG_X - 7, y: regY(i) + 3, width: 5, height: REG_H - 6, fill: COLORS.wb }));
      if (isP1) svg.appendChild(el('rect', { x: REG_X + REG_W + 2, y: regY(i) + 3, width: 5, height: 9, fill: COLORS.p1 }));
      if (isP2) svg.appendChild(el('rect', { x: REG_X + REG_W + 2, y: regY(i) + 14, width: 5, height: 9, fill: COLORS.p2 }));
    }

    // ---- instruction decode summary for ports
    const lane1 = 176, lane2 = 198;

    // ---- ALU
    const aluX = 300, aluY = 120, aluW = 120, aluH = 170;
    box(aluX, aluY, aluW, aluH, { fill: toAlu ? '#fffde7' : '#f5f5f5', stroke: toAlu ? '#000' : '#aaa', sw: toAlu ? 2 : 1, dim: !toAlu });
    text(aluX + aluW / 2, aluY + 22, 'ALU', { anchor: 'middle', bold: true, size: 15, dim: !toAlu });
    if (toAlu) {
      const isAddr = d.memRead || d.memWrite;
      text(aluX + aluW / 2, aluY + 42, `${E.ALU_NAMES[d.aluOp]} (${E.ALU_SYMBOLS[d.aluOp]})`, { anchor: 'middle', bold: true, size: 13 });
      if (isAddr) text(aluX + aluW / 2, aluY + 58, 'address', { anchor: 'middle', size: 11, fill: '#555' });
      if (d.jalr) text(aluX + aluW / 2, aluY + 58, 'jump target', { anchor: 'middle', size: 11, fill: '#555' });
      text(aluX + 6, 199, 'a ' + hex8(t.aluA), { fill: usesP1 ? COLORS.p1 : '#999', bold: true });
      text(aluX + 6, 255, 'b ' + hex8(t.aluB), { fill: d.aluBImm ? COLORS.imm : COLORS.p2, bold: true });
      text(aluX + aluW - 6, aluY + aluH - 8, 'y ' + hex8(t.aluY), { anchor: 'end', fill: COLORS.wb, bold: true });
    } else {
      text(aluX + aluW / 2, aluY + 60, 'not used', { anchor: 'middle', size: 12, dim: true });
    }

    // ---- B input multiplexer and immediate
    const muxX = 238, muxY = 215, muxW = 34, muxH = 70;
    box(muxX, muxY, muxW, muxH, { fill: toAlu ? '#fff' : '#f5f5f5', dim: !toAlu });
    text(muxX + muxW / 2, muxY + 14, 'MUX', { anchor: 'middle', size: 9, dim: !toAlu });
    text(muxX + 3, muxY + 24, 'reg', { size: 9, dim: !toAlu });
    text(muxX + 3, muxY + 56, 'imm', { size: 9, dim: !toAlu });
    const immShown = live && (d.aluBImm || d.branch || d.jal);
    box(210, 300, 82, 28, { fill: immShown ? '#f3e5f5' : '#f5f5f5', stroke: immShown ? COLORS.imm : '#aaa', sw: immShown ? 2 : 1, dim: !immShown });
    text(251, 311, 'immediate', { anchor: 'middle', size: 9, dim: !immShown });
    text(251, 323, immShown ? hex8(d.imm) : '', { anchor: 'middle', size: 11, fill: COLORS.imm, bold: true });

    // ---- branch comparator
    const cmpX = 300, cmpY = 350, cmpW = 120, cmpH = 56;
    box(cmpX, cmpY, cmpW, cmpH, { fill: isBranch ? '#fffde7' : '#f5f5f5', stroke: isBranch ? '#000' : '#aaa', sw: isBranch ? 2 : 1, dim: !isBranch });
    text(cmpX + cmpW / 2, cmpY + 17, 'Branch compare', { anchor: 'middle', size: 11, bold: true, dim: !isBranch });
    if (isBranch) {
      const cmp = { beq: '==', bne: '!=', blt: '<', bge: '>=', bltu: '<u', bgeu: '>=u' }[d.name];
      text(cmpX + cmpW / 2, cmpY + 33, `${regName(d.rs2)} ${cmp} ${regName(d.rs1)}`, { anchor: 'middle', size: 12 });
      text(cmpX + cmpW / 2, cmpY + 48, t.taken ? 'taken' : 'not taken', { anchor: 'middle', size: 12, bold: true, fill: t.taken ? COLORS.wb : '#b00020' });
    }

    // ---- wires from the registers
    if (usesP1) {
      const y = regMid(d.rs1);
      const target = isBranch ? 365 : 195;
      if (toAlu || isBranch) wire(`M${REG_X + REG_W + 8},${y} H${lane1} V${target} H${isBranch ? cmpX : aluX}`, 'p1', true);
    }
    if (usesP2) {
      const y = regMid(d.rs2);
      const from = `M${REG_X + REG_W + 8},${y} H${lane2}`;
      if (isBranch) wire(`${from} V385 H${cmpX}`, 'p2', true);
      else if (isMemW) wire(`${from} V420 H600 V260 H620`, 'p2', true);
      else if (!d.aluBImm) wire(`${from} V235 H${muxX}`, 'p2', true);
    }
    // inactive skeleton wires
    if (!usesP1 || !(toAlu || isBranch)) wire(`M${lane1},40 V195 H${aluX}`, 'p1', false, { arrow: false });
    if (!(usesP2 && !isBranch && !isMemW && !d.aluBImm)) wire(`M${lane2},40 V235 H${muxX}`, 'p2', false, { arrow: false });
    // mux -> ALU b, immediate -> mux
    wire(`M${muxX + muxW},250 H${aluX}`, d.aluBImm ? 'imm' : 'p2', toAlu);
    if (live && d.aluBImm) wire(`M236,300 V268 H${muxX}`, 'imm', true);
    else wire(`M236,300 V268 H${muxX}`, 'imm', false, { arrow: false });

    // ---- program counter
    box(300, 20, 90, 36, { fill: '#fff' });
    text(345, 34, 'PC', { anchor: 'middle', size: 10, fill: '#555' });
    text(345, 49, hex8(t.pc), { anchor: 'middle', bold: true });
    box(410, 20, 80, 36, { fill: '#fff' });
    text(450, 34, 'PC + 4', { anchor: 'middle', size: 10, fill: '#555' });
    text(450, 49, hex8(t.pc4), { anchor: 'middle' });
    wire('M390,38 H410', 'pc', true);

    box(540, 20, 140, 36, { fill: '#fff', stroke: '#000', sw: 2 });
    let nextHow = 'PC + 4';
    if (live && d.branch) nextHow = t.taken ? `PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)}` : 'PC + 4';
    else if (live && d.jal) nextHow = `PC ${d.imm < 0 ? '-' : '+'} ${Math.abs(d.imm)}`;
    else if (live && d.jalr) nextHow = 'jump target';
    else if (!live) nextHow = 'stays';
    text(610, 34, 'next PC = ' + nextHow, { anchor: 'middle', size: 9, fill: '#555' });
    text(610, 49, hex8(t.nextPc), { anchor: 'middle', bold: true });
    const defaultNext = live && !(d.jal || d.jalr || (d.branch && t.taken));
    wire('M490,38 H540', 'pc', defaultNext);
    if (isBranch) wire(`M${cmpX + cmpW},378 H610 V56`, 'wb', true);
    else wire(`M${cmpX + cmpW},378 H610 V56`, 'wb', false, { arrow: false });
    if (live && d.jalr) wire('M450,205 V100 H570 V56', 'wb', true);

    // ---- data memory
    const mX = 620, mY = 150, mW = 140, mH = 140;
    const memOn = isMemR || isMemW;
    box(mX, mY, mW, mH, { fill: memOn ? '#fffde7' : '#f5f5f5', stroke: memOn ? '#000' : '#aaa', sw: memOn ? 2 : 1, dim: !memOn });
    text(mX + mW / 2, mY + 20, 'Data memory', { anchor: 'middle', bold: true, size: 13, dim: !memOn });
    if (memOn) {
      text(mX + 6, 185, 'addr', { size: 10, fill: '#555' });
      text(mX + 6, 198, hex8(t.memAddr), { fill: COLORS.wb, bold: true });
      if (isMemW) {
        text(mX + 6, 256, 'write data', { size: 10, fill: '#555' });
        text(mX + 6, 270, hex8(t.memData), { fill: COLORS.p2, bold: true });
        text(mX + 6, 284, d.memByte ? `byte ${t.memLane}` : 'whole word', { size: 10, fill: '#555' });
      } else {
        text(mX + mW - 6, 225, 'read data', { anchor: 'end', size: 10, fill: '#555' });
        text(mX + mW - 6, 239, hex8(t.loadValue), { anchor: 'end', fill: COLORS.wb, bold: true });
        text(mX + 6, 284, d.memByte ? `byte ${t.memLane}` : 'whole word', { size: 10, fill: '#555' });
      }
    }
    // ALU result -> memory address, ALU result -> write back
    wire(`M${aluX + aluW},205 H450 V130 H590 V180 H${mX}`, 'wb', memOn);
    // memory read data -> write back
    wire(`M${mX + mW},232 H790 V450 H462 V250 H500`, 'wb', isMemR);

    // ---- write back multiplexer
    const wX = 500, wY = 190, wW = 30, wH = 130;
    box(wX, wY, wW, wH, { fill: writes ? '#fff' : '#f5f5f5', dim: !writes });
    text(wX + wW / 2, wY + 14, 'WB', { anchor: 'middle', size: 10, dim: !writes });
    text(wX + 2, 218, 'alu', { size: 8, dim: !writes });
    text(wX + 2, 253, 'mem', { size: 8, dim: !writes });
    text(wX + 2, 293, 'PC+4', { size: 8, dim: !writes });
    const wbAlu = writes && d.wbSel === 'alu';
    wire(`M${aluX + aluW},205 H450 V215 H${wX}`, 'wb', wbAlu);
    wire(`M485,56 V290 H${wX}`, 'wb', writes && d.wbSel === 'pc4');

    // ---- write back -> register file
    if (writes) {
      const y = regMid(d.rd);
      wire(`M${wX + wW},255 H548 V545 H4 V${y} H${REG_X - 8}`, 'wb', d.rd !== 0);
      if (d.rd === 0) text(40, 553, 'write to r0 is ignored', { size: 11, fill: '#b00020' });
      else text(560, 535, 'write ' + hex8(t.wbValue) + ' to ' + regName(d.rd), { size: 12, fill: COLORS.wb, bold: true });
    } else {
      wire(`M${wX + wW},255 H548 V545 H4 V40`, 'wb', false, { arrow: false });
    }

    // ---- labels
    text(lane1 - 4, 24, 'port 1', { size: 9, fill: COLORS.p1, anchor: 'middle' });
    text(lane2 + 14, 24, 'port 2', { size: 9, fill: COLORS.p2, anchor: 'middle' });
    if (d.illegal) text(415, 300, 'illegal instruction', { size: 14, fill: '#b00020', bold: true, anchor: 'middle' });
    if (d.halt) text(415, 300, 'halt', { size: 14, bold: true, anchor: 'middle' });
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
    $('hex').value = ex.text;
    $('datahex').value = ex.data;
    $('data-details').open = ex.data.trim() !== '';
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
      const idx = EXAMPLES.findIndex((ex) => ex.text === saved.text && ex.data === (saved.data || ''));
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
    document.addEventListener('keydown', (ev) => {
      if (ev.target.tagName === 'TEXTAREA' || ev.target.tagName === 'SELECT' || ev.ctrlKey || ev.metaKey || ev.altKey) return;
      if (ev.key === 's' || ev.key === 'S') { stop(); doStep(); }
      else if (ev.key === 'r' || ev.key === 'R') toggleRun();
      else if (ev.key === 'Escape') resetMachine();
    });
  }

  init();
})();
