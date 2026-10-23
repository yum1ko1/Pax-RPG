// Итог на моделях Meshy: в допуске полпикселя снимает лишь 1–13 % граней (у Meshy почти каждое ребро — шов UV) — в игру
// копии не пошли. Для моделей с нормальной развёрткой — рабочий инструмент.
// LOD-копии неподвижных моделей без рваных швов: <id>.glb → <id>_lod1.glb (с LOD_NEAR м) и <id>_lod2.glb (с LOD_MID м).
// Упрощение — meshoptimizer (как gltfpack и LOD самого Godot): он видит швы развёртки и жёсткие рёбра (одна точка — разные
// UV/нормали) и сводит рёбра вдоль шва только парой, поэтому щелей по швам нет. Прежний make_lods.py (Blender Decimate)
// без склейки вершин рвал швы, со склейкой — тянул шипы.
// Без потери качества: допуск — полпикселя на дальности включения копии при рендере 2160 строк и FOV 60° (худший случай
// настроек), нормали — до ~3°, развёртка — в мерах модели; если допуск не даёт ужать до доли r1/r2 — граней остаётся больше.
// Вершины копии — те же (позиция, нормаль, UV не пересчитываются), рамка модели та же (крайние точки закреплены — по ней
// шейдер ветра считает высоту), материалы и картинки — те же, поверхности в том же порядке (assets.gd → lod_base).
//   cd pax_rpg/dev/assets/lods && npm i && node lods.mjs <папка models> <id,id,...> [r1=0.30] [r2=0.12] [--dry]
// <id> — путь без .glb от папки models (gharn/hay_wagon). Масштаб копий в городе — из config/gharn_map.json (наибольший).
import fs from "node:fs";
import path from "node:path";
import { MeshoptSimplifier as S, MeshoptEncoder as E } from "meshoptimizer";

const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const DRY = process.argv.includes("--dry");
const ROOT = args[0];
const IDS = args[1].split(",");
const RATIO = [parseFloat(args[2] ?? "0.30"), parseFloat(args[3] ?? "0.12")];
const DIST = [55.0, 120.0];                       // city.gd: LOD_NEAR, LOD_MID
const PX = (2 * Math.tan((60 / 2) * Math.PI / 180)) / 2160;   // метров на пиксель на 1 м дальности
const NORMAL_TOL = 0.05;                          // отклонение нормали (~3°), равное всему допуску
const MIN_TRIS = 300;

await S.ready;
await E.ready;

// наибольший масштаб модели на карте (s у точек gharn_map.json)
const maxScale = {};
{
	const mapPath = path.join(ROOT, "..", "config", "gharn_map.json");
	const walk = (o) => {
		if (Array.isArray(o)) return o.forEach(walk);
		if (o && typeof o === "object") {
			const m = o.m ?? o.model ?? o.path;
			if (typeof m === "string" && m.endsWith(".glb")) {
				const k = path.basename(m);
				maxScale[k] = Math.max(maxScale[k] ?? 0, Number(o.s ?? 1));
			}
			Object.values(o).forEach(walk);
		}
	};
	if (fs.existsSync(mapPath)) walk(JSON.parse(fs.readFileSync(mapPath, "utf8")));
}

function readGlb(file) {
	const b = fs.readFileSync(file);
	if (b.readUInt32LE(0) !== 0x46546c67) throw new Error("not glb: " + file);
	const jl = b.readUInt32LE(12);
	const json = JSON.parse(b.subarray(20, 20 + jl).toString("utf8"));
	const bin = b.subarray(20 + jl + 8, 20 + jl + 8 + b.readUInt32LE(20 + jl));
	return { json, bin };
}

const COMP = { 5126: [Float32Array, 4], 5125: [Uint32Array, 4], 5123: [Uint16Array, 2], 5121: [Uint8Array, 1] };
const NC = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };

// аксессор → плотный массив его типа (count × компоненты)
function readAcc(g, ai) {
	const a = g.json.accessors[ai];
	const bv = g.json.bufferViews[a.bufferView];
	const [T, sz] = COMP[a.componentType];
	const nc = NC[a.type];
	const stride = bv.byteStride ?? nc * sz;
	const out = new T(a.count * nc);
	const base = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0);
	const dv = new DataView(g.bin.buffer, g.bin.byteOffset, g.bin.byteLength);
	for (let i = 0; i < a.count; i++)
		for (let c = 0; c < nc; c++) {
			const o = base + i * stride + c * sz;
			out[i * nc + c] = sz === 4 ? (T === Float32Array ? dv.getFloat32(o, true) : dv.getUint32(o, true))
				: sz === 2 ? dv.getUint16(o, true) : dv.getUint8(o);
		}
	return { data: out, acc: a, nc };
}

// масштаб узла сетки в модели (произведение масштабов по цепочке родителей)
function meshScale(json, mi) {
	const parent = {};
	json.nodes.forEach((n, i) => (n.children ?? []).forEach((c) => (parent[c] = i)));
	let best = 0;
	json.nodes.forEach((n, i) => {
		if (n.mesh !== mi) return;
		let s = 1;
		for (let k = i; k !== undefined; k = parent[k]) {
			const nd = json.nodes[k];
			if (nd.matrix) s *= Math.hypot(nd.matrix[0], nd.matrix[1], nd.matrix[2]);
			else if (nd.scale) s *= Math.max(...nd.scale.map(Math.abs));
		}
		best = Math.max(best, s);
	});
	return best || 1;
}

function simplifyPrim(g, prim, level, worldScale) {
	const P = readAcc(g, prim.attributes.POSITION);
	const N = prim.attributes.NORMAL !== undefined ? readAcc(g, prim.attributes.NORMAL) : null;
	const U = prim.attributes.TEXCOORD_0 !== undefined ? readAcc(g, prim.attributes.TEXCOORD_0) : null;
	const I = Uint32Array.from(readAcc(g, prim.indices).data);
	const vc = P.acc.count;
	const pos = Float32Array.from(P.data);
	// допуск в единицах сетки
	const err = (0.5 * PX * DIST[level]) / worldScale;
	const ext = Math.max(...[0, 1, 2].map((c) => P.acc.max[c] - P.acc.min[c]));
	const na = (N ? 3 : 0) + (U ? 2 : 0);
	const attrs = new Float32Array(vc * Math.max(na, 1));
	const w = [];
	if (N) w.push(...Array(3).fill(err / NORMAL_TOL));
	if (U) w.push(...Array(2).fill(ext));          // сдвиг UV на Δ ≈ сдвиг текстуры на Δ·размер модели
	for (let i = 0; i < vc; i++) {
		let k = 0;
		if (N) for (let c = 0; c < 3; c++) attrs[i * na + k++] = N.data[i * 3 + c];
		if (U) for (let c = 0; c < 2; c++) attrs[i * na + k++] = U.data[i * 2 + c];
	}
	// крайние точки по осям (со всеми их копиями по швам) закреплены — рамка модели не меняется
	const lock = new Uint8Array(vc);
	for (let c = 0; c < 3; c++)
		for (const v of [P.acc.min[c], P.acc.max[c]])
			for (let i = 0; i < vc; i++) if (pos[i * 3 + c] === v) lock[i] = 1;
	const tris = I.length / 3;
	const target = Math.max(RATIO[level], MIN_TRIS / tris);
	const [out, e] = S.simplifyWithAttributes(I, pos, 3, attrs, Math.max(na, 1), na ? w : [0], lock,
		Math.floor((tris * target)) * 3, err, (process.env.PERM ? ["LockBorder", "ErrorAbsolute", "Permissive"] : ["LockBorder", "ErrorAbsolute"]));
	const [remap, unique] = E.reorderMesh(out, true, false);   // кэш вершин + плотный порядок, лишние вершины — прочь
	return { P, N, U, idx: out, remap, unique, tris0: tris, tris1: out.length / 3, err: e * worldScale };
}

function writeGlb(g, prims, file) {
	const json = JSON.parse(JSON.stringify(g.json));
	const chunks = [];
	let off = 0;
	const views = [];
	const push = (u8, target) => {
		const pad = (4 - (off % 4)) % 4;
		if (pad) { chunks.push(Buffer.alloc(pad)); off += pad; }
		chunks.push(Buffer.from(u8.buffer, u8.byteOffset, u8.byteLength));
		views.push({ buffer: 0, byteOffset: off, byteLength: u8.byteLength, ...(target ? { target } : {}) });
		off += u8.byteLength;
		return views.length - 1;
	};
	// картинки — как были
	for (const im of json.images ?? []) {
		if (im.bufferView === undefined) continue;
		const bv = g.json.bufferViews[im.bufferView];
		im.bufferView = push(new Uint8Array(g.bin.buffer, g.bin.byteOffset + (bv.byteOffset ?? 0), bv.byteLength));
	}
	const accs = [];
	const addAcc = (src, data, nc, extra) => {
		const v = push(data, src ? 34962 : 34963);
		accs.push({ bufferView: v, componentType: extra.componentType, count: data.length / nc, type: extra.type, ...extra.more });
		return accs.length - 1;
	};
	json.meshes.forEach((m, mi) => m.primitives.forEach((p, pi) => {
		const r = prims[mi][pi];
		const n = r.unique;
		const gather = (A) => {
			const o = new Float32Array(n * A.nc);
			for (let i = 0; i < r.remap.length; i++) {
				const t = r.remap[i];
				if (t === 0xffffffff) continue;
				for (let c = 0; c < A.nc; c++) o[t * A.nc + c] = A.data[i * A.nc + c];
			}
			return o;
		};
		const pos = gather(r.P);
		const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
		for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) {
			mn[c] = Math.min(mn[c], pos[i * 3 + c]); mx[c] = Math.max(mx[c], pos[i * 3 + c]);
		}
		const attributes = { POSITION: addAcc(true, pos, 3, { componentType: 5126, type: "VEC3", more: { min: mn, max: mx } }) };
		if (r.N) attributes.NORMAL = addAcc(true, gather(r.N), 3, { componentType: 5126, type: "VEC3" });
		if (r.U) attributes.TEXCOORD_0 = addAcc(true, gather(r.U), 2, { componentType: 5126, type: "VEC2" });
		const idx = n < 65536 ? Uint16Array.from(r.idx) : r.idx;
		const indices = addAcc(false, idx, 1, { componentType: n < 65536 ? 5123 : 5125, type: "SCALAR" });
		m.primitives[pi] = { ...p, attributes, indices };
	}));
	json.accessors = accs;
	json.bufferViews = views;
	const bin = Buffer.concat(chunks);
	const binPad = Buffer.concat([bin, Buffer.alloc((4 - (bin.length % 4)) % 4)]);
	json.buffers = [{ byteLength: binPad.length }];
	let js = Buffer.from(JSON.stringify(json), "utf8");
	js = Buffer.concat([js, Buffer.alloc((4 - (js.length % 4)) % 4, 0x20)]);
	const head = Buffer.alloc(12);
	head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(12 + 8 + js.length + 8 + binPad.length, 8);
	const ch = (len, type) => { const b = Buffer.alloc(8); b.writeUInt32LE(len, 0); b.writeUInt32LE(type, 4); return b; };
	fs.writeFileSync(file, Buffer.concat([head, ch(js.length, 0x4e4f534a), js, ch(binPad.length, 0x004e4942), binPad]));
}

for (const id of IDS) {
	const src = path.join(ROOT, id + ".glb");
	const g = readGlb(src);
	if (g.json.skins?.length || g.json.animations?.length) { console.log(`${id}: скин/анимация — пропуск`); continue; }
	const place = maxScale[path.basename(src)] ?? 1;
	const line = [];
	for (let level = 0; level < 2; level++) {
		let t0 = 0, t1 = 0, e = 0;
		const prims = g.json.meshes.map((m, mi) => m.primitives.map((p) => {
			if ((p.mode ?? 4) !== 4 || p.indices === undefined) throw new Error(`${id}: не треугольники с индексами`);
			const r = simplifyPrim(g, p, level, meshScale(g.json, mi) * place);
			t0 += r.tris0; t1 += r.tris1; e = Math.max(e, r.err);
			return r;
		}));
		const out = path.join(ROOT, `${id}_lod${level + 1}.glb`);
		if (!DRY) writeGlb(g, prims, out);
		line.push(`lod${level + 1} ${t1} (${(100 * t1 / t0).toFixed(0)} %, ошибка ${(e * 1000).toFixed(1)} мм)`);
		if (level === 0) line.unshift(`${id}: ${t0} гр., масштаб ×${place}`);
	}
	console.log(line.join(" · "));
}
