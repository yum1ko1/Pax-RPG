extends Control
## Настройки главного меню Pax RPG — в стиле меню (Cinzel, тусклые пункты, алая черта у выбранного), по разделам:
## Graphics (качество игры, окно, кадры), City (графика городов мода — ключи gfx_* как в паузе), Combat, Audio,
## Controls. Значения игры — её же путями (качество — GraphicsSettings + set_graphics меню игры, громкость — его
## loudness), мода — set_setting. Фон — textures/menu/settings_bg.jpg, если есть (самурай на коленях с катаной),
## иначе фон меню под тёмной вуалью.

const PauseMenu := preload("res://mods/pax_rpg/src/location/pause_menu.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const AudioBus := preload("res://mods/pax_rpg/src/location/audio_bus.gd")
const CRIMSON := Color(1.0, 0.16, 0.22)
const TEXT := Color(0.74, 0.71, 0.79)
const BRIGHT := Color(1.0, 0.96, 0.97)
const VALUE := Color(1.0, 0.62, 0.66)

var mod: PaxMod
var _find: Callable                    # () -> меню игры (Menu.gd) или null
var _font: Font
var _value_font: Font
var _tabs: VBoxContainer
var _rows: VBoxContainer
var _tab := "GRAPHICS"
var _tab_labels := {}
var _mat: ShaderMaterial
var _embers: CPUParticles2D
var _mouse := Vector2.ZERO
var _t := 0.0

const TABS := ["GRAPHICS", "CITY", "COMBAT", "AUDIO", "CONTROLS"]


func setup(m: PaxMod, item_font: FontFile, value_font: FontFile, find_menu: Callable, back: Callable) -> void:
	mod = m
	_find = find_menu
	var fv := FontVariation.new()
	fv.base_font = item_font
	fv.spacing_glyph = 4
	_font = fv
	var vv := FontVariation.new()
	vv.base_font = value_font
	vv.variation_embolden = 0.3
	vv.spacing_glyph = 2
	_value_font = vv
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_tex: Texture2D = Assets.tex(mod, "textures/menu/settings_bg.jpg")   # самурай молится на выступе, катана на коленях
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = BG
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_mat.set_shader_parameter("plate", Assets.tex(mod, "textures/menu/settings_plate.jpg"))   # фон без скалы
		_mat.set_shader_parameter("fgmask", Assets.tex(mod, "textures/menu/settings_fg.png"))     # скала с самураем
		bg.material = _mat
		add_child(bg)
	_embers = CPUParticles2D.new()                   # искры пламени снизу справа: лёгкие, поднимаются и гаснут
	_embers.amount = 46
	_embers.lifetime = 7.0
	_embers.preprocess = 7.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.direction = Vector2(-0.35, -1.0)
	_embers.spread = 22.0
	_embers.gravity = Vector2(-6.0, -10.0)
	_embers.initial_velocity_min = 18.0
	_embers.initial_velocity_max = 60.0
	_embers.scale_amount_min = 1.0
	_embers.scale_amount_max = 2.6
	_embers.orbit_velocity_min = -0.004
	_embers.orbit_velocity_max = 0.004
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.55, 0.25, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.5, 0.22, 0.95))
	ramp.add_point(0.6, Color(1.0, 0.2, 0.22, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 0.1, 0.2, 0.0))
	_embers.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = add
	add_child(_embers)
	var veil := TextureRect.new()                    # тёмная колонка слева — под текстом, к середине тает
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.01, 0.06, 0.92))
	g.set_color(1, Color(0.03, 0.01, 0.06, 0.0))
	g.add_point(0.6, Color(0.03, 0.01, 0.06, 0.8))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	veil.texture = gt
	veil.anchor_bottom = 1.0
	veil.anchor_right = 0.62
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var head := _label("SETTINGS", 30, BRIGHT)
	head.position = Vector2(70, 60)
	add_child(head)
	var tick := ColorRect.new()
	tick.color = CRIMSON
	tick.position = Vector2(70, 108)
	tick.size = Vector2(46, 2)
	add_child(tick)
	_tabs = VBoxContainer.new()
	_tabs.position = Vector2(70, 150)
	_tabs.add_theme_constant_override("separation", 18)
	add_child(_tabs)
	for t: String in TABS:
		var l := _label(t, 17, TEXT)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		l.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_open(t))
		_tabs.add_child(l)
		_tab_labels[t] = l
	var bk := _label("BACK", 17, TEXT)
	bk.mouse_filter = Control.MOUSE_FILTER_STOP
	bk.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bk.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			back.call())
	_tabs.add_child(_spacer(26))
	_tabs.add_child(bk)
	var line := ColorRect.new()                      # тонкая черта между разделами и строками
	line.color = Color(TEXT, 0.18)
	line.position = Vector2(290, 150)
	line.size = Vector2(1, 560)
	add_child(line)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(320, 140)
	scroll.size = Vector2(620, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size = Vector2(600, 0)
	_rows.add_theme_constant_override("separation", 14)
	scroll.add_child(_rows)
	_open(_tab)


func _process(delta: float) -> void:
	_t += delta
	var vs := get_viewport_rect().size
	if vs.x <= 0.0:
		return
	var m := (get_local_mouse_position() / vs - Vector2(0.5, 0.5)) * 2.0
	_mouse = _mouse.lerp(m.clamp(Vector2(-1, -1), Vector2(1, 1)), 1.0 - exp(-delta * 3.0))
	if _mat != null:
		_mat.set_shader_parameter("mouse", _mouse)
		_mat.set_shader_parameter("time", _t)
	if _embers != null:
		_embers.position = Vector2(vs.x * 0.86, vs.y + 12.0) - _mouse * 14.0
		_embers.emission_rect_extents = Vector2(vs.x * 0.16, 10.0)


## Фон настроек: скала с самураем сдвигается за мышью (маска settings_fg.png поверх settings_plate.jpg — фон без
## неё), горы и небо стоят; туман ползёт у подножия, кольцо в небе дышит.
const BG := """shader_type canvas_item;
uniform sampler2D plate : filter_linear;
uniform sampler2D fgmask : filter_linear;
uniform vec2 mouse = vec2(0.0);
uniform float time = 0.0;
uniform vec2 ring = vec2(0.2405, 0.1827);
float n2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(n2(i), n2(i + vec2(1, 0)), f.x), mix(n2(i + vec2(0, 1)), n2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
void fragment() {
	vec2 uv = UV;
	vec2 fuv = clamp(uv - mouse * vec2(0.012, 0.008), vec2(0.001), vec2(0.999));
	float a = texture(fgmask, fuv).r;
	vec3 c = mix(texture(plate, uv).rgb, texture(TEXTURE, fuv).rgb, a);
	vec2 p = vec2(uv.x * 2.2 + time * 0.014, uv.y * 4.0);
	float f = smoothstep(0.4, 0.9, fbm(p + fbm(p * 1.3 - time * 0.02)));
	float low = smoothstep(0.55, 0.95, uv.y) * (1.0 - a);
	c = mix(c, vec3(0.62, 0.5, 0.68), low * f * 0.35);
	float r = length((uv - ring) * vec2(1.77, 1.0));
	c += vec3(1.0, 0.5, 0.58) * exp(-pow((r - 0.04) * 40.0, 2.0)) * (0.12 + 0.07 * sin(time * 1.3));
	COLOR = vec4(c, 1.0);
}"""


func _open(t: String) -> void:
	_tab = t
	for k: String in _tab_labels:
		var l: Label = _tab_labels[k]
		l.add_theme_color_override("font_color", BRIGHT if k == t else TEXT)
		l.add_theme_color_override("font_shadow_color", Color(CRIMSON, 0.7) if k == t else Color(0, 0, 0, 0.6))
	for c: Node in _rows.get_children():
		c.queue_free()
	match t:
		"GRAPHICS":
			_game_quality()
			_section("DISPLAY")
			_cycle("Window", [["full", "Fullscreen"], ["win", "Windowed"]],
				"full" if DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN] else "win", func(v: String) -> void:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if v == "full" else DisplayServer.WINDOW_MODE_WINDOWED))
			_gcycle("Frame limit", "fps_limit", [["0", "Off"], ["60", "60"], ["144", "144"], ["165", "165"], ["240", "240"]], "0")
			_gtoggle("V-Sync", "vsync", false)
		"CITY":
			_cycle("Preset", [["custom", "Custom"], ["low", "Low"], ["mid", "Medium"], ["high", "High"], ["ultra", "Ultra"]],
				"custom", func(v: String) -> void:
				var p: Dictionary = PauseMenu.PRESETS.get(v, {})
				for k: String in p:
					mod.set_setting(k if k == "vol_fog" else "gfx_" + k, p[k])
				if not p.is_empty():
					_open.call_deferred("CITY"))
			_gcycle("Resolution", "resolution", [["native", "Native"], ["1080", "1080p"], ["1440", "1440p"], ["2160", "2160p"]], "native")
			_gcycle("Anti-aliasing", "aa", [["taa", "TAA"], ["fsr2", "FSR 2"], ["msaa", "MSAA"], ["off", "Off"]], "taa")
			_gcycle("Upscaling", "upscale", [["native", "Native"], ["quality", "Quality"], ["balanced", "Balanced"],
				["performance", "Performance"]], "native")
			_gslider("Render scale", "fsr_scale", 1.0, 0.5, 1.0, 0.01, true)
			_section("LIGHT")
			_gtoggle("Global illumination", "gi", true)
			_gtoggle("Indirect light (SSIL)", "ssil", true)
			_gtoggle("Ambient occlusion", "ssao", true)
			_gtoggle("Reflections", "ssr", true)
			_gslider("Lamp shadows (nearest lights; farther ones get softer, never vanish)", "lamp_shadows_n", 40.0, 0.0, 40.0, 4.0, false)
			_slider("Volumetric fog", float(mod.get_setting("vol_fog", 0.5)), 0.0, 1.0, 0.01, true, func(v: float) -> void:
				mod.set_setting("vol_fog", v))
			_section("CAMERA")
			_gslider("Shaders «Yuruma Ultra» (sun rays, cinematic colour, soft bloom)", "shaders", 1.0, 0.0, 1.0, 0.01, true)
			_gslider("Glow", "glow", 0.55, 0.0, 1.0, 0.01, true)
			_gslider("Sharpen", "lens_sharpen", 0.3, 0.0, 1.0, 0.01, true)
			_gslider("Motion blur", "cam_blur", 0.35, 0.0, 1.0, 0.01, true)
			_gtoggle("Lens flare", "flare", true)
			_gtoggle("Auto exposure", "auto_exposure", true)
			_gslider("Grass density", "grass_density", 6.0, 0.0, 10.0, 1.0, false)
		"COMBAT":
			_toggle("Combat effects", bool(mod.get_setting("combat_fx", true)), func(on: bool) -> void:
				mod.set_setting("combat_fx", on))
			_toggle("Cinematic combat camera", bool(mod.get_setting("combat_cam", true)), func(on: bool) -> void:
				mod.set_setting("combat_cam", on))
			_toggle("Enemy AI voices", bool(mod.get_setting("foe_voice", false)), func(on: bool) -> void:
				mod.set_setting("foe_voice", on))
			_note("Enemy voices ask the neural network for every line (uses tokens).")
		"AUDIO":
			var menu: Variant = _find.call()
			if menu != null:
				var cur: Variant = (menu.settings as Dictionary).get("loudness", 0.8)
				_slider("Master", float(cur) if (cur is float or cur is int) else 0.8, 0.0, 1.0, 0.05, true,
					func(v: float) -> void:
					menu.settings["loudness"] = v
					var snd: Variant = menu._game_sound()
					if snd is Object and (snd as Object).has_method("set_common"):
						snd.set_common(v)
					else:
						AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
						AudioServer.set_bus_mute(0, v <= 0.001)
					menu.save_it())
			_slider("Music", float(mod.get_setting("music_volume", 0.6)), 0.0, 1.0, 0.01, true, func(v: float) -> void:
				mod.set_setting("music_volume", v)
				AudioBus.set_volume(AudioBus.MUSIC, v))
			_slider("Effects", float(mod.get_setting("sfx_volume", 1.0)), 0.0, 1.0, 0.01, true, func(v: float) -> void:
				mod.set_setting("sfx_volume", v)
				AudioBus.set_volume(AudioBus.SFX, v))
			_toggle("3D sound", bool(mod.get_setting("sfx_3d", true)), func(on: bool) -> void:
				mod.set_setting("sfx_3d", on))
			_toggle("Voice talk with townsfolk (experimental, hold B, say the name)", bool(mod.get_setting("voice_talk", false)), func(on: bool) -> void:
				mod.set_setting("voice_talk", on))
		"CONTROLS":
			_slider("Mouse sensitivity", float(mod.get_setting("mouse_sens", 1.0)), 0.3, 2.5, 0.05, false,
				func(v: float) -> void: mod.set_setting("mouse_sens", v))


## Качество графики игры (глобус, космос): её пресеты — тем же путём, что вкладка «Графика» меню игры.
func _game_quality() -> void:
	var menu: Variant = _find.call()
	if menu == null:
		return
	var GS: Variant = load("res://src/ui/GraphicsSettings.gd")
	var g: Dictionary = GS.read()
	if (menu.settings as Dictionary).get("graphics") is Dictionary:
		g.merge(menu.settings["graphics"], true)
	_cycle("World quality", [["low", "Low"], ["average", "Medium"], ["high", "High"], ["ultra", "Ultra"]],
		str(GS.which_preset(g)), func(v: String) -> void:
		menu.settings_screen().set_graphics(GS.with_preset(g, v)))


# ---------- строки ----------

func _row(text: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 16)
	var l := _label(text.to_upper(), 14, TEXT)
	l.custom_minimum_size = Vector2(300, 0)
	r.add_child(l)
	_rows.add_child(r)
	return r


func _section(text: String) -> void:
	_rows.add_child(_spacer(6))
	var l := _label(text, 12, Color(CRIMSON, 0.85))
	_rows.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.add_theme_font_override("font", _value_font)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(TEXT, 0.65))
	_rows.add_child(l)


## Выбор из нескольких: «‹ ЗНАЧЕНИЕ ›», щелчок — следующее (правой кнопкой — предыдущее).
func _cycle(text: String, options: Array, cur: String, apply: Callable) -> void:
	var r := _row(text)
	var idx := 0
	for i: int in options.size():
		if str((options[i] as Array)[0]) == cur:
			idx = i
	var v := _label("", 19, VALUE)
	v.add_theme_font_override("font", _value_font)
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	v.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var state := [idx]
	var show := func() -> void:
		v.text = "‹  %s  ›" % str((options[state[0]] as Array)[1])
	show.call()
	v.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			var b := (e as InputEventMouseButton).button_index
			if b != MOUSE_BUTTON_LEFT and b != MOUSE_BUTTON_RIGHT:
				return
			state[0] = (state[0] + (1 if b == MOUSE_BUTTON_LEFT else options.size() - 1)) % options.size()
			show.call()
			apply.call(str((options[state[0]] as Array)[0])))
	r.add_child(v)


func _toggle(text: String, on: bool, apply: Callable) -> void:
	_cycle(text, [["on", "On"], ["off", "Off"]], "on" if on else "off", func(v: String) -> void: apply.call(v == "on"))


func _slider(text: String, value: float, lo: float, hi: float, step: float, pct: bool, apply: Callable) -> void:
	var r := _row(text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(180, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(TEXT, 0.25)
	track.content_margin_top = 1
	track.content_margin_bottom = 1
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(CRIMSON, 0.85)
	fill.content_margin_top = 1
	fill.content_margin_bottom = 1
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	r.add_child(s)
	var v := _label("", 18, VALUE)
	v.add_theme_font_override("font", _value_font)
	v.custom_minimum_size = Vector2(60, 0)
	var show := func(x: float) -> void:
		v.text = ("%d%%" % roundi(x * 100.0)) if pct else (("%d" % roundi(x)) if step >= 1.0 else "×%.2f" % x)
	show.call(value)
	s.value_changed.connect(func(x: float) -> void:
		show.call(x)
		apply.call(x))
	r.add_child(v)


## Ключи графики городов — те же, что в паузе (gfx_<ключ>, их читает gfx.gd при входе в город).
func _gcycle(text: String, key: String, options: Array, def: String) -> void:
	_cycle(text, options, str(mod.get_setting("gfx_" + key, def)), func(v: String) -> void: mod.set_setting("gfx_" + key, v))


func _gtoggle(text: String, key: String, def: bool) -> void:
	var cur: Variant = mod.get_setting("gfx_" + key, def)
	var on := (cur is bool and bool(cur)) or (not (cur is bool) and str(cur) not in ["", "0", "0.0", "false", "off"])
	_toggle(text, on, func(v: bool) -> void:
		mod.set_setting("gfx_" + key, (1.0 if v else 0.0) if key == "flare" else v))


func _gslider(text: String, key: String, def: float, lo: float, hi: float, step: float, pct: bool) -> void:
	_slider(text, float(mod.get_setting("gfx_" + key, def)), lo, hi, step, pct, func(v: float) -> void:
		mod.set_setting("gfx_" + key, v))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.03, 0.0, 0.05, 0.75))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
