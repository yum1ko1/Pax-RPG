extends Control
## Выбор приёма за сданное поручение: две карточки (progress.gd → offer), щелчок или 1 / 2 — взять. Мир на паузе,
## пока открыт (location.gd → paused()). Закрыть без выбора нельзя: приём ждёт, пока его возьмут.

signal picked(id: String)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const W := 820.0
const H := 430.0

var mod: PaxMod
var hud: Hud
var choices: Array = []
var _serif: Font
var _sans: Font
var _hover := -1


func setup(m: PaxMod, h: Hud) -> void:
	mod = m
	hud = h
	name = "PaxRpgPerkPick"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_serif = Hud._sys(["Cormorant Garamond", "Georgia", "Times New Roman"], 700)
	_sans = Hud._sys(["Bahnschrift", "Segoe UI", "Arial"], 400)


func open(ids: Array) -> void:
	choices = ids
	_hover = -1
	visible = not ids.is_empty()
	queue_redraw()


func _scale() -> float:
	return clampf(size.y / 1080.0, 0.6, 2.0)


func _card(i: int) -> Rect2:
	var s := _scale()
	var r := Rect2((size - Vector2(W, H) * s) * 0.5, Vector2(W, H) * s)
	var cw := (r.size.x - 34.0 * 3.0 * s) * 0.5
	return Rect2(r.position + Vector2(34.0 * s + i * (cw + 34.0 * s), 120.0 * s), Vector2(cw, r.size.y - 160.0 * s))


func _take(i: int) -> void:
	if i < 0 or i >= choices.size():
		return
	var id := str(choices[i])
	visible = false
	choices = []
	picked.emit(id)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := -1
		for i: int in choices.size():
			if _card(i).has_point((e as InputEventMouseMotion).position):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()
	elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i: int in choices.size():
			if _card(i).has_point((e as InputEventMouseButton).position):
				_take(i)
				return


## Клавиша, пока окно открыто (location.gd → _input): 1 / 2 — взять карточку.
func key(code: int) -> void:
	match code:
		KEY_1, KEY_KP_1:
			_take(0)
		KEY_2, KEY_KP_2:
			_take(1)


func _draw() -> void:
	var s := _scale()
	var r := Rect2((size - Vector2(W, H) * s) * 0.5, Vector2(W, H) * s)
	var gold: Color = hud.c_gold if hud != null else Hud.GOLD
	var text: Color = hud.c_text if hud != null else Hud.TEXT
	var muted: Color = hud.c_muted if hud != null else Hud.MUTED
	var accent: Color = hud.c_pink if hud != null else Hud.PINK
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(r, Color(0.05, 0.04, 0.035, 0.96))
	draw_rect(r, Color(gold, 0.85), false, 2.0 * s)
	draw_rect(r.grow(-6.0 * s), Color(gold, 0.3), false, 1.0)
	var x := r.position.x + 34.0 * s
	var w := r.size.x - 68.0 * s
	draw_string(_serif, Vector2(x, r.position.y + 58.0 * s), mod.tr_key("pax_rpg_perk_title"), HORIZONTAL_ALIGNMENT_CENTER, w,
		int(36 * s), text)
	draw_string(_sans, Vector2(x, r.position.y + 92.0 * s), mod.tr_key("pax_rpg_perk_sub"), HORIZONTAL_ALIGNMENT_CENTER, w,
		int(16 * s), muted)
	for i: int in choices.size():
		var c := _card(i)
		var on := i == _hover
		draw_rect(c, Color(0.11, 0.08, 0.06, 0.95) if on else Color(0.08, 0.06, 0.05, 0.9))
		draw_rect(c, Color(gold, 0.95 if on else 0.5), false, (2.0 if on else 1.0) * s)
		var id := str(choices[i])
		var cx := c.position.x + 22.0 * s
		var cw := c.size.x - 44.0 * s
		draw_string(_sans, Vector2(cx, c.position.y + 34.0 * s), str(i + 1), HORIZONTAL_ALIGNMENT_RIGHT, cw, int(16 * s),
			Color(gold, 0.8))
		draw_string(_serif, Vector2(cx, c.position.y + 70.0 * s), "❖ " + mod.tr_key("pax_rpg_perk_" + id), HORIZONTAL_ALIGNMENT_LEFT,
			cw, int(28 * s), Color(1.0, 0.8, 0.35))
		draw_line(Vector2(cx, c.position.y + 88.0 * s), Vector2(cx + cw, c.position.y + 88.0 * s), Color(gold, 0.35), 1.0)
		draw_multiline_string(_sans, Vector2(cx, c.position.y + 122.0 * s), mod.tr_key("pax_rpg_perk_" + id + "_desc"),
			HORIZONTAL_ALIGNMENT_LEFT, cw, int(18 * s), -1, text)
		draw_string(_sans, Vector2(cx, c.end.y - 22.0 * s), mod.tr_key("pax_rpg_perk_take"), HORIZONTAL_ALIGNMENT_CENTER, cw,
			int(15 * s), accent if on else Color(muted, 0.8))
