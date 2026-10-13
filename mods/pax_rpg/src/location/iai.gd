extends Control
## «Иай: остановка времени» (V) — ультимейт катаной, как кат-сцена в бою (план — NOTEBOOK И-36):
##  0.0  герой опускается на колено (поза — пока Deathblow в низком приседе), двуручник скрыт, катана у бедра;
##  0.6  клинок выдвигается из ножен на палец — щелчок цубы (до этого мига приём сбивается ударом);
##  0.85 СТОП ВРЕМЕНИ: звук, музыка глохнет, мир замирает (враги, частицы, огонь, листья висят), шейдер
##       timestop.gdshader — рыбий глаз, расслоение цвета, сиреневый монохром, волна от героя; камера отъезжает,
##       FOV растёт;
##  1.25 20 линий разреза поверх экрана, всё чаще: 1.0 · 0.8ⁿ с (не меньше 0.12): прочерк, вспышка, шрам; свист и
##       микротряска; линии — через врагов (кого задели — список);
##  …    полсекунды тишины (сердце), все шрамы вспыхивают, из разрезов — мана;
##  …    ПЕРЕМОТКА: звук остановки задом наперёд, шейдер и камера обратно, время разгоняется 0 → 1;
##  …    катана с щелчком входит в ножны — урон всем задетым разом; герой встаёт.
## Время героя, камеры и эффектов — настоящее; мир стоит (у каждого узла своя скорость = 0, не Engine.time_scale).

const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Hero := preload("res://mods/pax_rpg/src/location/hero.gd")
const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")
const AudioBus := preload("res://mods/pax_rpg/src/location/audio_bus.gd")

const LINES := 20
const T_DRAW := 0.6
const T_STOP := 0.85
const T_LINES := 1.25
const STOP_IN := 0.35           # с — мир уходит в остановку
const REWIND := 0.9             # с — перемотка
const RAMP := 0.7               # с — время разгоняется после перемотки
const REACH := 12.0             # м — кого достают разрезы

signal finished(interrupted: bool)

var mod: PaxMod
var active := false
var cam_override := false       # location.gd не ведёт камеру, пока true
var _t := 0.0
var _hero: Hero
var _player: Node3D
var _cam: Camera3D
var _view: Node
var _enemies: Callable          # () -> Array (враги локации)
var _on_cut: Callable           # (враг) -> void — урон в финале
var _on_fx: Callable            # (позиция мира, цвет) -> void — выброс маны
var _set_hud: Callable          # (bool) -> void
var _fx: ColorRect
var _mat: ShaderMaterial
var _times: PackedFloat32Array = []
var _lines: Array = []          # {a, b, t0}
var _victims: Array = []
var _frozen: Array = []         # [узел, свойство, значение]
var _cam0: Transform3D
var _fov0 := 65.0
var _snd := {}
var _katana: Node3D             # ножны + клинок у бедра
var _blade: Node3D
var _done := {}
var _t_end := 0.0
var _shake := 0.0
var _hud_was := true


func setup(m: PaxMod, view: Node, hero: Hero, player: Node3D, cam: Camera3D, enemies: Callable, on_cut: Callable,
		on_fx: Callable, set_hud: Callable) -> void:
	mod = m
	name = "PaxRpgIai"
	_view = view
	_hero = hero
	_player = player
	_cam = cam
	_enemies = enemies
	_on_cut = on_cut
	_on_fx = on_fx
	_set_hud = set_hud
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()                  # разрезы — свечение (складывается со сценой)
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = mod.shader("shaders/timestop.gdshader")
	_fx.material = _mat
	_fx.visible = false
	add_child(_fx)
	for n: String in ["timestop", "rewind", "draw", "sheathe", "slash", "heart"]:
		var p := AudioStreamPlayer.new()
		p.stream = mod.sound("sounds/iai_%s.wav" % n)
		p.bus = "PaxRpgSfx"
		p.max_polyphony = 4
		add_child(p)
		_snd[n] = p
	# расписание линий: 1.0, 0.8, 0.64 … (не меньше 0.12 с)
	var at := T_LINES
	var gap := 1.0
	for i: int in LINES:
		_times.append(at)
		at += gap
		gap = maxf(0.12, gap * 0.8)


func _play(n: String, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _snd.get(n)
	if p != null and p.stream != null:
		p.pitch_scale = pitch
		p.play()
	if OS.is_debug_build():
		print("iai_sound %s %.3f %.3f" % [n, _t, pitch])          # стенд видео собирает по ним звуковую дорожку


func start() -> bool:
	if active or _hero == null or not _hero.iai_begin():
		return false
	active = true
	cam_override = false
	_t = 0.0
	_done = {}
	_lines = []
	_victims = []
	_shake = 0.0
	_t_end = _times[LINES - 1] + 0.65 + 0.2 + REWIND + RAMP + 1.6
	_attach_katana()
	return true


## Удар по герою до щелчка цубы — приём сорван.
func interrupt() -> bool:
	if not active or _t >= T_DRAW:
		return false
	_finish(true)
	return true


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	var t := _t
	var last := _times[LINES - 1]
	var t_flash := last + 0.65
	var t_rewind := t_flash + 0.2
	var t_ramp := t_rewind + REWIND
	var t_sheathe := t_ramp + 0.15
	_once("draw", T_DRAW, func() -> void:
		_play("draw")
		if _blade != null:
			var tw := create_tween()
			tw.tween_property(_blade, "position:x", -0.05, 0.12).set_ease(Tween.EASE_OUT))
	_once("stop", T_STOP, _time_stop)
	for i: int in LINES:
		_once("line%d" % i, _times[i], _cut.bind(i))
	_once("heart", last + 0.2, func() -> void: _play("heart"))
	_once("flash", t_flash, func() -> void:
		for v: Variant in _victims:
			if is_instance_valid(v) and _on_fx.is_valid():
				_on_fx.call((v as Node3D).global_position + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.85)))
	_once("rewind", t_rewind, func() -> void: _play("rewind"))
	_once("ramp", t_ramp, _unfreeze_start)
	_once("sheathe", t_sheathe, _sheathe)
	_once("rise", t_sheathe + 0.35, func() -> void: _hero.iai_end())
	# шейдер: остановка → держим → перемотка
	var k := 0.0
	if t >= T_STOP:
		k = smoothstep(T_STOP, T_STOP + STOP_IN, t) * (1.0 - smoothstep(t_rewind, t_rewind + REWIND, t))
	var wave := -1.0
	if t >= T_STOP and t < T_STOP + 0.9:
		wave = (t - T_STOP) * 1.6
	elif t >= t_rewind and t < t_rewind + REWIND:
		wave = 1.4 * (1.0 - (t - t_rewind) / REWIND)              # волна схлопывается обратно к герою
	var flash := 0.0
	if t >= t_flash:
		flash = 0.55 * exp(-(t - t_flash) * 9.0)
	if t >= t_sheathe:
		flash = maxf(flash, 0.35 * exp(-(t - t_sheathe) * 10.0))
	_fx.visible = k > 0.001 or flash > 0.001
	_mat.set_shader_parameter("k", k)
	_mat.set_shader_parameter("wave", wave)
	_mat.set_shader_parameter("flash", flash)
	if is_instance_valid(_player) and is_instance_valid(_cam):
		var sp := _cam.unproject_position(_player.global_position + Vector3(0, 0.6, 0))
		_mat.set_shader_parameter("center", sp / get_viewport_rect().size)
	_camera(k)
	if t >= t_ramp and t < t_ramp + RAMP:
		_unfreeze_step((t - t_ramp) / RAMP)
	_shake = maxf(0.0, _shake - delta * 4.0)
	if t >= _t_end:
		_finish(false)
	queue_redraw()


func _once(key: String, at: float, fn: Callable) -> void:
	if _t >= at and not _done.has(key):
		_done[key] = true
		fn.call()


# ---------- остановка времени ----------

func _time_stop() -> void:
	_play("timestop")
	_hud_was = true
	if _set_hud.is_valid():
		_set_hud.call(false)
	AudioBus.set_volume(AudioBus.MUSIC, float(mod.get_setting("music_volume", 0.6)) * 0.08)
	_freeze(true)
	_cam0 = _cam.global_transform
	_fov0 = _cam.fov
	cam_override = true


## Всё живое в мире замирает, кроме героя: скорость анимаций и частиц — 0, ИИ и процессы — стоп.
func _freeze(on: bool) -> void:
	if not on:
		return
	_frozen = []
	var stack: Array = [_view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == _player or (n is Node3D and _player.is_ancestor_of(n)):
			continue
		stack.append_array(n.get_children())
		if n is AnimationPlayer:
			_frozen.append([n, "speed_scale", (n as AnimationPlayer).speed_scale])
			(n as AnimationPlayer).speed_scale = 0.0
		elif n is CPUParticles3D:
			_frozen.append([n, "speed_scale", (n as CPUParticles3D).speed_scale])
			(n as CPUParticles3D).speed_scale = 0.0
		elif n is GPUParticles3D:
			_frozen.append([n, "speed_scale", (n as GPUParticles3D).speed_scale])
			(n as GPUParticles3D).speed_scale = 0.0
		if n is CharacterBody3D or n.is_processing() or n.is_physics_processing():
			if n != _view:
				_frozen.append([n, "proc", [n.is_processing(), n.is_physics_processing()]])
				n.set_process(false)
				n.set_physics_process(false)


func _unfreeze_start() -> void:
	AudioBus.set_volume(AudioBus.MUSIC, float(mod.get_setting("music_volume", 0.6)))


## Время разгоняется: f 0 → 1; процессы (ИИ) включаются на середине разгона.
func _unfreeze_step(f: float) -> void:
	var e := f * f
	for fr: Array in _frozen:
		var n: Node = fr[0]
		if not is_instance_valid(n):
			continue
		if str(fr[1]) == "speed_scale":
			n.set(StringName("speed_scale"), float(fr[2]) * e)
		elif f > 0.5:
			var pr: Array = fr[2]
			n.set_process(bool(pr[0]))
			n.set_physics_process(bool(pr[1]))


func _unfreeze_all() -> void:
	for fr: Array in _frozen:
		var n: Node = fr[0]
		if not is_instance_valid(n):
			continue
		if str(fr[1]) == "speed_scale":
			n.set(StringName("speed_scale"), float(fr[2]))
		else:
			var pr: Array = fr[2]
			n.set_process(bool(pr[0]))
			n.set_physics_process(bool(pr[1]))
	_frozen = []


# ---------- камера ----------

func _camera(k: float) -> void:
	if not cam_override or not is_instance_valid(_cam):
		return
	var e := k * k * (3.0 - 2.0 * k)
	var focus := _player.global_position + Vector3(0, 0.6, 0)
	var back := _cam0.origin - focus
	back.y = 0.0
	back = back.normalized() if back.length() > 0.01 else Vector3(0, 0, 1)
	var far := focus + back * 2.9 + Vector3(0, 0.9, 0)          # крупно: герой на колене в кадре
	var pos := _cam0.origin.lerp(far, e)
	var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.06 * _shake
	var xf := Transform3D(Basis(), pos).looking_at(focus, Vector3.UP)
	_cam.global_transform = Transform3D(_cam0.basis.slerp(xf.basis, e), pos + sh)
	_cam.fov = lerpf(_fov0, 84.0, e)


# ---------- линии разреза ----------

func _cut(i: int) -> void:
	_play("slash", randf_range(0.92, 1.12))
	_shake = 1.0
	var vs := get_viewport_rect().size
	var at := vs * Vector2(randf_range(0.1, 0.9), randf_range(0.15, 0.85))
	var pool: Array = []
	if _enemies.is_valid():
		for e: Variant in _enemies.call():
			if is_instance_valid(e) and (e as Goblin).is_alive() \
					and (e as Node3D).global_position.distance_to(_player.global_position) <= REACH:
				var p3 := (e as Node3D).global_position + Vector3(0, 0.9, 0)
				if not _cam.is_position_behind(p3):
					pool.append(e)
	if not pool.is_empty() and i % 3 != 2:                  # каждая третья линия — свободный разрез по кадру
		var e: Node3D = pool[i % pool.size()]
		at = _cam.unproject_position(e.global_position + Vector3(0, 0.9, 0)) + Vector2(randf_range(-160, 160), randf_range(-120, 120))
		if not _victims.has(e):
			_victims.append(e)
	var ang := randf_range(-PI * 0.45, PI * 0.45) + (PI * 0.5 if i % 3 == 1 else 0.0)
	var dir := Vector2(cos(ang), sin(ang))
	var reach := vs.length()
	_lines.append({"a": at - dir * reach, "b": at + dir * reach, "t0": _t})


func _draw() -> void:
	if not active:
		return
	var last := _times[LINES - 1]
	var t_flash := last + 0.65
	var t_rewind := t_flash + 0.2
	var fade := 1.0 - smoothstep(t_rewind, t_rewind + REWIND * 0.7, _t)
	var boom := exp(-maxf(0.0, _t - t_flash) * 6.0) if _t >= t_flash else 0.0
	for ln: Dictionary in _lines:
		var age := _t - float(ln.t0)
		var a: Vector2 = ln.a
		var b: Vector2 = ln.b
		var grow := clampf(age / 0.06, 0.0, 1.0)                  # прочерк от края к краю
		var tip := a.lerp(b, grow)
		var hot := exp(-age * 7.0)                                 # вспышка свежего разреза
		var w := 2.5 + 7.0 * hot + 7.0 * boom
		var glow := Color(1.0, 0.3, 0.75, (0.3 + 0.6 * hot + 0.7 * boom) * fade)
		draw_line(a, tip, Color(glow, glow.a * 0.35), w * 6.0, true)          # широкий ореол
		var core := Color(1.0, 0.98, 1.0, (0.75 + 0.25 * hot) * fade)
		draw_line(a, tip, glow, w * 2.2, true)
		draw_line(a, tip, core, w * 0.6, true)


# ---------- финал ----------

func _sheathe() -> void:
	_play("sheathe")
	_shake = 1.6
	if _blade != null:
		var tw := create_tween()
		tw.tween_property(_blade, "position:x", 0.0, 0.1).set_ease(Tween.EASE_IN)
	for v: Variant in _victims:
		if is_instance_valid(v) and _on_cut.is_valid():
			_on_cut.call(v)
	_unfreeze_all()
	cam_override = false
	if _set_hud.is_valid():
		_set_hud.call(true)


func _finish(interrupted: bool) -> void:
	_unfreeze_all()
	AudioBus.set_volume(AudioBus.MUSIC, float(mod.get_setting("music_volume", 0.6)))
	if is_instance_valid(_cam) and cam_override:
		_cam.fov = _fov0
	cam_override = false
	_fx.visible = false
	if _set_hud.is_valid():
		_set_hud.call(true)
	if is_instance_valid(_katana):
		_katana.get_parent().queue_free()                # вместе с креплением к кости
	_katana = null
	_blade = null
	if _hero != null and _hero.action == "Iai":
		_hero.iai_end()
	active = false
	queue_redraw()
	finished.emit(interrupted)


## Катана в ножнах — у левого бедра (кость Hips); клинок выдвигается из ножен вдоль своей оси.
func _attach_katana() -> void:
	var holder := _hero.bone_holder("Hips")
	if holder == null:
		return
	_katana = Node3D.new()
	holder.add_child(_katana)
	_katana.position = Vector3(0.16, -0.02, 0.08)            # левое бедро, чуть вперёд
	_katana.rotation_degrees = Vector3(0, 90, -60)           # рукоять вперёд-вверх, ножны назад-вниз
	var saya := Assets.model(mod, "models/weapons/katana_saya.glb")
	if saya != null:
		_katana.add_child(saya)
	_blade = Node3D.new()
	_katana.add_child(_blade)
	var blade := Assets.model(mod, "models/weapons/katana.glb")
	if blade != null:
		_blade.add_child(blade)
