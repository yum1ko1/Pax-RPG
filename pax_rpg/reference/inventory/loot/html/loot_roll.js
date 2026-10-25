  // ───────── прокрутка лута (перенос mods/pax_rpg/src/location/loot/roll.gd; те же времена и размеры, px макета 1080) ─────────
  const L = (() => {
    const IMG = {}, SND = {};
    const load = (n, src) => { const im = new Image(); im.src = src; IMG[n] = im; };
    ["ink_strip", "ink_glow", "ink_ring", "slash", "splat_l", "splat_r", "blot_0", "blot_1", "blot_2", "blot_3", "blot_4", "blot_5", "orb_rainbow"]
      .forEach(n => load(n, `loot/${n}.png`));
    load("katana", "loot/katana_sheet.webp");
    SND.ink = "loot/loot_ink.ogg"; SND.tick = "loot/loot_tick.ogg"; SND.spin = "loot/loot_spin.ogg";
    SND.slash = "loot/loot_slash.ogg"; SND.reveal = "loot/loot_reveal.ogg"; SND.epic = "loot/loot_reveal_epic.ogg";
    let soundOn = true;
    const play = (n, db, pitch = 1) => {
      if (!soundOn) return;
      const a = new Audio(SND[n]); a.volume = Math.min(1, Math.pow(10, db / 20)); a.preservesPitch = false; a.playbackRate = pitch;
      a.play().catch(() => {});
    };
    const STRIP_W = 700, CELL = 118, BLOT = 140, ICON = 80, RING = 200, KAT_H = 400;
    const MOVE_OFF = [-250, -300], T_SPIN = 0.75, SETTLE = 0.22, CUT_AFTER = 0.55, STROKE = 0.13, STROKE2 = 0.21, REVEAL_AFTER = 0.55, FLY = 0.75;
    const KAT_FRAMES = 80, KAT_COLS = 10, KAT_FW = 192, KAT_FH = 320;
    const W_RAR = [46, 28, 14, 8, 3.2, 0.8], N = 36, WIN = 30, SPIN = 3.6;
    const cv = document.getElementById("lootCv"), cx = cv.getContext("2d");
    const tipWrap = document.getElementById("lttWrap"), ltt = document.getElementById("ltt");
    const ease = u => 1 - Math.pow(1 - Math.min(1, Math.max(0, u)), 3);
    const back = u => { const x = Math.min(1, Math.max(0, u)) - 1; return 1 + 2.2 * x * x * x + 1.2 * x * x; };
    const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
    const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
    const bez = (p0, c, p1, k) => { const e = k * k * (3 - 2 * k); const l = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
      return l(l(p0, c, e), l(c, p1, e), e); };
    const rcol = r => getComputedStyle(document.documentElement).getPropertyValue(RC[r]).trim() || "#fff";
    const rgba = (hex, a) => { const c = document.createElement("canvas").getContext("2d"); c.fillStyle = hex; const h = c.fillStyle;
      const n = parseInt(h.slice(1), 16); return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`; };
    const icons = {}, rings = {};
    // иконка вещи на кляксе: ячейка листа сета, края уходят в прозрачность (круг)
    function icon(setKey, k, r) {
      const key = setKey + k + r;
      if (icons[key]) return icons[key];
      const sh = SETS[setKey].sheet, img = sheetImg[setKey];
      if (!img.complete) return null;
      const [x0, x1] = sh.cols[r], [y0, y1] = sh.rows[k], side = Math.min(x1 - x0, y1 - y0);
      const c = document.createElement("canvas"); c.width = c.height = 128; const g = c.getContext("2d");
      g.drawImage(img, x0 + (x1 - x0 - side) / 2, y0 + (y1 - y0 - side) / 2, side, side, 0, 0, 128, 128);
      g.globalCompositeOperation = "destination-in";
      const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64); gr.addColorStop(0.78, "#000"); gr.addColorStop(1, "rgba(0,0,0,0)");
      g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
      return (icons[key] = c);
    }
    function ring(hex) {
      if (rings[hex]) return rings[hex];
      const im = IMG.ink_ring; if (!im.complete) return null;
      const c = document.createElement("canvas"); c.width = im.width; c.height = im.height; const g = c.getContext("2d");
      g.drawImage(im, 0, 0); g.globalCompositeOperation = "source-in"; g.fillStyle = hex; g.fillRect(0, 0, c.width, c.height);
      return (rings[hex] = c);
    }
    // тёплый свет под тушью (ink_glow — белая, красится в цвет рисовой бумаги): тушь читается и на тёмном фоне
    const GLOW_PAD = 60;
    let glowC = null;
    function glow() {
      if (glowC) return glowC;
      const im = IMG.ink_glow; if (!im.complete) return null;
      const c = document.createElement("canvas"); c.width = im.width; c.height = im.height; const g = c.getContext("2d");
      g.drawImage(im, 0, 0); g.globalCompositeOperation = "source-in"; g.fillStyle = "rgb(245,224,184)"; g.fillRect(0, 0, c.width, c.height);
      return (glowC = c);
    }
    const sheetImg = {};
    SET_KEYS.forEach(k => { const im = new Image(); im.src = SETS[k].sheet.img; sheetImg[k] = im; });

    let st = null, flights = [], queue = [], last = 0, s = 1, W = 1920, lootN = 0;

    function randItem(forceR, forceMana) {
      let r = forceR;
      if (r < 0) { let x = Math.random() * W_RAR.reduce((a, b) => a + b, 0); r = 0; for (let i = 0; i < W_RAR.length; i++) { x -= W_RAR[i]; if (x <= 0) { r = i; break; } } }
      const setKey = SET_KEYS[Math.floor(Math.random() * SET_KEYS.length)], k = Math.floor(Math.random() * SLOTS.length);
      const mana = forceMana === undefined ? Math.random() < 0.04 : forceMana;
      return { setKey, k, r, mana, blot: Math.floor(Math.random() * 6), rot: (Math.random() - 0.5) };
    }
    // вещь победителя — полноценная (makeItem прототипа), id уникальный, чтобы лечь в выбор слота
    function makeLoot(w) {
      const it = makeItem(SLOTS[w.k], w.r, +lvlIn.value + w.r, w.mana, false);
      return Object.assign(it, { set: true, setKey: w.setKey, name: SETS[w.setKey].names[w.k], id: `loot-${++lootN}` });
    }
    function start(forceR, forceMana) {
      const items = []; for (let i = 0; i < N; i++) items.push(i === WIN ? randItem(forceR, forceMana) : randItem(-1));
      const w = items[WIN];
      w.item = makeLoot(w);
      st = { t: 0, items, off0: 2 * CELL, off1: WIN * CELL + (Math.random() - 0.5) * 0.76 * CELL, tick: -999, cutPlayed: false, revealed: false,
        big: w.r >= 4 || w.mana, tipAt: -1, tipLen: 0, rolls: [], anchor: [W - 390, 1080 - 175] };
      st.orbAt = revealT() + 1.5;
      play("ink", -4);
    }
    const katT = () => T_SPIN + SPIN + SETTLE, cutT = () => katT() + CUT_AFTER, revealT = () => cutT() + REVEAL_AFTER;
    function offset() {
      if (st.t < T_SPIN) return st.off0;
      const u = clamp((st.t - T_SPIN) / SPIN), off = st.off0 + (st.off1 - st.off0) * (1 - Math.pow(1 - u, 3));
      const q = clamp((st.t - T_SPIN - SPIN) / SETTLE); return off + (WIN * CELL - off) * q * q * (3 - 2 * q);
    }
    const groupOff = () => st.big ? [MOVE_OFF[0] * ease((st.t - revealT() - 0.8) / 0.5), MOVE_OFF[1] * ease((st.t - revealT() - 0.8) / 0.5)] : [0, 0];

    // окно характеристик: та же подсказка, что в инвентаре (render); усиленные и маны статы прокручиваются по очереди
    function openTip() {
      const w = st.items[WIN];
      ltt.style.setProperty("--rc", `var(${RC[w.r]})`);
      ltt.classList.toggle("mana", !!w.mana); ltt.dataset.r = w.r;
      ltt.innerHTML = render(w.item, w.k);
      ltt.querySelectorAll("li.boost").forEach(li => { li.style.setProperty("--bc", `var(${RC[w.r]})`); li.classList.add("b" + w.r); });
      ltt.classList.remove("show"); void ltt.offsetWidth; ltt.classList.add("show");
      st.rolls = [...ltt.querySelectorAll("li.boost, li.mana")].map(li => {
        const e = w.item[li.dataset.part][+li.dataset.j], m = (e.boost ? RAR[w.r].boost : 1) * (e.mana ? MANA.mult : 1);
        const cls = ["boost", "mana", "b" + w.r].filter(c => li.classList.contains(c));
        li.classList.remove(...cls);
        const v = li.querySelector(".v"); v.textContent = fmt(e.key, e.v / m);
        return { li, v, e, base: e.v / m, cls, step: -1, landed: false };
      });
      st.tipAt = st.t;
      st.tipLen = 0.35 + (st.rolls.length ? 0.5 + st.rolls.length * 0.6 + 0.45 : 0) + 1.4;
      st.orbAt = st.tipAt + st.tipLen + 0.3;
    }
    function tickRolls() {
      const rt = st.t - st.tipAt - 0.35;
      st.rolls.forEach((ro, i) => {
        const t0 = 0.5 + i * 0.6;
        if (rt < t0 || ro.landed) return;
        if (rt < t0 + 0.45) {
          const step = Math.floor((rt - t0) / 0.05);
          if (step !== ro.step) { ro.step = step; ro.v.textContent = fmt(ro.e.key, ro.base + Math.random() * (ro.e.v * 1.15 - ro.base)); play("tick", -16, 1.3 + Math.random() * 0.2); }
          return;
        }
        ro.landed = true; ro.v.textContent = fmt(ro.e.key, ro.e.v); ro.li.classList.add(...ro.cls, "landed");
        play("tick", -3, 0.7); play("ink", -14, 1.4);
      });
    }
    function placeTip() {
      const item = [st.anchor[0] + MOVE_OFF[0], st.anchor[1] + MOVE_OFF[1]], k = 0.82 * s;
      const w = ltt.offsetWidth * k, h = ltt.offsetHeight * k;
      const a = clamp((st.t - st.tipAt) / 0.3) * (1 - clamp((st.t - st.tipAt - st.tipLen) / 0.3));
      const x = (item[0] - RING * 0.5 - 14) * s - w + (1 - a) * 16 * s, y = clamp(item[1] * s - h * 0.45, 20 * s, 1060 * s - h);
      tipWrap.style.transform = `translate(${x}px, ${y}px) scale(${k})`;
      tipWrap.style.opacity = a;
    }

    function frame(now) {
      const dt = Math.min(0.05, (now - (last || now)) / 1000); last = now;
      const dpr = window.devicePixelRatio || 1;
      if (cv.width !== Math.round(innerWidth * dpr) || cv.height !== Math.round(innerHeight * dpr)) { cv.width = Math.round(innerWidth * dpr); cv.height = Math.round(innerHeight * dpr); }
      s = Math.min(innerHeight / 1080, innerWidth / 820); W = innerWidth / s;
      cx.setTransform(1, 0, 0, 1, 0, 0); cx.clearRect(0, 0, cv.width, cv.height);
      cx.setTransform(dpr * s, 0, 0, dpr * s, 0, 0);
      flights = flights.filter(f => { f.t += dt; if (f.t >= 0.8) { queue.push(f.args); return false; } return true; });
      flights.forEach(drawFlight);
      if (!st && queue.length) start(...queue.shift());
      if (st) { step(dt); if (st) draw(); }
      requestAnimationFrame(frame);
    }
    function drawFlight(f) {
      const p0 = [W * 0.5, 620], to = [W - 390, 1080 - 175], c = [(p0[0] + to[0]) / 2, (p0[1] + to[1]) / 2 - 260], k = clamp(f.t / 0.8);
      const p = bez(p0, c, to, k), r = 46 - 16 * k, im = IMG.orb_rainbow;
      for (let j = 6; j > 0; j--) { const tp = bez(p0, c, to, Math.max(0, k - j * 0.03)); circle(tp, 14 - j * 1.6, `rgba(255,230,150,${0.06 * (7 - j)})`); }
      cx.save(); cx.translate(p[0], p[1]); cx.rotate(performance.now() / 1000 * 0.9); cx.filter = `hue-rotate(${(performance.now() / 1000 * 80) % 360}deg)`;
      if (im.complete) cx.drawImage(im, -r, -r, r * 2, r * 2); cx.restore();
    }
    function step(dt) {
      st.t += dt;
      const stop = T_SPIN + SPIN;
      if (st.t >= T_SPIN && st.t < stop + SETTLE) { const i = Math.floor((offset() + CELL * 0.5) / CELL);
        if (i !== st.tick) { if (st.tick !== -999) play("tick", -8, 0.95 + Math.random() * 0.13); else play("spin", -6); st.tick = i; } }
      if (st.t >= cutT() - 0.04 && !st.cutPlayed) { st.cutPlayed = true; play("slash", -2); }
      if (st.t >= revealT() && !st.revealed) {
        st.revealed = true;
        const w = st.items[WIN];
        play(st.big ? "epic" : "reveal", -3);
        lootBag[w.k].push(w.item); bag[w.k].push(w.item);     // вещь — в выбор своего слота (клик по слоту в инвентаре ниже)
        const sl = document.getElementById("slot-" + SLOTS[w.k].key); if (sl) { sl.classList.remove("lootNew"); void sl.offsetWidth; sl.classList.add("lootNew"); }
      }
      if (st.big && st.tipAt < 0 && st.t >= revealT() + 1.2) openTip();
      if (st.tipAt >= 0) { tickRolls(); placeTip(); }
      if (st.t >= st.orbAt + 0.3 + FLY + 0.9) { st = null; tipWrap.style.opacity = 0; }
    }
    const circle = (p, r, col) => { cx.beginPath(); cx.arc(p[0], p[1], Math.max(0.1, r), 0, Math.PI * 2); cx.fillStyle = col; cx.fill(); };
    function draw() {
      const cut = cutT(), c = st.anchor, ce = clamp((st.t - cut - 0.3) / 0.7), e = ce * ce, g = groupOff();
      const orb = clamp((st.t - st.orbAt) / 0.3);
      for (const piece of [-1, 0, 1]) {
        const a = piece !== 0 ? 1 - ce : 1 - orb;
        if (a <= 0.01) continue;
        const off = piece !== 0 ? [piece * 90 * ce, 80 * e] : g;
        cx.save(); cx.translate(c[0] + off[0], c[1] + off[1]); cx.rotate(piece * 0.1 * ce);
        drawStrip(piece, a); drawItems(piece, a); cx.restore();
      }
      cx.save(); cx.translate(c[0], c[1]);
      drawMarker(); drawKatana();
      if (st.t >= cut) drawCut(cut);
      cx.restore();
      if (st.t >= revealT() - 0.05) { cx.save(); cx.translate(c[0] + g[0], c[1] + g[1]); drawReveal(revealT(), 1 - orb); cx.restore(); }
      drawBag();
    }
    function drawStrip(piece, a) {
      const im = IMG.ink_strip; if (!im.complete) return;
      const k = STRIP_W / im.width, h = im.height * k, cut = cutT();
      if (st.t < cut + STROKE2) {
        if (piece !== 0) return;
        const gr = ease(st.t / 0.5), w = STRIP_W * (0.25 + 0.75 * gr), hh = h * (0.7 + 0.3 * gr), gx = GLOW_PAD * k * w / STRIP_W, gy = GLOW_PAD * k * hh / h;
        const fa = a * clamp(st.t / 0.25), gl = glow();
        if (gl) { cx.globalAlpha = fa * 0.32; cx.drawImage(gl, -w / 2 - gx, -hh / 2 - gy, w + gx * 2, hh + gy * 2); }
        cx.globalAlpha = fa; cx.drawImage(im, -w / 2, -hh / 2, w, hh); cx.globalAlpha = 1; return;
      }
      let x0 = -STRIP_W / 2, x1 = STRIP_W / 2;
      if (piece === -1) x1 = -CELL / 2; else if (piece === 0) { x0 = -CELL / 2; x1 = CELL / 2; a *= 1 - clamp((st.t - cut - 0.3) / 0.4); } else x0 = CELL / 2;
      if (a <= 0.01) return;
      const gp = GLOW_PAD * k, gx0 = x0 - (piece === -1 ? gp : 0), gx1 = x1 + (piece === 1 ? gp : 0), gl = glow();
      if (gl) { cx.globalAlpha = a * 0.32; cx.drawImage(gl, GLOW_PAD + (gx0 + STRIP_W / 2) / k, 0, (gx1 - gx0) / k, gl.height, gx0, -h / 2 - gp, gx1 - gx0, h + gp * 2); }
      cx.globalAlpha = a; cx.drawImage(im, (x0 + STRIP_W / 2) / k, 0, (x1 - x0) / k, im.height, x0, -h / 2, x1 - x0, h); cx.globalAlpha = 1;
    }
    function drawItems(piece, a) {
      const off = offset(), cut = st.t >= cutT() + STROKE2;
      st.items.forEach((it, i) => {
        const x = i * CELL - off, d = Math.abs(x) / CELL;
        if (d > 3) return;
        const side = d < 0.5 ? 0 : (x < 0 ? -1 : 1);
        if ((cut && side !== piece) || (!cut && piece !== 0)) return;
        const pop = clamp((st.t - 0.3 - d * 0.07) / 0.25); if (pop <= 0) return;
        const sc = back(pop), vis = a * (1 - smooth(2, 2.75, d)) * Math.min(1, pop * 2); if (vis <= 0.01) return;
        const col = rcol(it.r), bl = IMG["blot_" + it.blot], bs = BLOT * sc;
        cx.save(); cx.translate(x, 0);
        cx.save(); cx.rotate(it.rot); cx.globalAlpha = vis; if (bl.complete) cx.drawImage(bl, -bs / 2, -bs / 2, bs, bs); cx.restore();
        for (let q = 0; q < 4; q++) circle([0, 0], ICON * 0.5 * sc * (1.05 + q * 0.12), rgba(col, 0.1 * vis));
        const ic = icon(it.setKey, it.k, it.r), isz = ICON * sc;
        cx.globalAlpha = vis; if (ic) cx.drawImage(ic, -isz / 2, -isz / 2, isz, isz); cx.globalAlpha = 1;
        cx.beginPath(); cx.arc(0, 0, isz / 2 + 1.5, 0, Math.PI * 2); cx.strokeStyle = rgba(col, 0.75 * vis); cx.lineWidth = 1.6; cx.stroke();
        if (it.mana) { cx.beginPath(); cx.arc(0, 0, isz / 2 + 4.5, 0, Math.PI * 2); cx.strokeStyle = `rgba(255,94,209,${0.7 * vis})`; cx.lineWidth = 1.2; cx.stroke(); }
        cx.restore();
      });
    }
    // указатель, пока ряд крутится: золотая черта с остриями к вещи; гаснет, когда появляется катана
    function drawMarker() {
      const a = clamp((st.t - 0.55) / 0.25) * (1 - clamp((st.t - katT()) / 0.15)); if (a <= 0) return;
      for (let q = 0; q < 3; q++) { cx.beginPath(); cx.moveTo(0, -88); cx.lineTo(0, 88); cx.strokeStyle = `rgba(255,217,140,${0.08 * a})`; cx.lineWidth = 4 + q * 4; cx.stroke(); }
      cx.beginPath(); cx.moveTo(0, -88); cx.lineTo(0, 88); cx.strokeStyle = `rgba(255,237,191,${0.9 * a})`; cx.lineWidth = 1.6; cx.stroke();
      for (const sd of [-1, 1]) {
        const y = sd < 0 ? -88 : 88;
        cx.beginPath(); cx.moveTo(-11, y + sd * 13.5); cx.lineTo(11, y + sd * 13.5); cx.lineTo(0, y - sd * 6.5); cx.closePath(); cx.fillStyle = `rgba(13,8,8,${0.8 * a})`; cx.fill();
        cx.beginPath(); cx.moveTo(-9, y + sd * 12); cx.lineTo(9, y + sd * 12); cx.lineTo(0, y - sd * 4); cx.closePath(); cx.fillStyle = `rgba(224,179,102,${a})`; cx.fill();
      }
    }
    // катана — кадры той же 3D-сцены из Godot (roll.gd → SubViewport): появляется на остановке рукоятью к игроку, два взмаха, уходит
    function drawKatana() {
      const cut = cutT(), a = clamp((st.t - katT()) / 0.15) * (1 - clamp((st.t - cut - STROKE2 - STROKE - 0.15) / 0.25));
      if (a <= 0 || !IMG.katana.complete) return;
      const f = Math.min(KAT_FRAMES - 1, Math.max(0, Math.floor((st.t - katT()) * 60)));
      cx.globalAlpha = a;
      cx.drawImage(IMG.katana, (f % KAT_COLS) * KAT_FW, Math.floor(f / KAT_COLS) * KAT_FH, KAT_FW, KAT_FH, -KAT_H * 0.3, -KAT_H * 0.5 - 30, KAT_H * 0.6, KAT_H);
      cx.globalAlpha = 1;
    }
    function drawCut(cut) {
      const sl = IMG.slash; if (!sl.complete) return;
      const h = 300, w = sl.width * h / sl.height, a = 1 - clamp((st.t - cut - 0.4) / 0.35); if (a <= 0) return;
      for (let n = 0; n < 2; n++) {
        const t0 = cut + n * STROKE2, u = clamp((st.t - t0) / STROKE); if (u <= 0) continue;
        const x = (n === 0 ? -1 : 1) * CELL / 2;
        cx.globalAlpha = a; cx.drawImage(sl, 0, 0, sl.width, sl.height * u, x - w / 2, -h / 2, w, h * u);
        const sp = clamp((st.t - t0 - 0.05) / 0.25);
        if (sp > 0) { const im = IMG[n === 0 ? "splat_l" : "splat_r"], sw = 190 * (0.6 + 0.4 * sp), sh = im.height * sw / im.width;
          cx.drawImage(im, n === 0 ? x - sw : x, 30 - sh / 2, sw, sh); }
        cx.globalAlpha = 1;
      }
    }
    function drawReveal(reveal, fade) {
      const w = st.items[WIN], col = rcol(w.r), u = clamp((st.t - reveal) / 0.35), e = ease(u), a = u * fade; if (a <= 0) return;
      const rg = ring(col), rs = RING * (1.5 - 0.5 * e);
      for (let q = 0; q < 5; q++) circle([0, 0], RING * 0.36 + q * 9, rgba(col, 0.07 * a));
      if (rg) { cx.globalAlpha = a; cx.drawImage(rg, -rs / 2, -rs * rg.height / rg.width / 2, rs, rs * rg.height / rg.width); cx.globalAlpha = 1; }
      const ta = st.big ? a * (1 - clamp((st.t - reveal - 0.8) / 0.3)) : a; if (ta <= 0.01) return;
      const y = RING / 2 + 18;
      cx.textAlign = "center"; cx.lineJoin = "round";
      cx.font = "700 26px 'Cormorant Garamond', serif"; cx.lineWidth = 6; cx.strokeStyle = `rgba(0,0,0,${0.75 * ta})`; cx.fillStyle = rgba(col, ta);
      cx.strokeText(w.item.name, 0, y + 21); cx.fillText(w.item.name, 0, y + 21);
      const t2 = RAR[w.r].name + (w.mana ? " · пропитано маной" : "") + "  ·  в выбор: " + SLOTS[w.k].type;
      cx.font = "600 16.5px 'Cormorant Garamond', serif"; cx.lineWidth = 5; cx.strokeStyle = `rgba(0,0,0,${0.7 * ta})`; cx.fillStyle = `rgba(237,222,204,${ta})`;
      cx.strokeText(t2, 0, y + 44); cx.fillText(t2, 0, y + 44);
    }
    // сумка (над полосой справа; пока нет арта — клякса с золотым кругом) и сфера вещи, летящая в неё
    function drawBag() {
      const t0 = st.orbAt, arrive = t0 + 0.3 + FLY, ba = clamp((st.t - t0 + 0.2) / 0.3) * (1 - clamp((st.t - arrive - 0.5) / 0.4)); if (ba <= 0) return;
      const bag = [W - 100, 750], open = st.t >= arrive - 0.12 && st.t < arrive + 0.4, bump = 1 + 0.12 * Math.max(0, 1 - Math.abs(st.t - arrive) / 0.25);
      const bl = IMG.blot_2, bs = 120 * bump;
      cx.globalAlpha = ba; cx.drawImage(bl, bag[0] - bs / 2, bag[1] - bs / 2, bs, bs); cx.globalAlpha = 1;
      cx.strokeStyle = `rgba(201,163,92,${ba})`; cx.lineWidth = 2;
      cx.beginPath(); cx.arc(bag[0], bag[1], 34 * bump, 0, Math.PI * 2); cx.stroke();
      cx.beginPath(); cx.arc(bag[0], bag[1], (open ? 26 : 18) * bump, Math.PI * 1.1, Math.PI * 1.9); cx.stroke();
      if (st.t < t0 || st.t > arrive) return;
      const w = st.items[WIN], col = rcol(w.r), g = groupOff(), from = [st.anchor[0] + g[0], st.anchor[1] + g[1]];
      const k = clamp((st.t - t0 - 0.3) / FLY), shrink = clamp((st.t - t0) / 0.3);
      const ctrl = [(from[0] + bag[0]) / 2 + 40, (from[1] + bag[1]) / 2 - 180], p = bez(from, ctrl, bag, k), r = (40 - 26 * shrink) * (1 - 0.3 * k);
      if (k > 0) for (let j = 6; j > 0; j--) circle(bez(from, ctrl, bag, Math.max(0, k - j * 0.035)), r * (1 - j * 0.12), rgba(col, 0.06 * (7 - j)));
      for (let q = 0; q < 4; q++) circle(p, r * (1.3 + q * 0.35), rgba(col, 0.12));
      circle(p, r, rgba(col, 1)); circle(p, r * 0.55, "rgba(255,255,255,.95)");
      if (shrink < 1) { const ic = icon(w.setKey, w.k, w.r), isz = ICON * (1 - shrink); cx.globalAlpha = 1 - shrink; if (ic) cx.drawImage(ic, p[0] - isz / 2, p[1] - isz / 2, isz, isz); cx.globalAlpha = 1; }
    }
    requestAnimationFrame(frame);
    // радужная сфера летит в угол → прокрутка (очередь, если уже крутится)
    return {
      roll(forceR, forceMana) {
        const it = randItem(forceR < 0 ? -1 : forceR, forceMana);
        flights.push({ t: 0, args: [it.r, it.mana] });
        play("ink", -12, 1.3);
      },
      sound(on) { soundOn = on; },
    };
  })();
