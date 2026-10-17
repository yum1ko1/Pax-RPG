extends CanvasLayer
## Главное меню Pax RPG — свой экран поверх меню игры (пока оно на главном шаге): фон Юрумы (textures/menu/bg.jpg)
## с глубиной — карта глубины (depth.png: скала с самураем ближе всего, город, небо дальше) сдвигает слои за мышью
## (параллакс в шейдере), туман ползёт по долине, кольцо в небе дышит, алые искры поднимаются от скалы.
## Кнопки — свои: наведение — сдвиг, алое свечение, растущая черта и искры; пункты зовут те же действия, что и
## кнопки меню игры (main.gd). Как только игра открыла другой экран (загрузка, настройки, сеть) — прячемся.

const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const CRIMSON := Color(1.0, 0.16, 0.22)
const GOLD := Color(0.93, 0.78, 0.5)
const RING := Vector2(0.766, 0.195)              # кольцо в небе — доля картинки

var mod: PaxMod
var _find: Callable                              # () -> меню игры (Menu.gd) или null
var _items: Array = []                           # [[ключ перевода, Callable]]
var _root: Control
var _bg: TextureRect
var _mat: ShaderMaterial
var _sparks: CPUParticles2D
var _col: VBoxContainer
var _hot := 0.0
var _hot_want := 0.0
var _mouse := Vector2.ZERO
var _t := 0.0
var _shown := false


func setup(m: PaxMod, find_menu: Callable, items: Array) -> void:
	mod = m
	_find = find_menu
	_items = items
	name = "PaxRpgMainMenu"
	layer = 60
	visible = false
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP     # меню игры под нами не нажимается
	add_child(_root)
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.texture = mod.texture("textures/menu/bg.jpg")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BG
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("depth", mod.texture("textures/menu/depth.png"))
	_mat.set_shader_parameter("ring", RING)
	_bg.material = _mat
	_root.add_child(_bg)
	_sparks = CPUParticles2D.new()                   # алые искры от скалы и над долиной
	_sparks.amount = 70
	_sparks.lifetime = 6.0
	_sparks.preprocess = 6.0
	_sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparks.direction = Vector2(0.25, -1.0)
	_sparks.spread = 25.0
	_sparks.gravity = Vector2(12.0, -14.0)
	_sparks.initial_velocity_min = 12.0
	_sparks.initial_velocity_max = 40.0
	_sparks.scale_amount_min = 1.5
	_sparks.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CRIMSON, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.35, 0.3, 0.95))
	ramp.set_color(1, Color(CRIMSON, 0.0))
	_sparks.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparks.material = add
	_root.add_child(_sparks)
	var shade := TextureRect.new()                   # тень слева — пункты читаются на небе и горах
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.01, 0.06, 0.85))
	g.set_color(1, Color(0.03, 0.01, 0.06, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(1, 0)
	shade.texture = gt
	shade.anchor_bottom = 1.0
	shade.anchor_right = 0.42
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var title := Label.new()
	title.text = "PAX RPG"
	var ff := FontFile.new()
	ff.data = mod.read_bytes("fonts/katsuno_demo.ttf")
	title.add_theme_font_override("font", ff)
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.98, 0.93, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(CRIMSON, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 18)
	title.position = Vector2(70, 26)
	title.name = "Title"
	_root.add_child(title)
	var sub := Label.new()
	sub.text = mod.tr_key("pax_rpg_menu_sub")
	sub.add_theme_font_override("font", _serif())
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(GOLD, 0.85))
	sub.position = Vector2(80, 206)
	_root.add_child(sub)
	_col = VBoxContainer.new()
	_col.position = Vector2(70, 262)
	_col.add_theme_constant_override("separation", 2)
	_root.add_child(_col)
	for it: Array in _items:
		_col.add_child(_button(mod.tr_key(str(it[0])), it[1] as Callable))


func _serif() -> Font:
	return Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)


## Пункт: текст и черта под ним; наведение — сдвиг вправо, алый цвет, черта растёт, искры; нажатие — действие.
func _button(text: String, fn: Callable) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(380, 48)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_override("font", _serif())
	lab.add_theme_font_size_override("font_size", 30)
	lab.add_theme_color_override("font_color", Color(0.94, 0.9, 0.92))
	lab.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.06, 0.8))
	lab.add_theme_constant_override("outline_size", 6)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lab)
	var line := ColorRect.new()
	line.color = CRIMSON
	line.position = Vector2(0, 42)
	line.size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.amount = 18
	burst.lifetime = 0.7
	burst.explosiveness = 0.9
	burst.direction = Vector2(1, -0.6)
	burst.spread = 50.0
	burst.gravity = Vector2(0, -40)
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 180.0
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 3.0
	burst.color = Color(1.0, 0.3, 0.3)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	burst.material = add
	burst.position = Vector2(0, 43)
	box.add_child(burst)
	var tw_ref := [null]
	var hover := func(on: bool) -> void:
		if tw_ref[0] != null:
			(tw_ref[0] as Tween).kill()
		var tw := box.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_ref[0] = tw
		tw.tween_property(lab, "position:x", 22.0 if on else 0.0, 0.22)
		tw.tween_property(lab, "theme_override_colors/font_color", Color(1.0, 0.55, 0.55) if on else Color(0.94, 0.9, 0.92), 0.18)
		tw.tween_property(line, "size:x", lab.get_minimum_size().x + 40.0 if on else 0.0, 0.3)
		if on:
			burst.position.x = 22.0 + lab.get_minimum_size().x
			burst.restart()
		_hot_want = 1.0 if on else 0.0
	box.mouse_entered.connect(hover.bind(true))
	box.mouse_exited.connect(hover.bind(false))
	box.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var tw := box.create_tween()
			tw.tween_property(lab, "scale", Vector2(0.96, 0.96), 0.05)
			tw.tween_property(lab, "scale", Vector2.ONE, 0.08)
			tw.tween_callback(fn))
	return box


## Меню игры на главном шаге — значит, мы на экране; другой шаг (загрузка, настройки, партия) — прячемся.
func _on_main() -> bool:
	var menu: Variant = _find.call()
	if menu == null or not (menu as CanvasItem).is_visible_in_tree():
		return false
	var scr: Node = menu.screen
	if scr == null:
		return false
	for b: Node in scr.get_children():
		if b is Button and str((b as Button).get_meta("menu_id", "")) == "mod:pax_rpg_continue":
			return true
	return false


func _process(delta: float) -> void:
	var want := _on_main()
	if want != _shown:
		_shown = want
		visible = want
		if want:
			_root.modulate.a = 0.0
			create_tween().tween_property(_root, "modulate:a", 1.0, 0.5)
	if not visible:
		return
	_t += delta
	var vs := _root.get_viewport_rect().size
	var m := (_root.get_local_mouse_position() / vs - Vector2(0.5, 0.5)) * 2.0
	_mouse = _mouse.lerp(m.clamp(Vector2(-1, -1), Vector2(1, 1)), 1.0 - exp(-delta * 3.0))   # плавно, без дрожи
	_hot = move_toward(_hot, _hot_want, delta * 3.0)
	_mat.set_shader_parameter("mouse", _mouse)
	_mat.set_shader_parameter("hot", _hot)
	_mat.set_shader_parameter("time", _t)
	_sparks.position = Vector2(vs.x * 0.16, vs.y * 0.78) - _mouse * 18.0
	_sparks.emission_rect_extents = Vector2(vs.x * 0.18, 20.0)
	var title: Control = _root.get_node("Title")
	title.position = Vector2(70, 26) - _mouse * 6.0
	_col.position = Vector2(70, 262) - _mouse * 4.0


const BG := """shader_type canvas_item;
uniform sampler2D depth : filter_linear;
uniform vec2 mouse = vec2(0.0);
uniform vec2 ring = vec2(0.766, 0.195);
uniform float hot = 0.0;
uniform float time = 0.0;
float n2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(n2(i), n2(i + vec2(1, 0)), f.x), mix(n2(i + vec2(0, 1)), n2(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	// параллакс: ближнее (светлое в depth) сдвигается сильнее; две выборки глубины — без «рваных» краёв
	vec2 uv = UV;
	float d = texture(depth, uv).r;
	vec2 off = -mouse * vec2(0.018, 0.012) * (d - 0.25);
	d = texture(depth, uv + off).r;
	off = -mouse * vec2(0.018, 0.012) * (d - 0.25);
	vec2 suv = clamp(uv + off, vec2(0.002), vec2(0.998));
	vec3 c = texture(TEXTURE, suv).rgb;
	// туман: две полосы шума ползут по долине (средний план)
	float band = smoothstep(0.42, 0.62, uv.y) * (1.0 - smoothstep(0.78, 0.98, uv.y)) * (1.0 - d * 0.9);
	float f = noise(vec2(uv.x * 3.0 + time * 0.03, uv.y * 8.0)) * 0.6 + noise(vec2(uv.x * 7.0 - time * 0.05, uv.y * 14.0)) * 0.4;
	c = mix(c, vec3(0.62, 0.5, 0.68), band * f * 0.28);
	// кольцо в небе дышит; при наведении на пункт — ярче, с алым ореолом
	vec2 rd = (suv - ring) * vec2(1.77, 1.0);
	float r = length(rd);
	float glow = exp(-pow((r - 0.085) * 28.0, 2.0)) * (0.18 + 0.08 * sin(time * 1.3) + 0.35 * hot);
	glow += exp(-r * 9.0) * 0.12 * hot;
	c += vec3(1.0, 0.45, 0.55) * glow;
	// огни города чуть мерцают
	float lit = smoothstep(0.55, 0.85, max(c.r, c.g)) * step(0.5, uv.y);
	c += c * lit * 0.12 * sin(time * 2.0 + n2(floor(suv * 300.0)) * 6.28);
	// виньетка
	float v = smoothstep(0.45, 1.0, length((uv - 0.5) * vec2(1.0, 1.2)));
	c *= 1.0 - v * 0.45;
	COLOR = vec4(c, 1.0);
}"""
