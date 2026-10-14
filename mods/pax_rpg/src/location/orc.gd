extends "res://mods/pax_rpg/src/location/goblin.gd"
## Гхаррок, орк-чемпион арены — мини-босс в духе тяжёлых боссов Sekiro. Тяжёлый и медленный, но коварный:
##  • удары с долгим замахом и задержкой (замах замирает — и обрушивается), иногда наоборот резкий быстрый выпад;
##  • держит блок и парирует: если ударить в первые доли его блока — отбивает, у героя сбита концентрация;
##  • «Вихрь» (как Джаггернаут): крутится с топором и медленно идёт за героем — не блокируется, только уйти кувырком;
##  • «Таран»: рёв, разгон и удар плечом — не блокируется, сбивает с ног; промахнулся — спотыкается, окно для удара.
## Опасные приёмы (вихрь, таран) предупреждает красный знак 危 над головой — как в Sekiro.
## Бой и интерфейс — как у гоблина (goblin.gd): здоровье, концентрация, добивание; меняются клипы, ИИ и удары.
## Темп каждого удара — TEMPO: [доля клипа от, до, скорость] — где замах тянется, где удар ускорен; HOLD — замирание.

const ORC_MODEL := "models/orc/orc_champion.glb"
const LOOPS := ["Idle", "BlockIdle", "WalkF", "WalkB", "WalkL", "WalkR", "TownWalk", "ChargeRun"]

# удары: клип → {hits: доли клипа, где бьёт (замерено по пику скорости кисти/стопы — clip_reach_blender.py); dmg; kind: "" обычный, heavy — тяжёлый (блок сильно сбивает
# концентрацию); reach — м; tempo; hold: [доля, с] — замереть в замахе; step — шаг вперёд м/с до первого удара}
const ATTACKS := {
	"Backhand": {"hits": [0.34], "dmg": 30.0, "kind": "heavy", "reach": 3.0, "step": 1.2,
		"tempo": [[0.0, 0.2, 0.55], [0.2, 0.4, 1.5], [0.4, 1.0, 1.0]], "hold": [0.18, 0.45]},
	"Combo1": {"hits": [0.18, 0.45, 0.64], "dmg": 22.0, "kind": "", "reach": 2.8, "step": 1.0,
		"tempo": [[0.0, 0.12, 0.8], [0.12, 0.5, 1.2], [0.5, 0.58, 0.45], [0.58, 1.0, 1.25]], "hold": [0.55, 0.5]},
	"Combo3": {"hits": [0.37, 0.64], "dmg": 26.0, "kind": "heavy", "reach": 2.8, "step": 1.4,
		"tempo": [[0.0, 0.26, 0.6], [0.26, 0.7, 1.3], [0.7, 1.0, 1.0]], "hold": []},
	"Kick": {"hits": [0.32], "dmg": 14.0, "kind": "", "reach": 2.2, "step": 0.0,
		"tempo": [[0.0, 0.28, 1.5], [0.28, 1.0, 1.1]], "hold": []},
	"JumpAttack": {"hits": [0.46], "dmg": 38.0, "kind": "heavy", "reach": 3.2, "step": 0.0, "leap": 4.8,
		"tempo": [[0.0, 0.3, 0.8], [0.3, 0.44, 1.0], [0.44, 1.0, 1.0]], "hold": [0.34, 0.35]},
}
const MOVES_NEAR := ["Combo1", "Combo3", "Backhand", "Kick"]
const SPIN_TIME := 3.4          # с вихря
const SPIN_SPEED := 1.6         # м/с — идёт за героем медленно: кувырком уйти можно
const SPIN_TICK := 0.45         # с между ударами вихря
const SPIN_RADIUS := 2.7
const SPIN_DMG := 16.0
const CHARGE_SPEED := 8.5
const CHARGE_TURN := 1.2        # рад/с — почти не поворачивает: уйти вбок
const CHARGE_TIME := 2.2
const CHARGE_DMG := 34.0
const PARRY_WINDOW := 0.28      # с от начала блока: удар героя отбит
const DIZZY_TIME := 1.6         # после вихря и промаха тараном — открыт

var _atk := ""
var _hits_done := 0
var _held := false
var _hold_t := 0.0
var _spin_tick := 0.0
var _charge_dir := Vector3.ZERO
var _since_special := 4.0
var _danger: Label3D
var _guard_hits := 0


func setup(m: PaxMod, target: Node3D, on_hit: Callable, at: Vector3, hero_attacking := Callable(),
		hero_blocking := Callable()) -> void:
	mod = m
	_hero_blocking = hero_blocking
	_target = target
	_on_hit = on_hit
	_hero_attacking = hero_attacking
	_spawn = at
	name = "OrcChampion"
	position = at
	max_hp = 420.0
	max_posture = 240.0
	hp = max_hp
	display_key = "pax_rpg_orc"
	boss = true
	title_key = "pax_rpg_orc_title"
	_snd_swing = _sound("sounds/swing_%d.wav", 1, 6, 0.62, 2.0)       # тяжёлый топор — ниже и громче
	_snd_impact = _sound("sounds/impact_%d.wav", 1, 3, 0.7, 4.0)
	_snd_clang = _sound("sounds/katana_hit_%d.ogg", 0, 3, 0.8, 0.0)
	_snd_hurt = _sound("sounds/impact_%d.wav", 1, 3, 0.55, 0.0)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = 2.3
	shape.shape = cap
	shape.position = Vector3(0.0, 1.15, 0.0)
	add_child(shape)
	voiced = false                                       # голос гоблина орку не подходит
	_model = Assets.model(mod, ORC_MODEL)
	if _model == null:
		mod.log_warning("Pax RPG: orc model did not load")
		_model = MeshInstance3D.new()
		(_model as MeshInstance3D).mesh = CapsuleMesh.new()
	add_child(_model)
	Assets.track(ORC_MODEL, _model)
	_model_y = _model.position.y
	_anim = _find_anim(_model)
	if _anim != null:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		for n: String in _anim.get_animation_list():
			var a := _anim.get_animation(n)
			a.loop_mode = Animation.LOOP_LINEAR if n in LOOPS else Animation.LOOP_NONE
	_mark = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.1, 0.1)
	mm.no_depth_test = true
	sm.material = mm
	_mark.mesh = sm
	_mark.position = Vector3(0.0, 1.5, 0.0)
	_mark.visible = false
	add_child(_mark)
	_danger = Label3D.new()                              # 危 — опасный приём: не блокировать, уходить
	_danger.text = "危"
	_danger.font_size = 160
	_danger.modulate = Color(1.0, 0.15, 0.1)
	_danger.outline_size = 24
	_danger.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_danger.no_depth_test = true
	_danger.position = Vector3(0.0, 3.0, 0.0)
	_danger.visible = false
	add_child(_danger)
	_set_state("idle")


# ---------- клипы гоблина → клипы орка ----------

func _clip(name_: String) -> String:
	if _anim == null:
		return ""
	var map := {"idle": "Idle", "walk": "WalkF", "run": "WalkF", "combat_idle": "Idle", "strafe_l": "WalkL",
		"strafe_r": "WalkR", "back": "WalkB", "hit": "ReactL", "deflected": "ReactR", "knockdown": "ReactR",
		"getup": "Idle", "attack": "Backhand"}
	var c := str(map.get(name_, name_))
	return c if _anim.has_animation(c) else "Idle"


func _set_state(s: String) -> void:
	super._set_state(s)
	_danger.visible = s in ["spin", "charge_wind", "charge"]
	match s:
		"broken":
			_play("ReactR", true)
		"dead":
			_play("Death", true)
		"guard":
			_play("BlockIdle", true, 0.12)
		"taunt":
			_play("Taunt", true)
		"spin":
			_play("Spin360High", true)
			_spin_tick = 0.5
		"charge_wind":
			_play("ChargeStart", true)
		"charge":
			_play("ChargeRun", true)
		"charge_end", "dizzy":
			_play("ChargeHit", true)


## Звуки орка: замах (свист), попадание (глухой удар), блок (сталь), получил урон (удар по телу).
var _snd_swing: AudioStreamPlayer3D
var _snd_impact: AudioStreamPlayer3D
var _snd_clang: AudioStreamPlayer3D
var _snd_hurt: AudioStreamPlayer3D


func _sound(pattern: String, first: int, n: int, pitch: float, db: float) -> AudioStreamPlayer3D:
	var rnd := AudioStreamRandomizer.new()
	rnd.random_pitch = 1.08
	for i: int in n:
		var st: AudioStream = mod.sound(pattern % (first + i))
		if st != null:
			rnd.add_stream(-1, st)
	var p := AudioStreamPlayer3D.new()
	p.stream = rnd
	p.pitch_scale = pitch
	p.volume_db = db
	p.unit_size = 6.0
	p.bus = "PaxRpgSfx"
	p.position = Vector3(0, 1.4, 0)
	add_child(p)
	return p


func _snd(p: AudioStreamPlayer3D) -> void:
	if p != null and p.stream != null and (p.stream as AudioStreamRandomizer).streams_count > 0:
		p.play()


## Удар героя: в первые доли блока — отбит (концентрация героя), в блоке — почти без урона; вихрь не сбить.
func take_damage(amount: float, from: Vector3, knock := false) -> void:
	if dead or _state == "broken":
		return
	if _state == "guard":
		var away := (from - global_position)
		away.y = 0.0
		var at := global_position + Vector3(0.0, 1.5, 0.0) + away.normalized() * 0.6
		_snd(_snd_clang)
		if _state_t <= PARRY_WINDOW:
			_burst(at, away, Color(1.0, 0.8, 0.35), 40, 5.0, 0.0, 0.3, 0.04, true)
			if _on_hit.is_valid():
				_on_hit.call(0.0, self, "parried")             # отбил: героя качнуло, его концентрация
			_atk_after_guard()
		else:
			_burst(at, away, Color(1.0, 0.6, 0.25), 14, 3.0, 0.0, 0.25, 0.03, true)
			posture = minf(max_posture, posture + amount * 0.25)
			hp = maxf(1.0, hp - amount * 0.1)
			_guard_hits += 1
			if _guard_hits >= 3:
				_atk_after_guard()                          # надоело стоять в блоке — контратака
		return
	_snd(_snd_hurt)
	if _state in ["spin", "charge", "charge_wind"] or _atk != "":
		hp = maxf(0.0, hp - amount)                         # в приёме — урон без срыва (гиперброня)
		posture = minf(max_posture, posture + amount * 0.4)
		_since_hit = 0.0
		if hp <= 0.0:
			_lethal = true
			_atk = ""
			_set_state("broken")
		return
	super.take_damage(amount * 0.8, from, false)            # тяжёлый — не отлетает


func _atk_after_guard() -> void:
	_guard_hits = 0
	_start_attack("Kick" if randf() < 0.5 else "Backhand")


func _start_attack(clip: String) -> void:
	_atk = clip
	_hits_done = 0
	_held = false
	_hold_t = 0.0
	_set_state("attack")
	_play(clip, true, 0.15)


# ---------- ИИ ----------

func _phys(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	_state_t += delta
	_since_hit += delta
	_since_special += delta
	if _state not in ["attack", "broken", "dead", "spin", "charge"] and _since_hit > 2.0 and posture > 0.0:
		posture = maxf(0.0, posture - delta * (10.0 if hp > max_hp * 0.5 else 4.0))
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var flat := Vector3.ZERO
	var swinging := _hero_attacking.is_valid() and bool(_hero_attacking.call())
	var new_swing := swinging and not _swing_seen
	match _state:
		"idle":
			_play("Idle")
			if not dead and dist < DETECT:
				_set_state("taunt")
		"taunt":
			_face(dir, delta * 0.5)
			if _state_t >= _clip_len("Taunt") * 0.9:
				_set_state("approach")
		"approach":
			_face(dir, delta * 0.6)
			flat = dir * 1.6
			_play("WalkF")
			if dist <= 4.2:
				_set_state("circle")
		"circle":
			_face(dir, delta * 0.6)
			if new_swing and dist < 3.4 and randf() < 0.55:
				_guard_hits = 0
				_set_state("guard")                          # видит замах — встаёт в блок (и может отбить)
			else:
				_switch_t -= delta
				if _switch_t <= 0.0:
					_switch_t = randf_range(1.6, 3.2)
					_circle_dir = -_circle_dir
				var radial := 0.0
				if dist > 3.6:
					radial = 1.0
				elif dist < 2.2:
					radial = -1.0
				flat = side * _circle_dir * 0.9 + dir * radial * 1.2
				_play("WalkF" if radial > 0.0 else ("WalkB" if radial < 0.0 else ("WalkR" if _circle_dir > 0.0 else "WalkL")))
				_wait -= delta
				if _wait <= 0.0:
					_choose(dist)
		"guard":
			_face(dir, delta)
			if _state_t > 1.1 and not swinging:
				_set_state("circle")
				_wait = randf_range(0.2, 0.6)
		"attack":
			flat = _attack_tick(delta, dist, dir)
		"spin":
			flat = _spin_tick_fn(delta, dist, dir)
		"charge_wind":
			_face(dir, delta * 1.5)
			if _state_t >= _clip_len("ChargeStart") * 0.85:
				_charge_dir = dir
				_set_state("charge")
		"charge":
			flat = _charge_tick(delta, dist, dir)
		"charge_end":
			_damp(delta)
			if _state_t >= _clip_len("ChargeHit") * 0.9:
				_set_state("circle")
				_wait = randf_range(0.8, 1.4)
		"dizzy":
			_damp(delta)
			if _anim != null:
				_anim.speed_scale = 0.5
			if _state_t >= DIZZY_TIME:
				_set_state("circle")
				_wait = randf_range(0.4, 0.9)
		"hurt", "deflected":
			_damp(delta)
			if _state_t >= 0.7:
				_set_state("circle")
				_wait = randf_range(0.3, 0.8)
		"broken":
			_damp(delta)
			if _anim != null and _state_t > 0.6:
				_anim.pause()
			if _state_t >= BROKEN_TIME + 0.8:
				if _lethal:
					_die()
				else:
					posture = max_posture * 0.45
					_set_state("circle")
		"dead":
			velocity.x = 0.0
			velocity.z = 0.0
	if new_swing:
		_swing_seen = true
	elif not swinging:
		_swing_seen = false
	if _state in ["approach", "circle", "attack", "spin", "charge", "idle", "taunt", "guard", "charge_wind"]:
		velocity.x = lerpf(velocity.x, flat.x, minf(1.0, delta * 8.0))
		velocity.z = lerpf(velocity.z, flat.z, minf(1.0, delta * 8.0))
	move_and_slide()


## Что делать: вблизи — удары и пинок, на средней — прыжок или вихрь, издалека — таран.
func _choose(dist: float) -> void:
	var low_hp := hp < max_hp * 0.5                       # вторая фаза: чаще особые приёмы
	if _since_special > (7.0 if low_hp else 10.0) and randf() < 0.6:
		_since_special = 0.0
		if dist > 5.0 or randf() < 0.5:
			_set_state("charge_wind")
		else:
			_set_state("spin")
		return
	if dist > 4.5:
		_start_attack("JumpAttack")
	else:
		_start_attack(MOVES_NEAR[randi() % MOVES_NEAR.size()])
	_wait = randf_range(1.0, 2.2) if not low_hp else randf_range(0.5, 1.4)


## Удар: темп по TEMPO, замирание HOLD (обманная задержка), удары в доли HITS, прыжок — LEAP м.
func _attack_tick(delta: float, dist: float, dir: Vector3) -> Vector3:
	var a: Dictionary = ATTACKS.get(_atk, {})
	var length := _clip_len(_atk)
	var frac := _anim.current_animation_position / maxf(length, 0.01) if _anim != null else 1.0
	var flat := Vector3.ZERO
	var hold: Array = a.get("hold", [])
	var hits: Array = a.get("hits", [])
	if hold.size() == 2 and not _held and frac >= float(hold[0]):
		_held = true
		_hold_t = float(hold[1]) * randf_range(0.6, 1.6)  # задержка разная — не выучить ритм
	var sp := 1.0
	for t: Variant in a.get("tempo", []):
		var tt: Array = t
		if frac >= float(tt[0]) and frac < float(tt[1]):
			sp = float(tt[2])
	if _hold_t > 0.0:
		_hold_t -= delta
		sp = 0.03                                          # застыл в замахе
		_face(dir, delta * 1.2)
	elif _hits_done < hits.size() and frac < float(hits[_hits_done]):
		_face(dir, delta * 0.8)                            # доворачивает за героем до удара
	if _anim != null:
		_anim.speed_scale = sp
	if a.has("leap") and _hits_done == 0:
		var t0 := 0.3
		var t1 := float(hits[0])
		if frac > t0 and frac < t1:
			var dur := (t1 - t0) * length / maxf(sp, 0.1)
			flat = dir * minf(float(a.leap), dist + 0.5) / maxf(dur, 0.2)
	elif _hits_done == 0 and frac < (float(hits[0]) if hits.size() > 0 else 0.0) and dist > 1.6:
		flat = dir * float(a.get("step", 0.0))
	if _hits_done < hits.size() and frac >= float(hits[_hits_done]):
		_hits_done += 1
		_snd(_snd_swing)
		if dist <= float(a.get("reach", 2.8)) and _on_hit.is_valid():
			_snd(_snd_impact)
			_on_hit.call(float(a.get("dmg", 20.0)), self, str(a.get("kind", "")))
	if frac >= 0.98 or (_anim != null and not _anim.is_playing()):
		_atk = ""
		_set_state("circle")
		_wait = randf_range(0.9, 1.8)
	return flat


## Вихрь: середина клипа 360 крутится по кругу, орк медленно идёт за героем, удары по кругу.
func _spin_tick_fn(delta: float, dist: float, dir: Vector3) -> Vector3:
	if _anim != null:
		var length := _clip_len("Spin360High")
		var p := _anim.current_animation_position
		if _state_t < SPIN_TIME and p >= length * 0.7:
			_anim.seek(length * 0.3, true)                  # крутится дальше
		_anim.speed_scale = 1.15
		if _state_t >= SPIN_TIME and (p >= length * 0.97 or not _anim.is_playing()):
			_set_state("dizzy")                             # закружился — окно для героя
			return Vector3.ZERO
	_spin_tick -= delta
	if _spin_tick <= 0.0 and _state_t < SPIN_TIME:
		_spin_tick = SPIN_TICK
		_snd(_snd_swing)
		if dist <= SPIN_RADIUS and _on_hit.is_valid():
			_on_hit.call(SPIN_DMG, self, "perilous")
	return dir * SPIN_SPEED if _state_t < SPIN_TIME else Vector3.ZERO


## Таран: бежит почти по прямой; задел — сбивает с ног; промахнулся или время вышло — спотыкается.
func _charge_tick(delta: float, dist: float, dir: Vector3) -> Vector3:
	var want := atan2(dir.x, dir.z)
	var cur := atan2(_charge_dir.x, _charge_dir.z)
	var nxt := cur + clampf(wrapf(want - cur, -PI, PI), -CHARGE_TURN * delta, CHARGE_TURN * delta)
	_charge_dir = Vector3(sin(nxt), 0.0, cos(nxt))
	_face(_charge_dir, delta * 3.0)
	if dist < 1.7 and _charge_dir.dot(dir) > 0.3:
		_snd(_snd_impact)
		if _on_hit.is_valid():
			_on_hit.call(CHARGE_DMG, self, "charge")
		_set_state("charge_end")
		return _charge_dir * 2.0
	if _state_t >= CHARGE_TIME or (get_slide_collision_count() > 0 and _state_t > 0.4):
		_set_state("dizzy")
		return Vector3.ZERO
	return _charge_dir * CHARGE_SPEED


## Модель орка смотрит вперёд по +Z (Meshy).
func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 6.0))


func _respawn() -> void:
	super._respawn()
	_atk = ""
	_since_special = 4.0
