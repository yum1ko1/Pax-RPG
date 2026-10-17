extends Control
## Карта города (M): весь город севером вверх — дороги по маске земли, здания (те же коробки, что у миникарты),
## подписи главных мест (config/<город>.json → landmarks), арена, ворота, враги и герой. Закрывается M или Esc.

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")

var mod: PaxMod
var st: Dictionary = {}               # тот же словарь кадра, что у HUD (location.gd)
var landmarks: Array = []             # [ключ перевода, x, z]
var arena := Vector3.ZERO             # x, z, радиус ямы (0 — нет)
var ground := Rect2()                 # мир (x, z) → весь лист карты
var roads: Texture2D                  # маска дорог (R — кладка, G — тропы)
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


## Данные города (планировка); пустая — карта не открывается (тестовая арена).
func set_city(layout: Dictionary) -> void:
	landmarks = layout.get("landmarks", [])
	var a: Array = layout.get("arena", [])
	arena = Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO
	var g: Array = layout.get("ground", [0, 0, 0, 0])
	ground = Rect2(float(g[2]) - float(g[0]) * 0.5, float(g[3]) - float(g[1]) * 0.5, float(g[0]), float(g[1]))
	var gm: Dictionary = layout.get("ground_mask", {})
	roads = mod.texture(str(gm.get("tex", ""))) if gm.has("tex") else null


func has_city() -> bool:
	return ground.size.x > 0.0


func toggle() -> void:
	visible = not visible and has_city()
	queue_redraw()


func _process(_delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("city_map._process")
	if visible:
		queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.08, 0.72))
	var side := minf(vs.x * 0.86, vs.y * 0.86)
	var k := side / maxf(ground.size.x, ground.size.y)
	var size := ground.size * k
	var o := (vs - size) * 0.5
	var to := func(w: Vector2) -> Vector2:
		return o + (w - ground.position) * k
	var s := vs.y / 1080.0
	draw_rect(Rect2(o - Vector2(10, 10) * s, size + Vector2(20, 20) * s), Hud.INK2)
	draw_rect(Rect2(o, size), Color(0.13, 0.12, 0.2))
	if roads != null:                                # дороги и тропы — из той же маски, что у земли
		draw_texture_rect(roads, Rect2(o, size), false, Color(0.95, 0.75, 0.9, 0.55))
	for rect: Variant in st.get("map_rects", []):
		var rr: Array = rect
		var c: Vector2 = to.call(rr[0] as Vector2)
		var h: Vector2 = (rr[1] as Vector2) * k * 0.5
		draw_rect(Rect2(c - h, h * 2.0), rr[2])
	draw_rect(Rect2(o, size), Color(Hud.PINK, 0.6), false, 2.0 * s)
	if arena.z > 0.0:                                # арена: песок и кольцо трибун
		var ac: Vector2 = to.call(Vector2(arena.x, arena.y))
		draw_circle(ac, arena.z * k, Color(0.78, 0.62, 0.42, 0.9))
		draw_arc(ac, (arena.z + 3.5) * k, 0.0, TAU, 48, Color(Hud.AMBER, 0.95), 3.0 * s, true)
	var gate: Vector2 = st.get("gate", Vector2.ZERO)
	draw_arc(to.call(gate), 9.0 * s, 0.0, TAU, 20, Hud.BLUE, 2.5 * s, true)
	for e: Variant in st.get("enemies", []):
		var ed: Dictionary = e
		draw_circle(to.call(ed.pos), 4.0 * s, Hud.RED)
	for lm: Variant in landmarks:                    # подписи главных мест
		var l: Array = lm
		var p: Vector2 = to.call(Vector2(float(l[1]), float(l[2])))
		var txt := mod.tr_key(str(l[0]))
		var fs := int(20 * s)
		var w := serif.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_circle(p, 3.5 * s, Hud.PINK)
		draw_string_outline(serif, p + Vector2(-w * 0.5, -8 * s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(5 * s),
			Hud.SHADOW)
		draw_string(serif, p + Vector2(-w * 0.5, -8 * s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Hud.TEXT)
	var me: Vector2 = st.get("me", Vector2.ZERO)     # герой — стрелка по повороту тела
	var body := float(st.get("body_yaw", 0.0))
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -13), Vector2(9, 11), Vector2(0, 6), Vector2(-9, 11)]:
		arrow.append(to.call(me) + v.rotated(-body) * s)
	draw_colored_polygon(arrow, Hud.BLUE)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Hud.SHADOW, 1.5 * s, true)
	var title := str(st.get("place", ""))
	var tw := serif.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * s)).x
	draw_string_outline(serif, Vector2(vs.x * 0.5 - tw * 0.5, o.y - 22 * s), title, HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(34 * s), int(6 * s), Hud.SHADOW)
	draw_string(serif, Vector2(vs.x * 0.5 - tw * 0.5, o.y - 22 * s), title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * s),
		Hud.TEXT)
	draw_string(cjk, Vector2(o.x + size.x - 28 * s, o.y + 30 * s), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, int(22 * s),
		Hud.PINK)
	var hint := mod.tr_key("pax_rpg_map_hint")
	draw_string(sans, Vector2(o.x, o.y + size.y + 34 * s), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * s), Hud.MUTED)
