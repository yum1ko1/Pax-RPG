// Геометрия LOD-копии для пересборки (lod_bake.py): сетка сварена по точкам (у Meshy почти каждое ребро — шов UV, без
// сварки её не упростить, не порвав) и упрощена meshoptimizer в допуске — полпикселя на дальности включения копии при
// рендере 2160 строк и FOV 60° (как lods.mjs). Выход — glb только с позициями и теми же узлами;
// развёртку, сглаживание и текстуры делает lod_bake.py (запекание с исходника).
//   node weld.mjs <вход.glb> <выход.glb> <дальность включения, м> [масштаб на карте]
import fs from "node:fs";
import { MeshoptSimplifier as S, MeshoptEncoder as E } from "meshoptimizer";

const [src, out, distArg, placeArg] = process.argv.slice(2);
const PX = (2 * Math.tan((60 / 2) * Math.PI / 180)) / 2160;
await S.ready;
await E.ready;

const b = fs.readFileSync(src);
const jl = b.readUInt32LE(12);
const json = JSON.parse(b.subarray(20, 20 + jl).toString("utf8"));
const bin = b.subarray(28 + jl, 28 + jl + b.readUInt32LE(20 + jl));
const NC = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 };

function read(ai) {
	const a = json.accessors[ai];
	const bv = json.bufferViews[a.bufferView];
	const nc = NC[a.type];
	const sz = { 5126: 4, 5125: 4, 5123: 2, 5121: 1 }[a.componentType];
	const stride = bv.byteStride ?? nc * sz;
	const base = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0);
	const o = a.componentType === 5126 ? new Float32Array(a.count * nc) : new Uint32Array(a.count * nc);
	for (let i = 0; i < a.count; i++)
		for (let c = 0; c < nc; c++) {
			const p = base + i * stride + c * sz;
			o[i * nc + c] = a.componentType === 5126 ? bin.readFloatLE(p) : sz === 4 ? bin.readUInt32LE(p) : sz === 2 ? bin.readUInt16LE(p) : bin[p];
		}
	return o;
}

function nodeScale(mi) {
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

const chunks = [];
let off = 0;
const views = [], accs = [];
const push = (arr, target) => {
	const pad = (4 - (off % 4)) % 4;
	if (pad) { chunks.push(Buffer.alloc(pad)); off += pad; }
	chunks.push(Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength));
	views.push({ buffer: 0, byteOffset: off, byteLength: arr.byteLength, target });
	off += arr.byteLength;
	return views.length - 1;
};
let t0 = 0, t1 = 0;
json.meshes.forEach((m, mi) => {
	const err = (0.5 * PX * Number(distArg)) / (nodeScale(mi) * Number(placeArg ?? 1));
	m.primitives = m.primitives.map((p) => {
		const pos = read(p.attributes.POSITION);
		const idx = read(p.indices);
		// сварка точно совпадающих позиций
		const key = new Map(), up = [], remap = new Uint32Array(pos.length / 3);
		for (let i = 0; i < remap.length; i++) {
			const k = pos[i * 3] + "," + pos[i * 3 + 1] + "," + pos[i * 3 + 2];
			if (!key.has(k)) { key.set(k, up.length / 3); up.push(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]); }
			remap[i] = key.get(k);
		}
		const P = Float32Array.from(up);
		const I = Uint32Array.from(idx, (x) => remap[x]);
		const vc = P.length / 3;
		const mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
		for (let i = 0; i < vc; i++)
			for (let c = 0; c < 3; c++) { mn[c] = Math.min(mn[c], P[i * 3 + c]); mx[c] = Math.max(mx[c], P[i * 3 + c]); }
		const [o] = S.simplify(I, P, 3, 3, err, ["ErrorAbsolute"]);
		const [rm, n] = E.reorderMesh(o, true, false);
		const P2 = new Float32Array(n * 3);
		for (let i = 0; i < rm.length; i++) if (rm[i] !== 0xffffffff) for (let c = 0; c < 3; c++) P2[rm[i] * 3 + c] = P[i * 3 + c];
		t0 += I.length / 3; t1 += o.length / 3;
		const pa = accs.push({ bufferView: push(P2, 34962), componentType: 5126, count: n, type: "VEC3", min: mn, max: mx }) - 1;
		const ia = accs.push({ bufferView: push(o, 34963), componentType: 5125, count: o.length, type: "SCALAR" }) - 1;
		return { attributes: { POSITION: pa }, indices: ia };
	});
});
delete json.materials; delete json.textures; delete json.images; delete json.samplers;
json.accessors = accs;
json.bufferViews = views;
let body = Buffer.concat(chunks);
body = Buffer.concat([body, Buffer.alloc((4 - (body.length % 4)) % 4)]);
json.buffers = [{ byteLength: body.length }];
let js = Buffer.from(JSON.stringify(json));
js = Buffer.concat([js, Buffer.alloc((4 - (js.length % 4)) % 4, 0x20)]);
const head = Buffer.alloc(12);
head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(28 + js.length + body.length, 8);
const ch = (len, t) => { const x = Buffer.alloc(8); x.writeUInt32LE(len, 0); x.writeUInt32LE(t, 4); return x; };
fs.writeFileSync(out, Buffer.concat([head, ch(js.length, 0x4e4f534a), js, ch(body.length, 0x004e4942), body]));
console.log(`weld ${src.split("/").pop()}: ${t0} → ${t1} граней (${(100 * t1 / t0).toFixed(0)} %)`);
