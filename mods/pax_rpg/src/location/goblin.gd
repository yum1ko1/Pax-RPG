extends CharacterBody3D
## Гоблин — враг-дуэлянт, бой как в Sekiro. Заметив героя, подходит на дистанцию поединка и кружит вокруг него лицом
## к нему, выжидая окно; потом короткий выпад: вспышка-предупреждение и рубящий удар. После удара — миг уязвимости и
## отход. Концентрация (posture): копится от парирований и ударов героя, переполнилась (или кончилось здоровье) —
## гоблин теряет равновесие, его можно добить (deathblow). Гибель — тело рассыпается маной.
## Атакует одновременно только один гоблин (жетон атаки). Модель и клипы — models/goblin/ (Meshy).

const DIR := "models/goblin/"
const CLIPS := {"idle": "idle.glb", "walk": "walk.glb", "run": "run.glb", "attack": "attack.glb", "hit": "hit.glb",
	"combat_idle": "combat_idle.glb", "strafe_l": "strafe_l.glb", "strafe_r": "strafe_r.glb", "back": "back.glb",
	"deflected": "deflected.glb"}
const LOOPED := ["idle", "walk", "run", "combat_idle", "strafe_l", "strafe_r", "back"]
const FALLBACK := {"combat_idle": "idle", "strafe_l": "walk", "strafe_r": "walk", "back": "walk", "deflected": "hit"}

const MAX_HP := 60.0
const MAX_POSTURE := 100.0
const DETECT := 14.0          # м, замечает героя
const LOSE := 24.0            # м, теряет
const CIRCLE_DIST := 4.0      # м, дистанция поединка — на ней кружит
const STRIKE_DIST := 2.3      # м, отсюда начинает замах (подходит крадучись, не бросается издалека)
const ATTACK_RANGE := 1.7     # м, с такой бьёт
const WALK_SPEED := 2.0
const RUN_SPEED := 4.2
const STRAFE_SPEED := 1.35
const LUNGE_SPEED := 1.6      # шаг в замахе
const STALK_SPEED := 1.4      # подкрадывается
const ATTACK_HIT_AT := 0.5    # доля клипа атаки — миг удара
const ATTACK_SPEED := 1.5
const DAMAGE := 12.0
const HURT_TIME := 0.45
const DEFLECTED_TIME := 0.9
const BROKEN_TIME := 3.2      # с без равновесия — окно добивания
const RECOVER_TIME := 0.6
const RESPAWN := 3.0
const KNOCKBACK := 5.0
const GRAVITY := 20.0
const MANA := Color(0.75, 0.45, 1.0)

static var _attacker: Node = null   # у кого жетон атаки

var mod: PaxMod
var hp := MAX_HP
var posture := 0.0
var dead := false
var _target: Node3D
var _hero_attacking: Callable  # () -> bool — герой сейчас бьёт (повод отскочить)
var _hero_blocking: Callable   # () -> bool — герой в блоке (повод подождать или обмануть)
var _on_hit: Callable          # on_hit.call(damage, self) — удар по герою (там решают: блок, парирование, урон)
var _spawn := Vector3.ZERO
var _model: Node3D
var _anim: AnimationPlayer
var _mark: MeshInstance3D       # красная метка добивания
var _state := "idle"
var _state_t := 0.0
var _struck := false
var _wait := 2.0               # с кружения до следующего выпада
var _circle_dir := 1.0         # +1 — вправо от героя, −1 — влево
var _switch_t := 2.0
var _since_hit := 99.0
var _lethal := false
var _feint := false            # этот подход — обманный: подойдёт и отскочит, не ударив


func setup(m: PaxMod, target: Node3D, on_hit: Callable, at: Vector3, hero_attacking := Callable(),
		hero_blocking := Callable()) -> void:
	mod = m
	_hero_blocking = hero_blocking
	_target = target
	_on_hit = on_hit
	_hero_attacking = hero_attacking
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
	_mark = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.1, 0.1)
	mm.no_depth_test = true
	sm.material = mm
	_mark.mesh = sm
	_mark.position = Vector3(0.0, 0.8, 0.0)
	_mark.visible = false
	add_child(_mark)
	_update_bars()
	_set_state("idle")


## Клипы Meshy — отдельными glb. Берём их анимацию и кладём в плеер гоблина под своим именем; нет файла — запасной.
func _add_clips() -> void:
	var lib: AnimationLibrary = _anim.get_animation_library("") if _anim.has_animation_library("") else AnimationLibrary.new()
	for clip: String in CLIPS:
		var src := mod.model(DIR + CLIPS[clip])
		if src == null:
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


func can_deathblow() -> bool:
	return _state == "broken"


## Полосы здоровья и концентрации — в HUD справа (location.gd читает hp / posture), над головой ничего.
func _update_bars() -> void:
	pass


## В бою с героем (для HUD): заметил его и не мёртв.
func in_combat() -> bool:
	return not dead and _state != "idle"


# ---------- что с ним делают ----------

## Удар героя: кровь, отлёт, атака сорвана; растёт концентрация. Без равновесия — не принимает обычных ударов.
func take_damage(amount: float, from: Vector3) -> void:
	if dead or _state == "broken":
		return
	hp = maxf(0.0, hp - amount)
	posture = minf(MAX_POSTURE, posture + amount * 0.7)
	_since_hit = 0.0
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	_burst(global_position + Vector3(0.0, 0.75, 0.0) - away * 0.2, away, Color(0.55, 0.02, 0.03), 36, 3.5, 9.0, 0.5,
		0.06)
	if hp <= 0.0 or posture >= MAX_POSTURE:
		_lethal = hp <= 0.0
		_set_state("broken")
	else:
		velocity = away * KNOCKBACK + Vector3(0.0, 2.0, 0.0)
		_set_state("hurt")
	_update_bars()


## Героя парировали удар: сильно сбивает концентрацию, гоблина отбрасывает в сторону.
func deflected(from: Vector3) -> void:
	if dead:
		return
	posture = minf(MAX_POSTURE, posture + 34.0)
	_since_hit = 0.0
	var away := global_position - from
	away.y = 0.0
	velocity = (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * 3.0
	_set_state("broken" if posture >= MAX_POSTURE else "deflected")
	_update_bars()


## Удар заблокирован: немного концентрации.
func blocked() -> void:
	posture = minf(MAX_POSTURE, posture + 8.0)
	_update_bars()


## Добивание: гибель.
func deathblow() -> void:
	if not dead:
		_die()


func _die() -> void:
	dead = true
	_release_token()
	_mark.visible = false
	_set_state("dead")
	_burst(global_position + Vector3(0.0, 0.6, 0.0), Vector3.UP, MANA, 90, 1.5, -1.5, 1.4, 0.07, true)
	if _model != null:
		var t := create_tween()
		t.tween_property(_model, "scale", Vector3(1.15, 0.05, 1.15), 0.6).set_ease(Tween.EASE_IN)
		t.tween_callback(func() -> void: _model.visible = false)
	get_tree().create_timer(RESPAWN).timeout.connect(_respawn)


func _respawn() -> void:
	hp = MAX_HP
	posture = 0.0
	dead = false
	_lethal = false
	if _model != null:
		_model.scale = Vector3.ONE
		_model.visible = true
	position = _spawn
	velocity = Vector3.ZERO
	_update_bars()
	_set_state("idle")


## Искры / капли: amount частиц из at в сторону dir; gravity < 0 — летят вверх; glow — светятся (мана).
func _burst(at: Vector3, dir: Vector3, color: Color, amount: int, speed: float, gravity: float, life: float,
		size: float, glow := false) -> void:
	var p := CPUParticles3D.new()
	p.top_level = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = 55.0 if not glow else 80.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.damping_min = 0.5
	p.damping_max = 2.0
	if glow:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var q := SphereMesh.new()
	q.radius = size
	q.height = size * 2.0
	q.radial_segments = 6
	q.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
	q.material = m
	p.mesh = q
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## Предупреждение перед выпадом: вспышка над оружием (как красный иероглиф опасности в Sekiro — здесь мана).
func _telegraph() -> void:
	_burst(global_position + Vector3(0.0, 1.25, 0.0), Vector3.UP, Color(1.0, 0.35, 0.2), 14, 0.6, 0.0, 0.45, 0.05,
		true)


# ---------- состояния ----------

func _take_token() -> bool:
	if _attacker == null or not is_instance_valid(_attacker) or _attacker == self:
		_attacker = self
		return true
	return false


func _release_token() -> void:
	if _attacker == self:
		_attacker = null


func _set_state(s: String) -> void:
	_state = s
	_state_t = 0.0
	_struck = false
	if _anim != null:
		_anim.speed_scale = 1.0
	if s in ["hurt", "deflected", "broken", "dead", "recover", "circle", "idle", "evade"]:
		if s != "recover":
			_release_token()
	_mark.visible = s == "broken"
	match s:
		"idle":
			_play("idle")
		"circle", "recover":
			_play("combat_idle")
			if s == "circle":
				_wait = randf_range(1.2, 3.2)
		"windup":
			_telegraph()
		"attack":
			_play("attack", true)
			if _anim != null:
				_anim.speed_scale = ATTACK_SPEED
		"hurt":
			_play("hit", true)
		"deflected":
			_play("deflected", true)
		"broken", "dead":
			_play("hit", true)


func _clip(name_: String) -> String:
	if _anim == null:
		return ""
	if _anim.has_animation(name_):
		return name_
	return str(FALLBACK.get(name_, "idle"))


func _play(clip: String, restart := false) -> void:
	var c := _clip(clip)
	if c == "" or not _anim.has_animation(c):
		return
	if restart or _anim.current_animation != c:
		_anim.play(c, 0.2)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	if position.y < -20.0:
		_respawn()
	_state_t += delta
	_since_hit += delta
	if _state not in ["attack", "windup", "broken", "dead"] and _since_hit > 1.5 and posture > 0.0:
		posture = maxf(0.0, posture - delta * (14.0 if hp > MAX_HP * 0.5 else 6.0))
		_update_bars()
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var side := Vector3(-dir.z, 0.0, dir.x)          # вправо от гоблина, если он смотрит на героя
	var flat := Vector3.ZERO
	match _state:
		"idle":
			if not dead and dist < DETECT:
				_set_state("approach")
		"approach":
			if dist > LOSE:
				_set_state("idle")
			elif dist <= CIRCLE_DIST + 0.8:
				_set_state("circle")
			else:
				var fast := dist > 9.0                   # издалека бежит, ближе — идёт, не врываясь
				flat = dir * (RUN_SPEED if fast else WALK_SPEED)
				_play("run" if fast else "walk")
				_face(dir, delta)
		"circle":
			_face(dir, delta)
			var hero_swing := _hero_attacking.is_valid() and bool(_hero_attacking.call())
			if dist > LOSE:
				_set_state("idle")
			elif dist > CIRCLE_DIST + 3.0:
				_set_state("approach")
			elif hero_swing and dist < 3.4:
				_set_state("evade")                      # герой замахнулся рядом — уйти вбок-назад
			else:
				_switch_t -= delta
				if _switch_t <= 0.0:
					_switch_t = randf_range(1.2, 2.8)
					_circle_dir = -_circle_dir
				var radial := 0.0
				if dist < CIRCLE_DIST - 0.7:
					radial = -1.0
				elif dist > CIRCLE_DIST + 0.7:
					radial = 1.0
				flat = side * _circle_dir * STRAFE_SPEED + dir * radial * WALK_SPEED * 0.5
				if radial < 0.0:
					_play("back")
				elif radial > 0.0:
					_play("walk")
				else:
					_play("strafe_r" if _circle_dir > 0.0 else "strafe_l")
				_wait -= delta
				if _wait <= 0.0:
					if _hero_blocking.is_valid() and bool(_hero_blocking.call()) and randf() < 0.4:
						_wait = randf_range(0.8, 1.6)    # герой в блоке — подождать, пусть раскроется
					elif _take_token():
						_feint = randf() < 0.25
						_set_state("stalk")
					else:
						_wait = randf_range(0.5, 1.2)
		"stalk":
			_face(dir, delta)
			flat = dir * STALK_SPEED
			_play("walk")
			if _hero_attacking.is_valid() and bool(_hero_attacking.call()) and dist < 3.0:
				_set_state("evade")
			elif dist <= STRIKE_DIST + (0.4 if _feint else 0.0):
				if _feint:
					velocity = -dir * 4.0 + side * _circle_dir * 1.5   # финт: дёрнулся вперёд — и отскок
					_set_state("evade")
				else:
					_set_state("windup")
			elif _state_t > 3.0:
				_set_state("circle")
		"evade":
			_face(dir, delta)
			flat = -dir * WALK_SPEED * 1.2 + side * _circle_dir * STRAFE_SPEED
			_play("back")
			if _state_t > 0.7:
				_set_state("circle")
		"windup":
			_face(dir, delta)
			flat = dir * LUNGE_SPEED
			_play("combat_idle")
			if _state_t >= _f_windup():
				_set_state("attack")
		"attack":
			_face(dir, delta * 0.4)
			var hit_at := _clip_len("attack") / ATTACK_SPEED * ATTACK_HIT_AT
			if _state_t < hit_at * 0.7 and dist > 1.2:
				flat = dir * 2.0                         # шаг с ударом
			if not _struck and _state_t >= hit_at:
				_struck = true
				if dist <= ATTACK_RANGE + 0.5 and _on_hit.is_valid():
					_on_hit.call(DAMAGE, self)
			if _state == "attack" and _state_t >= _clip_len("attack") / ATTACK_SPEED:
				_set_state("recover")
		"recover":
			_face(dir, delta)
			if _state_t > RECOVER_TIME:
				_release_token()
				flat = -dir * WALK_SPEED
				_play("back")
				if _state_t > RECOVER_TIME + 0.8:
					_set_state("circle")
		"hurt":
			_damp(delta)
			if _state_t >= HURT_TIME:
				_set_state("evade")                      # получил — отступить, а не лезть снова
		"deflected":
			_damp(delta)
			if _state_t >= DEFLECTED_TIME:
				_set_state("circle")
		"broken":
			_damp(delta)
			if _anim != null and _state_t > 0.5:
				_anim.pause()                            # на коленях, ждёт добивания
			if _state_t >= BROKEN_TIME:
				if _lethal:
					_die()                               # без добивания — всё равно пал
				else:
					posture = MAX_POSTURE * 0.5
					_update_bars()
					_set_state("circle")
		"dead":
			velocity.x = 0.0
			velocity.z = 0.0
	if _state in ["approach", "circle", "stalk", "evade", "windup", "attack", "recover", "idle"]:
		velocity.x = lerpf(velocity.x, flat.x, minf(1.0, delta * 10.0))
		velocity.z = lerpf(velocity.z, flat.z, minf(1.0, delta * 10.0))
	move_and_slide()


## Замах — короткая пауза с предупреждением (у слабых врагов короче).
func _f_windup() -> float:
	return 0.45


func _damp(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, minf(1.0, delta * 6.0))
	velocity.z = lerpf(velocity.z, 0.0, minf(1.0, delta * 6.0))


func _clip_len(clip: String) -> float:
	var c := _clip(clip)
	if c == "" or not _anim.has_animation(c):
		return 1.0
	return _anim.get_animation(c).length


## Модель смотрит вперёд по +Z (у гоблина Meshy ставит вперёд +Z).
func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	var want := atan2(dir.x, dir.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, want, minf(1.0, delta * 10.0))
