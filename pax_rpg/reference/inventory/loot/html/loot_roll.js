  // ───────── прокрутка лута (перенос mods/pax_rpg/src/location/loot/roll.gd + loot.gd; те же времена и размеры, px макета 1080) ─────────
  const L = (() => {
    const IMG = {}, SND = {};
    const load = (n, src) => { const im = new Image(); im.src = src; IMG[n] = im; };
    ["ink_strip", "ink_glow", "ink_ring", "slash", "splat_l", "splat_r", "blot_0", "blot_1", "blot_2", "blot_3", "blot_4", "blot_5", "orb_rainbow", "bag_closed", "bag_open"]
      .forEach(n => load(n, `loot/${n}.png`));
    load("katana", "loot/katana_sheet.webp");
    SND.ink = "loot/loot_ink.ogg"; SND.tick = "loot/loot_tick.ogg"; SND.spin = "loot/loot_spin.ogg";
    SND.slash = "loot/loot_slash.ogg"; SND.reveal = "loot/loot_reveal.ogg"; SND.epic = "loot/loot_reveal_epic.ogg";
    SND.statSpin = "loot/loot_stat_spin.ogg"; SND.statLand = "loot/loot_stat_land.ogg"; SND.statMana = "loot/loot_stat_mana.ogg";
    SND.tipOpen = "loot/loot_tip_open.ogg"; SND.toBag = "loot/loot_to_bag.ogg"; SND.lid = "loot/loot_bag_lid.ogg";
    let soundOn = true;
    const play = (n, db, pitch = 1) => {
      if (!soundOn) return;
      const a = new Audio(SND[n]); a.volume = Math.min(1, Math.pow(10, db / 20)); a.preservesPitch = false; a.playbackRate = pitch;
      a.play().catch(() => {});
    };
    const STRIP_W = 700, CELL = 118, BLOT = 140, ICON = 80, RING = 200, KAT_H = 400, GLOW_PAD = 60;
    const MOVE_OFF = [-250, -300], T_SPIN = 0.75, CUT1_U = 0.7, STROKE = 0.13, CUT2_AFTER = 0.12, KAT_LEAD = 0.45, REVEAL_AFTER = 0.45, FLY = 0.75;
    const KAT_FRAMES = 132, KAT_COLS = 12, KAT_FW = 288, KAT_FH = 480;   // кадры 3D-катаны из Godot (preview_loot.gd --kat), 60 к/с от появления
    const W_RAR = [46, 28, 14, 8, 3.2, 0.8], N = 36, WIN = 30, SPIN = 3.6, ROLLS = 3, ROLL_STEP = 250;
    const cv = document.getElementById("lootCv"), cx = cv.getContext("2d");
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
    const sheetImg = {};
    SET_KEYS.forEach(k => { const im = new Image(); im.src = SETS[k].sheet.img; sheetImg[k] = im; });
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
    function tinted(name, hex, cache) {
      if (cache[hex]) return cache[hex];
      const im = IMG[name]; if (!im.complete) return null;
      const c = document.createElement("canvas"); c.width = im.width; c.height = im.height; const g = c.getContext("2d");
      g.drawImage(im, 0, 0); g.globalCompositeOperation = "source-in"; g.fillStyle = hex; g.fillRect(0, 0, c.width, c.height);
      return (cache[hex] = c);
    }
    const glows = {};
    const glow = () => tinted("ink_glow", "rgb(245,224,184)", glows);   // тёплый свет под тушью: читается и на тёмном фоне

    // места прокруток: 0 — правый нижний угол, следующие — выше; справа — колонка сумки
    const slots = Array.from({ length: ROLLS }, (_, i) => {
      const wrap = document.createElement("div"); wrap.className = "lttWrap";
      const tip = document.createElement("div"); tip.className = "tt"; tip.setAttribute("aria-hidden", "true");
      wrap.appendChild(tip); document.body.appendChild(wrap);
      return { i, st: null, wrap, tip };
    });
    let st = null, flights = [], pending = [], last = 0, s = 1, W = 1920, lootN = 0;
    const corner = i => [W - 480, 1080 - 175 - i * ROLL_STEP];
    const freeSlot = () => { const sl = slots.find(x => !x.st && !flights.some(f => f.slot === x.i)); return sl ? sl.i : -1; };

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
    // выпавшая вещь известна заранее: ряд встаёт ровно на ней, катана режет путь прямо перед ней
    function start(slot, forceR, forceMana) {
      const items = []; for (let i = 0; i < N; i++) items.push(i === WIN ? randItem(forceR, forceMana) : randItem(-1));
      const w = items[WIN];
      w.item = makeLoot(w);
      slot.st = { slot, t: 0, items, off0: 2 * CELL, off1: WIN * CELL, tick: -999, cut1: false, cut2: false, revealed: false,
        big: w.r >= 4 || w.mana, tipAt: -1, tipLen: 0, rolls: [], anchor: corner(slot.i) };
      st = slot.st; st.orbAt = revealT() + 1.5;
      play("ink", -13);                                       // прокрутки частые — обычные звуки тихие; громко — только редкая вещь
    }
    const stopT = () => T_SPIN + SPIN, c1T = () => T_SPIN + SPIN * CUT1_U, c2T = () => stopT() + CUT2_AFTER;
    const katT = () => c1T() - KAT_LEAD, revealT = () => c2T() + REVEAL_AFTER;
    const offAt = t => t < T_SPIN ? st.off0 : st.off0 + (st.off1 - st.off0) * (1 - Math.pow(1 - clamp((t - T_SPIN) / SPIN), 3));
    const offset = () => offAt(st.t);
    const gap1 = () => st.off1 - offAt(c1T()) - CELL / 2;                           // промежуток перед вещью в миг первого взмаха
    const v1 = () => (st.off1 - st.off0) * 3 * Math.pow(1 - CUT1_U, 2) / SPIN;      // скорость ряда в этот миг, px/с
    const moveOff = () => [MOVE_OFF[0], Math.max(MOVE_OFF[1], 180 - st.anchor[1])];
    const groupOff = () => { if (!st.big) return [0, 0]; const e = ease((st.t - revealT() - 0.8) / 0.5), m = moveOff(); return [m[0] * e, m[1] * e]; };

    // окно характеристик: та же подсказка, что в инвентаре (render); усиленные и маны статы прокручиваются по очереди
    function openTip() {
      const w = st.items[WIN], ltt = st.slot.tip;
      ltt.style.setProperty("--rc", `var(${RC[w.r]})`);
      ltt.classList.toggle("mana", !!w.mana); ltt.dataset.r = w.r;
      ltt.innerHTML = render(w.item, w.k);
      ltt.querySelectorAll("li.boost").forEach(li => { li.style.setProperty("--bc", `var(${RC[w.r]})`); li.classList.add("b" + w.r); });
      ltt.classList.remove("show"); void ltt.offsetWidth; ltt.classList.add("show");
      st.rolls = [...ltt.querySelectorAll("li.boost, li.mana")].map(li => {
        const e = w.item[li.dataset.part][+li.dataset.j], m = (e.boost ? RAR[w.r].boost : 1) * (e.mana ? MANA.mult : 1);
        const cls = ["boost", "mana", "b" + w.r].filter(c => li.classList.contains(c));
        li.classList.remove(...cls);
        const v = li.querySelector(".v"); v.textContent = fmtR(e.key, e.v / m);
        return { li, v, e, base: e.v / m, cls, step: -1, landed: false };
      });
      play("tipOpen", -6);
      st.tipAt = st.t;
      st.tipLen = 0.35 + (st.rolls.length ? 0.5 + st.rolls.length * 0.6 + 0.45 : 0) + 1.4;
      st.orbAt = st.tipAt + st.tipLen + 0.3;
    }
    const fmtR = (key, v) => fmt(key, STATS[key].pct ? Math.round(v * 10) / 10 : Math.max(1, Math.round(v)));   // как eq.fmt в игре
    function tickRolls() {
      const rt = st.t - st.tipAt - 0.35;
      st.rolls.forEach((ro, i) => {
        const t0 = 0.5 + i * 0.6;
        if (rt < t0 || ro.landed) return;
        if (rt < t0 + 0.45) {
          const step = Math.floor((rt - t0) / 0.05);
          if (step !== ro.step) { if (step === 0) play("statSpin", -8, 0.96 + Math.random() * 0.1); ro.step = step; ro.v.textContent = fmtR(ro.e.key, ro.base + Math.random() * (ro.e.v * 1.15 - ro.base)); }
          return;
        }
        ro.landed = true; ro.v.textContent = fmt(ro.e.key, ro.e.v); ro.li.classList.add(...ro.cls, "landed");
        if (ro.e.mana) play("statMana", -5); else play("statLand", -4, st.items[WIN].r >= 4 ? 0.86 : 1);
      });
    }
    function placeTip() {
      const m = moveOff(), item = [st.anchor[0] + m[0], st.anchor[1] + m[1]], k = 0.82 * s, ltt = st.slot.tip;
      const w = ltt.offsetWidth * k, h = ltt.offsetHeight * k;
      const a = clamp((st.t - st.tipAt) / 0.3) * (1 - clamp((st.t - st.tipAt - st.tipLen) / 0.3));
      const x = (item[0] - RING * 0.5 - 14) * s - w + (1 - a) * 16 * s, y = clamp(item[1] * s - h * 0.45, 20 * s, 1060 * s - h);
      st.slot.wrap.style.transform = `translate(${x}px, ${y}px) scale(${k})`;
      st.slot.wrap.style.opacity = a;
    }

    function frame(now) {
      const dt = Math.min(0.05, (now - (last || now)) / 1000); last = now;
      const dpr = window.devicePixelRatio || 1;
      if (cv.width !== Math.round(innerWidth * dpr) || cv.height !== Math.round(innerHeight * dpr)) { cv.width = Math.round(innerWidth * dpr); cv.height = Math.round(innerHeight * dpr); }
      s = Math.min(innerHeight / 1080, innerWidth / 900); W = innerWidth / s;
      cx.setTransform(1, 0, 0, 1, 0, 0); cx.clearRect(0, 0, cv.width, cv.height);
      cx.setTransform(dpr * s, 0, 0, dpr * s, 0, 0);
      flights = flights.filter(f => {
        f.t += dt;
        if (f.t < 0.8) return true;
        if (f.slot >= 0) start(slots[f.slot], ...f.args); else pending.push(f.args);
        return false;
      });
      if (pending.length) { const i = freeSlot(); if (i >= 0) start(slots[i], ...pending.shift()); }
      flights.forEach(drawFlight);
      for (const sl of slots) {
        if (!sl.st) continue;
        st = sl.st; step(dt);
        if (sl.st) draw();
      }
      drawBagOnce();
      requestAnimationFrame(frame);
    }
    function drawFlight(f) {
      const p0 = [W * 0.5, 620], to = corner(Math.max(0, f.slot)), c = [(p0[0] + to[0]) / 2, (p0[1] + to[1]) / 2 - 260], k = clamp(f.t / 0.8);
      const p = bez(p0, c, to, k), r = 46 - 16 * k, im = IMG.orb_rainbow;
      for (let j = 6; j > 0; j--) { const tp = bez(p0, c, to, Math.max(0, k - j * 0.03)); circle(tp, 14 - j * 1.6, `rgba(255,230,150,${0.06 * (7 - j)})`); }
      cx.save(); cx.translate(p[0], p[1]); cx.rotate(performance.now() / 1000 * 0.9); cx.filter = `hue-rotate(${(performance.now() / 1000 * 80) % 360}deg)`;
      if (im.complete) cx.drawImage(im, -r, -r, r * 2, r * 2); cx.restore();
    }
    function step(dt) {
      st.t += dt;
      if (st.t >= T_SPIN && st.t < c1T()) { const i = Math.floor((offset() + CELL * 0.5) / CELL);
        if (i !== st.tick) { if (st.tick !== -999) play("tick", -17, 0.95 + Math.random() * 0.13); else play("spin", -15); st.tick = i; } }
      if (st.t >= c1T() - 0.04 && !st.cut1) { st.cut1 = true; play("slash", -11); }
      if (st.t >= c2T() - 0.04 && !st.cut2) { st.cut2 = true; play("slash", -14, 1.08); }
      if (st.t >= revealT() && !st.revealed) {
        st.revealed = true;
        const w = st.items[WIN];
        play(st.big ? "epic" : "reveal", st.big ? -3 : -12);
        lootBag[w.k].push(w.item); bag[w.k].push(w.item);     // вещь — в выбор своего слота (клик по слоту в инвентаре ниже)
        const sl = document.getElementById("slot-" + SLOTS[w.k].key); if (sl) { sl.classList.remove("lootNew"); void sl.offsetWidth; sl.classList.add("lootNew"); }
      }
      if (st.big && st.tipAt < 0 && st.t >= revealT() + 1.2) openTip();
      if (st.tipAt >= 0) { tickRolls(); placeTip(); }
      const arrive = st.orbAt + 0.3 + FLY;                    // сфера в сумку: свист, крышка открывается к прилёту и закрывается
      [[st.orbAt, "toBag", -14, 1], [arrive - 0.12, "lid", -15, 1], [arrive + 0.4, "lid", -18, 0.88]].forEach(([t0, n, db, pt]) => { if (st.t >= t0 && st.t - dt < t0) play(n, db, pt); });
      if (st.t >= st.orbAt + 0.3 + FLY + 0.9) { st.slot.wrap.style.opacity = 0; st.slot.st = null; }
    }
    const circle = (p, r, col) => { cx.beginPath(); cx.arc(p[0], p[1], Math.max(0.1, r), 0, Math.PI * 2); cx.fillStyle = col; cx.fill(); };
    function group(pos, rot, fn) { cx.save(); cx.translate(pos[0], pos[1]); cx.rotate(rot); fn(); cx.restore(); }
    function draw() {
      const c = st.anchor, c1 = c1T(), c2 = c2T(), g = groupOff(), orb = clamp((st.t - st.orbAt) / 0.3);
      if (st.t < c1) group(c, 0, () => { drawStripFull(); drawItems(0, N, offset(), 1); });
      else {
        const off1 = offAt(c1), ce1 = clamp((st.t - c1) / 0.8);
        if (ce1 < 1) group([c[0] - v1() * (st.t - c1) * (1 - 0.4 * ce1), c[1] + 90 * ce1 * ce1], -0.1 * ce1, () => {   // путь перед вещью: срезан на ходу — летит дальше
          drawStripPart(-STRIP_W / 2, gap1(), 0, 1 - ce1, true, false); drawItems(0, WIN, off1, 1 - ce1); });
        const d = off1 - offset();                                                             // остаток полосы едет вместе с вещью
        if (st.t < c2) group(c, 0, () => { drawStripPart(gap1(), STRIP_W / 2, d, 1, false, true); drawItems(WIN, N, offset(), 1); });
        else {
          const split = CELL / 2 - d, ce2 = clamp((st.t - c2) / 0.7);
          if (ce2 < 1) group([c[0] + 90 * ce2, c[1] + 80 * ce2 * ce2], 0.1 * ce2, () => { drawStripPart(split, STRIP_W / 2, d, 1 - ce2, false, true); drawItems(WIN + 1, N, offset(), 1 - ce2); });
          group([c[0] + g[0], c[1] + g[1]], 0, () => {
            drawStripPart(gap1(), split, d, (1 - orb) * (1 - clamp((st.t - c2 - 0.3) / 0.4)), false, false); drawItems(WIN, WIN + 1, offset(), 1 - orb); });
        }
      }
      group(c, 0, () => { drawMarker(); drawKatana(); if (st.t >= c1) drawCut(); });
      if (st.t >= revealT() - 0.05) group([c[0] + g[0], c[1] + g[1]], 0, () => drawReveal(revealT(), 1 - orb));
      drawOrb();
    }
    function drawStripFull() {
      const im = IMG.ink_strip; if (!im.complete) return;
      const k = STRIP_W / im.width, h = im.height * k, gr = ease(st.t / 0.5), w = STRIP_W * (0.25 + 0.75 * gr), hh = h * (0.7 + 0.3 * gr);
      const gx = GLOW_PAD * k * w / STRIP_W, gy = GLOW_PAD * k * hh / h, fa = clamp(st.t / 0.25), gl = glow();
      if (gl) { cx.globalAlpha = fa * 0.32; cx.drawImage(gl, -w / 2 - gx, -hh / 2 - gy, w + gx * 2, hh + gy * 2); }
      cx.globalAlpha = fa; cx.drawImage(im, -w / 2, -hh / 2, w, hh); cx.globalAlpha = 1;
    }
    // кусок полосы [x0, x1] (px от центра целой полосы), сдвинутый на shift; свет — с запасом у внешних краёв
    function drawStripPart(x0, x1, shift, a, glowL, glowR) {
      const im = IMG.ink_strip; if (!im.complete || a <= 0.01 || x1 <= x0) return;
      const k = STRIP_W / im.width, h = im.height * k, gp = GLOW_PAD * k, gx0 = x0 - (glowL ? gp : 0), gx1 = x1 + (glowR ? gp : 0), gl = glow();
      if (gl) { cx.globalAlpha = a * 0.32; cx.drawImage(gl, GLOW_PAD + (gx0 + STRIP_W / 2) / k, 0, (gx1 - gx0) / k, gl.height, gx0 + shift, -h / 2 - gp, gx1 - gx0, h + gp * 2); }
      cx.globalAlpha = a; cx.drawImage(im, (x0 + STRIP_W / 2) / k, 0, (x1 - x0) / k, im.height, x0 + shift, -h / 2, x1 - x0, h); cx.globalAlpha = 1;
    }
    function drawItems(from, to, off, a) {
      for (let i = from; i < to; i++) {
        const it = st.items[i], x = i * CELL - off, d = Math.abs(x) / CELL;
        if (d > 3) continue;
        const pop = clamp((st.t - 0.3 - d * 0.07) / 0.25); if (pop <= 0) continue;
        const sc = back(pop), vis = a * (1 - smooth(2, 2.75, d)) * Math.min(1, pop * 2); if (vis <= 0.01) continue;
        const col = rcol(it.r), bl = IMG["blot_" + it.blot], bs = BLOT * sc;
        cx.save(); cx.translate(x, 0);
        cx.save(); cx.rotate(it.rot); cx.globalAlpha = vis; if (bl.complete) cx.drawImage(bl, -bs / 2, -bs / 2, bs, bs); cx.restore();
        for (let q = 0; q < 4; q++) circle([0, 0], ICON * 0.5 * sc * (1.05 + q * 0.12), rgba(col, 0.1 * vis));
        const ic = icon(it.setKey, it.k, it.r), isz = ICON * sc;
        cx.globalAlpha = vis; if (ic) cx.drawImage(ic, -isz / 2, -isz / 2, isz, isz); cx.globalAlpha = 1;
        cx.beginPath(); cx.arc(0, 0, isz / 2 + 1.5, 0, Math.PI * 2); cx.strokeStyle = rgba(col, 0.75 * vis); cx.lineWidth = 1.6; cx.stroke();
        if (it.mana) { cx.beginPath(); cx.arc(0, 0, isz / 2 + 4.5, 0, Math.PI * 2); cx.strokeStyle = `rgba(255,94,209,${0.7 * vis})`; cx.lineWidth = 1.2; cx.stroke(); }
        cx.restore();
      }
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
    // катана — кадры той же 3D-сцены из Godot (в сцене она по центру; по полосе её ведёт katX). Приходит дважды и на вещи
    // не стоит: на ходу рубит путь перед вещью и уходит, после остановки приходит к её правому краю — второй взмах.
    // Во взмахе — шлейф прошлых кадров и блик удара
    const katCut = () => st.t < c1T() + STROKE + 0.45 ? c1T() : c2T();
    const katX = () => katCut() === c1T() ? gap1() : CELL / 2;
    function katFrame(f, x, a, op) {
      f = Math.min(KAT_FRAMES - 1, Math.max(0, f));
      cx.globalAlpha = a; cx.globalCompositeOperation = op;
      cx.drawImage(IMG.katana, (f % KAT_COLS) * KAT_FW, Math.floor(f / KAT_COLS) * KAT_FH, KAT_FW, KAT_FH, x - KAT_H * 0.3, -KAT_H * 0.5 - 30, KAT_H * 0.6, KAT_H);
      cx.globalAlpha = 1; cx.globalCompositeOperation = "source-over";
    }
    function drawKatana() {
      const t0 = katCut(), a = clamp((st.t - t0 + KAT_LEAD) / 0.15) * (1 - clamp((st.t - t0 - STROKE - 0.15) / 0.25));
      if (a <= 0 || !IMG.katana.complete) return;
      const f = Math.floor((st.t - katT()) * 60), x = katX();
      if (st.t >= t0 - 0.02 && st.t < t0 + STROKE + 0.04) [[2, 0.32], [4, 0.2], [6, 0.11]].forEach(([b, ga]) => katFrame(f - b, x, a * ga, "lighter"));
      katFrame(f, x, a, "source-over");
      const u = (st.t - t0 - STROKE * 0.45) / 0.14;                              // блик удара — в миг, когда клинок проходит ряд
      if (u >= 0 && u <= 1) {
        const r = 26 + 40 * u, gr = cx.createRadialGradient(x, 0, 0, x, 0, r);
        gr.addColorStop(0, `rgba(255,255,255,${0.9 * (1 - u)})`); gr.addColorStop(0.35, `rgba(255,236,210,${0.4 * (1 - u)})`); gr.addColorStop(1, "rgba(255,236,210,0)");
        cx.globalCompositeOperation = "lighter"; cx.fillStyle = gr; cx.fillRect(x - r, -r, r * 2, r * 2);
        cx.fillStyle = `rgba(255,255,255,${0.85 * (1 - u)})`; cx.fillRect(x - 60 * (1 - u * 0.5), -1, 120 * (1 - u * 0.5), 2);
        cx.globalCompositeOperation = "source-over";
      }
    }
    function drawCut() {
      const sl = IMG.slash; if (!sl.complete) return;
      const h = 300, w = sl.width * h / sl.height;
      for (let n = 0; n < 2; n++) {
        const t0 = n === 0 ? c1T() : c2T(), u = clamp((st.t - t0) / STROKE), a = 1 - clamp((st.t - t0 - 0.4) / 0.35);
        if (u <= 0 || a <= 0) continue;
        const x = n === 0 ? gap1() : CELL / 2;
        cx.globalAlpha = a; cx.drawImage(sl, 0, 0, sl.width, sl.height * u, x - w / 2, -h / 2, w, h * u);
        const sp = clamp((st.t - t0 - 0.05) / 0.25);
        if (sp > 0) { const im = IMG[n === 0 ? "splat_l" : "splat_r"], sw = 190 * (0.6 + 0.4 * sp), sh = im.height * sw / im.width;
          cx.drawImage(im, n === 0 ? x - sw : x, 30 - sh / 2, sw, sh); }
        cx.globalAlpha = 1;
      }
    }
    function drawReveal(reveal, fade) {
      const w = st.items[WIN], col = rcol(w.r), u = clamp((st.t - reveal) / 0.35), e = ease(u), a = u * fade; if (a <= 0) return;
      const rg = tinted("ink_ring", col, rings), rs = RING * (1.5 - 0.5 * e);
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
    // сумка этой вещи: [видимость, открыта, «подпрыгивание»] — рисуется одна на все прокрутки (drawBagOnce)
    function bagState() {
      const t0 = st.orbAt, arrive = t0 + 0.3 + FLY;
      return [clamp((st.t - t0 + 0.2) / 0.3) * (1 - clamp((st.t - arrive - 0.5) / 0.4)), st.t >= arrive - 0.12 && st.t < arrive + 0.4,
        1 + 0.12 * Math.max(0, 1 - Math.abs(st.t - arrive) / 0.25)];
    }
    const bagPos = () => [W - 70, 1080 - 120];
    // сфера вещи, летящая в сумку (сумка поверх — сфера в неё «входит»)
    function drawOrb() {
      const t0 = st.orbAt, arrive = t0 + 0.3 + FLY;
      if (st.t < t0 || st.t > arrive) return;
      const bag = bagPos(), w = st.items[WIN], col = rcol(w.r), g = groupOff(), from = [st.anchor[0] + g[0], st.anchor[1] + g[1]];
      const k = clamp((st.t - t0 - 0.3) / FLY), shrink = clamp((st.t - t0) / 0.3);
      const ctrl = [(from[0] + bag[0]) / 2 + 40, (from[1] + bag[1]) / 2 - 180], p = bez(from, ctrl, bag, k), r = (40 - 26 * shrink) * (1 - 0.3 * k);
      if (k > 0) for (let j = 6; j > 0; j--) circle(bez(from, ctrl, bag, Math.max(0, k - j * 0.035)), r * (1 - j * 0.12), rgba(col, 0.06 * (7 - j)));
      for (let q = 0; q < 4; q++) circle(p, r * (1.3 + q * 0.35), rgba(col, 0.12));
      circle(p, r, rgba(col, 1)); circle(p, r * 0.55, "rgba(255,255,255,.95)");
      if (shrink < 1) { const ic = icon(w.setKey, w.k, w.r), isz = ICON * (1 - shrink); cx.globalAlpha = 1 - shrink; if (ic) cx.drawImage(ic, p[0] - isz / 2, p[1] - isz / 2, isz, isz); cx.globalAlpha = 1; }
    }
    // сумка в правом нижнем углу — одна: видна, пока в неё летит хоть одна вещь; открывается к каждому прилёту
    function drawBagOnce() {
      let a = 0, open = false, bump = 1;
      for (const sl of slots) if (sl.st) { st = sl.st; const b = bagState(); a = Math.max(a, b[0]); open = open || b[1]; bump = Math.max(bump, b[2]); }
      if (a <= 0) return;
      const bag = bagPos(), bi = IMG[open ? "bag_open" : "bag_closed"], bh = 140 * bump, bw = bi.width * bh / (bi.height || 1);
      cx.globalAlpha = a; if (bi.complete) cx.drawImage(bi, bag[0] - bw / 2, bag[1] - bh / 2, bw, bh); cx.globalAlpha = 1;
    }
    requestAnimationFrame(frame);
    // радужная сфера летит к свободному месту → прокрутка; мест нет — ждёт в очереди
    return {
      roll(forceR, forceMana) {
        const it = randItem(forceR < 0 ? -1 : forceR, forceMana);
        flights.push({ t: 0, args: [it.r, it.mana], slot: pending.length ? -1 : freeSlot() });
        play("ink", -19, 1.3);
      },
      sound(on) { soundOn = on; },
    };
  })();
