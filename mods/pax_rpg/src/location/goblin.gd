extends CharacterBody3D
## Гоблин — враг на тестовой арене. ИИ: стоит, пока не заметит героя; потом гонится за ним и бьёт.
## Получив урон, проигрывает анимацию Hit и на время теряет ход. Погиб — через пару секунд возрождается.
## Модель и клипы — models/goblin/ (Meshy: риг + idle / walk / run / attack / hit, в один AnimationPlayer).

const DIR := "models/goblin/"
const CLIPS := {"idle": "idle.glb", "walk": "walk.glb", "run": "run.glb", "attack": "attack.glb", "hit": "hit.glb"}
const LOOPED := ["idle", "walk", "run"]

const MAX_HP := 60.0
const DETECT := 14.0          # м, на таком расстоянии гоблин замечает героя
const LOSE := 22.0           # м, дальше — забывает и стоит
const ATTACK_RANGE := 1.8    # м, с такого расстояния бьёт
const WALK_SPEED := 2.2
const RUN_SPEED := 4.2
const RUN_FROM := 6.0        # м, дальше этого бежит, а не идёт
const ATTACK_HIT_AT := 0.45  # доля анимации атаки, когда удар попадает
const COOLDOWN := 1.6        # с между ударами
const HURT_TIME := 0.55      # с, на которые гоблин теряет ход после удара
const RESPAWN := 3.0         # с до возрождения
const DAMAGE := 10.0         # урон героя за удар
const GRAVITY := 20.0

var mod: PaxMod
var hp := MAX_HP
var dead := false
var _target: Node3D          # герой
var _on_hit: Callable        # on_hit.call(damage) — урон герою
var _spawn := Vector3.ZERO
var _model: Node3D
var _anim: AnimationPlayer
var _label: Label3D
var _state := "idle"         # idle / chase / attack / hurt / dead
var _state_t := 0.0
var _cooldown := 0.0
var _struck := false         # удар этой атаки уже прошёл


func setup(m: PaxMod, target: Node3D, on_hit: Callable, at: Vector3) -> void:
	mod = m
	_target = target
	_on_hit = on_hit
	_spawn = at
	name = "Goblin"
	position = at
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.1
	shape.shape = cap
	shape.position = Vector3(0.0, 0.55, 0.0)
	add_child(shape)
	_model = mod.model(DIR + "goblin_rigged.glb")
	if _model == null:
		mod.log_warning("Pax RPG: goblin model did not load — the goblin is a box")
		_model = MeshInstance3D.new()
		(_model as MeshInstance3D).mesh = BoxMesh.new()
		(_model as MeshInstance3D).position = Vector3(0.0, 0.55, 0.0)
	add_child(_model)
	_anim = _find_anim(_model)
	if _anim != null:
		_add_clips()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 48
	_label.outline_size = 10
	_label.pixel_size = 0.0045
	_label.position = Vector3(0.0, 1.45, 0.0)
	_label.modulate = Color(0.75, 1.0, 0.55)
	add_child(_label)
	_update_label()
	_set_state("idle")


## Клипы Meshy — отдельными glb (один клип в каждом). Берём их анимацию и кладём в плеер гоблина под своим именем.
func _add_clips() -> void:
	var lib: AnimationLibrary = _anim.get_animation_library("") if _anim.has_animation_library("") else AnimationLibrary.new()
	for clip: String in CLIPS:
		var src := mod.model(DIR + CLIPS[clip])
		if src == null:
			mod.log_warning("Pax RPG: goblin clip %s did not load" % clip)
			continue
		var from := _find_anim(src)
		if from != null and from.get_animation_list().size() > 0:
			var anim: Animation = (from.get_animation(from.get_animation_list()[0]).duplicate() as Animation)
			anim.loop_mode = Animation.LOOP_LINEAR if clip in LOOPED else Animation.LOOP_NONE
			lib.add_animation(clip, anim)
		src.free()
	if not _anim.has_animation_library(""):
		_anim.add_animation_library("", lib)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


func is_alive() -> bool:
	return not dead


func _update_label() -> void:
	if _label != null:
		_label.text = "%s  %d / %d" % [mod.tr_key("pax_rpg_goblin"), ceili(hp), int(MAX_HP)]


# ---------- урон ----------

## Удар героя: отбрасывает и переводит гоблина в «получил урон».
func take_damage(amount: float, from: Vector3) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	_update_label()
	if hp <= 0.0:
		_die()
		return
	var away := global_position - from
	away.y = 0.0
	if away.length() > 0.01:
		velocity = away.normalized() * 2.5
	_set_state("hurt")


func _die() -> void:
	dead = true
	_set_state("dead")
	get_tree().create_timer(RESPAWN).timeout.connect(_respawn)


func _respawn() -> void:
	hp = MAX_HP
	dead = false
	position = _spawn
	velocity = Vector3.ZERO
	_update_label()
	_set_state("idle")


# ---------- состояния ----------

func _set_state(s: String) -> void:
	_state = s
	_state_t = 0.0
	_struck = false
	match s:
		"idle":
			_play("idle")
		"attack":
			_play("attack", true)
		"hurt", "dead":
			_play("hit", true)
			if s == "dead" and _anim != null:
				_anim.pause()


func _play(clip: String, restart := false) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	if restart or _anim.current_animation != clip:
		_anim.play(clip, 0.15)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	if position.y < -20.0:
		_respawn()
	_cooldown -= delta
	_state_t += delta
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var flat := Vector3.ZERO
	match _state:
		"idle":
			if not dead and dist < DETECT:
				_set_state("chase")
		"chase":
			if dist > LOSE:
				_set_state("idle")
			elif dist <= ATTACK_RANGE and _cooldown <= 0.0:
				_set_state("attack")
			else:
				var dir := to / maxf(dist, 0.001)
				var fast := dist > RUN_FROM
				flat = dir * (RUN_SPEED if fast else WALK_SPEED)
				_play("run" if fast else "walk")
				_face(dir, delta)
		"attack":
			_face(to / maxf(dist, 0.001), delta)
			if not _struck and _anim != null and _state_t >= _clip_len("attack") * ATTACK_HIT_AT:
				_struck = true
				if dist <= ATTACK_RANGE + 0.4 and _on_hit.is_valid():
					_on_hit.call(DAMAGE)
			if _state_t >= _clip_len("attack"):
				_cooldown = COOLDOWN
				_set_state("chase")
		"hurt":
			velocity.x = lerpf(velocity.x, 0.0, minf(1.0, delta * 6.0))
			velocity.z = lerpf(velocity.z, 0.0, minf(1.0, delta * 6.0))
			if _state_t >= HURT_TIME:
				_set_state("chase")
		"dead":
			velocity.x = 0.0
			velocity.z = 0.0
	if _state == "chase" or _state == "attack" or _state == "idle":
		velocity.x = flat.x
		velocity.z = flat.z
	elif _state == "dead":
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()


func _clip_len(clip: String) -> float:
	if _anim == null or not _anim.has_animation(clip):
		return 1.0
	return _anim.get_animation(clip).length


## Модель смотрит вперёд по +Z (как glb героя — по -Z, но у гоблина Meshy ставит вперёд +Z).
func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, want, minf(1.0, delta * 10.0))
