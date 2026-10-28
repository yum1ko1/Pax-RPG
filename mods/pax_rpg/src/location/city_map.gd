extends Control
## Карта города (M) в стиле меню (ночь, алая тушь, Cormorant): районы с подписями (config/<город>_map.json → zones),
## дороги по маске земли (R — кладка, G — тропы), здания (коробки миникарты), места — медальоны с иероглифом
## (pois), арена, ворота, враги и герой; справа легенда. Закрывается M или Esc.

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")

var mod: PaxMod
var st: Dictionary = {}               # тот же словарь кадра, что у HUD (location.gd)
var landmarks: Array = []             # [ключ перевода, x, z]
var arena := Vector3.ZERO             # x, z, радиус ямы (0 — нет)
var ground := Rect2()                 # мир (x, z) → весь лист карты
var roads: Texture2D                  # маска дорог (R — кладка, G — тропы)
var roads_rect := Rect2()             # где лежит маска в мире (x, z, ш, г)
var zones: Array = []                 # районы: {r: [x0, z0, x1, z1], name, col}
var pois: Array = []                  # места: {key, x, z, glyph, kind}
var kinds: Dictionary = {}            # вид места → цвет медальона
var title_font: FontFile
var _roads_view: TextureRect          # дороги — своим шейдером (кладка тёплая, тропы бледные)
var _ink: Control                     # верхний слой: здания, значки, легенда

const CRIMSON := Color(1.0, 0.16, 0.22)
const NIGHT := Color(0.035, 0.012, 0.06)
const PAPER := Color(0.09, 0.05, 0.12)
const ROADS_SH := """shader_type canvas_item;
uniform vec4 paved : source_color = vec4(0.93, 0.78, 0.74, 0.85);
uniform vec4 trail : source_color = vec4(0.62, 0.5, 0.58, 0.55);
void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float p = smoothstep(0.3, 0.6, m.r);
	float t = smoothstep(0.3, 0.6, m.g) * (1.0 - p);
	COLOR = paved * p + trail * t;
	COLOR.a = paved.a * p + trail.a * t;
}"""
const KIND_KEYS := ["gate", "fight", "trade", "rest", "craft", "power", "nature", "beast", "home", "road"]
var serif: Font
var sans: Font
var cjk: Font


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgCityMap"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	serif = Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)
	sans = Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	cjk = Hud._sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "Noto Serif CJK JP", "SimSun", "MS Gothic"], 700)
	title_font = FontFile.new()
	title_font.data = mod.read_bytes("fonts/cormorant_garamond.ttf")
	_roads_view = TextureRect.new()
	_roads_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roads_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_roads_view.stretch_mode = TextureRect.STRETCH_SCALE
	var sh := Shader.new()
	sh.code = ROADS_SH
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_roads_view.material = mat
	add_child(_roads_view)
	_ink = Control.new()
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ink.draw.connect(_draw_ink)
	add_child(_ink)


## Данные города (планировка); пустая — карта не открывается (тестовая арена).
func set_city(layout: Dictionary) -> void:
	landmarks = layout.get("landmarks", [])
	var a: Array = layout.get("arena", [])
	arena = Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO
	var g: Array = layout.get("ground", [0, 0, 0, 0])
	ground = Rect2(float(g[2]) - float(g[0]) * 0.5, float(g[3]) - float(g[1]) * 0.5, float(g[0]), float(g[1]))
	var gm: Dictionary = layout.get("ground_mask", {})
	roads = mod.texture(str(gm.get("tex", ""))) if gm.has("tex") else null
	var mr: Array = gm.get("rect", [])
	roads_rect = Rect2(float(mr[0]), float(mr[1]), float(mr[2]), float(mr[3])) if mr.size() >= 4 else ground
	_roads_view.texture = roads
	var mp: Variant = JSON.parse_string(mod.read_text(str(layout.get("map", "")))) if layout.has("map") else null
	_art = {}
	if mp is Dictionary:
		zones = (mp as Dictionary).get("zones", [])
		pois = (mp as Dictionary).get("pois", [])
		kinds = (mp as Dictionary).get("kinds", {})
		_art = (mp as Dictionary).get("art", {})
	pin = Vector2(INF, INF)
	_load_art()


func has_city() -> bool:
	return ground.size.x > 0.0


func toggle() -> void:
	set_open(not visible)


## Открыть / закрыть: на запечённой карте мышь — карте (масштаб, перетаскивание, метка, подсказки).
func set_open(on: bool) -> void:
	visible = on and has_city()
	if visible:
		_center_on_hero()
	mouse_filter = Control.MOUSE_FILTER_STOP if visible and _art_on() else Control.MOUSE_FILTER_IGNORE
	_hover = ""
	queue_redraw()
	_ink.queue_redraw()


func _process(_delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("city_map._process")
	if visible:
		queue_redraw()
		_ink.queue_redraw()


## Лист карты: квадрат слева от легенды; мир (x, z) → экран.
func _sheet() -> Dictionary:
	var vs := get_viewport_rect().size
	var s := vs.y / 1080.0
	var leg := 360.0 * s
	var side := minf((vs.x - leg) * 0.86, vs.y * 0.8)
	var k := side / maxf(ground.size.x, ground.size.y)
	var size := ground.size * k
	var o := Vector2((vs.x - leg - size.x) * 0.5, (vs.y - size.y) * 0.5 + 18.0 * s)
	return {"vs": vs, "s": s, "k": k, "size": size, "o": o, "leg": leg}


func _to(sh: Dictionary, w: Vector2) -> Vector2:
	return (sh.o as Vector2) + (w - ground.position) * float(sh.k)


func _hex(c: String, a: float) -> Color:
	var col := Color.html(c) if Color.html_is_valid(c) else Color.WHITE
	return Color(col, a)


func _draw() -> void:
	if _art_on():
		_draw_art()
		return
	var sh := _sheet()
	var vs: Vector2 = sh.vs
	var s := float(sh.s)
	var o: Vector2 = sh.o
	var size: Vector2 = sh.size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(NIGHT, 0.9))
	for i: int in 6:                                  # мягкая алая дымка снизу, как в меню
		var t := float(i) / 6.0
		draw_rect(Rect2(0, vs.y * (0.7 + t * 0.3), vs.x, vs.y * 0.05 + 1.0), Color(CRIMSON, 0.025))
	draw_rect(Rect2(o - Vector2(14, 14) * s, size + Vector2(28, 28) * s), Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(Rect2(o, size), PAPER)
	var step := 20.0 * float(sh.k)                    # сетка 20 м — тонкие линии туши
	var x := o.x
	while x < o.x + size.x:
		draw_line(Vector2(x, o.y), Vector2(x, o.y + size.y), Color(1, 1, 1, 0.025), 1.0)
		x += step
	var y := o.y
	while y < o.y + size.y:
		draw_line(Vector2(o.x, y), Vector2(o.x + size.x, y), Color(1, 1, 1, 0.025), 1.0)
		y += step
	for zv: Variant in zones:                         # районы — цветная заливка и пунктир границы
		var z: Dictionary = zv
		var r: Array = z.r
		var a: Vector2 = _to(sh, Vector2(float(r[0]), float(r[1])))
		var b: Vector2 = _to(sh, Vector2(float(r[2]), float(r[3])))
		var rc := Rect2(a, b - a)
		var col := _hex(str(z.col), 1.0)
		draw_rect(rc, Color(col, 0.13))
		for e: Array in [[rc.position, Vector2(rc.end.x, rc.position.y)], [Vector2(rc.end.x, rc.position.y), rc.end],
				[rc.end, Vector2(rc.position.x, rc.end.y)], [Vector2(rc.position.x, rc.end.y), rc.position]]:
			draw_dashed_line(e[0], e[1], Color(col, 0.45), 1.2 * s, 6.0 * s)
	if roads != null:
		_roads_view.position = _to(sh, roads_rect.position)
		_roads_view.size = roads_rect.size * float(sh.k)
		_roads_view.visible = true
	else:
		_roads_view.visible = false


func _draw_ink() -> void:
	if _art_on():
		_draw_art_ink()
		return
	var sh := _sheet()
	var vs: Vector2 = sh.vs
	var s := float(sh.s)
	var o: Vector2 = sh.o
	var size: Vector2 = sh.size
	var k := float(sh.k)
	for rect: Variant in st.get("map_rects", []):    # постройки — тёмные силуэты с тонкой обводкой
		var rr: Array = rect
		var c: Vector2 = _to(sh, rr[0] as Vector2)
		var h: Vector2 = (rr[1] as Vector2) * k * 0.5
		var col: Color = rr[2]
		_ink.draw_rect(Rect2(c - h, h * 2.0), Color(col.darkened(0.45), 0.9))
		_ink.draw_rect(Rect2(c - h, h * 2.0), Color(1.0, 0.8, 0.85, 0.18), false, 1.0)
	if arena.z > 0.0:
		var ac: Vector2 = _to(sh, Vector2(arena.x, arena.y))
		_ink.draw_circle(ac, arena.z * k, Color(0.55, 0.38, 0.3, 0.85))
		_ink.draw_arc(ac, (arena.z + 3.5) * k, 0.0, TAU, 64, Color(CRIMSON, 0.9), 2.5 * s, true)
	for zv: Variant in zones:                         # подписи районов — капителью, приглушённо
		var z: Dictionary = zv
		var r: Array = z.r
		var a: Vector2 = _to(sh, Vector2(float(r[0]), float(r[1])))
		var txt := str(z.name).to_upper()
		var fs := int(13 * s)
		_ink.draw_string_outline(title_font, a + Vector2(5, 15) * s, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			int(4 * s), Color(NIGHT, 0.9))
		_ink.draw_string(title_font, a + Vector2(5, 15) * s, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			_hex(str(z.col), 0.85))
	var gate: Vector2 = st.get("gate", Vector2.ZERO)
	_ink.draw_arc(_to(sh, gate), 11.0 * s, 0.0, TAU, 24, Hud.BLUE, 2.5 * s, true)
	for e: Variant in st.get("enemies", []):
		var ed: Dictionary = e
		var ep: Vector2 = _to(sh, ed.pos)
		_ink.draw_circle(ep, 5.0 * s, Color(CRIMSON, 0.35))
		_ink.draw_circle(ep, 3.0 * s, CRIMSON)
	if pois.is_empty():                              # нет данных карты — старые подписи
		for lm: Variant in landmarks:
			pois.append({"key": lm[0], "x": lm[1], "z": lm[2], "glyph": "・", "kind": "road"})
	for pv: Variant in pois:                          # места — медальон с иероглифом и подпись
		var pd: Dictionary = pv
		var p: Vector2 = _to(sh, Vector2(float(pd.x), float(pd.z)))
		var col := _hex(str(kinds.get(str(pd.kind), "#ff8cc6")), 1.0)
		var rad := 12.0 * s
		_ink.draw_circle(p, rad + 2.0 * s, Color(NIGHT, 0.95))
		_ink.draw_circle(p, rad, Color(col, 0.22))
		_ink.draw_arc(p, rad, 0.0, TAU, 32, col, 1.8 * s, true)
		var g := str(pd.glyph)
		var gs := int(15 * s)
		var gw := cjk.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, gs)
		_ink.draw_string(cjk, p + Vector2(-gw.x * 0.5, gs * 0.36), g, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, col.lightened(0.4))
		var txt := mod.tr_key(str(pd.key))
		var fs := int(17 * s)
		var w := title_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := p + Vector2(-w * 0.5, rad + 16.0 * s)
		_ink.draw_string_outline(title_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(5 * s), Color(NIGHT, 0.95))
		_ink.draw_string(title_font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.98, 0.93, 0.95))
	var me: Vector2 = st.get("me", Vector2.ZERO)     # герой — стрелка по повороту тела, с алым ореолом
	var body := float(st.get("body_yaw", 0.0))
	var mp: Vector2 = _to(sh, me)
	_ink.draw_circle(mp, 16.0 * s, Color(CRIMSON, 0.18))
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -13), Vector2(9, 11), Vector2(0, 6), Vector2(-9, 11)]:
		arrow.append(mp + v.rotated(-body) * s)
	_ink.draw_colored_polygon(arrow, Color(1.0, 0.96, 0.97))
	_ink.draw_polyline(arrow + PackedVector2Array([arrow[0]]), CRIMSON, 1.8 * s, true)
	_ink.draw_rect(Rect2(o, size), Color(CRIMSON, 0.7), false, 2.0 * s)   # рамка листа и уголки
	for cn: Vector2 in [o, o + Vector2(size.x, 0), o + size, o + Vector2(0, size.y)]:
		_ink.draw_rect(Rect2(cn - Vector2(5, 5) * s, Vector2(10, 10) * s), CRIMSON)
	var title := str(st.get("place", ""))
	var ts := int(40 * s)
	var tw := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x
	var tp := Vector2(o.x + size.x * 0.5 - tw * 0.5, o.y - 24 * s)
	_ink.draw_string_outline(title_font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, int(8 * s), Color(CRIMSON, 0.35))
	_ink.draw_string(title_font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(0.98, 0.93, 0.95))
	_ink.draw_line(Vector2(tp.x - 40 * s, tp.y + 10 * s), Vector2(tp.x + tw + 40 * s, tp.y + 10 * s), Color(CRIMSON, 0.8),
		1.5 * s)
	_ink.draw_string(cjk, Vector2(o.x + size.x - 30 * s, o.y + 32 * s), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * s),
		CRIMSON)
	_ink.draw_line(Vector2(o.x + size.x - 19 * s, o.y + 38 * s), Vector2(o.x + size.x - 19 * s, o.y + 60 * s), CRIMSON, 2.0 * s)
	var bar := 20.0 * k                               # масштаб: 20 м
	var bp := Vector2(o.x + 16 * s, o.y + size.y - 18 * s)
	_ink.draw_line(bp, bp + Vector2(bar, 0), Color(0.98, 0.93, 0.95), 2.0 * s)
	_ink.draw_string(sans, bp + Vector2(bar + 6 * s, 5 * s), "20 m", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), Hud.MUTED)
	_legend(sh)
	var hint := mod.tr_key("pax_rpg_map_hint")
	_ink.draw_string(sans, Vector2(o.x, o.y + size.y + 30 * s), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * s), Hud.MUTED)


## Легенда справа: виды мест (цвет медальона), дороги, ворота, враги, герой.
func _legend(sh: Dictionary) -> void:
	var s := float(sh.s)
	var o: Vector2 = sh.o
	var size: Vector2 = sh.size
	var x := o.x + size.x + 40.0 * s
	var w := float(sh.leg) - 30.0 * s
	var rows: Array = []                              # [вид значка, цвет, подпись]
	for kk: String in KIND_KEYS:
		if kinds.has(kk):
			rows.append(["medal", _hex(str(kinds[kk]), 1.0), mod.tr_key("pax_rpg_map_k_" + kk)])
	rows.append(["paved", Color(0.93, 0.78, 0.74), mod.tr_key("pax_rpg_map_paved")])
	rows.append(["trail", Color(0.62, 0.5, 0.58), mod.tr_key("pax_rpg_map_trail")])
	rows.append(["house", Color(0.5, 0.4, 0.45), mod.tr_key("pax_rpg_map_house")])
	rows.append(["gate", Hud.BLUE, mod.tr_key("pax_rpg_map_gate")])
	rows.append(["foe", CRIMSON, mod.tr_key("pax_rpg_map_foe")])
	rows.append(["me", Color(1.0, 0.96, 0.97), mod.tr_key("pax_rpg_map_me")])
	var lh := 30.0 * s
	var h := 60.0 * s + rows.size() * lh
	var y0 := o.y
	_ink.draw_rect(Rect2(x, y0, w, h), Color(NIGHT, 0.92))
	_ink.draw_rect(Rect2(x, y0, w, h), Color(CRIMSON, 0.55), false, 1.5 * s)
	var head := mod.tr_key("pax_rpg_map_legend")
	_ink.draw_string(title_font, Vector2(x + 18 * s, y0 + 34 * s), head, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * s),
		Color(0.98, 0.93, 0.95))
	_ink.draw_line(Vector2(x + 18 * s, y0 + 44 * s), Vector2(x + w - 18 * s, y0 + 44 * s), Color(CRIMSON, 0.7), 1.2 * s)
	var y := y0 + 60.0 * s
	for rv: Variant in rows:
		var r: Array = rv
		var c := Vector2(x + 32 * s, y + 10 * s)
		var col: Color = r[1]
		match str(r[0]):
			"medal":
				_ink.draw_circle(c, 9.0 * s, Color(col, 0.22))
				_ink.draw_arc(c, 9.0 * s, 0.0, TAU, 24, col, 1.6 * s, true)
			"paved", "trail":
				_ink.draw_line(c - Vector2(12, 0) * s, c + Vector2(12, 0) * s, col, (7.0 if r[0] == "paved" else 4.0) * s)
			"house":
				_ink.draw_rect(Rect2(c - Vector2(8, 6) * s, Vector2(16, 12) * s), col)
			"gate":
				_ink.draw_arc(c, 8.0 * s, 0.0, TAU, 20, col, 2.2 * s, true)
			"foe":
				_ink.draw_circle(c, 4.0 * s, col)
			"me":
				var ar := PackedVector2Array()
				for v: Vector2 in [Vector2(0, -10), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)]:
					ar.append(c + v * s)
				_ink.draw_colored_polygon(ar, col)
		_ink.draw_string(title_font, Vector2(x + 54 * s, y + 16 * s), str(r[2]), HORIZONTAL_ALIGNMENT_LEFT, w - 64 * s,
			int(18 * s), Color(0.9, 0.86, 0.95))
		y += lh


## Скрыт — не обрабатывается совсем (раньше _process звался каждый кадр и сразу выходил).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_READY:
		set_process(is_visible_in_tree())


# ---------- запечённая карта (config/<город>_map.json → art): арт с подписями улиц, значки, легенда-фильтр ----------
# Макет 1920×1080 (масштаб по высоте). Колесо — масштаб к курсору, ПКМ — двигать, ЛКМ — метка (её видят компас и
# миникарта: static pin), L — легенда, Пробел — к герою, наведение на значок — подсказка.

static var pin := Vector2(INF, INF)   # метка игрока на карте (мир x, z); INF — нет
var _art: Dictionary = {}
var _map_tex: Texture2D
var _glyphs: Texture2D
var _frame_tip: Texture2D
var _div: Texture2D
var _vign: GradientTexture2D
var _f_sc: Font
var _f_it: Font
var _zoom := 1.0
var _view := Vector2(-6, -8)          # мир в точке привязки экрана
var _legend_on := true
var _hidden := {}                     # вид места → скрыт фильтром легенды
var _hover := ""
var _drag := false
var _press := Vector2.ZERO
const ANCHOR := Vector2(830, 540)     # точка привязки вида (макет): левее середины — справа легенда
const PPM := 5.2                      # px макета на метр при масштабе 1
const LEG := Rect2(1570, 150, 300, 0) # легенда (x — от правого края: 1920 − 350)
const KEYS_H := 46.0
const IVORY := Color(0.945, 0.886, 0.769)
const IVORY_DIM := Color(0.78, 0.69, 0.55)
const GOLD := Color(0.84, 0.675, 0.384)
const RED := Color(0.77, 0.125, 0.17)
const KCOL := {"gate": Color8(120, 170, 200), "fight": Color8(196, 40, 52), "trade": Color8(200, 150, 60),
	"rest": Color8(200, 150, 60), "craft": Color8(170, 110, 70), "power": Color8(140, 80, 160), "nature": Color8(90, 140, 90),
	"beast": Color8(150, 120, 80), "home": Color8(130, 110, 90), "road": Color8(160, 120, 100)}


func _art_on() -> bool:
	return _map_tex != null


func _load_art() -> void:
	_map_tex = null
	if _art.is_empty() or mod == null:
		return
	var lang := "ru" if mod.tr_key("pax_rpg_map_legend") == "Легенда" else "en"
	var t := mod.texture(str(_art.get("map_" + lang, _art.get("map_ru", ""))))
	if t == null:
		return
	var img := t.get_image()                              # мипмапы — при отдалении подписи не рябят
	if img != null:
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	_map_tex = t
	_glyphs = mod.texture(str(_art.get("glyphs", "")))
	_frame_tip = mod.texture("textures/inventory/frame_mini.png")
	_div = mod.texture("textures/inventory/div_header.png")
	if _f_sc == null:
		_f_sc = _ff("fonts/cormorant_sc.ttf")
		_f_it = _ff("fonts/cormorant_garamond_italic.ttf")
	if _vign == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.03, 0.008, 0.016, 0.0))
		g.add_point(0.62, Color(0.03, 0.008, 0.016, 0.0))
		g.set_color(g.get_point_count() - 1, Color(0.03, 0.008, 0.016, 0.92))
		_vign = GradientTexture2D.new()
		_vign.gradient = g
		_vign.fill = GradientTexture2D.FILL_RADIAL
		_vign.fill_from = Vector2(0.5, 0.5)
		_vign.fill_to = Vector2(1.05, 1.05)
		_vign.width = 256
		_vign.height = 256
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ff(path: String) -> Font:
	var f := FontFile.new()
	f.data = mod.read_bytes(path)
	return f if not f.data.is_empty() else title_font


func _s() -> float:
	return get_viewport_rect().size.y / 1080.0


## Мир (x, z) → экран.
func _w2s(w: Vector2) -> Vector2:
	return (ANCHOR + Vector2((get_viewport_rect().size.x / _s() - 1920.0) * 0.5, 0.0) + (w - _view) * PPM * _zoom) * _s()


func _s2w(p: Vector2) -> Vector2:
	return (p / _s() - ANCHOR - Vector2((get_viewport_rect().size.x / _s() - 1920.0) * 0.5, 0.0)) / (PPM * _zoom) + _view


func _art_rect() -> Rect2:
	var r: Array = _art.get("rect", [-132, -132, 264, 264])
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


func _center_on_hero() -> void:
	if not _art_on():
		return
	_view = Vector2(-6, -8) if _zoom <= 1.0 else st.get("me", Vector2(-6, -8))   # весь город; приближено — к герою
	_clamp_view()


func _clamp_view() -> void:
	var g := ground.grow(10.0)
	_view = Vector2(clampf(_view.x, g.position.x, g.end.x), clampf(_view.y, g.position.y, g.end.y))


func _legend_x() -> float:
	return get_viewport_rect().size.x / _s() - 350.0


## Значки мест, что есть на запечённой карте: [ключ, мир, номер значка, вид, крупный].
func _markers() -> Array:
	var out: Array = []
	var mk: Dictionary = _art.get("markers", {})
	var big: Array = _art.get("big", [])
	for pv: Variant in pois:
		var pd: Dictionary = pv
		if mk.has(str(pd.key)):
			out.append([str(pd.key), Vector2(float(pd.x), float(pd.z)), int(mk[str(pd.key)]), str(pd.kind), str(pd.key) in big])
	return out


func _gui_input(event: InputEvent) -> void:
	if not visible or not _art_on():
		return
	var s := _s()
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := _s2w(mb.position)
			_zoom = clampf(_zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.7, 2.6)
			_view += before - _s2w(mb.position)               # масштаб — к курсору
			_clamp_view()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press = mb.position
			if not _legend_click(mb.position / s):
				var w := _s2w(mb.position)
				pin = Vector2(INF, INF) if pin.x != INF and (_w2s(pin) - mb.position).length() < 16.0 * s else w
		accept_event()
		queue_redraw()
		_ink.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag:
			_view -= mm.relative / (PPM * _zoom * s)
			_clamp_view()
		var best := ""
		var bd := 22.0 * s
		for m: Variant in _markers():
			var ma: Array = m
			if _hidden.get(str(ma[3]), false):
				continue
			var d := (_w2s(ma[1]) - mm.position).length()
			if d < bd:
				bd = d
				best = str(ma[0])
		_hover = best
		accept_event()


func _input(event: InputEvent) -> void:
	if not visible or not _art_on() or not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_L:
		_legend_on = not _legend_on
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_SPACE:
		_zoom = maxf(_zoom, 1.3)
		_view = st.get("me", _view)
		_clamp_view()
		get_viewport().set_input_as_handled()


## Щелчок по строке легенды — скрыть / показать этот вид значков.
func _legend_click(p: Vector2) -> bool:
	if not _legend_on:
		return false
	var lx := _legend_x()
	if p.x < lx or p.x > lx + LEG.size.x or p.y < LEG.position.y or p.y > LEG.position.y + 520.0:
		return false
	var y := LEG.position.y + 90.0
	for kk: String in _legend_kinds():
		if absf(p.y - y) < 20.0:
			_hidden[kk] = not bool(_hidden.get(kk, false))
			return true
		y += 44.0
	return true


func _legend_kinds() -> Array:
	var out: Array = []
	for m: Variant in _markers():
		var kd := str((m as Array)[3])
		if not kd in out:
			out.append(kd)
	var order := ["gate", "fight", "trade", "rest", "craft", "power", "nature", "beast", "home", "road"]
	out.sort_custom(func(a: String, b: String) -> bool: return order.find(a) < order.find(b))
	return out


func _draw_art() -> void:
	_roads_view.visible = false
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color8(12, 4, 6))
	var ar := _art_rect()
	var a := _w2s(ar.position)
	var b := _w2s(ar.end)
	draw_texture_rect(_map_tex, Rect2(a, b - a), false)
	draw_texture_rect(_vign, Rect2(Vector2.ZERO, vs), false)


## Буквы вразрядку (заголовки): x — левый край или середина (center).
func _spaced(ci: CanvasItem, p: Vector2, txt: String, f: Font, fs: int, col: Color, sp: float, center := false, outline := 0) -> void:
	var w := 0.0
	for ch: String in txt:
		w += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp
	w -= sp
	var x := p.x - w * 0.5 if center else p.x
	for ch: String in txt:
		if outline > 0:
			ci.draw_string_outline(f, Vector2(x, p.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0.04, 0.01, 0.015, 0.85))
		ci.draw_string(f, Vector2(x, p.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp


## Ромб места (как на запечённой миникарте): тень, тёмная заливка, золотой кант, кант цвета вида, значок.
func _marker(c: Vector2, idx: int, kind: String, sz: float, hl := false) -> void:
	var r := sz * 0.62
	_ink.draw_circle(c + Vector2(0, r * 0.35), r * 1.05, Color(0, 0, 0, 0.35))
	var dm := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	_ink.draw_colored_polygon(dm, Color8(24, 8, 10, 235))
	_ink.draw_polyline(dm + PackedVector2Array([dm[0]]), Color(1.0, 0.86, 0.59) if hl else GOLD, 3.0 if hl else 2.0, true)
	var i := r - sz * 0.18
	var dm2 := PackedVector2Array([c + Vector2(0, -i), c + Vector2(i, 0), c + Vector2(0, i), c + Vector2(-i, 0)])
	_ink.draw_polyline(dm2 + PackedVector2Array([dm2[0]]), Color(KCOL.get(kind, Color8(120, 40, 40)), 0.8), 1.0, true)
	if _glyphs != null:
		var cols := int(_art.get("glyph_cols", 5))
		var cell := float(_glyphs.get_width()) / cols
		var src := Rect2((idx % cols) * cell, (idx / cols) * cell, cell, cell)
		var gs := sz * 0.74
		_ink.draw_texture_rect_region(_glyphs, Rect2(c - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), src)


func _draw_art_ink() -> void:
	var s := _s()
	var vs := get_viewport_rect().size
	_ink.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mk := _markers()
	for m: Variant in mk:                                  # значки мест
		var ma: Array = m
		if _hidden.get(str(ma[3]), false):
			continue
		_marker(_w2s(ma[1]), int(ma[2]), str(ma[3]), (34.0 if bool(ma[4]) else 28.0) * s * clampf(sqrt(_zoom), 0.85, 1.35),
			str(ma[0]) == _hover)
	for e: Variant in st.get("enemies", []):              # враги
		var p := _w2s((e as Dictionary).pos)
		var dm := PackedVector2Array([p + Vector2(0, -6) * s, p + Vector2(6, 0) * s, p + Vector2(0, 6) * s, p + Vector2(-6, 0) * s])
		_ink.draw_colored_polygon(dm, RED)
		_ink.draw_polyline(dm + PackedVector2Array([dm[0]]), Color(0.08, 0.0, 0.0), 1.0, true)
	if pin.x != INF:                                       # метка игрока
		var pp := _w2s(pin)
		_ink.draw_line(pp, pp + Vector2(0, -22) * s, GOLD, 2.0 * s, true)
		var fl := PackedVector2Array([pp + Vector2(0, -22) * s, pp + Vector2(14, -17) * s, pp + Vector2(0, -12) * s])
		_ink.draw_colored_polygon(fl, RED)
		_ink.draw_polyline(fl + PackedVector2Array([fl[0]]), GOLD, 1.2 * s, true)
		_ink.draw_circle(pp, 3.0 * s, GOLD)
	var me: Vector2 = st.get("me", Vector2.ZERO)          # герой: конус взгляда камеры и стрелка по телу
	var hp := _w2s(me)
	var yaw := float(st.get("yaw", 0.0))
	var cone := PackedVector2Array([hp])
	for i: int in 11:
		var an := -yaw - 0.5 + i * 0.1
		cone.append(hp + Vector2(sin(an), -cos(an)) * 60.0 * s)
	_ink.draw_colored_polygon(cone, Color(1.0, 0.86, 0.63, 0.2))
	var body := float(st.get("body_yaw", yaw))
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -13), Vector2(9, 10), Vector2(0, 5), Vector2(-9, 10)]:
		arrow.append(hp + v.rotated(-body) * s)
	_ink.draw_colored_polygon(arrow, Color(1.0, 0.91, 0.7))
	_ink.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0.35, 0.08, 0.08), 1.5 * s, true)
	_ink.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var W := vs.x / s
	var H := 1080.0
	# заголовок — город вразрядку, под ним — золотой разделитель
	_spaced(_ink, Vector2(70, 78), str(st.get("place", "")).to_upper(), _f_sc, 46, Color(0.965, 0.886, 0.73), 10.0, false, 6)
	if _div != null:
		_ink.draw_texture_rect(_div, Rect2(52, 92, 300, 30), false)
	# компас справа сверху: север всегда вверху
	var cc := Vector2(W - 180.0, 80.0)
	_ink.draw_arc(cc, 30.0, 0.0, TAU, 48, Color8(150, 104, 56), 1.0, true)
	var nd := PackedVector2Array([cc + Vector2(0, -26), cc + Vector2(6, 0), cc + Vector2(0, 26), cc + Vector2(-6, 0)])
	_ink.draw_colored_polygon(nd, Color8(150, 30, 36))
	_ink.draw_polyline(nd + PackedVector2Array([nd[0]]), GOLD, 1.2, true)
	_spaced(_ink, Vector2(cc.x, cc.y - 36.0), _north(), _f_sc, 20, GOLD, 0.0, true)
	if _legend_on:
		_draw_art_legend(mk)
	if _hover != "":
		_draw_tip(mk)
	# строка клавиш внизу
	_ink.draw_rect(Rect2(0, H - KEYS_H, W, KEYS_H), Color8(8, 2, 4, 210))
	_ink.draw_line(Vector2(0, H - KEYS_H), Vector2(W, H - KEYS_H), Color8(120, 84, 48), 1.0)
	var keys := [[mod.tr_key("pax_rpg_key_lmb"), "pax_rpg_map_key_pin"], [mod.tr_key("pax_rpg_key_wheel"), "pax_rpg_map_key_zoom"],
		[mod.tr_key("pax_rpg_key_rmb"), "pax_rpg_map_key_pan"], ["L", "pax_rpg_map_key_legend"],
		[mod.tr_key("pax_rpg_key_space"), "pax_rpg_map_key_center"], ["M", "pax_rpg_map_key_close"]]
	var tot := 0.0
	for kv: Variant in keys:
		tot += _f_sc.get_string_size(str((kv as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 26.0
		tot += title_font.get_string_size(mod.tr_key(str((kv as Array)[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 36.0
	var x := (W - tot) * 0.5
	for kv: Variant in keys:
		var cap := str((kv as Array)[0])
		var cw := _f_sc.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 18.0
		_ink.draw_rect(Rect2(x, H - 34.0, cw, 22.0), GOLD, false, 1.0)
		_ink.draw_string(_f_sc, Vector2(x + 9.0, H - 17.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, IVORY)
		x += cw + 8.0
		var lab := mod.tr_key(str((kv as Array)[1]))
		_ink.draw_string(title_font, Vector2(x, H - 17.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color8(200, 176, 140))
		x += title_font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 36.0


func _north() -> String:
	return "С" if mod.tr_key("pax_rpg_map_legend") == "Легенда" else "N"


func _draw_art_legend(mk: Array) -> void:
	var lx := _legend_x()
	var ly := LEG.position.y
	var lw := LEG.size.x
	var kinds_l := _legend_kinds()
	var lh := 90.0 + kinds_l.size() * 44.0 + 6.0 + 26.0 + 3.0 * 36.0
	_ink.draw_rect(Rect2(lx, ly, lw, lh), Color8(14, 5, 7, 200))
	_ink.draw_rect(Rect2(lx, ly, lw, lh), Color8(150, 104, 56), false, 1.0)
	_ink.draw_rect(Rect2(lx + 4, ly + 4, lw - 8, lh - 8), Color8(90, 60, 34), false, 1.0)
	_spaced(_ink, Vector2(lx + lw * 0.5, ly + 38.0), mod.tr_key("pax_rpg_map_legend").to_upper(), _f_sc, 22, Color8(240, 220, 180), 5.0, true)
	if _div != null:
		_ink.draw_texture_rect(_div, Rect2(lx + 20, ly + 46, 260, 24), false)
	var cnt := {}
	for m: Variant in mk:
		cnt[str((m as Array)[3])] = int(cnt.get(str((m as Array)[3]), 0)) + 1
	var y := ly + 90.0
	for kk: String in kinds_l:
		var off := bool(_hidden.get(kk, false))
		var idx := 0
		for m: Variant in mk:
			if str((m as Array)[3]) == kk:
				idx = int((m as Array)[2])
				break
		_ink.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_marker(Vector2(lx + 34.0, y) * _s(), idx, kk, 26.0 * _s())
		_ink.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s(), _s()))
		var col := IVORY if not off else Color(IVORY_DIM, 0.6)
		_ink.draw_string(title_font, Vector2(lx + 60.0, y + 6.0), mod.tr_key("pax_rpg_map_k_" + kk), HORIZONTAL_ALIGNMENT_LEFT, lw - 120.0, 18, col)
		_ink.draw_string(title_font, Vector2(lx + lw - 84.0, y + 6.0), str(cnt.get(kk, 0)), HORIZONTAL_ALIGNMENT_RIGHT, 40.0, 18, Color8(180, 150, 110))
		_ink.draw_rect(Rect2(lx + lw - 34.0, y - 8.0, 16.0, 16.0), GOLD, false, 1.0)
		if not off:
			_ink.draw_polyline(PackedVector2Array([Vector2(lx + lw - 31.0, y), Vector2(lx + lw - 27.0, y + 5.0),
				Vector2(lx + lw - 21.0, y - 5.0)]), GOLD, 2.0, true)
		y += 44.0
	y += 6.0
	_ink.draw_line(Vector2(lx + 20.0, y), Vector2(lx + lw - 20.0, y), Color8(110, 76, 44), 1.0)
	y += 26.0
	_ink.draw_colored_polygon(PackedVector2Array([Vector2(lx + 34, y - 10), Vector2(lx + 41, y + 7), Vector2(lx + 34, y + 3),
		Vector2(lx + 27, y + 7)]), Color(1.0, 0.91, 0.7))
	_ink.draw_string(title_font, Vector2(lx + 60.0, y + 6.0), mod.tr_key("pax_rpg_map_me"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, IVORY)
	y += 36.0
	_ink.draw_colored_polygon(PackedVector2Array([Vector2(lx + 34, y - 6), Vector2(lx + 40, y), Vector2(lx + 34, y + 6),
		Vector2(lx + 28, y)]), RED)
	_ink.draw_string(title_font, Vector2(lx + 60.0, y + 6.0), mod.tr_key("pax_rpg_map_foe"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, IVORY)
	y += 36.0
	_ink.draw_line(Vector2(lx + 34, y + 6), Vector2(lx + 34, y - 12), GOLD, 2.0, true)
	_ink.draw_colored_polygon(PackedVector2Array([Vector2(lx + 34, y - 12), Vector2(lx + 46, y - 8), Vector2(lx + 34, y - 4)]), RED)
	_ink.draw_string(title_font, Vector2(lx + 60.0, y + 6.0), mod.tr_key("pax_rpg_map_pin"), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, IVORY)


## Подсказка у значка под курсором: название, вид места, сколько идти.
func _draw_tip(mk: Array) -> void:
	for m: Variant in mk:
		var ma: Array = m
		if str(ma[0]) != _hover:
			continue
		var q := _w2s(ma[1]) / _s()
		var r := Rect2(q + Vector2(30, 10), Vector2(340, 118))
		if r.end.x > _legend_x() - 10.0 and _legend_on:
			r.position.x = q.x - 30.0 - r.size.x
		if _frame_tip != null:
			_ink.draw_texture_rect(_frame_tip, r, false)
		else:
			_ink.draw_rect(r, Color8(14, 5, 7, 230))
		_ink.draw_string(title_font, r.position + Vector2(24, 40), mod.tr_key(str(ma[0])), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0, 26, IVORY)
		_ink.draw_string(_f_it, r.position + Vector2(24, 66), mod.tr_key("pax_rpg_map_k_" + str(ma[3])), HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 48.0, 18, Color8(200, 170, 130))
		var me: Vector2 = st.get("me", Vector2.ZERO)
		_ink.draw_string(title_font, r.position + Vector2(24, 94), mod.tr_key("pax_rpg_map_dist") % int((ma[1] as Vector2).distance_to(me)),
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 48.0, 18, Color8(240, 190, 100))
		return
