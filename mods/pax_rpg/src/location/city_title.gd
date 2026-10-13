extends Control
## Заставка входа в город (как в больших играх), настоящие 3D-модели (ui/katana3d.gd):
##  1. катана в ножнах влетает в кадр, вращаясь вокруг клинка;
##  2. клинок выходит из ножен (ножны соскальзывают и падают);
##  3. сверху справа рубит чужой тёмный клинок — катана отбивает: вспышка, сноп искр, встряска экрана, звон;
##  4. клинки разлетаются в стороны, а на месте искр из тлеющих искр проступает название места.

const Katana3D := preload("res://mods/pax_rpg/src/ui/katana3d.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const HOLD := 4.2
const CLASH := Vector3(0.05, 0.06, 0.0)       # точка удара в сцене, м

var _name := ""
var _t := -1.0                                # время заставки, с (<0 — ещё не началась)
var _stage: Katana3D
var _kat: Node3D
var _saya: Node3D
var _foe: Node3D
var _font: Font
var _text_a := 0.0
var _flash := 0.0
var _shake := 0.0
var _sparks: CPUParticles2D
var _embers: CPUParticles2D
var _snd_fly: AudioStreamPlayer
var _snd_draw: AudioStreamPlayer
var _snd_hit: AudioStreamPlayer
var _done := {}                               # какие события уже были
var _end := 0.0


func setup(mod: PaxMod, place: String) -> void:
	name = "PaxRpgCityTitle"
	_name = place
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Hud._sys(["Yu Mincho", "Cormorant Garamond", "Georgia", "Times New Roman"], 700)
	_snd_fly = _snd(mod, "sounds/katana_fly_%d.ogg", 3, -3.0)
	_snd_draw = _snd(mod, "sounds/swing_%d.wav", 6, -6.0)
	_snd_hit = _snd(mod, "sounds/katana_hit_%d.ogg", 3, 0.0)
	_stage = Katana3D.new()
	_stage.setup(mod, Vector2i(1600, 900), 1.35)
	add_child(_stage)
	_kat = _stage.pivot
	_saya = _stage.piece("models/weapons/katana_saya.glb")
	_foe = _stage.piece("models/weapons/katana.glb", Color(0.35, 0.3, 0.4))
	for n: Node3D in [_kat, _saya, _foe]:
		n.visible = false
	_sparks = _particles(70, 0.55, 900.0, Color(1.0, 0.85, 0.5), 3.0)
	_sparks.explosiveness = 1.0
	_sparks.one_shot = true
	_sparks.emitting = false
	_embers = _particles(26, 2.6, 60.0, Color(1.0, 0.55, 0.3), 2.0)  # тлеющие искры вокруг названия
	_embers.emitting = false
	_embers.gravity = Vector2(0, -25)
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE


func _snd(mod: PaxMod, pattern: String, n: int, db: float) -> AudioStreamPlayer:
	var rnd := AudioStreamRandomizer.new()
	rnd.random_pitch = 1.06
	for i: int in n:
		var st: AudioStream = mod.sound(pattern % (i + (1 if pattern.ends_with(".wav") else 0)))
		if st != null:
			rnd.add_stream(-1, st)
	if rnd.streams_count == 0:
		return null
	var p := AudioStreamPlayer.new()
	p.bus = "PaxRpgSfx"
	p.stream = rnd
	p.volume_db = db
	add_child(p)
	return p


func _particles(n: int, life: float, speed: float, col: Color, sz: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 900)
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.scale_amount_min = sz * 0.5
	p.scale_amount_max = sz
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.9, 1))
	g.add_point(0.3, col)
	g.set_color(1, Color(col.r, col.g * 0.4, col.b * 0.2, 0))
	p.color_ramp = g
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	add_child(p)
	return p


func play(delay := 0.4) -> void:
	_t = -delay


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _ease_in(x: float) -> float:
	return pow(clampf(x, 0.0, 1.0), 2.4)


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


func _once(key: String, at: float, fn: Callable) -> void:
	if _t >= at and not _done.has(key):
		_done[key] = true
		fn.call()


func _process(delta: float) -> void:
	if _t < -100.0:
		return
	_t += delta
	if _t < 0.0:
		return
	var t := _t
	_flash = maxf(0.0, _flash - delta * 3.5)
	_shake = maxf(0.0, _shake - delta * 2.5)
	# 1. влёт в ножнах (0 … 0.5 с): из-за левого края, вращение вокруг клинка
	var k1 := _ease_out(_seg(t, 0.0, 0.5))
	var rest := Vector3(-0.35, -0.05, 0.0)
	var fly := Vector3(-2.2, 0.35, 0.0).lerp(rest, k1)
	var roll := (1.0 - k1) * TAU * 2.0
	var tilt := lerpf(-0.6, 0.12, k1)
	_once("fly", 0.0, func() -> void:
		_kat.visible = true
		_saya.visible = true
		if _snd_fly != null:
			_snd_fly.play())
	# 2. вынимание (0.65 … 0.95): ножны соскальзывают к острию, потом падают вниз, вращаясь
	var k2 := _ease_in(_seg(t, 0.65, 0.95))
	var saya_off := Vector3(0.95 * k2, 0.0, 0.0)
	var k2b := _seg(t, 0.95, 1.6)
	saya_off += Vector3(0.25 * k2b, -1.4 * k2b * k2b, 0.0)
	_once("draw", 0.65, func() -> void:
		if _snd_draw != null:
			_snd_draw.play())
	# 3. удар чужого клинка (1.0 … 1.15) и парирование: катана встречает его своим взмахом
	var kf := _ease_in(_seg(t, 1.0, 1.15))
	var foe_from := Vector3(1.4, 1.3, 0.0)
	var foe_hit := CLASH + Vector3(-0.28, 0.0, 0.0)
	var foe_pos := foe_from.lerp(foe_hit, kf)
	var foe_rot := lerpf(-2.4, -2.75, kf)              # рукоять сверху справа, клинок — вниз-влево
	var parry := _ease_out(_seg(t, 0.98, 1.15))
	var kat_rot := tilt + 0.35 * parry
	var kat_pos := fly + Vector3(0.12, 0.04, 0.0) * parry
	_once("clash", 1.15, _clash)
	# 4. отскок: чужой клинок отлетает вверх-вправо, катана — вниз-влево за край
	var k4 := _ease_in(_seg(t, 1.2, 1.65))
	foe_pos += Vector3(1.8, 1.4, 0.0) * k4
	foe_rot -= 3.0 * k4
	kat_pos += Vector3(-2.6, -0.5, 0.0) * k4
	kat_rot += 1.2 * k4
	_kat.position = kat_pos
	_kat.rotation = Vector3(roll, 0.0, kat_rot)
	_saya.position = fly + saya_off
	_saya.rotation = Vector3(roll, 0.0, tilt - 2.5 * k2b)
	_foe.visible = t >= 0.98 and k4 < 1.0
	_foe.position = foe_pos
	_foe.rotation = Vector3(0.4, 0.0, foe_rot)
	_stage.glint_at = _seg(t, 0.5, 0.75) * 1.2 - 0.1 if t < 0.8 else -1.0
	# 5. название: тлеет и держится, потом гаснет
	_text_a = _seg(t, 1.2, 1.7) * (1.0 - _seg(t, 1.7 + HOLD, 2.5 + HOLD))
	if t > 1.7 and _embers.emitting and t > 1.7 + HOLD:
		_embers.emitting = false
	if t > 3.0 + HOLD:
		queue_free()
	queue_redraw()


func _clash() -> void:
	_flash = 1.0
	_shake = 1.0
	if _snd_hit != null:
		_snd_hit.play()
	var c := _clash_px()
	_sparks.position = c
	_sparks.restart()
	_sparks.emitting = true
	_embers.position = c
	_embers.emission_rect_extents = Vector2(_text_w() * 0.5, 18.0)
	_embers.emitting = true


func _scale() -> float:
	var vs := get_viewport_rect().size
	return maxf(vs.x / 1600.0, vs.y / 900.0)


func _origin() -> Vector2:
	var vs := get_viewport_rect().size
	return (vs - Vector2(1600, 900) * _scale()) * 0.5 + Vector2(0, -vs.y * 0.12)


func _clash_px() -> Vector2:
	return _origin() + _stage.to_px(CLASH) * _scale()


func _fs() -> int:
	return int(get_viewport_rect().size.y * 0.075)


func _text_w() -> float:
	return _font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs()).x


func _draw() -> void:
	if _t < 0.0:
		return
	var sh := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _shake * _shake
	var sc := _scale()
	draw_texture_rect(_stage.get_texture(), Rect2(_origin() + sh, Vector2(1600, 900) * sc), false)
	var c := _clash_px()
	if _flash > 0.0:                                     # вспышка удара: белая звезда и мягкий круг
		var r := 260.0 * sc * (1.2 - _flash * 0.4)
		draw_circle(c, r, Color(1.0, 0.85, 0.7, 0.18 * _flash))
		draw_circle(c, r * 0.3, Color(1.0, 1.0, 1.0, 0.5 * _flash))
		for i: int in 4:
			var a := PI * 0.25 + i * PI * 0.5
			var d := Vector2(cos(a), sin(a)) * r * 1.3
			draw_line(c - d, c + d, Color(1, 1, 1, 0.7 * _flash), 3.0 * sc * _flash + 1.0, true)
	if _text_a > 0.0:                                    # название — на месте искр, из огня в белое
		var fs := _fs()
		var w := _text_w()
		var p := c + Vector2(-w * 0.5, fs * 0.35)
		var hot := 1.0 - _seg(_t, 1.2, 2.4)
		var col := Color(1.0, lerpf(1.0, 0.62, hot), lerpf(1.0, 0.3, hot), _text_a)
		draw_string_outline(_font, p, _name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.16),
			Color(0.05, 0.02, 0.08, 0.85 * _text_a))
		draw_string(_font, p + Vector2(0, 2), _name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1.0, 0.45, 0.2, 0.5 * _text_a * hot))
		draw_string(_font, p, _name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var lw := w * 0.6 * _seg(_t, 1.4, 2.0)               # черта под названием
		draw_line(c + Vector2(-lw, fs * 0.6), c + Vector2(lw, fs * 0.6), Color(Hud.PINK, 0.8 * _text_a), 2.0)
