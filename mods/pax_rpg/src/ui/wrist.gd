extends Control
## Наручный терминал героя (TAB / Esc в городе): голографическая панель встаёт над левым запястьем героя (точка на
## экране — location.gd, по кости руки) и раскрывается снизу вверх. Кнопки: Инвентарь, Карта, Меню — сигнал picked(id).
## Стиль — палитра HUD героя (hud.gd: c_gold, c_pink, c_text). Пока открыт, мир на паузе (location.gd → paused()).

signal picked(id: String)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const ITEMS := [["inventory", "pax_rpg_wrist_inventory", "TAB"], ["map", "pax_rpg_wrist_map", "M"],
	["menu", "pax_rpg_wrist_menu", "Esc"]]
const W := 300.0
const ROW := 58.0

var mod: PaxMod
var hud: Hud
var anchor := Vector2.ZERO           # запястье на экране (px окна)
var _open := 0.0                     # 0..1 — раскрытие
var _t := 0.0
var _hover := -1
var _font: Font
var _mono: Font


func setup(m: PaxMod, h: Hud) -> void:
	mod = m
	hud = h
	name = "PaxRpgWrist"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_font = Hud._sys(["Cormorant Garamond", "Georgia", "Times New Roman"], 700)
	_mono = Hud._sys(["Bahnschrift", "Consolas", "Segoe UI"], 400)


func open_at(p: Vector2) -> void:
	anchor = p
	_open = 0.0
	_hover = -1
	visible = true


func close() -> void:
	visible = false


func _s() -> float:
	return maxf(size.y, 1.0) / 1080.0


## Прямоугольник панели (px окна): над запястьем, не вылезает за экран.
func _panel_rect() -> Rect2:
	var s := _s()
	var h := (ROW * ITEMS.size() + 74.0) * s
	var w := W * s
	var pos := anchor + Vector2(-w * 0.5, -h - 60.0 * s)
	pos.x = clampf(pos.x, 16.0 * s, size.x - w - 16.0 * s)
	pos.y = clampf(pos.y, 16.0 * s, size.y - h - 16.0 * s)
	return Rect2(pos, Vector2(w, h))


func _row_rect(i: int) -> Rect2:
	var r := _panel_rect()
	var s := _s()
	return Rect2(r.position + Vector2(14.0 * s, (54.0 + ROW * i) * s), Vector2(r.size.x - 28.0 * s, (ROW - 8.0) * s))


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_open = minf(1.0, _open + delta * 5.0)
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_hover = -1
		for i: int in ITEMS.size():
			if _row_rect(i).has_point((e as InputEventMouseMotion).position):
				_hover = i
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mp := (e as InputEventMouseButton).position
		for i: int in ITEMS.size():
			if _row_rect(i).has_point(mp):
				picked.emit(str(ITEMS[i][0]))
				return
		if not _panel_rect().has_point(mp):
			close()
			picked.emit("")                              # щелчок мимо — закрыть


func _draw() -> void:
	var gold: Color = hud.c_gold if hud != null else Hud.GOLD
	var accent: Color = hud.c_pink if hud != null else Hud.PINK
	var text: Color = hud.c_text if hud != null else Hud.TEXT
	var muted: Color = hud.c_muted if hud != null else Hud.MUTED
	var s := _s()
	var r := _panel_rect()
	var k := _open * _open * (3.0 - 2.0 * _open)
	# луч от запястья к панели (проектор браслета)
	var base := Vector2(r.get_center().x, r.end.y)
	draw_colored_polygon(PackedVector2Array([anchor + Vector2(-6, 0) * s, anchor + Vector2(6, 0) * s,
		base + Vector2(r.size.x * 0.45, 0) * k, base - Vector2(r.size.x * 0.45, 0) * k]), Color(accent, 0.08 * k))
	draw_circle(anchor, 6.0 * s, Color(accent, 0.9))
	draw_arc(anchor, (10.0 + 4.0 * sin(_t * 6.0)) * s, 0.0, TAU, 24, Color(accent, 0.5), 1.5 * s, true)
	# панель раскрывается снизу вверх
	var rr := Rect2(Vector2(r.position.x, r.end.y - r.size.y * k), Vector2(r.size.x, r.size.y * k))
	draw_rect(rr, Color(0.03, 0.03, 0.04, 0.82))
	for y: int in int(rr.size.y / (3.0 * s)):          # строки развёртки голограммы
		draw_line(Vector2(rr.position.x, rr.position.y + y * 3.0 * s), Vector2(rr.end.x, rr.position.y + y * 3.0 * s),
			Color(accent, 0.035), 1.0)
	draw_rect(rr, Color(gold, 0.85), false, 1.5 * s)
	for cx: float in [rr.position.x, rr.end.x]:        # уголки
		for cy: float in [rr.position.y, rr.end.y]:
			var dx := 14.0 * s * (1.0 if cx == rr.position.x else -1.0)
			var dy := 14.0 * s * (1.0 if cy == rr.position.y else -1.0)
			draw_line(Vector2(cx, cy), Vector2(cx + dx, cy), gold, 3.0 * s)
			draw_line(Vector2(cx, cy), Vector2(cx, cy + dy), gold, 3.0 * s)
	if k < 0.98:
		return
	draw_string(_mono, r.position + Vector2(18, 32) * s, mod.tr_key("pax_rpg_wrist_title").to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * s), Color(accent, 0.9))
	draw_line(r.position + Vector2(18, 42) * s, r.position + Vector2(r.size.x / s - 18, 42) * s, Color(gold, 0.4), 1.0)
	for i: int in ITEMS.size():
		var rw := _row_rect(i)
		var on := i == _hover
		draw_rect(rw, Color(accent, 0.16 if on else 0.05))
		draw_rect(rw, Color(gold if on else muted, 0.7 if on else 0.3), false, 1.0)
		var fs := int(24 * s)
		draw_string(_font, rw.position + Vector2(14 * s, rw.size.y * 0.5 + fs * 0.35), mod.tr_key(str(ITEMS[i][1])),
			HORIZONTAL_ALIGNMENT_LEFT, rw.size.x - 80 * s, fs, text if on else muted)
		draw_string(_mono, rw.position + Vector2(rw.size.x - 64 * s, rw.size.y * 0.5 + 6 * s), str(ITEMS[i][2]),
			HORIZONTAL_ALIGNMENT_RIGHT, 52 * s, int(14 * s), Color(gold, 0.8))
