extends Control
## Меню паузы локации (Esc) в стиле HUD «Сакура и сталь»: затемнение, свиток по центру, кнопки.
## «Графика» — качество одной кнопкой (низкое … ультра) и каждая настройка отдельно; значения — в настройках мода
## (gfx_<ключ>), применяются сразу (gfx_changed → location.gd → gfx.gd set_option), трава — со следующего входа.
## Мир локации на паузе, пока меню открыто (location.gd отключает обработку SubViewport).

signal resume
signal leave_city
signal show_help
signal sens_changed(v: float)
signal fog_changed(v: float)
signal gfx_changed(key: String, value: Variant)

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const AudioBus := preload("res://mods/pax_rpg/src/location/audio_bus.gd")

var _box: VBoxContainer
var _leave: Button
var _title: Label
var _main: Array = []                # кнопки главного вида (прячутся, пока открыты настройки)
var _settings: VBoxContainer
var _gfx_panel: VBoxContainer      # раздел «Графика»: прокрутка со строками + «Назад»
var _gfx_rows: VBoxContainer
var _gfx_cfg: Dictionary = {}      # config/location.json → gfx — значения по умолчанию
var _serif: Font
var _mod: PaxMod


func setup(mod: PaxMod, leave_text: String, gfx_cfg: Dictionary = {}) -> void:
	_gfx_cfg = gfx_cfg
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
	_button(mod.tr_key("pax_rpg_graphics"), serif).pressed.connect(func() -> void: _show_gfx(true))
	_button(mod.tr_key("pax_rpg_help"), serif).pressed.connect(func() -> void: show_help.emit())
	_leave = _button(leave_text, serif)
	_leave.pressed.connect(func() -> void: leave_city.emit())
	_main = _box.get_children().slice(3)                 # после знака, заголовка и черты
	_serif = serif
	_build_settings(serif)
	_build_gfx()
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
	# бой: алая мана и блики (combat_fx), подъезд камеры в серии и акцент финала (combat_cam) — можно выключить
	for kv: Array in [["pax_rpg_set_combat_fx", "combat_fx"], ["pax_rpg_set_combat_cam", "combat_cam"]]:
		var r := HBoxContainer.new()
		r.add_child(_label(str(kv[0])))
		var c := CheckButton.new()
		c.focus_mode = Control.FOCUS_NONE
		var key := str(kv[1])
		c.button_pressed = bool(_mod.get_setting(key, true))
		c.toggled.connect(func(on: bool) -> void: _mod.set_setting(key, on))
		r.add_child(c)
		_settings.add_child(r)
	# реплики врагов голосом ИИ: выкл. по умолчанию — каждая реплика — запрос к нейросети (токены)
	var row := HBoxContainer.new()
	row.add_child(_label("pax_rpg_set_foe_voice"))
	var cb := CheckButton.new()
	cb.focus_mode = Control.FOCUS_NONE
	cb.button_pressed = bool(_mod.get_setting("foe_voice", false))
	cb.toggled.connect(func(on: bool) -> void: _mod.set_setting("foe_voice", on))
	row.add_child(cb)
	_settings.add_child(row)
	var note := Label.new()
	note.text = _mod.tr_key("pax_rpg_set_foe_voice_note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(520, 0)
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(Hud.TEXT, 0.65))
	_settings.add_child(note)
	var back := _button(_mod.tr_key("pax_rpg_set_back"), serif)
	_box.remove_child(back)
	_settings.add_child(back)
	back.pressed.connect(func() -> void: _show_settings(false))


func _slider(label: String, key: String, def: float, lo: float, hi: float, apply: Callable, parent: Container = null,
		step := 0.01) -> void:
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
	s.step = step
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
		if step >= 1.0:
			pct.text = "%d" % roundi(v)
		else:
			pct.text = ("×%.1f" % v) if hi > 1.0 else ("%d%%" % roundi(v * 100.0))
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		show.call(v)
		apply.call(v)
		_mod.set_setting(key, v))
	(parent if parent != null else _settings).add_child(row)


func _show_settings(on: bool) -> void:
	_settings.visible = on
	for b: Variant in _main:
		(b as Control).visible = not on
	_title.text = _mod.tr_key("pax_rpg_settings" if on else "pax_rpg_pause")


func reset_view() -> void:
	if _settings != null and _settings.visible:
		_show_settings(false)
	if _gfx_panel != null and _gfx_panel.visible:
		_show_gfx(false)


func _show_gfx(on: bool) -> void:
	_gfx_panel.visible = on
	for b: Variant in _main:
		(b as Control).visible = not on
	_title.text = _mod.tr_key("pax_rpg_graphics" if on else "pax_rpg_pause")


# ---------- «Графика» ----------

## Качество одной кнопкой: значения настроек (ключи gfx.gd; vol_fog — ползунок объёмного тумана).
const PRESETS := {
	"low": {"gi": false, "ssil": false, "ssao": false, "ssr": false, "aa": "fsr2", "fsr_scale": 0.77, "lamp_shadows_n": 8.0,
		"glow": 0.3, "lens_sharpen": 0.3, "cam_blur": 0.0, "flare": true, "auto_exposure": false, "grass_density": 2.0,
		"vol_fog": 0.0, "shaders": 0.0},
	"mid": {"gi": false, "ssil": false, "ssao": true, "ssr": true, "aa": "taa", "fsr_scale": 1.0, "lamp_shadows_n": 16.0,
		"glow": 0.4, "lens_sharpen": 0.3, "cam_blur": 0.25, "flare": true, "auto_exposure": true, "grass_density": 4.0,
		"vol_fog": 0.3, "shaders": 0.6},
	"high": {"gi": true, "ssil": true, "ssao": true, "ssr": true, "aa": "taa", "fsr_scale": 1.0, "lamp_shadows_n": 32.0,
		"glow": 0.4, "lens_sharpen": 0.3, "cam_blur": 0.35, "flare": true, "auto_exposure": true, "grass_density": 6.0,
		"vol_fog": 0.5, "shaders": 0.85},
	"ultra": {"gi": true, "ssil": true, "ssao": true, "ssr": true, "aa": "taa", "fsr_scale": 1.0, "lamp_shadows_n": 40.0,
		"glow": 0.45, "lens_sharpen": 0.3, "cam_blur": 0.35, "flare": true, "auto_exposure": true, "grass_density": 9.0,
		"vol_fog": 0.6, "shaders": 1.0},
}


func _build_gfx() -> void:
	_gfx_panel = VBoxContainer.new()
	_gfx_panel.add_theme_constant_override("separation", 10)
	_gfx_panel.visible = false
	_box.add_child(_gfx_panel)
	_box.move_child(_gfx_panel, 3)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_gfx_panel.add_child(scroll)
	_gfx_rows = VBoxContainer.new()
	_gfx_rows.add_theme_constant_override("separation", 8)
	_gfx_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_gfx_rows)
	_fill_gfx()
	var back := _button(_mod.tr_key("pax_rpg_set_back"), _serif)
	_box.remove_child(back)
	_gfx_panel.add_child(back)
	back.pressed.connect(func() -> void: _show_gfx(false))


## Строки «Графики» (заново — после выбора качества, чтобы показать новые значения).
func _fill_gfx() -> void:
	for c: Node in _gfx_rows.get_children():
		c.queue_free()
	_choice("pax_rpg_gfx_preset", "preset", [["custom", "pax_rpg_gfx_custom"], ["low", "pax_rpg_gfx_low"],
		["mid", "pax_rpg_gfx_mid"], ["high", "pax_rpg_gfx_high"], ["ultra", "pax_rpg_gfx_ultra"]], "custom")
	_choice("pax_rpg_gfx_res", "resolution", [["native", "pax_rpg_gfx_res_native"], ["1080", "pax_rpg_gfx_res_1080"],
		["1440", "pax_rpg_gfx_res_1440"], ["2160", "pax_rpg_gfx_res_2160"]], str(_gfx_cfg.get("resolution", "native")))
	_choice("pax_rpg_gfx_fps", "fps_limit", [["0", "pax_rpg_gfx_fps_off"], ["60", "pax_rpg_gfx_fps_60"],
		["144", "pax_rpg_gfx_fps_144"], ["165", "pax_rpg_gfx_fps_165"], ["240", "pax_rpg_gfx_fps_240"]],
		str(_gfx_cfg.get("fps_limit", "0")))
	_toggle("pax_rpg_gfx_vsync", "vsync", bool(_gfx_cfg.get("vsync", false)))
	_toggle("pax_rpg_gfx_gi", "gi", str(_gfx_cfg.get("gi", "sdfgi")) == "sdfgi")
	_toggle("pax_rpg_gfx_ssil", "ssil", bool(_gfx_cfg.get("ssil", true)))
	_toggle("pax_rpg_gfx_ssao", "ssao", bool(_gfx_cfg.get("ssao", true)))
	_toggle("pax_rpg_gfx_ssr", "ssr", bool(_gfx_cfg.get("ssr", true)))
	_choice("pax_rpg_gfx_aa", "aa", [["taa", "pax_rpg_gfx_aa_taa"], ["fsr2", "pax_rpg_gfx_aa_fsr2"],
		["msaa", "pax_rpg_gfx_aa_msaa"], ["off", "pax_rpg_gfx_aa_off"]], str(_gfx_cfg.get("aa", "taa")))
	_choice("pax_rpg_gfx_upscale", "upscale", [["native", "pax_rpg_gfx_up_native"], ["quality", "pax_rpg_gfx_up_quality"],
		["balanced", "pax_rpg_gfx_up_balanced"], ["performance", "pax_rpg_gfx_up_performance"]], str(_gfx_cfg.get("upscale", "native")))
	_gslider("pax_rpg_gfx_scale", "fsr_scale", float(_gfx_cfg.get("fsr_scale", 1.0)), 0.5, 1.0, 0.01)
	_gslider("pax_rpg_gfx_lamps", "lamp_shadows_n", float(_gfx_cfg.get("lamp_shadows_n", 40.0)), 0.0, 40.0, 4.0)
	_slider(_mod.tr_key("pax_rpg_set_volfog"), "vol_fog", 0.5, 0.0, 1.0, func(v: float) -> void:
		fog_changed.emit(v), _gfx_rows)
	_gslider("pax_rpg_gfx_shaders", "shaders", float(_gfx_cfg.get("shaders", 1.0)), 0.0, 1.0, 0.01)
	_gslider("pax_rpg_gfx_glow", "glow", float(_gfx_cfg.get("glow", 0.55)), 0.0, 1.0, 0.01)
	_gslider("pax_rpg_gfx_sharpen", "lens_sharpen", float(_gfx_cfg.get("lens_sharpen", 0.3)), 0.0, 1.0, 0.01)
	_toggle("pax_rpg_gfx_flare", "flare", float(_gfx_cfg.get("flare", 1.0)) > 0.0)
	_toggle("pax_rpg_gfx_exposure", "auto_exposure", bool(_gfx_cfg.get("auto_exposure", true)))
	_gslider("pax_rpg_gfx_grass", "grass_density", float(_gfx_cfg.get("grass_density", 6.0)), 0.0, 10.0, 1.0)


func _set_gfx(key: String, value: Variant) -> void:
	_mod.set_setting("gfx_" + key, value)
	gfx_changed.emit(key, value)


func _label(text_key: String) -> Label:
	var l := Label.new()
	l.text = _mod.tr_key(text_key)
	l.custom_minimum_size = Vector2(230, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Hud.TEXT)
	return l


func _toggle(text_key: String, key: String, def: bool) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(text_key))
	var cb := CheckButton.new()
	cb.focus_mode = Control.FOCUS_NONE
	var v: Variant = _mod.get_setting("gfx_" + key, def)
	cb.button_pressed = (v is bool and bool(v)) or (not (v is bool) and float(v) > 0.0)
	cb.toggled.connect(func(on: bool) -> void:
		_set_gfx(key, on if key != "flare" else (1.0 if on else 0.0)))
	row.add_child(cb)
	_gfx_rows.add_child(row)


func _choice(text_key: String, key: String, options: Array, def: String) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(text_key))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.custom_minimum_size = Vector2(200, 0)
	var cur := str(_mod.get_setting("gfx_" + key, def)) if key != "preset" else "custom"
	for i: int in options.size():
		var o: Array = options[i]
		ob.add_item(_mod.tr_key(str(o[1])), i)
		if str(o[0]) == cur:
			ob.select(i)
	ob.item_selected.connect(func(idx: int) -> void:
		var val := str((options[idx] as Array)[0])
		if key == "preset":
			_apply_preset(val)
		else:
			_set_gfx(key, val))
	row.add_child(ob)
	_gfx_rows.add_child(row)


func _gslider(text_key: String, key: String, def: float, lo: float, hi: float, step: float) -> void:
	_slider(_mod.tr_key(text_key), "gfx_" + key, def, lo, hi, func(v: float) -> void:
		gfx_changed.emit(key, v), _gfx_rows, step)


func _apply_preset(name_v: String) -> void:
	var p: Dictionary = PRESETS.get(name_v, {})
	if p.is_empty():
		return
	for k: String in p:
		if k == "vol_fog":
			_mod.set_setting("vol_fog", p[k])
			fog_changed.emit(float(p[k]))
		else:
			_set_gfx(k, p[k])
	_fill_gfx.call_deferred()
