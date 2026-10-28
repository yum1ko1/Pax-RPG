extends "res://mods/pax_rpg/src/location/goblin.gd"

signal slammed(at: Vector3)          # прыжок с ударом приземлился — location.gd: мини-землетрясение
## Гхаррок, орк-чемпион арены — мини-босс в духе тяжёлых боссов Sekiro. Тяжёлый и медленный, но коварный:
##  • удары с долгим замахом и задержкой (замах замирает — и обрушивается), иногда наоборот резкий быстрый выпад;
##  • держит блок и парирует: если ударить в первые доли его блока — отбивает, у героя сбита концентрация;
##  • «Вихрь» (как Джаггернаут): крутится с топором и медленно идёт за героем — не блокируется, только уйти кувырком;
##  • «Таран»: рёв, разгон и удар плечом — не блокируется, сбивает с ног; промахнулся — спотыкается, окно для удара.
## Опасные приёмы (вихрь, таран) предупреждает красный знак 危 над головой — как в Sekiro.
## Бой и интерфейс — как у гоблина (goblin.gd): здоровье, концентрация (выдержка, от 100 к 0), Кровожадная атака;
## меняются клипы, ИИ и удары. Концентрация босса: пропущенный удар героя стоит мало (hit_conc), свои приёмы — много,
## парирование его удара — 0, но в сериях (Combo1, Combo3) в 0 уводит только последний удар, прежние — −CHAIN_PARRY.
## Кровожадная атака снимает треть здоровья: три слома — три фазы (phase), с каждой он быстрее и злее.
## Темп каждого удара — TEMPO: [доля клипа от, до, скорость] — где замах тянется, где удар ускорен; HOLD — замирание.

const ORC_MODEL := "models/orc/orc_champion.glb"
const LOOPS := ["Idle", "BlockIdle", "WalkF", "WalkB", "WalkL", "WalkR", "TownWalk", "ChargeRun"]

# удары: клип → {hits: доли клипа, где бьёт (замерено по пику скорости кисти/стопы — clip_reach_blender.py); dmg; kind: "" обычный, heavy — тяжёлый (блок сильно сбивает
# концентрацию); reach — м; tempo; hold: [доля, с] — замереть в замахе; step — шаг вперёд м/с до первого удара}
const ATTACKS := {
	"Backhand": {"hits": [0.34], "dmg": 30.0, "kind": "heavy", "reach": 3.0, "step": 1.2,
		"tempo": [[0.0, 0.2, 0.55], [0.2, 0.4, 1.5], [0.4, 1.0, 1.0]], "hold": [0.18, 0.45]},
	"Combo1": {"hits": [0.18, 0.43, 0.62], "dmg": 22.0, "kind": "", "reach": 2.8, "step": 1.0,
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
const SKID_DECEL := 11.0      # м/с²: торможение после промаха тараном
const CHARGE_DMG := 34.0
const PARRY_WINDOW := 0.28      # с от начала блока: удар героя отбит
const DIZZY_TIME := 1.6         # после вихря и промаха тараном — открыт
const CHAIN_PARRY := 25.0       # парирован не последний удар серии — столько концентрации, а не всю
const COST_ATTACK := 8.0        # концентрация на свой удар (тяжёлый — COST_HEAVY, вихрь и таран — COST_SPECIAL)
const COST_HEAVY := 12.0
const COST_SPECIAL := 15.0
const ORC_REGEN := 9.0          # в секунду на отдыхе (дальше 5 м — ×1.5, раненый — медленнее)

var _atk := ""
var _hits_done := 0
var _slam_done := false
var _roar_taunt := false             # насмешка после промаха тараном — рёв, а не смех
var _charge_min := INF              # м: ближе всего к герою за таран (отошёл дальше — промах)
var _skid_v := 0.0                   # м/с: скорость торможения после промаха
var _whoosh_done := 0                # сколько свистов замаха уже прозвучало (до удара, не в миг урона)
var _skel: Skeleton3D
const AXE := 0.95                    # м: от кисти до лезвия топора
const CONTACT := 1.1                 # м: от кисти до тела героя — топор (~1 м) и плечо удара; ближе — попал
const WINDOW := [0.06, 0.12]         # доли клипа до и после замеренного удара: в этом окне топор может задеть
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
	max_hp = 1100.0                                  # босс арены: не падает от пары серий
	conc_max = 100.0
	conc = conc_max
	hit_conc = 0.45                                  # тяжёлый: удар героя выдержку почти не сбивает
	_guard_chance = 0.15                             # сам блок ставит, видя замах (ИИ); случайный — редко
	hp = max_hp
	display_key = "pax_rpg_orc"
	boss = true
	flinch_pitch = false                             # наклон корпуса вперёд/назад ведёт сам (торможение)
	mass = 150.0                                     # кг с топором и бронёй: удары его почти не сдвигают
	title_key = "pax_rpg_orc_title"
	_snd_swing = _sound("sounds/foe_swing_%d.mp3", 1, 1, 0.75, 8.0)      # тяжёлый топор — тот же свист, ниже       # тяжёлый топор — ниже и громче
	_snd_impact = _sound("sounds/impact_%d.wav", 1, 3, 0.7, 8.0)
	_snd_clang = _sound("sounds/katana_hit_%d.ogg", 0, 3, 0.8, 0.0)
	_snd_hurt = _sound("sounds/orc_hurt_%d.mp3", 1, 1, 1.0, 4.0)        # попадание по орку (меньше половины здоровья)
	_snd_hurt_hi = _sound("sounds/orc_hurt_hi_%d.mp3", 1, 1, 1.0, 4.0)  # попадание, пока здоровья больше половины
	_snd_cheer = _sound("sounds/orc_cheer_%d.mp3", 1, 1, 1.0, -2.0)      # радость: герой пал
	_snd_laugh = _sound("sounds/orc_laugh_%d.mp3", 1, 1, 1.0, -3.0)      # насмешка, удачный удар
	_snd_idle = _sound("sounds/orc_idle_%d.mp3", 1, 1, 1.0, -6.0)        # рычание и сопение между ударами
	_snd_grunt = _sound("sounds/orc_roar_%d.mp3", 1, 1, 1.0, -3.0)       # рёв перед ударом и в насмешке
	_snd_heavy = _sound("sounds/impact_%d.wav", 1, 3, 0.45, 7.0)     # тяжёлый удар — ниже и громче
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
		"getup": "GetUp", "attack": "Backhand", "stagger": "Stagger", "parry": "Parry", "block": "BlockIdle"}
	var c := str(map.get(name_, name_))
	return c if _anim.has_animation(c) else "Idle"


func _set_state(s: String) -> void:
	super._set_state(s)
	if _model != null and s != "skid":
		_model.rotation.x = 0.0                          # торможение прервали (удар и т. п.) — выпрямился
	_danger.visible = s in ["spin", "charge_wind", "charge"]
	match s:
		"broken":
			_play("Stagger", true, 0.1)                   # шатается и падает на колено (окно Кровожадной атаки)
		"dead":
			_play("Death", true)
			var ds: AudioStream = mod.sound("sounds/orc_death.mp3")    # предсмертный рёв
			if ds != null:
				var dp := AudioStreamPlayer3D.new()
				dp.stream = ds
				dp.bus = "PaxRpgSfx"
				dp.volume_db = 6.0
				dp.unit_size = 14.0
				dp.position = Vector3(0, 1.6, 0)
				add_child(dp)
				dp.play()
		"guard":
			_play("BlockIdle", true, 0.12)
		"parry":
			_play("Parry", true, 0.08)
			_snd(_snd_clang)
		"taunt":
			_play("Taunt", true)
			_snd(_snd_grunt if _roar_taunt else _snd_laugh)
			_roar_taunt = false
		"skid":
			_play("ChargeHit", true, 0.1)                 # не бег: упор ногами, корпус назад
		"spin":
			_play("Spin360High", true)
			_spin_tick = 0.5
		"charge_wind":
			_play("ChargeStart", true)
		"charge":
			_play("ChargeRun", true)
		"charge_end", "dizzy":
			_play("ChargeHit", true)


## Кат-сцена: удар — ReactL, отброс — ReactR, падение — Fall (навзничь, Meshy), подъём — GetUp.
func cine_anim(kind: String) -> void:
	if dead or _anim == null:
		return
	match kind:
		"hurt":
			_set_state_keep("hurt")
			_anim.play("ReactL", 0.05)
		"knock":
			_set_state_keep("knockdown")
			_anim.play("ReactR", 0.05)
		"fall":
			_set_state_keep("knockdown")
			_anim.play("Fall" if _anim.has_animation("Fall") else "Death", 0.08)
			_anim.speed_scale = 1.3
		"getup":
			_set_state_keep("getup")
			if _anim.has_animation("GetUp"):
				_anim.play("GetUp", 0.15)
				_anim.speed_scale = 1.6
			else:
				_anim.play("Idle", 0.3)


func cine_release(v: Vector3) -> void:
	cine = false
	_hitstop = 0.0
	if _anim != null:
		_anim.active = true
	conc = maxf(conc, conc_max * 0.25)
	if _anim != null:
		_anim.speed_scale = 1.0
	if dead:
		return
	velocity = Vector3(v.x, 0.0, v.z) * 0.4                 # тяжёлый — отъезжает, не летит
	var lying := _anim != null and _anim.current_animation in ["Fall", "Death"]
	if lying:
		_set_state("getup")                              # лежит после сцены — встаёт (GetUp), потом снова в бой
	else:
		_set_state("circle")
		_wait = randf_range(0.5, 1.0)


## Звуки орка: замах (свист), попадание (глухой удар), блок (сталь), получил урон (удар по телу).
var _snd_swing: AudioStreamPlayer3D
var _snd_impact: AudioStreamPlayer3D
var _snd_clang: AudioStreamPlayer3D
var _snd_hurt: AudioStreamPlayer3D
var _snd_grunt: AudioStreamPlayer3D
var _snd_idle: AudioStreamPlayer3D
var _snd_laugh: AudioStreamPlayer3D
var _snd_hurt_hi: AudioStreamPlayer3D
var _snd_cheer: AudioStreamPlayer3D


## Герой пал от его удара — ликует (location.gd → _on_hero_hit).
func cheer() -> void:
	if not dead:
		_snd(_snd_cheer)
var _idle_snd_t := 4.0                  # с до следующего рычания
var _snd_heavy: AudioStreamPlayer3D


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
	p.unit_size = 14.0                               # арена большая: слышно и с края
	p.bus = "PaxRpgSfx"
	p.position = Vector3(0, 1.4, 0)
	add_child(p)
	return p


func _snd(p: AudioStreamPlayer3D) -> void:
	if p != null and p.stream != null and (p.stream as AudioStreamRandomizer).streams_count > 0:
		if p in [_snd_grunt, _snd_laugh, _snd_idle, _snd_cheer] and (_voice_busy() or p.playing):
			return                                       # голос не перебивает сам себя — иначе рёв рвётся
		p.play()


## Орк уже что-то кричит (рёв, смех, рычание, ликование).
func _voice_busy() -> bool:
	for v: AudioStreamPlayer3D in [_snd_grunt, _snd_laugh, _snd_idle, _snd_cheer]:
		if v != null and v.playing:
			return true
	return false


## Удар героя: в первые доли блока — отбит ("parry": концентрация героя в 0), в блоке — почти без урона ("guard"),
## в приёме — гиперброня (урон без срыва); иначе — как у гоблина (тяжёлый — не отлетает).
func take_damage(amount: float, from: Vector3, knock := false) -> String:
	if dead:
		return "dead"
	mod.log_info("[pax_rpg] orc hit %.0f (hp %.0f/%.0f, conc %.0f/%.0f, %s)" % [amount, hp, max_hp, conc, conc_max, _state])
	if _state == "broken":                                   # на колене: раны идут, слом не снимают
		hp = maxf(1.0, hp - amount)
		_snd(_snd_hurt)
		return "hit"
	if _state == "guard":
		var away := (from - global_position)
		away.y = 0.0
		var at := global_position + Vector3(0.0, 1.5, 0.0) + away.normalized() * 0.6
		_snd(_snd_clang)
		if _state_t <= PARRY_WINDOW:
			_burst(at, away, Color(1.0, 0.8, 0.35), 40, 5.0, 0.0, 0.3, 0.04, true)
			_set_state("parry")                               # отбил: концентрация героя — в 0 (location.gd)
			return "parry"
		_burst(at, away, Color(1.0, 0.6, 0.25), 14, 3.0, 0.0, 0.25, 0.03, true)
		spend(amount * 0.25)
		hp = maxf(1.0, hp - amount * 0.1)
		_guard_hits += 1
		if _state != "broken" and _guard_hits >= 3:
			_atk_after_guard()                          # надоело стоять в блоке — контратака
		return "broken" if _state == "broken" else "guard"
	_snd(_snd_hurt_hi if hp > max_hp * 0.5 else _snd_hurt)
	if _state in ["spin", "charge", "charge_wind"] or _atk != "":
		hp = maxf(0.0, hp - amount)                         # в приёме — урон без срыва (гиперброня)
		_since_hit = 0.0
		if hp <= 0.0:
			_lethal = true
			_atk = ""
			_die()
			return "dead"
		spend(amount * hit_conc)
		if _state == "broken":
			_atk = ""
			return "broken"
		return "hit"
	return super.take_damage(amount * 0.8, from, false)     # тяжёлый — не отлетает


## Герой парировал его удар: в серии (не последний удар) — −CHAIN_PARRY и удар продолжается; последний — 0, слом.
func deflected(from: Vector3) -> void:
	if dead:
		return
	var hits: Array = (ATTACKS.get(_atk, {}) as Dictionary).get("hits", [])
	if _atk != "" and _hits_done < hits.size():
		spend(CHAIN_PARRY)
		if _state == "broken":
			_atk = ""
		return
	_atk = ""
	spend(conc + 1.0)


## Удар орка принят героем в блок: атакующий тратит больше (тяжёлый — ещё больше).
func on_blocked(dmg: float, heavy: bool) -> void:
	spend(dmg * (0.6 if heavy else 0.45))


func _atk_after_guard() -> void:
	_guard_hits = 0
	_start_attack("Kick" if randf() < 0.5 else "Backhand")


func _start_attack(clip: String) -> void:
	var heavy_atk := str((ATTACKS.get(clip, {}) as Dictionary).get("kind", "")) == "heavy"
	spend(COST_HEAVY if heavy_atk else COST_ATTACK)          # замах — усталость; на нуле — слом вместо удара
	if _state == "broken" or dead:
		return
	_atk = clip
	_hits_done = 0
	_whoosh_done = 0
	_slam_done = false
	_hand_prev = Vector3.INF
	if randf() < 0.3 or (str((ATTACKS.get(clip, {}) as Dictionary).get("kind", "")) == "heavy" and randf() < 0.6):
		_snd(_snd_grunt)
	_held = false
	_hold_t = 0.0
	_set_state("attack")
	_play(clip, true, 0.15)


# ---------- ИИ ----------

func _phys(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	_idle_snd_t -= delta                               # время от времени рычит, пока не бьёт и жив
	if _idle_snd_t <= 0.0:
		_idle_snd_t = randf_range(6.0, 12.0)
		if not dead and _atk == "" and _state in ["idle", "circle", "stalk", "guard"] 				and not (_snd_grunt != null and _snd_grunt.playing):
			_snd(_snd_idle)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	_state_t += delta
	_since_hit += delta
	_since_special += delta
	var to := _target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	_conc_idle += delta
	if _state not in ["attack", "guard", "parry", "broken", "rise", "dead", "spin", "charge", "charge_wind"] \
			and _conc_idle > CONC_IDLE and conc < conc_max:
		var kr := (1.5 if dist > 5.0 else 1.0) * (0.35 + 0.65 * hp / maxf(max_hp, 1.0))
		conc = minf(conc_max, conc + ORC_REGEN * kr * delta)
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
				if hero_broken and dist < 8.0:
					_wait = minf(_wait, 0.05)                    # герой сломлен — наказать сразу
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
				_charge_min = INF
				_set_state("charge")
		"charge":
			flat = _charge_tick(delta, dist, dir)
		"skid":
			# по инерции: скорость гаснет трением, корпус откинут назад, ноги скользят, пыль из-под ступней
			_skid_v = move_toward(_skid_v, 0.0, SKID_DECEL * delta)
			flat = _charge_dir * _skid_v
			var k := _skid_v / CHARGE_SPEED
			if _model != null:
				_model.rotation.x = -0.32 * k
			if _anim != null:
				_anim.speed_scale = 0.6
			if randf() < k * 0.6:
				_burst(global_position + _charge_dir * 0.4, Vector3.UP, Color(0.6, 0.5, 0.4), 4, 1.5, 2.0, 0.6, 0.06)
			if _skid_v <= 0.4:
				if _model != null:
					_model.rotation.x = 0.0
				_roar_taunt = true
				_set_state("taunt")                          # встал — ревёт и снова идёт за героем
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
		"parry":                                         # отбил удар героя — ответ без замаха (герой на нуле)
			_face(dir, delta * 2.0)
			_damp(delta)
			if _state_t >= 0.35:
				_atk_after_guard()
		"broken":
			_damp(delta)
			if _anim != null and _anim.is_playing() and _anim.current_animation == "Stagger" \
					and _anim.current_animation_position >= _anim.current_animation_length * KNEEL_AT:
				_anim.pause()                            # на колене — окно Кровожадной атаки
			if _state_t >= BROKEN_TIME + 0.4:
				if _lethal:
					_die()
				else:
					conc = conc_max * RISE_CONC
					_set_state("rise")
		"getup":
			_damp(delta)
			if _anim != null:
				_anim.speed_scale = 1.4
			if _state_t >= _clip_len("GetUp") / 1.4 * 0.95 or (_anim != null and not _anim.is_playing()):
				_set_state("circle")
				_wait = randf_range(0.4, 0.9)
		"rise":
			_damp(delta)
			_face(dir, delta * 0.4)
			if _state_t >= _clip_len("Stagger") * (1.0 - KNEEL_AT) / 1.7 * 0.85:
				if _roar_phase:
					_roar_phase = false
					_roar_taunt = true
					_set_state("taunt")                  # новая фаза — рёв
				else:
					_set_state("circle")
					_wait = randf_range(0.4, 0.9)
		"dead":
			velocity.x = 0.0
			velocity.z = 0.0
	if new_swing:
		_swing_seen = true
	elif not swinging:
		_swing_seen = false
	if _state in ["approach", "circle", "attack", "spin", "charge", "idle", "taunt", "guard", "charge_wind", "skid"]:
		velocity.x = lerpf(velocity.x, flat.x, minf(1.0, delta * 8.0))
		velocity.z = lerpf(velocity.z, flat.z, minf(1.0, delta * 8.0))
	move_and_slide()


## Что делать: вблизи — удары и пинок, на средней — прыжок или вихрь, издалека — таран. С каждой фазой (сломом
## с Кровожадной атакой) особые приёмы чаще, паузы короче.
func _choose(dist: float) -> void:
	var ph := clampi(phase, 0, 2)
	if hero_broken and dist <= 4.5:                       # герой сломлен — сразу тяжёлый удар
		_start_attack("Backhand")
		_wait = 0.6
		return
	if _since_special > [10.0, 7.5, 5.5][ph] and randf() < 0.6:
		_since_special = 0.0
		spend(COST_SPECIAL)
		if _state == "broken":
			return
		if dist > 5.0 or randf() < 0.5:
			_set_state("charge_wind")
		else:
			_set_state("spin")
		return
	if dist > 4.5:
		_start_attack("JumpAttack")
	else:
		_start_attack(MOVES_NEAR[randi() % MOVES_NEAR.size()])
	var w: Array = [[1.0, 2.2], [0.7, 1.6], [0.4, 1.1]][ph]
	_wait = randf_range(float(w[0]), float(w[1]))


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
		_anim.speed_scale = sp * (1.0 + 0.08 * clampi(phase, 0, 2)) * (0.85 if low_conc() else 1.0)
	if a.has("leap") and _hits_done == 0:
		var t0 := 0.3
		var t1 := float(hits[0])
		if frac > t0 and frac < t1:
			var dur := (t1 - t0) * length / maxf(sp, 0.1)
			flat = dir * minf(float(a.leap), dist + 0.5) / maxf(dur, 0.2)
	elif _hits_done == 0 and frac < (float(hits[0]) if hits.size() > 0 else 0.0) and dist > 1.6:
		flat = dir * float(a.get("step", 0.0))
	# свист — чуть раньше удара (топор уже летит), а урон — только когда кисть с топором прошла у тела героя:
	# окно вокруг замеренного удара; не дотянулся до конца окна — промах (кувырок/шаг назад спасают)
	# замах с замиранием (hold): пока орк застыл или ещё не дошёл до него — ни свиста, ни урона (удар не начался)
	var holding := hold.size() == 2 and (_hold_t > 0.0 or (not _held and frac < float(hold[0])))
	if not holding and _whoosh_done < hits.size() and frac >= float(hits[_whoosh_done]) - 0.04:
		_whoosh_done += 1
		_snd(_snd_swing)
	if _atk == "JumpAttack" and not _slam_done and hits.size() > 0 and frac >= float(hits[0]):
		_slam_done = true
		var fw := _model.global_transform.basis.z if _model != null else -global_transform.basis.z   # модель смотрит по +Z
		slammed.emit(global_position + Vector3(fw.x, 0.0, fw.z).normalized() * 1.7)   # куда вбит топор
	if _hits_done < hits.size():
		var ht := float(hits[_hits_done])
		if not holding and frac >= ht - float(WINDOW[0]):
			var touch := _contact(_atk == "Kick")
			if touch and _on_hit.is_valid():
				_hits_done += 1
				var heavy := str(a.get("kind", "")) == "heavy"
				_snd(_snd_heavy if heavy else _snd_impact)
				_on_hit.call(float(a.get("dmg", 20.0)), self, str(a.get("kind", "")))
				if randf() < 0.25:                           # попал — иногда хохочет вслед
					get_tree().create_timer(0.7).timeout.connect(func() -> void:
						if is_instance_valid(self) and not dead:
							_snd(_snd_laugh))
			elif frac >= ht + float(WINDOW[1]):
				_hits_done += 1                              # мимо
	if frac >= 0.98 or (_anim != null and not _anim.is_playing()):
		_atk = ""
		_set_state("circle")
		_wait = randf_range(0.9, 1.8)
	return flat


var _hand_prev := Vector3.INF


## Кисть летит (а не замерла в замахе рядом с героем): скорость больше 3 м/с — удар, а не прицеливание.
func _hand_fast(delta: float) -> bool:
	if _skel == null or delta <= 0.0:
		return true
	var bi := _skel.find_bone("RightFoot" if _atk == "Kick" else "RightHand")
	if bi < 0:
		return true
	var p := _skel.global_transform * _skel.get_bone_global_pose(bi).origin
	var fast := _hand_prev != Vector3.INF and p.distance_to(_hand_prev) / delta > 3.0
	_hand_prev = p
	return fast


## Кровожадная атака по боссу: треть здоровья (последняя треть — гибель); новая фаза — выдержка полная, встаёт
## с колена и ревёт.
var _roar_phase := false


func bloodthirsty() -> void:
	if dead:
		return
	cine = false
	if _anim != null:
		_anim.active = true
	var cut := max_hp / 3.0
	if hp <= cut + 1.0:
		hp = 0.0
		_lethal = true
		_atk = ""
		_die()
		return
	hp = maxf(1.0, hp - cut)
	phase += 1
	conc = conc_max
	_lethal = false
	_atk = ""
	_burst(global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP, Color(0.55, 0.02, 0.03), 60, 4.0, 9.0, 0.6, 0.07)
	_snd(_snd_hurt)
	_roar_phase = true
	if _anim != null and _anim.has_animation("Stagger"):   # с колена — вторая половина клипа слома
		_anim.play("Stagger", 0.15)
		_anim.seek(_anim.get_animation("Stagger").length * KNEEL_AT, true)
	_set_state("rise")
	mod.log_info("[pax_rpg] orc bloodthirsty: phase %d, hp %.0f/%.0f" % [phase, hp, max_hp])


## Достаёт ли удар героя сейчас: кисть (у пинка — стопа) ближе CONTACT к телу героя (отрезок от колен до головы).
## Нет скелета — по старому: дистанция до героя.
func _contact(foot: bool) -> bool:
	if _skel == null:
		_skel = BodyFx.find_skeleton(_model)
	var hero_lo := _target.global_position + Vector3(0, 0.3, 0)
	var hero_hi := _target.global_position + Vector3(0, 1.7, 0)
	if _skel == null:
		return global_position.distance_to(_target.global_position) <= float((ATTACKS.get(_atk, {}) as Dictionary).get("reach", 2.8))
	# не запястье, а сам топор: отрезок от кисти до лезвия (~AXE м по оси кисти — замерено покадрово в Blender:
	# в миг удара лезвие выходит на 0.8–1.0 м перед тазом); пинок — стопа
	var best := INF
	for bn: String in (["RightFoot", "LeftFoot"] if foot else ["RightHand"]):
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var g := _skel.global_transform * _skel.get_bone_global_pose(bi)
		var a := g.origin
		var b := a if foot else a + g.basis.y.normalized() * AXE
		var cp := Geometry3D.get_closest_points_between_segments(a, b, hero_lo, hero_hi)
		best = minf(best, (cp[0] as Vector3).distance_to(cp[1]))
	return best <= (0.6 if foot else 0.5)


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
	_spin_hit_t = maxf(0.0, _spin_hit_t - delta)
	if _state_t > 0.7 and _contact(false):
		_spin_hit_t = 0.2                                   # топор прошёл по герою между тиками — удар засчитается
	if _spin_tick <= 0.0 and _state_t < SPIN_TIME:
		_spin_tick = SPIN_TICK
		_snd(_snd_swing)
		if _state_t > 0.7 and _spin_contact() and _on_hit.is_valid():   # бьёт топор, когда он реально проходит по герою
			_on_hit.call(SPIN_DMG, self, "perilous")
	return dir * SPIN_SPEED if _state_t < SPIN_TIME else Vector3.ZERO


## Вихрь: топор (кисть → лезвие) в 0.6 м от тела героя — в любой момент последних 0.2 с (кружится быстро).
func _spin_contact() -> bool:
	if _spin_hit_t > 0.0:
		return true
	return _contact(false)


var _spin_hit_t := 0.0


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
	if get_slide_collision_count() > 0 and _state_t > 0.4:
		_set_state("dizzy")                                  # врезался в стену — оглушён
		return Vector3.ZERO
	_charge_min = minf(_charge_min, dist)
	var passed := _charge_min < 4.0 and dist > _charge_min + 0.8      # проскочил мимо героя (тот увернулся)
	if _state_t >= CHARGE_TIME or (_state_t > 0.4 and (passed or _charge_dir.dot(dir) < -0.1)):
		_skid_v = CHARGE_SPEED                               # промахнулся (герой позади) — тормозит по инерции
		_set_state("skid")
		return _charge_dir * _skid_v
	return _charge_dir * CHARGE_SPEED


## Модель орка смотрит вперёд по +Z (Meshy).
func _face(dir: Vector3, delta: float) -> void:
	if _model == null or dir.length() < 0.01:
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 6.0))


func _respawn() -> void:
	super._respawn()
	_atk = ""
	_roar_phase = false
	_since_special = 4.0


## Угроза для указателя у края экрана: таран и вихрь — не парировать (2), прочие замахи — 1.
func threat() -> int:
	if dead:
		return 0
	if _state in ["charge_wind", "charge", "spin"]:
		return 2
	return 1 if _state == "attack" else 0
