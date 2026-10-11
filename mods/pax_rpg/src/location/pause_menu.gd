extends Control
## Меню паузы локации (Esc) в стиле HUD «Сакура и сталь»: затемнение, свиток по центру, кнопки.
## Мир локации на паузе, пока меню открыто (location.gd отключает обработку SubViewport).

signal resume
signal leave_city
signal show_help

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")

var _box: VBoxContainer
var _leave: Button
var _title: Label


func setup(mod: PaxMod, leave_text: String) -> void:
	name = "PaxRpgPause"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.09, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Hud.INK
	sb.border_color = Color(Hud.PINK, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	sb.content_margin_top = 32
	sb.content_margin_bottom = 36
	sb.shadow_color = Color(Hud.PINK, 0.18)
	sb.shadow_size = 24
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	panel.add_child(_box)
	var serif := Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)
	var mark := Label.new()
	mark.text = "休"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_theme_font_override("font", Hud._sys(["Yu Mincho", "MS Mincho", "Noto Serif JP", "SimSun"], 700))
	mark.add_theme_font_size_override("font_size", 44)
	mark.add_theme_color_override("font_color", Hud.PINK)
	_box.add_child(mark)
	_title = Label.new()
	_title.text = mod.tr_key("pax_rpg_pause")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", serif)
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Hud.TEXT)
	_box.add_child(_title)
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _line())
	_box.add_child(sep)
	_button(mod.tr_key("pax_rpg_pause_resume"), serif).pressed.connect(func() -> void: resume.emit())
	_button(mod.tr_key("pax_rpg_help"), serif).pressed.connect(func() -> void: show_help.emit())
	_leave = _button(leave_text, serif)
	_leave.pressed.connect(func() -> void: leave_city.emit())
	var hint := Label.new()
	hint.text = mod.tr_key("pax_rpg_pause_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Hud.DIM)
	_box.add_child(hint)


func set_leave_text(t: String) -> void:
	_leave.text = t


static func _line() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(Hud.BLUE, 0.35)
	l.thickness = 1
	return l


func _button(text: String, font: Font) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", Hud.TEXT)
	b.add_theme_color_override("font_hover_color", Hud.PINK)
	for st: String in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Hud.INK2 if st == "normal" else Color(0.2, 0.12, 0.3, 0.95)
		s.border_color = Color(Hud.BLUE, 0.4) if st == "normal" else Hud.PINK
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		b.add_theme_stylebox_override(st, s)
	_box.add_child(b)
	return b
