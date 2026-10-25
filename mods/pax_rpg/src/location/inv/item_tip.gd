extends Control
## Подсказка вещи — как в прототипе: рамка с сакурой (цвет редкости; у маны — розовая, с кристаллами в углах), шапка
## (иконка, имя, редкость, «Пропитано маной», уровень предмета, цена с монетой), полоса типа, плашка требуемого уровня,
## древо статов (основные — узлы, дополнительные — ветки; свечение, мана), сет (плашка, значки слотов, бонусы), лор.
## Размеры — в пикселях прототипа, окно масштабируется целиком (scale). lines — строки для мини-подсказок.

const Ui := preload("res://mods/pax_rpg/src/location/inv/ui.gd")
const OUT_W := 425.0                 # ширина окна с рамкой
const X0 := 20.0                     # левый край содержимого
const CW := 386.0                    # ширина содержимого

var ui: Ui
var eq: RefCounted                   # equip.gd
var lines: Array = []                # [{rect, part: "main"|"extra"|"set", j}]
var ring: TextureProgressBar
var seal: TextureRect
var glow: Control                    # подсветка закрепления (за рамкой)
var color := Color.WHITE             # цвет подсветки (редкость / мана)
var _frame: Control
var _mana_fx: Array = []
var _t := 0.0


func build(u: Ui, e: RefCounted, it: Dictionary, k: int, hero_lvl: int, passive: Dictionary) -> void:
	ui = u
	eq = e
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	lines = []
	_mana_fx = []
	var r := int(it["r"])
	var rc: Color = eq.rc(r)
	var mana := bool(it.get("mana", false))
	color = Ui.MANA if mana else rc
	glow = Control.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate.a = 0.0
	add_child(glow)
	_frame = ui.frame(self, "frame_main.png", [75, 70, 70, 48], 0.754, Rect2(0, 0, OUT_W, 200))
	_tint(_frame, color)
	var y := 26.0
	# ── шапка
	var icon_r := Rect2(X0 + 4, y + 14, 64, 66)
	var S: Dictionary = (eq.sets as Dictionary)[it["set"]]
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.04, 0.045)
	bg.position = icon_r.position
	bg.size = icon_r.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	ui.item_icon(self, str(S["sheet"]), eq.cell(str(it["set"]), k, r), icon_r)
	_border(icon_r, rc)
	if mana:
		_mana_rim(icon_r, 12.0)
	var price_s: String = eq.money(int(it["price"]))
	var pw := ui.text_w(price_s, ui.body, 15) + 40.0
	var tx := X0 + 4 + 64 + 10
	var tw := CW - (tx - X0) - pw - 8
	var ny := y + 12
	var nl := ui.label(self, str(it["name"]), ui.caps(19, 0.07), 19, rc, Vector2(tx, ny), tw, HORIZONTAL_ALIGNMENT_LEFT, Color(rc.r, rc.g, rc.b, 0.4))
	ny += nl.size.y + 5
	ny += _rarity(Vector2(tx, ny), str((eq.rar[r] as Dictionary)["name"]), rc) + 5
	if mana:
		ny += _manatag(Vector2(tx - 6, ny)) + 4
	var il := ui.label(self, "Уровень предмета ", ui.body, 13, Ui.MUTED, Vector2(tx, ny))
	ui.label(self, str(it["lvl"]), ui.body, 13, Ui.TEXT, Vector2(tx + il.size.x, ny))
	ny += il.size.y
	_price(Rect2(X0 + CW - pw, y + 28, pw, 28), price_s)
	y = maxf(y + 14 + 66 + 10, ny + 10)
	# ── тип вещи
	var slot: Dictionary = (eq.slots as Array)[k]
	var kb := _strip(Rect2(X0, y, CW, 52))
	ui.pic(self, "type_%s.png" % slot["key"], Rect2(X0 + 8, y + 6, 40, 40))
	ui.label(self, str(slot["type"]).to_upper(), ui.caps(15, 0.07), 15, Ui.TEXT, Vector2(X0 + 58, y + 7))
	ui.label(self, str(slot["kind"]), ui.body, 12, Ui.MUTED, Vector2(X0 + 58, y + 28))
	y += 52 + 8
	# ── требуемый уровень
	var req: int = eq.req_level(it)
	_lvl_plaque(Rect2(X0, y, CW, 34), req, req > hero_lvl)
	y += 34 + 8
	ui.pic(self, "div_header.png", Rect2(X0 - 6, y, CW + 12, 14), false)
	y += 14 + 8
	# ── статы
	y = _cap("Основные", Vector2(X0, y))
	for j: int in (it["main"] as Array).size():
		y = _line((it["main"] as Array)[j], Vector2(X0 + 12, y), r, "main", j)
	y += 6
	var tree_x := X0 + 13
	y = _cap("Дополнительные", Vector2(tree_x + 24, y))
	var ty0 := y
	var mids: Array = []
	for j: int in (it["extra"] as Array).size():
		var y0 := y
		y = _line((it["extra"] as Array)[j], Vector2(tree_x + 24, y), r, "extra", j)
		mids.append((y0 + y - 5) * 0.5)
	_tree(tree_x, ty0 - 24, mids)
	if str(slot["key"]) == "cloak":
		y += 6
		var hn := ui.label(self, "✧ %s: на Тянь Лун все статы плаща ×1,5" % passive.get("name", ""), ui.body, 13, Color(0.94, 0.81, 0.54),
			Vector2(X0 + 10, y + 4), CW - 14)
		var bar := ColorRect.new()
		bar.color = Color(0.79, 0.64, 0.36, 0.9)
		bar.position = Vector2(X0, y)
		bar.size = Vector2(2, hn.size.y + 8)
		add_child(bar)
		y += hn.size.y + 10
	y = _set_box(it, k, y + 10)
	# ── лор
	y = _lore(str((((eq.d.get("lore", {}) as Dictionary).get(it["set"], []) as Array)[k] as Array)[r]), y + 10)
	var h := y + 22
	Ui.frame_resize(_frame, Vector2(OUT_W, h))
	size = Vector2(OUT_W, h)
	_glow_frame(h)
	# кольцо закрепления — в гнезде рамки
	ring = TextureProgressBar.new()
	ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	ring.texture_under = ui.tex("ring_empty.png")
	ring.texture_progress = ui.tex("ring_full.png")
	ring.nine_patch_stretch = true
	ring.max_value = 1.0
	ring.step = 0.0
	ring.value = 0.0
	ring.position = Vector2(OUT_W - 21.8 - 23 - 1, 25.8 - 1)
	ring.size = Vector2(25, 25)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)
	seal = ui.pic(self, "ring_seal.png", Rect2(ring.position, ring.size))
	seal.pivot_offset = ring.size * 0.5
	seal.modulate.a = 0.0
	if mana:
		_mana_corners(h)


## Рамка — перекрашенная копия золотой (шейдер: яркость рамки × цвет редкости / маны).
func _tint(box: Control, c: Color) -> void:
	var sh: Shader = ui.mod.shader("shaders/inv_tint.gdshader")
	if sh == null:
		return
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", c)
	(box.get_meta(&"np") as CanvasItem).material = m


func _glow_frame(h: float) -> void:
	var g := ui.frame(glow, "frame_main.png", [75, 70, 70, 48], 0.754, Rect2(-6, -6, OUT_W + 12, h + 12))
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	(g.get_meta(&"np") as CanvasItem).material = m
	(g.get_meta(&"np") as CanvasItem).modulate = Color(color.r, color.g, color.b, 0.55)


func _draw_ctl(rect: Rect2, fn: Callable) -> Control:
	var c := Control.new()
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn.bind(c))
	add_child(c)
	return c


func _border(rect: Rect2, c: Color) -> void:
	_draw_ctl(rect, func(ci: Control) -> void: Ui.rarity_border(ci, Rect2(Vector2.ZERO, rect.size), c))


func _mana_rim(rect: Rect2, mw: float) -> void:
	var o := mw * 32.0 / 76.0
	var box := ui.frame(self, "mana_rim.png", [76, 76, 76, 76], mw / 76.0, rect.grow(o))
	(box.get_meta(&"np") as NinePatchRect).draw_center = false
	_mana_fx.append(box)


func _rarity(pos: Vector2, text: String, rc: Color) -> float:
	var t := text.to_upper()
	var f := ui.caps(11, 0.1)
	var w := ui.text_w(t, f, 11) + 19.0
	_draw_ctl(Rect2(pos, Vector2(w, 20)), func(ci: Control) -> void:
		var r := Rect2(Vector2.ZERO, Vector2(w, 20))
		for i: int in 16:
			var u := i / 16.0
			ci.draw_rect(Rect2(w * u, 0, w / 16.0 + 1, 20), Color(rc.r, rc.g, rc.b, lerpf(0.26, 0.0, minf(u / 0.9, 1.0))))
		ci.draw_rect(r, Color(rc.r, rc.g, rc.b, 0.55), false, 1.0)
		var c := Vector2(11, 10)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), rc))
	ui.label(self, t, f, 11, rc, pos + Vector2(20, 3))
	return 20.0


func _manatag(pos: Vector2) -> float:
	var t := "ПРОПИТАНО МАНОЙ"
	var f := ui.caps(11, 0.12)
	var w := ui.text_w(t, f, 11) + 46.0
	var b := ui.frame(self, "mana_badge.png", [63, 0, 51, 0], 30.0 / 72.0, Rect2(pos, Vector2(w, 30)))
	b.z_index = 0
	var l := ui.label(self, t, f, 11, Color(1.0, 0.75, 0.94), pos + Vector2(26, 8))
	_mana_fx.append(l)
	return 30.0


func _price(rect: Rect2, s: String) -> void:
	_draw_ctl(rect, func(ci: Control) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		ci.draw_rect(r, Color(0.11, 0.07, 0.05))
		ci.draw_rect(r, Ui.GOLD_DIM, false, 1.0)
		var c := Vector2(15, rect.size.y * 0.5)
		ci.draw_circle(c, 10.5, Color(0.62, 0.42, 0.10))
		ci.draw_circle(c, 9.0, Color(0.95, 0.76, 0.32))
		ci.draw_arc(c, 7.0, 0, TAU, 20, Color(0.55, 0.36, 0.08), 1.2)
		ci.draw_rect(Rect2(c + Vector2(-4, -1), Vector2(8, 4)), Color(0.48, 0.30, 0.06)))
	ui.label(self, s, ui.body, 15, Color(0.95, 0.84, 0.55), rect.position + Vector2(30, 4))


func _strip(rect: Rect2) -> Control:
	return _draw_ctl(rect, func(ci: Control) -> void:
		var r := Rect2(Vector2.ZERO, rect.size)
		for i: int in 20:
			var t := i / 20.0
			ci.draw_rect(Rect2(r.size.x * t, 0, r.size.x / 20.0 + 1, r.size.y), Color(0.79, 0.64, 0.36, lerpf(0.10, 0.02, minf(t / 0.7, 1.0))))
		ci.draw_rect(r, Color(0.79, 0.64, 0.36, 0.28), false, 1.0))


## Плашка требуемого уровня: края и ромб по центру — без растяжения, середина тянется; красная — уровень героя ниже.
func _lvl_plaque(rect: Rect2, req: int, bad: bool) -> void:
	var p := "lvl_bad_" if bad else "lvl_ok_"
	var k := rect.size.y / 72.0
	var lw := 166.0 * k
	ui.pic(self, p + "M.png", Rect2(rect.position + Vector2(lw - 2, 0), Vector2(rect.size.x - lw * 2 + 4, rect.size.y)), false)
	ui.pic(self, p + "L.png", Rect2(rect.position, Vector2(lw, rect.size.y)), false)
	ui.pic(self, p + "R.png", Rect2(rect.position + Vector2(rect.size.x - lw, 0), Vector2(lw, rect.size.y)), false)
	ui.pic(self, p + "C.png", Rect2(rect.position + Vector2((rect.size.x - 48 * k) * 0.5, 0), Vector2(48 * k, rect.size.y)), false)
	ui.label(self, "ТРЕБУЕТСЯ УРОВЕНЬ", ui.caps(11, 0.1), 11, Color(1.0, 0.6, 0.56) if bad else Ui.MUTED, rect.position + Vector2(30, 11))
	var nl := ui.label(self, str(req), ui.body, 19, Color(1.0, 0.35, 0.3) if bad else Color(0.95, 0.84, 0.55), Vector2.ZERO)
	nl.position = rect.position + Vector2(rect.size.x - 30 - nl.size.x, 4)


func _cap(text: String, pos: Vector2) -> float:
	ui.label(self, text.to_upper(), ui.caps(11, 0.1), 11, Ui.GOLD, pos + Vector2(0, 2))
	ui.pic(self, "div_section.png", Rect2(pos + Vector2(0, 18), Vector2(150, 8)), false)
	return pos.y + 30


## Строка стата. Основные — с узлом древа цветом редкости; свечение — полоса и звезда; мана — розовая полоса и ромб.
func _line(e: Dictionary, pos: Vector2, r: int, part: String, j: int) -> float:
	var main := part == "main"
	var h := 26.0 if main else 24.0
	var boost := bool(e.get("boost", false))
	var mana := bool(e.get("mana", false))
	var rc: Color = eq.rc(r)
	var w := CW - (pos.x - X0)
	if boost:
		var g := ui.pic(self, ["glow_epic.png", "glow_leg.png", "glow_myth.png"][clampi(r - 3, 0, 2)], Rect2(pos + Vector2(0, h - 10), Vector2(w, 14)), false)
		g.modulate.a = 0.9
		_draw_ctl(Rect2(pos, Vector2(w, h)), func(ci: Control) -> void:
			ci.draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(rc.r, rc.g, rc.b, 0.10)))
	if mana:
		var ms := ui.pic(self, "mana_strip.png", Rect2(pos + Vector2(-6, h - 18), Vector2(w, 30)), false)
		_mana_fx.append(ms)
	if main:
		var node := ui.pic(self, "node_main.png", Rect2(pos + Vector2(-10, h * 0.5 - 8), Vector2(15, 16)))
		node.modulate = Color(1, 1, 1).lerp(rc, 0.55) if not bool(e.get("mana_main", false)) else Ui.MANA
	var key := str(e["key"])
	var x := pos.x + (14.0 if main else 6.0)
	ui.pic(self, "st_%s.png" % key, Rect2(Vector2(x, pos.y + (h - 18) * 0.5), Vector2(18, 18)))
	x += 26
	var vc := Color(1.0, 0.95, 0.86) if main else (Ui.TEXT if bool(e.get("minor", false)) else Ui.TEXT)
	var kc := Ui.TEXT if main else Ui.MUTED
	if boost:
		vc = rc
		kc = rc
	if mana:
		vc = Color(1.0, 0.62, 0.9)
		kc = Color(1.0, 0.75, 0.94)
	var fs := 17 if main else 14
	var vl := ui.label(self, eq.fmt(key, float(e["v"])), ui.body, fs, vc, Vector2(x, pos.y + (h - fs * 1.25) * 0.5),
		0.0, HORIZONTAL_ALIGNMENT_LEFT, Color(vc.r, vc.g, vc.b, 0.35) if boost or mana else Color(0, 0, 0, 0))
	x += vl.size.x + 8
	var nm := str(((eq.stats as Dictionary)[key] as Dictionary)["name"])
	var kfs := 16 if main else 14
	var kl := ui.label(self, nm, ui.body, kfs, kc, Vector2(x, pos.y + (h - kfs * 1.35) * 0.5))
	if bool(e.get("mana_main", false)):
		ui.pic(self, "mana_gem.png", Rect2(Vector2(kl.position.x + kl.size.x + 6, pos.y + h * 0.5 - 6), Vector2(9, 12)))
	var mx := pos.x + w - 16
	if mana:
		ui.pic(self, "mana_gem.png", Rect2(Vector2(mx - (14 if boost else 0), pos.y + h * 0.5 - 8), Vector2(12, 16)))
	if boost:
		ui.pic(self, ["star_epic.png", "star_leg.png", "star_myth.png"][clampi(r - 3, 0, 2)], Rect2(Vector2(mx, pos.y + h * 0.5 - 7), Vector2(14, 14)))
	lines.append({"rect": Rect2(pos, Vector2(w, h)), "part": part, "j": j})
	return pos.y + h + 5


func _tree(x: float, y_top: float, mids: Array) -> void:
	if mids.is_empty():
		return
	var bead := ui.tex("node_bead.png")
	_draw_ctl(Rect2(Vector2(x, 0), Vector2(30, mids[mids.size() - 1] + 10)), func(ci: Control) -> void:
		ci.draw_line(Vector2(0, y_top), Vector2(0, float(mids[mids.size() - 1])), Ui.GOLD_DIM, 1.0)
		for m: Variant in mids:
			ci.draw_line(Vector2(0, float(m)), Vector2(17, float(m)), Ui.GOLD_DIM, 1.0)
			if bead != null:
				ci.draw_texture_rect(bead, Rect2(Vector2(17, float(m) - 3), Vector2(6, 6)), false))


## Сет: плашка (эмблема, имя, «n / 8»), значки слотов (надетые вещи этого сета светятся), бонусы с печатями порогов.
func _set_box(it: Dictionary, k: int, y: float) -> float:
	var key := str(it["set"])
	var S: Dictionary = (eq.sets as Dictionary)[key]
	var sc := Color.html(str(S.get("color", "#4fd1b8")))
	var n: int = eq.set_count(key)
	var kk := 46.0 / 96.0
	var lw := 138.0 * kk
	var rw := 76.0 * kk
	ui.pic(self, "plaque_M.png", Rect2(X0 - 4 + lw - 1, y, CW + 8 - lw - rw + 2, 46), false)
	ui.pic(self, "plaque_L.png", Rect2(X0 - 4, y, lw, 46), false)
	ui.pic(self, "plaque_R.png", Rect2(X0 - 4 + CW + 8 - rw, y, rw, 46), false)
	ui.pic(self, str(S["emblem"]), Rect2(X0 - 4 + 23, y + 7, 32, 32))
	var cnt := ui.label(self, "%d / %d" % [n, (eq.slots as Array).size()], ui.body, 14, Color(0.87, 0.98, 0.96), Vector2.ZERO)
	cnt.position = Vector2(X0 + CW - 34 - cnt.size.x, y + 14)
	var nl := ui.label(self, str(S["name"]), ui.caps(16, 0.03), 16, sc, Vector2(X0 - 4 + 66, y + 14), 0.0, HORIZONTAL_ALIGNMENT_LEFT, Color(sc.r, sc.g, sc.b, 0.35))
	nl.clip_text = true
	nl.size.x = minf(nl.size.x, cnt.position.x - nl.position.x - 8)
	y += 46 + 6
	var pips: Array = ["helmet", "chest", "gloves", "shoulders", "boots", "cloak", "ring", "amulet"]
	var gap := (CW - 12 - pips.size() * 24) / float(pips.size() - 1)
	for i: int in pips.size():
		var on: bool = str(eq.item_at(i).get("set", "")) == key
		var p := ui.pic(self, "pip_%s_%s.png" % [pips[i], "on" if on else "off"], Rect2(X0 + 6 + i * (24 + gap), y, 24, 24))
		p.modulate.a = 1.0 if on else 0.7
		if i == k:
			p.pivot_offset = p.size * 0.5
			p.scale = Vector2(1.18, 1.18)
	y += 24 + 6
	var bon: Array = S.get("bonuses", [])
	for j: int in bon.size():
		var b: Dictionary = bon[j]
		var act := n >= int(b["n"])
		var tl := ui.label(self, "%s: %s" % [b["title"], b["text"]], ui.body, 13, Ui.SET if act else Ui.MUTED, Vector2(X0 + 4 + 26 + 8, y + 2), CW - 46)
		var sy := y + 2 + (tl.size.y - 26) * 0.5
		var seal_p := ui.pic(self, "seal_on.png" if act else "seal_off.png", Rect2(X0 + 4, sy, 26, 26))
		var nn := ui.label(self, str(int(b["n"])), ui.body, 13, Color(0.92, 1.0, 0.98) if act else Ui.MUTED, Vector2(X0 + 4, sy + 4), 26, HORIZONTAL_ALIGNMENT_CENTER,
			Color(0, 0, 0, 0.9) if act else Color(0, 0, 0, 0))
		if not act:
			for c: CanvasItem in [tl, seal_p, nn]:
				c.modulate.a = 0.7
		lines.append({"rect": Rect2(Vector2(X0, y), Vector2(CW, tl.size.y + 4)), "part": "set", "j": j})
		y += tl.size.y + 4 + 4
	return y


## Свиток лора: картинка целиком (без растяжения), курсив по центру; длинный текст уменьшается, пока не влезет.
func _lore(text: String, y: float) -> float:
	var h := CW * 242.0 / 1000.0
	ui.pic(self, "lore_full.png", Rect2(X0, y, CW, h), false)
	var iw := CW * 0.75
	var ih := h * (1.0 - 0.054 - 0.052) - CW * 0.106   # как в прототипе: поля свитка 5,4 % / 5,2 % и запас у краёв
	var fs := 14
	while fs > 10 and ui.italic.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, iw, ui.px(ui.italic, fs)).y > ih - 4:
		fs -= 1
	var l := ui.label(self, text, ui.italic, fs, Color(0.886, 0.816, 0.69), Vector2(X0 + CW * 0.125, y), iw, HORIZONTAL_ALIGNMENT_CENTER, Color(0, 0, 0, 0.7))
	l.position.y = y + (h - l.size.y) * 0.5
	return y + h


func _mana_corners(h: float) -> void:
	for c: Array in [["mana_c_tl.png", Vector2(-14, -12), 185.0], ["mana_c_tr.png", Vector2(OUT_W - 82, -12), 185.0],
			["mana_c_bl.png", Vector2(-14, h - 66), 161.0], ["mana_c_br.png", Vector2(OUT_W - 82, h - 66), 161.0]]:
		var p := ui.pic(self, str(c[0]), Rect2(c[1], Vector2(96, 96.0 * float(c[2]) / 200.0)))
		_mana_fx.append(p)


## Мини-подсказка стата или бонуса сета (только у закреплённой подсказки).
func mini_text(it: Dictionary, part: String, j: int, passive: Dictionary) -> Array:
	if part == "set":
		var b: Dictionary = (((eq.sets as Dictionary)[it["set"]] as Dictionary)["bonuses"] as Array)[j]
		var n: int = eq.set_count(str(it["set"]))
		return [str(b["title"]), str(b["info"]), "Надето %d из %d" % [n, int(b["n"])], Ui.SET, ""]
	var e: Dictionary = (it[part] as Array)[j]
	var s: Dictionary = (eq.stats as Dictionary)[e["key"]]
	var r := int(it["r"])
	var boost := float(((eq.rar as Array)[r] as Dictionary)["boost"])
	var mm := float(((eq.d as Dictionary).get("mana", {}) as Dictionary).get("mult", 5))
	var tag := ""
	if bool(e.get("mana", false)) and bool(e.get("boost", false)):
		tag = "◆ Мана ×%s поверх свечения ×%s — всего ×%s" % [_n(mm), _n(boost), _n(mm * boost)]
	elif bool(e.get("mana", false)):
		tag = "◆ Усилено маной · ×%s" % _n(mm)
	elif bool(e.get("mana_main", false)):
		tag = "◆ Лишний основной стат от маны"
	elif bool(e.get("boost", false)):
		tag = "✦ Усилено свечением · ×%s" % _n(boost)
	elif bool(e.get("minor", false)):
		tag = "Основной стат в роли дополнительного · 45 % силы"
	elif part == "main":
		tag = "Основной стат предмета"
	var c: Color = Ui.MANA if bool(e.get("mana", false)) or bool(e.get("mana_main", false)) else (eq.rc(r) if bool(e.get("boost", false)) else Ui.GOLD)
	var hero := ""
	if bool(e.get("hero", false)):
		hero = "✧ %s: плащ на Тянь Лун ×1,5 · без пассива %s" % [passive.get("name", ""), eq.fmt(str(e["key"]), float(e["base"]))]
	return [str(s["name"]), str(s["info"]), "На этом предмете: " + eq.fmt(str(e["key"]), float(e["v"])), c, tag + ("\n" + hero if hero != "" else "")]


static func _n(v: float) -> String:
	return str(snappedf(v, 0.01)).replace(".", ",")


func set_arm(p: float) -> void:
	if is_instance_valid(ring):
		ring.value = p


func set_pinned(on: bool) -> void:
	if is_instance_valid(seal):
		seal.modulate.a = 1.0 if on else 0.0
		seal.scale = Vector2(1.15, 1.15) if on else Vector2(0.4, 0.4)
	if is_instance_valid(ring):
		ring.value = 1.0 if on else 0.0


func _process(delta: float) -> void:
	_t += delta
	var a := 0.82 + 0.18 * sin(_t * TAU / 4.0)                  # мана — мягко «дышит» за 4 с
	for n: Variant in _mana_fx:
		if is_instance_valid(n):
			(n as CanvasItem).modulate.a = a
