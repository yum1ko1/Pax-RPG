extends Control
## Меню паузы локации (Esc) в стиле HUD «Сакура и сталь»: затемнение, свиток по центру, кнопки.
## Мир локации на паузе, пока меню открыто (location.gd отключает обработку SubViewport).

signal resume
signal leave_city
signal show_help
signal sens_changed(v: float)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const AudioBus := preload("res://mods/pax_rpg/src/location/audio_bus.gd")

var _box: VBoxContainer
var _leave: Button
var _title: Label
var _main: Array = []                # кнопки главного вида (прячутся, пока открыты настройки)
var _settings: VBoxContainer
var _mod: PaxMod


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
	_mod = mod
	_button(mod.tr_key("pax_rpg_pause_resume"), serif).pressed.connect(func() -> void: resume.emit())
	_button(mod.tr_key("pax_rpg_settings"), serif).pressed.connect(func() -> void: _show_settings(true))
	_button(mod.tr_key("pax_rpg_help"), serif).pressed.connect(func() -> void: show_help.emit())
	_leave = _button(leave_text, serif)
	_leave.pressed.connect(func() -> void: leave_city.emit())
	_main = _box.get_children().slice(3)                 # после знака, заголовка и черты
	_build_settings(serif)
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


## Настройки: громкость музыки и звуков, чувствительность мыши. Сохраняются в настройках мода.
func _build_settings(serif: Font) -> void:
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 10)
	_settings.visible = false
	_box.add_child(_settings)
	_box.move_child(_settings, 3)
	_slider(_mod.tr_key("pax_rpg_set_music"), "music_volume", 0.6, 0.0, 1.0, func(v: float) -> void:
		AudioBus.set_volume(AudioBus.MUSIC, v))
	_slider(_mod.tr_key("pax_rpg_set_sfx"), "sfx_volume", 1.0, 0.0, 1.0, func(v: float) -> void:
		AudioBus.set_volume(AudioBus.SFX, v))
	_slider(_mod.tr_key("pax_rpg_set_mouse"), "mouse_sens", 1.0, 0.3, 2.5, func(v: float) -> void:
		sens_changed.emit(v))
	var back := _button(_mod.tr_key("pax_rpg_set_back"), serif)
	_box.remove_child(back)
	_settings.add_child(back)
	back.pressed.connect(func() -> void: _show_settings(false))


func _slider(label: String, key: String, def: float, lo: float, hi: float, apply: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Hud.TEXT)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = float(_mod.get_setting(key, def))
	s.custom_minimum_size = Vector2(200, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(56, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_color_override("font_color", Hud.PINK)
	pct.add_theme_font_size_override("font_size", 18)
	row.add_child(pct)
	var show := func(v: float) -> void:
		pct.text = ("×%.1f" % v) if hi > 1.0 else ("%d%%" % roundi(v * 100.0))
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		show.call(v)
		apply.call(v)
		_mod.set_setting(key, v))
	_settings.add_child(row)


func _show_settings(on: bool) -> void:
	_settings.visible = on
	for b: Variant in _main:
		(b as Control).visible = not on
	_title.text = _mod.tr_key("pax_rpg_settings" if on else "pax_rpg_pause")


func reset_view() -> void:
	if _settings != null and _settings.visible:
		_show_settings(false)
