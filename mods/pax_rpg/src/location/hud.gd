extends Control
## HUD локации «Сакура и сталь» (концепт A): ночная лазурь и сакура, иероглифы вместо иконок.
## Слева вверху — герой (портрет, уровень, здоровье, концентрация), сверху — компас, справа — миникарта, задание и
## враг в бою; внизу — эликсир, боевые приёмы, кольцо добивания, опыт и мана. Всё рисуется здесь (_draw) по
## словарю st, который location.gd заполняет каждый кадр. Макет — 1920×1080, на другом экране масштаб по высоте.

const PINK := Color(1.0, 0.55, 0.78)
const BLUE := Color(0.47, 0.84, 1.0)
const INK := Color(0.04, 0.06, 0.14, 0.82)
const INK2 := Color(0.11, 0.11, 0.27, 0.95)
const TEXT := Color(0.96, 0.94, 1.0)
const MUTED := Color(0.78, 0.8, 0.94)
const DIM := Color(0.55, 0.58, 0.77)
const AMBER := Color(1.0, 0.71, 0.28)
const RED := Color(1.0, 0.36, 0.56)
const SHADOW := Color(0.03, 0.03, 0.1, 0.85)
const MAP_R := 118.0                # px макета, радиус миникарты
const MAP_M := 30.0                 # м мира от центра до края миникарты

var mod: PaxMod
var st: Dictionary = {}             # состояние кадра (location.gd)
var portrait: Texture2D             # портрет врага
var hero_portrait: Texture2D        # портрет героя (textures/hero_portrait.png — pax_rpg/dev/blender/knight/portrait.py)
var serif: Font
var sans: Font
var cjk: Font
var _s := 1.0                       # масштаб макета
var _w := 1920.0                    # ширина экрана в px макета
var _mask: Control                  # круг миникарты: всё, что рисует _map, обрезается по нему
var _map: Control


func setup(m: PaxMod, enemy_portrait: Texture2D) -> void:
	mod = m
	portrait = enemy_portrait
	hero_portrait = m.texture("textures/hero_portrait.png")
	name = "PaxRpgHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	serif = _sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)
	sans = _sys(["Bahnschrift", "Segoe UI", "Arial"], 400)
	cjk = _sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "Noto Serif CJK JP", "SimSun", "MS Gothic"], 700)
	_mask = Control.new()
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_mask.draw.connect(_draw_mask)
	add_child(_mask)
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	_mask.add_child(_map)


static func _sys(names: Array, weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.font_weight = weight
	return f


## Новый кадр: location.gd положил st — перерисовать.
func refresh() -> void:
	_s = maxf(size.y, 1.0) / 1080.0
	_w = size.x / _s
	var side := (MAP_R * 2.0 + 4.0) * _s
	_mask.position = Vector2((_w - 40.0 - MAP_R * 2.0 - 2.0) * _s, 28.0 * _s)
	_mask.size = Vector2(side, side)
	_map.size = _mask.size
	queue_redraw()
	_mask.queue_redraw()
	_map.queue_redraw()


func _g(k: String, d: Variant = 0.0) -> Variant:
	return st.get(k, d)


func _tr(k: String) -> String:
	return mod.tr_key(k) if mod != null else k


# ---------- рисование ----------

func _draw() -> void:
	if st.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_s, _s))
	_draw_player()
	_draw_compass()
	_draw_map_frame()
	_draw_quest()
	_draw_enemy()
	_draw_marks()
	_draw_toast()
	_draw_flask()
	_draw_skills()
	_draw_hint()
	_draw_orbs()


func _text(pos: Vector2, s: String, font: Font, fs: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT,
		width := -1.0, outline := 4) -> void:
	if outline > 0:
		draw_string_outline(font, pos, s, align, width, fs, outline, Color(SHADOW, SHADOW.a * color.a))
	draw_string(font, pos, s, align, width, fs, color)


## Текст по центру точки (по ширине и примерно по высоте).
func _center(c: Vector2, s: String, font: Font, fs: int, color: Color, outline := 0) -> void:
	_text(Vector2(c.x - 200.0, c.y + fs * 0.36), s, font, fs, color, HORIZONTAL_ALIGNMENT_CENTER, 400.0, outline)


func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


func _outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, color, width, true)


## Полоса-параллелограмм (наклон как у мазка кисти).
func _skew_bar(x: float, y: float, w: float, h: float, frac: float, color: Color) -> void:
	var k := h * 0.35
	var f := clampf(frac, 0.0, 1.0) * w
	draw_colored_polygon(PackedVector2Array([Vector2(x + k, y), Vector2(x + k + f, y), Vector2(x + f, y + h),
		Vector2(x, y + h)]), color)


func _draw_player() -> void:
	var c := Vector2(98, 92)
	draw_circle(c, 66.0, Color(PINK, 0.10))
	draw_circle(c, 58.0, INK2)
	if hero_portrait != null:                            # портрет в круге (многоугольник с UV)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i: int in 48:
			var a := TAU * i / 48.0
			var d := Vector2(cos(a), sin(a))
			pts.append(c + d * 56.0)
			uvs.append(Vector2(0.5, 0.5) + d * 0.5)
		draw_polygon(pts, PackedColorArray([Color.WHITE]), uvs, hero_portrait)
	else:
		_center(c, "騎", cjk, 52, TEXT)
	draw_arc(c, 58.0, 0.0, TAU, 64, PINK, 2.0, true)
	var d := _diamond(Vector2(140, 136), 22.0)
	draw_colored_polygon(d, Color(0.04, 0.06, 0.14))
	_outline(d, BLUE, 2.0)
	_center(Vector2(140, 136), str(int(_g("level", 1))), sans, 16, BLUE)
	var name_s := _tr("pax_rpg_hero_name")
	_text(Vector2(178, 66), name_s, serif, 32, TEXT)
	var nw := serif.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	_text(Vector2(178 + nw + 14, 64), _tr("pax_rpg_hero_title").to_upper(), sans, 13, MUTED)
	# здоровье: розовый «след» недавней потери, поверх — голубое текущее
	_skew_bar(176, 84, 440, 16, 1.0, INK)
	_skew_bar(176, 84, 440, 16, float(_g("hp_ghost", 1.0)), PINK)
	_skew_bar(176, 84, 440, 16, float(_g("hp", 1.0)), BLUE)
	_text(Vector2(178, 122), "%s  %d / %d" % [_tr("pax_rpg_hero_hp"), int(_g("hp_abs", 100)),
		int(_g("hp_max", 100))], sans, 13, TEXT)
	# концентрация — от середины к краям, как в Sekiro; ближе к пределу — краснее
	var p := float(_g("posture", 0.0))
	draw_rect(Rect2(178, 132, 440, 8), INK)
	draw_rect(Rect2(178, 132, 440, 8), Color(TEXT, 0.25), false, 1.0)
	if p > 0.005:
		draw_rect(Rect2(398 - 220 * p, 132, 440 * p, 8), AMBER.lerp(RED, p))
	draw_rect(Rect2(397, 128, 2, 16), TEXT)
	# опыт: сюда перетекает мана повергнутых врагов
	var xp := float(_g("xp", 0.0))
	draw_rect(Rect2(XP_BAR.position, XP_BAR.size), INK)
	if xp > 0.002:
		var f := XP_BAR.size.x * xp
		draw_polygon(PackedVector2Array([XP_BAR.position, XP_BAR.position + Vector2(f, 0), XP_BAR.position + Vector2(f, XP_BAR.size.y),
			XP_BAR.position + Vector2(0, XP_BAR.size.y)]), PackedColorArray([BLUE, PINK, PINK, BLUE]))
		draw_circle(XP_BAR.position + Vector2(f, XP_BAR.size.y * 0.5), 4.0, Color(1, 0.9, 0.97, 0.9))
	draw_rect(Rect2(XP_BAR.position, XP_BAR.size), Color(TEXT, 0.22), false, 1.0)
	_text(XP_BAR.position + Vector2(0, 22), "%s %d · %d / %d" % [_tr("pax_rpg_hud_level"), int(_g("level", 1)),
		int(_g("xp_abs", 0)), int(_g("xp_need", 100))], sans, 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var sp := int(_g("skill_points", 0))
	if sp > 0:
		var at := XP_BAR.position + Vector2(XP_BAR.size.x - 150, 22)
		_text(at, "◆ %s: %d" % [_tr("pax_rpg_hud_skill_points"), sp], sans, 13, AMBER, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var fl := float(_g("lvl_flash", 0.0))
	if fl > 0.0:                                         # новый уровень: свет вокруг ромба уровня
		var a := clampf(fl / 1.6, 0.0, 1.0)
		for k: int in 4:
			draw_circle(Vector2(140, 136), 22.0 + (1.0 - a) * 60.0 + k * 6.0, Color(PINK, 0.12 * a))
		draw_rect(Rect2(XP_BAR.position - Vector2(4, 4), XP_BAR.size + Vector2(8, 8)), Color(PINK, 0.35 * a), false, 2.0)


const XP_BAR := Rect2(178, 152, 440, 6)              # px макета


## Куда летит мана (экранные px): конец заполненной части полоски опыта.
func xp_target(frac: float) -> Vector2:
	return (XP_BAR.position + Vector2(XP_BAR.size.x * clampf(frac, 0.0, 1.0), XP_BAR.size.y * 0.5)) * _s


func _draw_orbs() -> void:
	for o: Variant in _g("orbs", []):
		var trail: Array = (o as Array)[2]
		var k := float((o as Array)[1])
		for j: int in trail.size():                       # шлейф
			var tp: Vector2 = trail[j] / _s
			var ta := float(j + 1) / (trail.size() + 1)
			draw_circle(tp, lerpf(3.0, 9.0, ta) * (1.2 - k * 0.5), Color(1.0, 0.35, 0.72, 0.25 * ta))
		var pos: Vector2 = (o as Array)[0] / _s
		var r := lerpf(13.0, 6.0, k)
		draw_circle(pos, r * 2.4, Color(1.0, 0.3, 0.7, 0.16))
		draw_circle(pos, r * 1.15, Color(0.25, 0.04, 0.2, 0.55))
		draw_circle(pos, r, Color(1.0, 0.36, 0.74))
		draw_circle(pos, r * 0.45, Color(1, 0.95, 0.98))


func _draw_compass() -> void:
	var cx := _w * 0.5
	var yaw := float(_g("yaw", 0.0))
	var line_y := 52.0
	for i: int in 24:
		var a := float(i) / 24.0
		draw_rect(Rect2(cx - 300 + 600 * a, line_y, 600.0 / 24.0, 1), Color(TEXT, 0.7 * sin(a * PI)))
	var marks := [["С", 0.0], ["СЗ", 45.0], ["З", 90.0], ["ЮЗ", 135.0], ["Ю", 180.0], ["ЮВ", -135.0], ["В", -90.0],
		["СВ", -45.0]]
	for m: Array in marks:
		var rel := wrapf(deg_to_rad(float(m[1])) - yaw, -PI, PI)
		if absf(rel) > PI * 0.5:
			continue
		var x := cx - rel / (PI * 0.5) * 300.0
		var al := 1.0 - absf(rel) / (PI * 0.5)
		if str(m[0]) == "С":
			_center(Vector2(x, 38), "北", cjk, 18, Color(PINK, al), 3)
		else:
			_center(Vector2(x, 38), str(m[0]), sans, 15, Color(MUTED if str(m[0]).length() == 2 else TEXT, al), 3)
	for t: Variant in _g("targets", []):
		var td: Dictionary = t
		var rel := wrapf(float(td.yaw) - yaw, -PI, PI)
		if absf(rel) > PI * 0.5:
			continue
		var x := cx - rel / (PI * 0.5) * 300.0
		var col: Color = td.color
		if bool(td.get("ring", false)):
			draw_arc(Vector2(x, line_y), 6.0, 0.0, TAU, 20, col, 2.0, true)
		else:
			draw_colored_polygon(_diamond(Vector2(x, line_y), 8.0), col)
		var ly := line_y + (38.0 if bool(td.get("ring", false)) else 22.0)   # ворота — ниже, не налезают на врага
		_center(Vector2(x, ly), "%d м" % int(td.dist), sans, 13, col, 3)
	draw_rect(Rect2(cx - 1, 40, 2, 24), TEXT)


func _draw_map_frame() -> void:
	var c := Vector2(_w - 40.0 - MAP_R, 30.0 + MAP_R)
	draw_arc(c, MAP_R + 9.0, 0.0, TAU, 96, Color(PINK, 0.12), 8.0, true)
	draw_arc(c, MAP_R + 13.0, 0.0, TAU, 96, Color(PINK, 0.5), 1.5, true)
	draw_arc(c, MAP_R + 1.0, 0.0, TAU, 96, Color(TEXT, 0.6), 2.0, true)
	# север на кольце: карта вращается с камерой
	var yaw := float(_g("yaw", 0.0))
	var n := c + Vector2(sin(yaw), -cos(yaw)) * (MAP_R - 14.0)
	_center(n, "北", cjk, 14, PINK, 3)
	_center(Vector2(c.x, c.y + MAP_R + 36), str(_g("place", "")), serif, 26, TEXT, 4)
	_center(Vector2(c.x, c.y + MAP_R + 60), _tr("pax_rpg_hud_region"), sans, 13, MUTED, 3)


func _draw_mask() -> void:
	var r := MAP_R * _s
	_mask.draw_circle(Vector2(r + 2.0 * _s, r + 2.0 * _s), r, Color(0.075, 0.1, 0.235))


## Миникарта (внутри круга): верх — куда смотрит камера; платформы, ворота, враги, герой.
func _draw_map() -> void:
	if st.is_empty():
		return
	var r := MAP_R * _s
	var c := Vector2(r + 2.0 * _s, r + 2.0 * _s)
	var k := r / MAP_M
	var yaw := float(_g("yaw", 0.0))
	var me: Vector2 = _g("me", Vector2.ZERO)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var to_map := func(w: Vector2) -> Vector2:
		var d := w - me
		return c + Vector2(d.dot(right), -d.dot(fwd)) * k
	# только то, что попадает в круг карты (в городе — сотни коробок; все подряд съедали ~7 мс кадра)
	var reach := MAP_M * 1.5
	var pts := PackedVector2Array()
	pts.resize(4)
	var ax := Vector2(right.x, -fwd.x) * k                # мир → карта: p = c + (d.x * ax + d.y * ay)
	var ay := Vector2(right.y, -fwd.y) * k
	for rect: Variant in _g("map_rects", []):
		var rr: Array = rect
		var d: Vector2 = (rr[0] as Vector2) - me
		var half: Vector2 = (rr[1] as Vector2) * 0.5
		if absf(d.x) - half.x > reach or absf(d.y) - half.y > reach:
			continue
		pts[0] = c + (d.x - half.x) * ax + (d.y - half.y) * ay
		pts[1] = c + (d.x + half.x) * ax + (d.y - half.y) * ay
		pts[2] = c + (d.x + half.x) * ax + (d.y + half.y) * ay
		pts[3] = c + (d.x - half.x) * ax + (d.y + half.y) * ay
		_map.draw_colored_polygon(pts, rr[2])
	var gate: Vector2 = _g("gate", Vector2.ZERO)
	_map.draw_arc(to_map.call(gate), 7.0 * _s, 0.0, TAU, 20, BLUE, 2.0 * _s, true)
	for e: Variant in _g("enemies", []):
		var ed: Dictionary = e
		var p: Vector2 = to_map.call(ed.pos)
		var col: Color = RED if bool(ed.get("locked", false)) else PINK
		var dm := PackedVector2Array()
		for v: Vector2 in _diamond(p, 6.0 * _s):
			dm.append(v)
		_map.draw_colored_polygon(dm, col)
	# герой — стрелка вверх (камера) повёрнута на поворот тела
	var body := float(_g("body_yaw", yaw)) - yaw
	var arrow := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -12), Vector2(8, 10), Vector2(0, 5), Vector2(-8, 10)]:
		arrow.append(c + v.rotated(-body) * _s)
	_map.draw_colored_polygon(arrow, BLUE)


func _draw_quest() -> void:
	var rx := _w - 40.0
	var y := 372.0
	_text(Vector2(rx - 320, y), _tr("pax_rpg_hud_quest").to_upper(), sans, 12, PINK, HORIZONTAL_ALIGNMENT_RIGHT, 320)
	_text(Vector2(rx - 320, y + 32), _tr("pax_rpg_quest_title"), serif, 27, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 320)
	_text(Vector2(rx - 320, y + 62), _tr("pax_rpg_quest_kills") % int(_g("kills", 0)), sans, 15, TEXT,
		HORIZONTAL_ALIGNMENT_RIGHT, 320)
	var near := bool(_g("near_gate", false))
	_text(Vector2(rx - 320, y + 90), _tr("pax_rpg_quest_exit"), sans, 15, PINK if near else DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, 320)


func _draw_enemy() -> void:
	var e: Dictionary = _g("enemy", {})
	if e.is_empty():
		_boss_ghost = 1.0
		return
	if bool(e.get("boss", false)):
		_draw_boss(e)
		return
	var r := Rect2(_w - 40.0 - 380.0, 580.0, 380.0, 116.0)
	draw_rect(r, Color(0.04, 0.06, 0.14, 0.72))
	draw_rect(r, Color(PINK, 0.45), false, 1.0)
	var pic := Rect2(r.position + Vector2(16, 16), Vector2(84, 84))
	draw_rect(pic, Color(0.16, 0.11, 0.24))
	if portrait != null:
		draw_texture_rect(portrait, pic, false)
	else:
		_center(pic.get_center(), "鬼", cjk, 40, PINK)
	draw_rect(pic, PINK, false, 1.0)
	var x := r.position.x + 116.0
	var w := r.size.x - 132.0
	_text(Vector2(x, r.position.y + 38), str(e.get("name", "")), serif, 23, TEXT)
	draw_rect(Rect2(x, r.position.y + 52, w, 10), Color(0.1, 0.08, 0.19))
	draw_rect(Rect2(x, r.position.y + 52, w * float(e.get("hp", 1.0)), 10), RED)
	var p := float(e.get("posture", 0.0))
	draw_rect(Rect2(x, r.position.y + 68, w, 6), Color(0.1, 0.08, 0.19))
	if p > 0.005:
		draw_rect(Rect2(x + w * 0.5 * (1.0 - p), r.position.y + 68, w * p, 6), AMBER.lerp(RED, p))
	var status := ""
	var sc := MUTED
	if bool(e.get("broken", false)):
		status = _tr("pax_rpg_hud_broken")
		sc = PINK
	elif p > 0.7:
		status = _tr("pax_rpg_hud_posture_high")
		sc = AMBER
	else:
		status = _tr("pax_rpg_hud_weak")
	_text(Vector2(x, r.position.y + 96), status, sans, 13, sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 0)


## Босс — полоса в стиле Гхарна вверху по центру (под компасом, не мешает приёмам внизу): тёмная лакированная
## плашка в двойной золотой рамке с клыками на концах (как Врата Клыка), слева — красный ромб с 闘, над полосой —
## имя золотом, под ней — титул. Здоровье — киноварь со «следом» снятого урона; концентрация — под полосой от центра.
var _boss_ghost := 1.0
const GOLD := Color(0.88, 0.68, 0.32)
const CINNABAR := Color(0.78, 0.12, 0.16)


func _draw_boss(e: Dictionary) -> void:
	var w := 760.0
	var x := (_w - w) * 0.5
	var y := 132.0                                     # верх полосы (под компасом)
	var h := 14.0
	var hp := clampf(float(e.get("hp", 1.0)), 0.0, 1.0)
	_boss_ghost = maxf(hp, move_toward(_boss_ghost, hp, 0.004))
	# плашка
	var plate := PackedVector2Array([Vector2(x - 34, y - 46), Vector2(x + w + 34, y - 46), Vector2(x + w + 20, y + h + 30),
		Vector2(x - 20, y + h + 30)])
	draw_colored_polygon(plate, Color(0.06, 0.03, 0.05, 0.78))
	draw_polyline(plate + PackedVector2Array([plate[0]]), Color(GOLD, 0.35), 1.0, true)
	# имя — золотом по центру, титул — под полосой
	_center(Vector2(_w * 0.5, y - 22.0), str(e.get("name", "")), serif, 28, Color(1.0, 0.9, 0.7), 4)
	var title := str(e.get("title", ""))
	if title != "":
		_center(Vector2(_w * 0.5, y + h + 18.0), title.to_upper(), sans, 12, Color(GOLD, 0.9), 3)
	# полоса: подложка, след, здоровье, блик
	draw_rect(Rect2(x, y, w, h), Color(0.12, 0.04, 0.06))
	draw_rect(Rect2(x, y, w * _boss_ghost, h), Color(1.0, 0.82, 0.7, 0.5))
	draw_rect(Rect2(x, y, w * hp, h), CINNABAR)
	draw_rect(Rect2(x, y + 1.0, w * hp, 3.0), Color(1.0, 0.45, 0.4, 0.75))
	for k: int in range(1, 10):                          # насечки по десятым — читается остаток
		draw_line(Vector2(x + w * k / 10.0, y), Vector2(x + w * k / 10.0, y + h), Color(0, 0, 0, 0.35), 1.0)
	# двойная золотая рамка и клыки на концах
	draw_rect(Rect2(x - 2, y - 2, w + 4, h + 4), GOLD, false, 1.5)
	draw_rect(Rect2(x - 5, y - 5, w + 10, h + 10), Color(GOLD, 0.45), false, 1.0)
	for sd: float in [-1.0, 1.0]:
		var ex := x - 5.0 if sd < 0.0 else x + w + 5.0
		var fang := PackedVector2Array([Vector2(ex, y - 5), Vector2(ex + sd * 26.0, y + h * 0.5), Vector2(ex, y + h + 5),
			Vector2(ex + sd * 9.0, y + h * 0.5)])
		draw_colored_polygon(fang, GOLD)
		draw_line(Vector2(ex + sd * 26.0, y + h * 0.5), Vector2(ex + sd * 38.0, y + h * 0.5), Color(GOLD, 0.6), 1.5)
	# ромб с 闘 слева
	var dc := Vector2(x - 62.0, y + h * 0.5)
	var dm := PackedVector2Array()
	for v: Vector2 in _diamond(dc, 22.0):
		dm.append(v)
	draw_colored_polygon(dm, CINNABAR)
	_outline(dm, GOLD, 2.0)
	_center(dc + Vector2(0, 7), "闘", cjk, 22, Color(1.0, 0.92, 0.8), 2)
	# концентрация — тонкая под полосой, от центра в стороны
	var p := clampf(float(e.get("posture", 0.0)), 0.0, 1.0)
	var broken := bool(e.get("broken", false))
	if p > 0.005 or broken:
		var pw := 420.0
		var py := y + h + 30.0
		draw_rect(Rect2((_w - pw) * 0.5, py, pw, 6.0), Color(0.05, 0.03, 0.06, 0.85))
		var col := PINK if broken else AMBER.lerp(RED, p)
		var pp := 1.0 if broken else p
		draw_rect(Rect2((_w - pw * pp) * 0.5, py, pw * pp, 6.0), col)
		draw_rect(Rect2(_w * 0.5 - 1.0, py - 3.0, 2.0, 12.0), Color(GOLD, 0.9))


## Метки поверх мира: прицел захвата и цифры урона (координаты — пиксели экрана, location.gd проецирует).
func _draw_marks() -> void:
	var lk: Variant = _g("lock_screen", null)
	if lk is Vector2:
		var p: Vector2 = lk / _s
		draw_circle(p, 22.0, Color(PINK, 0.12))
		draw_arc(p, 20.0, 0.0, TAU, 40, PINK, 2.0, true)
		var dm := _diamond(p, 8.0 if not bool(_g("lock_broken", false)) else 11.0)
		draw_colored_polygon(dm, RED if bool(_g("lock_broken", false)) else Color(PINK, 0.8))
	for n: Variant in _g("numbers", []):
		var nd: Dictionary = n
		var p: Vector2 = nd.p / _s
		var a := float(nd.a)
		var crit := bool(nd.get("crit", false))
		if crit:
			_text(p + Vector2(4, -36), _tr("pax_rpg_hud_crit"), sans, 13, Color(1.0, 0.89, 0.95, a), HORIZONTAL_ALIGNMENT_LEFT,
				-1, 3)
		_text(p, str(nd.v), sans, 40 if crit else 30, Color(PINK if crit else TEXT, a), HORIZONTAL_ALIGNMENT_LEFT,
			-1, 6)


func _draw_toast() -> void:
	var t: Dictionary = _g("toast", {})
	if t.is_empty():
		return
	var a := float(t.get("a", 1.0))
	var r := Rect2(40, 430, 380, 42)
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([Color(PINK, 0.3 * a), Color(PINK, 0.0), Color(PINK, 0.0), Color(PINK, 0.3 * a)]))
	_outline(_diamond(Vector2(62, 451), 10.0), Color(BLUE, a), 2.0)
	_text(Vector2(84, 457), str(t.get("text", "")), sans, 17, Color(TEXT, a))


func _draw_flask() -> void:
	var n := int(_g("flask", 0))
	var nmax := int(_g("flask_max", 3))
	var box := Rect2(40, 1080 - 60 - 92, 92, 92)
	draw_rect(box, INK)
	draw_rect(box, Color(TEXT, 0.7), false, 2.0)
	_text(Vector2(40, box.position.y - 12), _tr("pax_rpg_hud_flask"), sans, 13, MUTED)
	var o := box.position + Vector2(24, 18)
	var bottle := PackedVector2Array([o + Vector2(16, 0), o + Vector2(28, 0), o + Vector2(28, 10), o + Vector2(40, 26),
		o + Vector2(40, 54), o + Vector2(4, 54), o + Vector2(4, 26), o + Vector2(16, 10)])
	if n > 0:
		var lvl := 54.0 - 28.0 * float(n) / float(maxi(nmax, 1))
		draw_colored_polygon(PackedVector2Array([o + Vector2(6, lvl), o + Vector2(38, lvl), o + Vector2(38, 52),
			o + Vector2(6, 52)]), PINK)
	_outline(bottle, Color(1.0, 0.89, 0.95), 2.0)
	_text(Vector2(box.end.x - 22, box.end.y - 8), str(n), sans, 20, TEXT if n > 0 else DIM)


func _draw_skills() -> void:
	var rx := _w - 40.0
	# кольцо добивания: заполнено концентрацией врага, горит, когда можно добить
	var uc := Vector2(rx - 68, 1080 - 50 - 68 - 10)
	var up := float(_g("ult", 0.0))
	var ready := bool(_g("ult_ready", false))
	if ready:
		draw_circle(uc, 80.0, Color(PINK, 0.18))
	draw_circle(uc, 68.0, Color(TEXT, 0.15))
	if up > 0.0:
		draw_arc(uc, 63.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(up, 0.0, 1.0), 72, PINK, 10.0, true)
	draw_circle(uc, 58.0, Color(0.07, 0.06, 0.16))
	_center(uc, "桜", cjk, 56, Color(1.0, 0.89, 0.95) if ready else Color(0.72, 0.66, 0.8))
	_text(Vector2(uc.x - 160, uc.y + 98), _tr("pax_rpg_hud_deathblow_ready") if ready else
		_tr("pax_rpg_hud_deathblow") % int(up * 100.0), sans, 13, PINK if ready else MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 228)
	var x := uc.x - 68.0 - 70.0
	var skills: Array = _g("skills", [])
	for i: int in range(skills.size() - 1, -1, -1):
		var sd: Dictionary = skills[i]
		var c := Vector2(x, uc.y - 8)
		var on := bool(sd.get("on", false))
		var ring: Color = sd.get("color", PINK)
		var dm := _diamond(c, 47.0)
		draw_colored_polygon(dm, Color(0.04, 0.06, 0.14, 0.9 if on else 0.6))
		_outline(dm, ring if on else Color(TEXT, 0.35), 2.5 if on else 1.5)
		if on:
			draw_colored_polygon(_diamond(c, 41.0), Color(ring, 0.18))
		var ic: Variant = sd.get("icon", null)
		if ic is Texture2D:                              # своя иконка (приём) вместо иероглифа
			var isz := 62.0
			draw_texture_rect(ic, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false,
				Color(1, 1, 1, 1.0 if bool(sd.get("ready", true)) else 0.35))
		else:
			_center(c, str(sd.k), cjk, 30, TEXT if on or bool(sd.get("ready", true)) else DIM)
		var cd := float(sd.get("cd", 0.0))
		if cd > 0.0:                                     # перезарядка: тёмная часть ромба сверху и секунды
			var full := _diamond(c, 41.0)
			var cut := c.y + 41.0 - 82.0 * (1.0 - cd)
			var top := Geometry2D.intersect_polygons(full, PackedVector2Array([Vector2(c.x - 50, c.y - 50),
				Vector2(c.x + 50, c.y - 50), Vector2(c.x + 50, cut), Vector2(c.x - 50, cut)]))
			if top.size() > 0:
				draw_colored_polygon(top[0], Color(0.02, 0.02, 0.06, 0.7))
			_center(c + Vector2(0, 10), str(sd.get("cd_s", "")), sans, 22, TEXT, 4)
		_center(Vector2(c.x, c.y + 66), "%s · %s" % [sd.key, sd.label], sans, 13, MUTED, 3)
		x -= 116.0


func _draw_xp() -> void:
	var x0 := 560.0
	var x1 := _w - 560.0
	if x1 - x0 < 300.0:
		x0 = _w * 0.5 - 150.0
		x1 = _w * 0.5 + 150.0
	var y := 1080.0 - 26.0
	var xp := float(_g("xp", 0.0))
	_text(Vector2(x0, y - 10), "%s %d · %d%%" % [_tr("pax_rpg_hud_level"), int(_g("level", 1)), int(xp * 100.0)], sans,
		13, MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var mana := "%d %s" % [int(_g("mana", 0)), _tr("pax_rpg_hud_mana")]
	_text(Vector2(x1 - 300, y - 10), mana, sans, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 300, 3)
	var mw := sans.get_string_size(mana, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_colored_polygon(_diamond(Vector2(x1 - mw - 10, y - 15), 5.0), BLUE)
	draw_rect(Rect2(x0, y, x1 - x0, 3), Color(TEXT, 0.15))
	var f := (x1 - x0) * clampf(xp, 0.0, 1.0)
	if f > 1.0:
		draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x0 + f, y), Vector2(x0 + f, y + 3), Vector2(x0, y + 3)]),
			PackedColorArray([BLUE, PINK, PINK, BLUE]))


## Разбить строку по словам (разделитель « · » — по пунктам), чтобы каждая часть влезала в width.
func _wrap(line: String, width: float, fs: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for word: String in line.split(" "):
		var next := word if cur == "" else cur + " " + word
		if cur != "" and sans.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			out.append(cur)
			cur = word
		else:
			cur = next
	if cur != "":
		out.append(cur)
	return out


func _draw_hint() -> void:
	var a := float(_g("hint_a", 0.0))
	if a > 0.01:
		var y := 250.0
		var width := minf(1100.0, _w - 40.0 - 480.0)          # не залезать под миникарту и задание справа
		for line: String in str(_g("hint", "")).split("\n"):
			for part: String in _wrap(line, width, 14):
				_text(Vector2(40, y), part, sans, 14, Color(MUTED, a), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
				y += 22.0
	var g := str(_g("gate_hint", ""))
	if g != "":
		_center(Vector2(_w * 0.5, 1080 - 90), g, sans, 18, PINK, 5)
