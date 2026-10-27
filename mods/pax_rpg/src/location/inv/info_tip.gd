extends Control
## Окна описаний: приём оружия (урон, ХА, откат, ролик), пассив Тянь Лун, репутация (шкала, империи), ранг (шкала,
## условия). Рамка — лист деталей окон (wf_frame: сакура, ромб сверху, гнездо кольца закрепления). Цифры и строки,
## у которых есть разбор, попадают в hovers — их подсказку показывает inventory.gd, когда окно закреплено.

const Ui := preload("res://mods/pax_rpg/src/location/inv/ui.gd")

var ui: Ui
var eq: RefCounted
var hovers: Array = []               # [{rect (локальный), kind, arg}]
var ring: TextureProgressBar
var seal: TextureRect
var glow: Control
var color := Color(0.79, 0.64, 0.36)
var on_meta: Callable                # (kind, arg, on, global_rect) — наведение на число в тексте
var _frame: Control
var _w := 300.0
var _y := 0.0
var _video: VideoStreamPlayer


func _begin(u: Ui, e: RefCounted, w: float) -> void:
	ui = u
	eq = e
	_w = w
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	hovers = []
	_video = null
	glow = Control.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate.a = 0.0
	add_child(glow)
	_frame = ui.frame(self, "wf_frame.png", [68, 83, 65, 65], 0.5, Rect2(0, 0, w, 120))
	_y = 22.0


func _end() -> void:
	var h := _y + 22.0
	Ui.frame_resize(_frame, Vector2(_w, h))
	size = Vector2(_w, h)
	ui.pic(self, "wf_gem.png", Rect2(_w * 0.5 - 18, -2, 36, 19))
	var g := ui.frame(glow, "wf_frame.png", [68, 83, 65, 65], 0.5, Rect2(-5, -5, _w + 10, h + 10))
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	(g.get_meta(&"np") as CanvasItem).material = m
	(g.get_meta(&"np") as CanvasItem).modulate = Color(color.r, color.g, color.b, 0.5)
	ring = TextureProgressBar.new()
	ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	ring.texture_under = ui.tex("ring_empty.png")
	ring.texture_progress = ui.tex("ring_full.png")
	ring.nine_patch_stretch = true
	ring.max_value = 1.0
	ring.step = 0.0
	ring.position = Vector2(_w - 15.75 - 9, 11.75 - 9)
	ring.size = Vector2(18, 18)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	seal = ui.pic(self, "ring_seal.png", Rect2(ring.position, ring.size))
	seal.pivot_offset = ring.size * 0.5
	seal.modulate.a = 0.0


func set_arm(p: float) -> void:
	if is_instance_valid(ring):
		ring.value = p


func set_pinned(on: bool) -> void:
	if is_instance_valid(seal):
		seal.modulate.a = 1.0 if on else 0.0
	if is_instance_valid(ring):
		ring.value = 1.0 if on else 0.0


## Шапка: иконка в золотом гнезде (приём, пассив) или медальон (репутация, ранг), название, подзаголовок.
func _head(icon: String, socket: bool, title: String, sub: String) -> void:
	var x := 19.0
	if socket:
		ui.pic(self, "wf_socket.png", Rect2(x, _y, 52, 52))
		var ic := ui.pic(self, icon, Rect2(x + 10, _y + 10, 32, 32), false)   # поверх тёмного дна гнезда
		ic.material = _circle_mat()
	else:
		ui.pic(self, icon, Rect2(x, _y, 52, 52))
	var tl := ui.label(self, title.to_upper(), ui.caps(14, 0.1), 14, Ui.TEXT, Vector2(x + 62, _y + 4), _w - x - 62 - 26)
	ui.label(self, sub, ui.body, 11, Ui.GOLD, Vector2(x + 62, _y + 6 + tl.size.y), _w - x - 62 - 20)
	_y += 60


func _circle_mat() -> ShaderMaterial:
	var sh: Shader = ui.mod.shader("shaders/inv_circle.gdshader")
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _para(bb: String, fs := 13) -> void:
	var r := ui.rich(self, bb, fs, Vector2(19, _y), _w - 38, _meta)
	_y += r.size.y + 6


func _meta(meta: String, on: bool, r: RichTextLabel) -> void:
	if on_meta.is_valid():
		var p := meta.split(":")
		on_meta.call(p[0], p[1] if p.size() > 1 else "", on, Rect2(get_global_mouse_position() - Vector2(4, 8), Vector2(8, 16)))


static func num(kind: String, arg: String, text: String) -> String:
	return "[url=%s:%s][color=#fff3dc][b]%s[/b][/color][/url]" % [kind, arg, text]


# ── урон приёма: база × уровень героя (+3 % за уровень) × оружие от характеристик (как Progress.scaling_mult)
static func saturation(v: float) -> float:
	var pts := [[10.0, 0.0], [20.0, 0.35], [40.0, 0.75], [60.0, 0.9], [99.0, 1.0]]
	if v <= 10.0:
		return 0.0
	for i: int in range(1, pts.size()):
		if v <= float(pts[i][0]):
			return lerpf(float(pts[i - 1][1]), float(pts[i][1]), (v - float(pts[i - 1][0])) / (float(pts[i][0]) - float(pts[i - 1][0])))
	return 1.0


func dmg_calc(sk: String, lvl: int, attrs: Dictionary) -> Dictionary:
	var S: Dictionary = (eq.d["skills"] as Dictionary)[sk]
	var weapon := "spear" if sk in ["sunset", "vine"] else "katana"
	var scaling: Dictionary = ((eq.d["weapons"] as Dictionary)[weapon] as Dictionary)["scaling"]
	var lm := 1.0 + 0.03 * (lvl - 1)
	var parts: Array = []
	var wm := 1.0
	for k: String in scaling:
		var add := float((eq.d["grades"] as Dictionary).get(str(scaling[k]), 0.0)) * saturation(float(attrs.get(k, 0)))
		parts.append([k, str(scaling[k]), int(attrs.get(k, 0)), add])
		wm += add
	var one := float(S["base"]) * lm * wm
	var hits: Array = []
	var total := 0
	for h: Variant in S.get("hits", [1]):
		hits.append(int(roundf(one * float(h))))
		total += int(roundf(one * float(h)))
	return {"S": S, "lm": lm, "parts": parts, "hits": hits, "total": total, "lvl": lvl}


func build_skill(u: Ui, e: RefCounted, sk: String, title: String, sub: String, lvl: int, attrs: Dictionary) -> void:
	_begin(u, e, 300.0)
	var S: Dictionary = (eq.d["skills"] as Dictionary)[sk]
	_head(str(S["icon"]), true, title, sub)
	var dc := dmg_calc(sk, lvl, attrs)
	for t: Variant in S.get("text", []):
		var s := str(t)
		s = s.replace("{range}", str(int(S.get("range", 0))))
		s = s.replace("{dmg}", num("dmg", sk, str(dc["total"])))
		if S.has("conc"):
			s = s.replace("{conc}", num("conc", sk, "−%d" % int(S["conc"])))
		if S.has("conc_boss"):
			s = s.replace("{conc}", num("conc", sk, "−%d %%" % int(S["conc_boss"])))
		_para(s)
	var cost := "Откат %d с" % int(S["cd"])
	if S.has("ha"):
		cost = "Стоимость %s · откат %d с" % [num("ha", sk, "%d ХА" % int(S["ha"])), int(S["cd"])]
	_para("[color=#ecdfcb]%s[/color]" % cost, 13)
	if bool(S.get("draft", false)):
		ui.label(self, "Числа предварительные", ui.italic, 12, Ui.MUTED, Vector2(19, _y))
		_y += 18
	if S.has("clip"):
		_y += 4
		var vw := _w - 38
		var vh := vw * 246.0 / 480.0
		ui.pic(self, "wf_video.png", Rect2(19, _y, vw, vh), false)
		_video = VideoStreamPlayer.new()
		var st := VideoStreamTheora.new()
		st.file = ui.mod.path(str(S["clip"]))
		_video.stream = st
		_video.loop = true
		_video.autoplay = true
		_video.expand = true
		_video.position = Vector2(19 + vw * 0.034, _y + vh * 0.045)
		_video.size = Vector2(vw * 0.932, vh * 0.91)
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_video.volume_db = -80.0
		add_child(_video)
		_y += vh + 4
	_end()


func breakdown(kind: String, sk: String, lvl: int, attrs: Dictionary) -> Array:
	var S: Dictionary = (eq.d["skills"] as Dictionary)[sk]
	if kind == "dmg":
		var dc := dmg_calc(sk, lvl, attrs)
		var rows: Array = [["База приёма", str(S["base"])]]
		if (S.get("hits", []) as Array).size() > 1:
			var hs: PackedStringArray = []
			for h: Variant in S["hits"]:
				hs.append("%d %%" % roundi(float(h) * 100))
			rows.append(["Удары, доля базы", " / ".join(hs)])
		rows.append(["Уровень Тянь Лун %d" % lvl, "+%d %%" % roundi((float(dc["lm"]) - 1.0) * 100)])
		var names := {"agility": "Ловкость", "strength": "Сила"}
		for p: Array in dc["parts"]:
			rows.append(["%s %d (оценка %s)" % [names.get(p[0], p[0]), int(p[2]), p[1]], "+%d %%" % roundi(float(p[3]) * 100)])
		if (dc["hits"] as Array).size() > 1:
			var hs2: PackedStringArray = []
			for h: Variant in dc["hits"]:
				hs2.append(str(h))
			rows.append(["По ударам", " + ".join(hs2)])
		rows.append(["Итого", str(dc["total"]), true])
		return ["Урон: %d" % int(dc["total"]), "", rows]
	if kind == "ha":
		return ["Стоимость: %d ХА" % int(S["ha"]), "Приём тратит ХА Тянь Лун — выдержку бойца: ХА уходит на удары и приёмы и восстанавливается, пока она не бьёт; на 0 — слом.", []]
	var row: Array = ["У босса", "−%d %% полоски" % int(S["conc_boss"])] if S.has("conc_boss") else \
		["Обычный враг, из 100", "−%d%s" % [int(S.get("conc", 0)), " за удар" if (S.get("hits", []) as Array).size() > 1 else ""]]
	return ["ХА врага", "Выдержка врага: в начале боя у всех 100, на 0 — слом и окно Кровожадной атаки.", [row]]


func build_passive(u: Ui, e: RefCounted) -> void:
	_begin(u, e, 300.0)
	var P: Dictionary = eq.d["passive"]
	_head("pas_dance.jpg", true, str(P["name"]), "Пассивный навык · Тянь Лун")
	_section("Плащ по плечу", ["Плащи на Тянь Лун: все статы плаща ×%s." % str(P["cloak"]).replace(".", ",")])
	_section("Танец без ран", ["Удары подряд, пока Тянь Лун не получает урон, усиливают каждый следующий удар:"])
	for s: Array in P["streak"]:
		ui.label(self, "больше %d ударов" % int(s[0]), ui.body, 13, Ui.MUTED, Vector2(19, _y))
		ui.label(self, "+%d %% урона" % int(s[1]), ui.body, 13, Ui.TEXT, Vector2(150, _y))
		_y += 19
	_para("Пропущенный удар обнуляет серию.")
	var syn: Dictionary = P["synergy"]
	_section("Синергия: " + str(((eq.d["weapons"] as Dictionary)[syn["weapon"]] as Dictionary)["name"]),
		["Когда копьё в руках (основное оружие): Ловкость ×%s, ХА восстанавливается в %s раза быстрее." % [str(syn["agi"]).replace(".", ","), str(syn["ha"]).replace(".", ",")]])
	_end()


func _section(title: String, paras: Array) -> void:
	_y += 4
	ui.pic(self, "wf_div.png", Rect2(_w * 0.24, _y, _w * 0.52, _w * 0.52 * 62.0 / 469.0), false)
	_y += 22
	ui.label(self, title.to_upper(), ui.caps(12, 0.06), 12, Color(0.94, 0.81, 0.54), Vector2(19, _y))
	_y += 20
	for p: Variant in paras:
		_para(str(p))


## Шкала: значки ступеней над серединами отрезков (текущая — подсвечена), желобок с цветами ступеней, ромб — значение.
func _scale_bar(icons: Array, colors: Array, cur: int, t: float, kind: String, ends: bool) -> void:
	var x0 := 23.0
	var bw := _w - 46.0
	var n := icons.size()
	for i: int in n:
		var on := i == cur
		var sz := 38.0 if on else 30.0
		var cx := x0 + bw * (i + 0.5) / n
		var p := ui.pic(self, str(icons[i]), Rect2(cx - sz * 0.5, _y + (38 - sz), sz, sz))
		if not on:
			p.modulate = Color(0.55, 0.52, 0.5, 0.5)
		hovers.append({"rect": Rect2(cx - 16, _y + 4, 32, 34), "kind": kind, "arg": i})
	_y += 46
	var by := _y
	var c := Control.new()
	c.position = Vector2(x0, by)
	c.size = Vector2(bw, 10)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		for i: int in n:
			var col: Color = colors[i]
			c.draw_rect(Rect2(bw * i / n, 1, bw / n, 8), Color(col.r, col.g, col.b, 0.42))
		for i: int in range(1, n):
			c.draw_line(Vector2(bw * i / n, -1), Vector2(bw * i / n, 11), Color(0.04, 0.02, 0.03, 0.9), 1.0))
	add_child(c)
	ui.pic(self, "wf_track.png", Rect2(x0 - 7, by - 5, bw + 14, 20), false)
	var mk := ui.pic(self, "wf_marker.png", Rect2(x0 + bw * t - 11, by - 6, 22, 22))
	mk.modulate = Color(1, 1, 1).lerp(colors[cur], 0.25)
	_y += 18
	if ends:
		ui.label(self, "−100", ui.body, 11, Ui.MUTED, Vector2(x0, _y))
		var z := ui.label(self, "0", ui.body, 11, Ui.MUTED, Vector2.ZERO)
		z.position = Vector2(x0 + bw * 0.5 - z.size.x * 0.5, _y)
		var hi := ui.label(self, "+100", ui.body, 11, Ui.MUTED, Vector2.ZERO)
		hi.position = Vector2(x0 + bw - hi.size.x, _y)
		_y += 18


static func tier_of(tiers: Array, v: int) -> int:
	var t := 0
	for i: int in tiers.size():
		if v >= int((tiers[i] as Dictionary)["min"]):
			t = i
	return t


static func sgn(v: int) -> String:
	return ("+" if v > 0 else ("−" if v < 0 else "")) + str(absi(v))


func build_rep(u: Ui, e: RefCounted, rel: Dictionary) -> void:
	_begin(u, e, 340.0)
	var tiers: Array = eq.d["rep_tiers"]
	var emp: Array = eq.d["empires"]
	var tot := 0
	for em: Dictionary in emp:
		tot += int(rel.get(em["key"], 0))
	tot = roundi(float(tot) / maxf(1.0, emp.size()))
	var t := tier_of(tiers, tot)
	_head("rep_%d.png" % t, false, "Репутация: " + str((tiers[t] as Dictionary)["name"]), "%s · среднее отношение пяти империй" % sgn(tot))
	var icons: Array = []
	var cols: Array = []
	for i: int in tiers.size():
		icons.append("rep_%d.png" % i)
		cols.append(Color.html(str((tiers[i] as Dictionary)["color"])))
	_scale_bar(icons, cols, t, (tot + 100) / 200.0, "tier", true)
	for i: int in emp.size():
		var em: Dictionary = emp[i]
		var v := int(rel.get(em["key"], 0))
		var et: Dictionary = tiers[tier_of(tiers, v)]
		var tc := Color.html(str(et["color"]))
		ui.pic(self, "emp_%s.png" % em["key"], Rect2(19, _y, 24, 24))
		ui.label(self, str(em["name"]), ui.serif, 13, Ui.TEXT, Vector2(50, _y + 2))
		ui.label(self, str(et["name"]), ui.body, 11, tc, Vector2(50, _y + 20))
		var bx := _w - 100.0
		var bar := Control.new()
		bar.position = Vector2(bx, _y + 9)
		bar.size = Vector2(56, 5)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.draw.connect(func() -> void:
			bar.draw_rect(Rect2(0, 0, 56, 5), Color(1, 1, 1, 0.08))
			bar.draw_line(Vector2(28, -2), Vector2(28, 7), Color(0.94, 0.81, 0.54, 0.5), 1.0)
			var w := 28.0 * absf(v) / 100.0
			bar.draw_rect(Rect2(28.0 if v >= 0 else 28.0 - w, 0, w, 5), tc))
		add_child(bar)
		var vl := ui.label(self, sgn(v), ui.serif, 13, tc, Vector2.ZERO)
		vl.position = Vector2(_w - 22 - vl.size.x, _y + 2)
		hovers.append({"rect": Rect2(19, _y - 2, bx - 26, 36), "kind": "emp", "arg": i})
		_y += 38
	_end()


func build_rank(u: Ui, e: RefCounted, r: int, st: Dictionary) -> void:
	_begin(u, e, 340.0)
	var ranks: Array = eq.d["ranks"]
	var nxt: Dictionary = ranks[r + 1] if r + 1 < ranks.size() else {}
	_head("rank_%d.png" % r, false, "Ранг %d: %s" % [r, (ranks[r] as Dictionary)["name"]],
		("Следующий — ранг %d: %s" % [r + 1, nxt["name"]]) if not nxt.is_empty() else "Высший ранг")
	var icons: Array = []
	var cols: Array = []
	for i: int in ranks.size():
		icons.append("rank_%d.png" % i)
		cols.append(Color.html(str((eq.d["rank_colors"] as Array)[i])))
	_scale_bar(icons, cols, r, (r + 0.5) / ranks.size(), "rank", false)
	if not nxt.is_empty():
		ui.label(self, ("До ранга %d" % (r + 1)).to_upper(), ui.caps(12, 0.06), 12, Color(0.94, 0.81, 0.54), Vector2(19, _y))
		_y += 22
		_reqs(nxt, st, true)
	_end()


## Условия ранга: ✓ / ✕, текст, текущее значение.
func _reqs(R: Dictionary, st: Dictionary, values: bool) -> void:
	for q: Array in req_rows(R, st):
		var ok: bool = q[0]
		ui.label(self, "✓" if ok else "✕", ui.serif, 13, Color(0.56, 0.88, 0.62) if ok else Color(0.88, 0.44, 0.42), Vector2(19, _y))
		ui.label(self, str(q[1]), ui.body, 13, Ui.TEXT, Vector2(38, _y), _w - 38 - 90)
		if values:
			var vl := ui.label(self, str(q[2]), ui.body, 12, Ui.MUTED, Vector2.ZERO)
			vl.position = Vector2(_w - 19 - vl.size.x, _y + 1)
		_y += 22


func req_rows(R: Dictionary, st: Dictionary) -> Array:
	var out: Array = []
	var rar: Array = eq.rar
	if R.has("rar"):
		var v := int(R["rar"])
		out.append([int(st["rar"]) >= v, "Все вещи — %s%s" % [str((rar[v] as Dictionary)["name"]).to_lower(), " или выше" if v < 5 else ""],
			str((rar[int(st["rar"])] as Dictionary)["name"])])
	if R.has("mana"):
		out.append([int(st["mana"]) >= int(R["mana"]), "Мифическая вещь, пропитанная маной", "есть" if int(st["mana"]) >= 1 else "нет"])
	if R.has("lvl"):
		out.append([int(st["lvl"]) >= int(R["lvl"]), "Уровень %d+" % int(R["lvl"]), str(st["lvl"])])
	if R.has("combo"):
		out.append([int(st["combo"]) >= int(R["combo"]), "Лучшее комбо — %d+ ударов" % int(R["combo"]), str(st["combo"])])
	if R.has("leg"):
		out.append([int(st["leg"]) >= int(R["leg"]), "Легендарные данжи: %d+" % int(R["leg"]), str(st["leg"])])
	if R.has("night"):
		out.append([int(st["night"]) >= int(R["night"]), "Кошмарные данжи: %d+" % int(R["night"]), str(st["night"])])
	return out
