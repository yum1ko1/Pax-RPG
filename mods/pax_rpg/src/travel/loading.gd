extends CanvasLayer
## Экран загрузки между картой мира и локацией. Фон — арт (textures/loading/art_*.jpg, медленно наезжает),
## сверху вниз: название места, строка рассказчика; внизу — чёрный воин на колене в кольце загрузки.
## Каждые 20 % в него вонзается катана (звон, искры, вздрагивает); на 100 % — пять катан, воин падает, и от
## места, где он лёг, экран «расползается» (shaders/reveal.gdshader) — под ним уже игра.
## run(): появление → middle (построить / убрать локацию, пока экран закрыт) → катаны → падение → done.

const Katana := preload("res://mods/pax_rpg/src/ui/katana.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const FADE := 0.35
const ARTS := 4
# катаны: точка попадания на воине (доли картинки), откуда летит (угол от точки), сколько клинка в теле
const HITS := [[0.52, 0.3, -2.25], [0.6, 0.4, -0.85], [0.45, 0.45, -2.75], [0.56, 0.24, -1.45], [0.5, 0.55, -0.45]]
const PIVOT := Vector2(0.24, 0.97)        # колено/ступня впереди — вокруг неё он падает (доли картинки)
const HIP := Vector2(0.55, 0.6)           # поясница: вокруг неё оседает корпус
const WAIST := 0.6                        # выше — корпус (оседает), ниже — ноги

var mod: PaxMod
var _stage: Control
var _text: Label
var _busy := false
var _art: Texture2D
var _warrior: Texture2D
var _title := ""
var _t := 0.0                      # с от начала показа
var _p := 0.0                      # прогресс 0..1
var _stuck: Array = []             # {i, t} — вонзённые катаны, t — когда
var _fall := 0.0                   # 0..1 — воин заваливается (из _die)
var _die := 0.0                    # 0..1 — вся смерть: дрожь → корпус оседает → падает → отскок, пыль
var _shake := 0.0
var _fly: AudioStreamPlayer
var _hit: AudioStreamPlayer
var _thud: AudioStreamPlayer
var _serif: Font
var _flash := 0.0                  # вспышка при ударе катаны
var _fx: Array = []                # частицы: {p: Vector2 (доли экрана), v, kind: 0 — уголёк, 1 — лепесток, rot, size}


func setup(m: PaxMod = null) -> void:
	mod = m
	name = "PaxRpgLoading"
	layer = 110                    # над окнами игры и над локацией
	visible = false
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 20)
	_text.add_theme_color_override("font_color", Color(0.86, 0.9, 1.0))
	_text.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 0.9))
	_text.add_theme_constant_override("outline_size", 6)
	_stage.add_child(_text)
	_serif = Hud._sys(["Cormorant Garamond", "Georgia", "Palatino Linotype", "Times New Roman"], 600)
	_text.add_theme_font_override("font", _serif)
	if mod == null:
		return
	_warrior = mod.texture("textures/loading/warrior.png")
	var sh: Shader = mod.shader("shaders/reveal.gdshader")
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_stage.material = mat
	_fly = _player("sounds/katana_fly_%d.ogg", 3, -6.0)
	_hit = _player("sounds/katana_hit_%d.ogg", 3, -4.0)
	_thud = _player("sounds/body_fall.ogg", 0, -3.0)


func _player(pattern: String, n: int, vol: float) -> AudioStreamPlayer:
	var rnd := AudioStreamRandomizer.new()
	rnd.random_pitch = 1.08
	for i: int in maxi(n, 1):
		var st: AudioStream = mod.sound(pattern % i if n > 0 else pattern)
		if st != null:
			rnd.add_stream(-1, st)
	if rnd.streams_count == 0:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = rnd
	p.volume_db = vol
	p.max_polyphony = 3
	add_child(p)
	return p


func _sfx(p: AudioStreamPlayer) -> void:
	if p != null:
		p.play()


func busy() -> bool:
	return _busy


func run(title: String, text: String, seconds: float, middle: Callable, done: Callable) -> void:
	if _busy:
		return
	_busy = true
	_title = title
	_text.text = text
	_t = 0.0
	_p = 0.0
	_fall = 0.0
	_die = 0.0
	_shake = 0.0
	_stuck.clear()
	_flash = 0.0
	_fx.clear()
	for i: int in 90:
		_fx.append(_new_fx(randf()))
	_set_reveal(0.0)
	if mod != null:
		_art = mod.texture("textures/loading/art_%d.jpg" % (randi() % ARTS + 1))
	_stage.modulate.a = 0.0
	_text.modulate.a = 1.0
	visible = true
	var tw := create_tween()
	tw.tween_property(_stage, "modulate:a", 1.0, FADE)
	tw.tween_interval(0.05)
	tw.tween_callback(middle)                         # строим за закрытым экраном (кадры на миг замрут)
	tw.tween_property(self, "_p", 1.0, maxf(seconds, 2.5)).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.3)
	tw.tween_property(self, "_die", 1.0, 1.7)
	tw.parallel().tween_callback(_sfx.bind(_thud)).set_delay(1.3)
	tw.tween_interval(0.2)
	tw.tween_method(_set_reveal, 0.0, 2.2, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish.bind(done))


func _finish(done: Callable) -> void:
	visible = false
	_busy = false
	_set_reveal(0.0)
	done.call()


func _set_reveal(r: float) -> void:
	_text.modulate.a = clampf(1.0 - r * 3.0, 0.0, 1.0)
	var mat := _stage.material as ShaderMaterial
	if mat == null:
		if r > 0.0:
			_stage.modulate.a = clampf(1.0 - r, 0.0, 1.0)   # без шейдера — просто растаять
		return
	if not _stage.is_inside_tree():
		return
	var vs := _stage.get_viewport_rect().size
	mat.set_shader_parameter("radius", r)
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	mat.set_shader_parameter("center", _body_point(Vector2(0.4, 0.75)) / vs)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_shake = maxf(0.0, _shake - delta * 3.0)
	var due := mini(5, int(floor(_p * 5.0 + 0.0001)))
	while _stuck.size() < due:                          # каждые 20 % — катана
		_stuck.append({"i": _stuck.size(), "t": _t})
		_sfx(_fly)
		get_tree().create_timer(0.16).timeout.connect(func() -> void:
			_sfx(_hit)
			_shake = 1.0
			_flash = 1.0)
	_flash = maxf(0.0, _flash - delta * 4.0)
	for f: Dictionary in _fx:                          # угольки поднимаются, лепестки летят вниз наискось
		var pp: Vector2 = f.p
		pp += (f.v as Vector2) * delta + Vector2(sin(_t * 1.3 + float(f.rot) * 5.0) * 0.006 * delta, 0.0)
		f.rot = float(f.rot) + delta * (1.5 if int(f.kind) == 1 else 0.0)
		f.p = pp
		if pp.y < -0.05 or pp.y > 1.05 or pp.x > 1.05:
			var nf := _new_fx(0.0)
			f.p = nf.p
			f.v = nf.v
	_stage.queue_redraw()


func _new_fx(spread: float) -> Dictionary:
	var petal := randf() < 0.35
	if petal:
		return {"p": Vector2(randf_range(-0.2, 0.9), lerpf(-0.04, 1.0, spread)), "v": Vector2(randf_range(0.03, 0.07),
			randf_range(0.04, 0.09)), "kind": 1, "rot": randf() * TAU, "size": randf_range(5.0, 9.0)}
	return {"p": Vector2(randf(), lerpf(1.04, 0.0, spread)), "v": Vector2(randf_range(-0.01, 0.01),
		-randf_range(0.03, 0.09)), "kind": 0, "rot": randf() * TAU, "size": randf_range(1.2, 3.0)}


# ---------- рисование ----------

func _h() -> float:
	return _stage.get_viewport_rect().size.y


## Рамка воина на экране: позиция картинки (левый верх) и размер.
func _warrior_rect() -> Rect2:
	var vs := _stage.get_viewport_rect().size
	var h := vs.y * 0.2
	var w := h * (630.0 / 729.0)
	return Rect2(Vector2(vs.x * 0.5 - w * 0.5, vs.y * 0.955 - h), Vector2(w, h))


## Смерть по фазам (_die 0..1): дрожь, корпус оседает вперёд вокруг поясницы, тело заваливается вокруг колена,
## отскок о землю.
func _slump() -> float:
	var f := clampf((_die - 0.42) / 0.36, 0.0, 1.0)
	return -0.45 * smoothstep(0.12, 0.42, _die) - 0.75 * f * f       # корпус оседает, потом лицом в землю


func _fall_angle() -> float:
	var f := clampf((_die - 0.42) / 0.36, 0.0, 1.0)
	_fall = f * f
	var bounce := 0.0
	if _die > 0.78:
		var b := (_die - 0.78) / 0.22
		bounce = 0.09 * sin(b * PI) * (1.0 - b)
	var shiver := sin(_t * 55.0) * 0.025 * (1.0 - smoothstep(0.0, 0.2, _die)) * float(_die > 0.0)
	return -0.5 * _fall + bounce + shiver + sin(_t * 60.0) * 0.02 * _shake


## Поворот куска тела в точке uv (корпус — ещё и оседание).
func _rot_at(uv: Vector2) -> float:
	return _fall_angle() + (_slump() if uv.y < WAIST else 0.0)


## Точка картинки воина (доли) → экран, с оседанием корпуса, падением, отскоком и дрожью.
func _body_point(uv: Vector2) -> Vector2:
	var r := _warrior_rect()
	var p := r.position + uv * r.size
	if uv.y < WAIST:
		var hip := r.position + HIP * r.size
		p = hip + (p - hip).rotated(_slump())
	var pivot := r.position + PIVOT * r.size
	return pivot + (p - pivot).rotated(_fall_angle())


func _draw_stage() -> void:
	var vs := _stage.get_viewport_rect().size
	var h := vs.y
	# фон: арт «cover» с медленным наездом, затемнение снизу
	_stage.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.02, 0.06))
	if _art != null:
		var ts := _art.get_size()
		var k := maxf(vs.x / ts.x, vs.y / ts.y) * (1.06 + 0.03 * minf(_t / 8.0, 1.0))
		var sz := ts * k
		var drift := Vector2(sin(_t * 0.25) * vs.x * 0.012, cos(_t * 0.19) * vs.y * 0.008)   # медленный дрейф
		_stage.draw_texture_rect(_art, Rect2((vs - sz) * 0.5 + drift, sz), false, Color(0.82, 0.8, 0.86))
	var dark := Color(0.02, 0.02, 0.07, 0.9)                 # градиент снизу (без полос)
	var clear := Color(0.02, 0.02, 0.07, 0.0)
	_stage.draw_polygon(PackedVector2Array([Vector2(0, h * 0.5), Vector2(vs.x, h * 0.5), Vector2(vs.x, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, dark, dark]))
	# частицы
	for f: Dictionary in _fx:
		var at: Vector2 = (f.p as Vector2) * vs
		if int(f.kind) == 0:
			var fl := 0.5 + 0.5 * sin(_t * 7.0 + float(f.rot) * 3.0)
			_stage.draw_circle(at, float(f.size) * 2.2, Color(1.0, 0.45, 0.3, 0.06 * fl))
			_stage.draw_circle(at, float(f.size), Color(1.0, 0.7, 0.45, 0.55 + 0.35 * fl))
		else:
			var sz2 := float(f.size)
			var ro := float(f.rot)
			var pet := PackedVector2Array()
			for j: int in 8:
				var a := TAU * j / 8.0
				pet.append(at + Vector2(cos(a) * sz2, sin(a) * sz2 * (0.45 + 0.25 * sin(ro))).rotated(ro))
			_stage.draw_colored_polygon(pet, Color(1.0, 0.68, 0.84, 0.75))
	# виньетка
	var vig := Color(0.0, 0.0, 0.03, 0.55)
	var nov := Color(0.0, 0.0, 0.03, 0.0)
	_stage.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vs.x * 0.18, 0), Vector2(vs.x * 0.18, h), Vector2(0, h)]),
		PackedColorArray([vig, nov, nov, vig]))
	_stage.draw_polygon(PackedVector2Array([Vector2(vs.x * 0.82, 0), Vector2(vs.x, 0), Vector2(vs.x, h), Vector2(vs.x * 0.82, h)]),
		PackedColorArray([nov, vig, vig, nov]))
	# название места
	if _title != "":
		var fs := int(h * 0.05)
		var tw := _serif.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(vs.x * 0.5 - tw * 0.5, h * 0.66)
		_stage.draw_string_outline(_serif, at, _title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0.02, 0.02, 0.07, 0.85))
		_stage.draw_string(_serif, at, _title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.95))
	_text.position = Vector2(vs.x * 0.2, h * 0.68)
	_text.size = Vector2(vs.x * 0.6, h * 0.08)
	_draw_ring(h)
	# подсветка за воином (чёрный силуэт на тёмном арте иначе не читается)
	var glow_c := _warrior_rect().position + Vector2(0.5, 0.55) * _warrior_rect().size
	for g: int in 10:
		var rr := h * (0.16 - g * 0.013)
		_stage.draw_circle(glow_c, rr, Color(1.0, 0.45, 0.72, 0.035 * (1.0 - _fall * 0.7)))
	# катаны — ПОЗАДИ воина: часть клинка в теле скрыта силуэтом, острие выходит с другой стороны
	for s: Dictionary in _stuck:
		var hit: Array = HITS[int(s.i)]
		var uv := Vector2(float(hit[0]), float(hit[1]))
		var age := _t - float(s.t)
		var entry := _body_point(uv)
		var from_ang := float(hit[2]) + _rot_at(uv)
		var dir := Vector2.from_angle(from_ang)              # от острия к рукояти
		var k := clampf(age / 0.16, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var tip := entry - dir * h * 0.075 + dir * h * 0.6 * (1.0 - k)   # насквозь на 7.5 % высоты экрана
		Katana.draw(_stage, tip, from_ang, h * 0.17, 1.0, 0.0, "", null, 0, 1.0, false, true)
	# воин: ноги и корпус отдельно (корпус оседает вокруг поясницы), куски чуть перекрываются — шва не видно
	if _warrior != null:
		var r := _warrior_rect()
		var ts := _warrior.get_size()
		var pivot := r.position + PIVOT * r.size
		var hip := r.position + HIP * r.size
		var fa := _fall_angle()
		var lo := WAIST - 0.03
		_stage.draw_set_transform(pivot, fa, Vector2.ONE)
		_stage.draw_texture_rect_region(_warrior, Rect2(r.position + Vector2(0, lo * r.size.y) - pivot,
			Vector2(r.size.x, (1.0 - lo) * r.size.y)), Rect2(0, lo * ts.y, ts.x, (1.0 - lo) * ts.y))
		var hp := pivot + (hip - pivot).rotated(fa)
		_stage.draw_set_transform(hp, fa + _slump(), Vector2.ONE)
		var hi := WAIST + 0.03
		_stage.draw_texture_rect_region(_warrior, Rect2(r.position - hip, Vector2(r.size.x, hi * r.size.y)),
			Rect2(0, 0, ts.x, hi * ts.y))
		_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s: Dictionary in _stuck:                            # искры удара — поверх
		var hit: Array = HITS[int(s.i)]
		var age := _t - float(s.t)
		if age > 0.16 and age < 0.5:
			var target := _body_point(Vector2(float(hit[0]), float(hit[1])))
			var a := 1.0 - (age - 0.16) / 0.34
			for j: int in 9:
				var d := Vector2.from_angle(j * 0.7 + float(s.i)) * h * 0.05 * (1.0 - a + 0.2)
				_stage.draw_line(target + d * 0.5, target + d, Color(1.0, 0.55, 0.8, a), 2.0, true)
	if _die > 0.74:                                         # пыль от удара о землю — мягкое облако
		var b := (_die - 0.74) / 0.26
		var ground := _body_point(Vector2(0.3, 0.3))
		ground.y = _warrior_rect().end.y
		for j: int in 22:
			var hsh := fmod(sin(j * 12.9898) * 43758.5453, 1.0)
			var dx := (float(j) / 21.0 - 0.5) * h * 0.26 * (0.5 + b * 0.8)
			var rr := h * (0.02 + 0.02 * absf(hsh)) * (0.6 + b * 1.4)
			var up := h * 0.03 * b * absf(hsh)
			_stage.draw_circle(ground + Vector2(dx, -rr * 0.4 - up), rr, Color(0.62, 0.56, 0.6, 0.09 * (1.0 - b)))
	_draw_flash(vs)


func _draw_flash(vs: Vector2) -> void:
	if _flash > 0.0:
		_stage.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.8, 0.9, 0.16 * _flash))


func _draw_ring(h: float) -> void:
	var wr := _warrior_rect()
	var c := wr.position + Vector2(0.5, 0.55) * wr.size
	var r := h * 0.135
	var fade := 1.0 - _fall
	if fade <= 0.0:
		return
	_stage.draw_arc(c, r, 0.0, TAU, 96, Color(0.47, 0.84, 1.0, 0.18 * fade), 3.0, true)
	if _p > 0.0:
		var a0 := -PI * 0.5
		var a1 := a0 + TAU * _p
		var pulse := 1.0 + 0.35 * sin(_t * 3.2)
		for g: Array in [[14.0, 0.07], [8.0, 0.14], [3.0, 1.0]]:     # свечение — три слоя, дышит
			_stage.draw_arc(c, r, a0, a1, 96, Color(1.0, 0.55, 0.78, float(g[1]) * fade * (pulse if g[1] < 1.0 else 1.0)),
				float(g[0]) * (pulse if g[1] < 1.0 else 1.0), true)
		var head := c + Vector2.from_angle(a1) * r
		_stage.draw_circle(head, 4.0, Color(1, 0.9, 0.97, fade))
	for i: int in 5:                                    # засечки 20 %
		var a := -PI * 0.5 + TAU * (i + 1) / 5.0
		var on := _p >= (i + 1) / 5.0 - 0.001
		var d := Vector2.from_angle(a)
		_stage.draw_line(c + d * (r - 7), c + d * (r + 7), Color(1.0, 0.55, 0.78, fade) if on else Color(0.47, 0.84, 1.0, 0.4 * fade), 2.0, true)
	var pct := "%d%%" % int(round(_p * 100.0))
	var fs := int(h * 0.018)
	_stage.draw_string(_serif, c + Vector2(r + 18, fs * 0.35), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.86, 0.9, 1.0, fade))
