extends CanvasLayer
## Экран загрузки между картой мира и локацией. Фон — арт (textures/loading/art_*.jpg, медленно наезжает),
## сверху вниз: название места, строка рассказчика; внизу — чёрный воин на колене в кольце загрузки.
## Каждые 20 % в него вонзается катана (звон, искры, вздрагивает); на 100 % — пять катан, и воин падает замертво
## (покадровая анимация: textures/loading/death_sheet.png — рыцарь мода с анимацией смерти Meshy, отрисованный
## силуэтом в Blender, pax_rpg/dev/blender/knight/death_frames.py; катаны едут за его костями из death.json).
## От места, где он лёг, экран «расползается» (shaders/reveal.gdshader) — под ним уже игра.
## run(): появление → middle (построить / убрать локацию, пока экран закрыт) → катаны → падение → done.

const Katana := preload("res://mods/pax_rpg/src/ui/katana.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const FADE := 0.35
const ARTS := 4
# катаны: отрезок между костями (от нижней к верхней), где на нём, угол рукояти к отрезку (рад)
const HITS := [["Spine02", "Spine01", 0.5, 0.85], ["Spine01", "Spine", 0.4, -0.8], ["Spine", "neck", 0.3, 1.45],
	["Hips", "Spine02", 0.7, -1.5], ["Spine01", "Spine", 0.85, 0.3]]
const KNEEL := Vector2(0.75, 0.55)        # середина воина на колене (доли кадра) — центр кольца
const FIG := 0.82                         # доля высоты кадра, которую занимает воин на колене

var mod: PaxMod
var _stage: Control
var _text: Label
var _busy := false
var _art: Texture2D
var _sheet: Texture2D               # кадры смерти
var _anim: Dictionary = {}          # death.json: frames, cols, rows, cell, bones
var _title := ""
var _t := 0.0                      # с от начала показа
var _p := 0.0                      # прогресс 0..1
var _stuck: Array = []             # {i, t} — вонзённые катаны, t — когда
var _fall := 0.0                   # 0..1 — воин заваливается (из _die)
var _smoke: Texture2D
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
	_sheet = Assets.tex(mod, "textures/loading/death_sheet.png")
	var parsed: Variant = JSON.parse_string(mod.read_text("textures/loading/death.json"))
	_anim = parsed if parsed is Dictionary else {}
	var sh: Shader = mod.shader("shaders/reveal.gdshader")
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_stage.material = mat
	_fly = _player("sounds/katana_hit_%d.ogg", 3, -8.0)       # вместо свиста — звон катаны, как в заставке города
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
	p.bus = "PaxRpgSfx"
	p.stream = rnd
	p.volume_db = vol
	p.max_polyphony = 3
	add_child(p)
	return p


func _sfx(p: AudioStreamPlayer) -> void:
	if p != null:
		p.play()


var _wait := Callable()
var _done_cb := Callable()
var _waiting := false


func busy() -> bool:
	return _busy


## wait — () -> bool: можно ли открывать (город строится по кадрам — экран держится, пока не готов).
func run(title: String, text: String, seconds: float, middle: Callable, done: Callable, wait := Callable()) -> void:
	if _busy:
		return
	_busy = true
	_wait = wait
	_done_cb = done
	_waiting = false
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
	tw.tween_callback(middle)                         # строим за закрытым экраном (город — по кадрам, ролик живой)
	tw.tween_property(self, "_p", 1.0, maxf(seconds, 1.5)).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _waiting = true)   # дальше — когда локация готова (_process)


## Вторая половина ролика: воин падает, экран раскрывается. Только когда локация готова.
func _outro() -> void:
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_property(self, "_die", 1.0, 1.6)
	tw.tween_interval(0.1)
	tw.tween_method(_set_reveal, 0.0, 2.2, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish.bind(_done_cb))


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
	preload("res://mods/pax_rpg/src/trace.gd").tick("loading._process")
	if not visible:
		return
	if _waiting and (not _wait.is_valid() or bool(_wait.call())):
		_waiting = false
		_outro()
	_t += delta
	_shake = maxf(0.0, _shake - delta * 3.0)
	var due := mini(5, int(floor(_p * 5.0 + 0.0001)))
	while _stuck.size() < due:                          # каждые 20 % — катана
		_stuck.append({"i": _stuck.size(), "t": _t})
		_sfx(_fly)
		get_tree().create_timer(0.16).timeout.connect(func() -> void:
			_sfx(_hit))                                  # без вспышки и тряски — только звук входа клинка
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


## Кадр воина на экране (весь кадр листа; воин на колене — по центру внизу).
func _warrior_rect() -> Rect2:
	var vs := _stage.get_viewport_rect().size
	var cell: Array = _anim.get("cell", [418, 300])
	var h := vs.y * 0.2 / FIG
	var w := h * float(cell[0]) / float(cell[1])
	return Rect2(Vector2(vs.x * 0.5 - KNEEL.x * w, vs.y * 0.955 - h), Vector2(w, h))


## Номер кадра: дрожь (первые 12 %) — кадр 0, потом вся анимация падения.
func _frame() -> int:
	var n := int(_anim.get("frames", 1))
	var k := clampf((_die - 0.12) / 0.88, 0.0, 1.0)
	return mini(int(k * n), n - 1)


func _shiver() -> Vector2:
	var s := sin(_t * 60.0) * _shake * 3.0
	if _die > 0.0 and _die < 0.12:
		s += sin(_t * 70.0) * 2.5
	return Vector2(s, 0.0)


## Кость в текущем кадре → экран.
func _bone(name: String) -> Vector2:
	var bones: Array = _anim.get("bones", [])
	var r := _warrior_rect()
	if bones.is_empty():
		return r.position + KNEEL * r.size
	var fr: Dictionary = bones[_frame()]
	var b: Array = fr.get(name, [KNEEL.x, KNEEL.y])
	return r.position + Vector2(float(b[0]), float(b[1])) * r.size + _shiver()


## Где на теле катана и куда смотрит её рукоять.
func _hit_pose(i: int) -> Array:
	var hit: Array = HITS[i]
	var a := _bone(str(hit[0]))
	var b := _bone(str(hit[1]))
	var seg := (b - a).angle() if a.distance_to(b) > 0.5 else -PI * 0.5
	return [a.lerp(b, float(hit[2])), seg + float(hit[3])]


## Точка на экране для «расползания» — где он лёг (таз в последнем кадре).
func _body_point(_uv: Vector2) -> Vector2:
	return _bone("Spine02")


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
	var wr := _warrior_rect()
	var glow_c := wr.position + KNEEL * wr.size
	for g: int in 10:
		var rr := h * (0.16 - g * 0.013)
		_stage.draw_circle(glow_c, rr, Color(1.0, 0.45, 0.72, 0.035 * (1.0 - _die * 0.6)))
	# катаны — ПОЗАДИ воина: часть клинка в теле скрыта силуэтом, острие выходит с другой стороны
	for s: Dictionary in _stuck:
		var pose := _hit_pose(int(s.i))
		var entry: Vector2 = pose[0]
		var ang := float(pose[1])
		var dir := Vector2.from_angle(ang)                   # от острия к рукояти
		var age := _t - float(s.t)
		var k := clampf(age / 0.16, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		var tip := entry - dir * h * 0.06 + dir * h * 0.6 * (1.0 - k)
		Katana.draw(_stage, tip, ang, h * 0.17, 1.0, 0.0, "", null, 0, 1.0, false, true)
	# воин — кадр листа
	if _sheet != null and not _anim.is_empty():
		var cols := int(_anim.get("cols", 8))
		var cell: Array = _anim.get("cell", [418, 300])
		var f := _frame()
		var src := Rect2(float((f % cols) * int(cell[0])), float((f / cols) * int(cell[1])), float(cell[0]), float(cell[1]))
		_stage.draw_texture_rect_region(_sheet, Rect2(wr.position + _shiver(), wr.size), src)
	_draw_flash(vs)


func _draw_flash(vs: Vector2) -> void:
	if _flash > 0.0:
		_stage.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.8, 0.9, 0.16 * _flash))


func _draw_ring(h: float) -> void:
	var wr := _warrior_rect()
	var c := wr.position + KNEEL * wr.size
	var r := h * 0.135
	var fade := 1.0 - smoothstep(0.1, 0.5, _die)
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
