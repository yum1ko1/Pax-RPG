extends CharacterBody3D
## Мирный житель (гоблин): ходит по маршрутам улиц из планировки города («paths»: ломаные XZ), иногда
## останавливается поглазеть; на героя не нападает, обходить его не умеет — просто ждёт, если упёрся.
## Модель и клипы — как у гоблина-врага (models/goblin/), без боя.
const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")

const DIR := "models/goblin/"
const SPEED := 1.3

var mod: PaxMod
var _model: Node3D
var _anim: AnimationPlayer
var _path: PackedVector3Array = PackedVector3Array()
var _i := 0
var _dir := 1
var _wait := 0.0
var _speed := SPEED
var _stuck := 0                    # сколько раз подряд упёрся — на третий разворачивается назад по маршруту


func setup(m: PaxMod, path: PackedVector3Array, start_i: int, seed_v: int) -> void:
	mod = m
	_path = path
	_i = clampi(start_i, 0, path.size() - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_speed = SPEED * rng.randf_range(0.8, 1.25)
	_dir = 1 if rng.randf() < 0.5 else -1
	position = path[_i]
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.1
	shape.shape = cap
	shape.position = Vector3(0, 0.55, 0)
	add_child(shape)
	_model = mod.model(DIR + "goblin_rigged.glb")
	if _model == null:
		return
	_model.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)
	add_child(_model)
	_anim = _find(_model)
	if _anim != null:
		var lib: AnimationLibrary = _anim.get_animation_library("") if _anim.has_animation_library("") else AnimationLibrary.new()
		for clip: String in ["walk", "idle"]:
			var src := mod.model(DIR + clip + ".glb")
			if src == null:
				continue
			var a := _find(src)
			if a != null and a.get_animation_list().size() > 0:
				var an: Animation = a.get_animation(a.get_animation_list()[0]).duplicate()
				an.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(clip, an)
			src.free()
		if not _anim.has_animation_library(""):
			_anim.add_animation_library("", lib)
		_play("walk")
		_anim.seek(rng.randf_range(0.0, 1.0), true)


static func _find(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find(c)
		if f != null:
			return f
	return null


func _play(c: String) -> void:
	if _anim != null and _anim.has_animation(c) and _anim.current_animation != c:
		_anim.play(c, 0.3)


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_phys(delta)
	Prof.add("NPC", t0)


func _phys(delta: float) -> void:
	if _path.size() < 2:
		return
	var fall := velocity.y - 20.0 * delta if not is_on_floor() else -0.5      # по пандусам и ступеням — с землёй
	if _wait > 0.0:
		_wait -= delta
		velocity = Vector3(0.0, fall, 0.0)
		move_and_slide()
		_play("idle")
		return
	var target := _path[_i]
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.5:
		_stuck = 0
		var nxt := _i + _dir
		if nxt < 0 or nxt >= _path.size():
			_dir = -_dir
			_wait = randf_range(2.0, 6.0)               # конец маршрута — постоять
			return
		_i = nxt
		if randf() < 0.12:
			_wait = randf_range(1.5, 4.0)
		return
	var d := to.normalized()
	velocity = Vector3(d.x * _speed, fall, d.z * _speed)
	move_and_slide()
	var hv := get_real_velocity()
	hv.y = 0.0
	if hv.length() < _speed * 0.2:                      # упёрся (в героя, в соседа) — постоять, потом назад
		_stuck += 1
		_wait = 0.8
		if _stuck >= 3:
			_stuck = 0
			_dir = -_dir
			_i = clampi(_i + _dir, 0, _path.size() - 1)
	else:
		_stuck = 0
	_play("walk")
	if _model != null:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(d.x, d.z), minf(1.0, delta * 6.0))
