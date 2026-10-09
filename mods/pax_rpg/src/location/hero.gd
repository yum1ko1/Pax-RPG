extends RefCounted
## Герой локации: модель (config/hero.json → models/*.glb) и её состояние — меч на спине, в руке или волочится
## по земле в беге, доставание и убирание, комбо из трёх тяжёлых ударов, прыжок, плащ на пружинных костях.
## Удары ведёт root motion (смещение таза вынуто при сборке — pax_rpg/dev/blender/knight/*.py → *_anim.json):
## инерция меча тянет персонажа. Удар без продолжения кончается сразу после взмаха и плавно уходит в стойку.
## location.gd каждый кадр зовёт tick() и двигает CharacterBody3D по тому, что тот вернул.

const ATTACKS := ["Attack1", "Attack2", "Attack3"]
const LOOPS := ["Idle", "IdleArmed", "Walk", "Run", "RunArmed", "WalkArmed"]
const ONCE := ["Draw", "Sheathe", "Jump", "Attack1", "Attack2", "Attack3"]

var cfg: Dictionary = {}
var meta: Dictionary = {}           # *_anim.json: root_motion, sword_switch, impact, cape
var model: Node3D
var anim: AnimationPlayer
var armed := false
var action := ""                    # разовый клип: Draw / Sheathe / Jump / AttackN; "" — ходьба и стойки
var _queued := false                # удар нажат во время текущего — следующий удар комбо
var _airborne := false
var _sword_back: Node3D
var _sword_hand: Node3D
var _sword_drag: Node3D
var _prev_off := Vector2.ZERO       # root motion: смещение клипа на прошлом кадре
var _swing: AudioStreamPlayer       # свист меча (sounds/swing_*.wav)
var _impact: AudioStreamPlayer      # удар о землю (sounds/impact_*.wav)
var _swing_done := false
var _impact_done := false
var _cape: Node                     # SpringBoneSimulator3D плаща
var _mod: PaxMod


func load_model(mod: PaxMod, c: Dictionary) -> Node3D:
	cfg = c
	_mod = mod
	model = mod.model(str(cfg.get("model", "models/hero_simple.glb")))
	if model == null:
		return null
	var mp := str(cfg.get("anim_meta", ""))
	if mp != "":
		var parsed: Variant = JSON.parse_string(mod.read_text(mp))
		meta = parsed if parsed is Dictionary else {}
	_sword_back = model.find_child("Sword_Back", true, false) as Node3D
	_sword_hand = model.find_child("Sword_Hand", true, false) as Node3D
	_sword_drag = model.find_child("Sword_Drag", true, false) as Node3D
	_swing = _player(cfg.get("swing_files", []), _f("swing_pitch_spread", 1.06), _f("swing_volume_db", -4.0))
	_impact = _player(cfg.get("impact_files", []), 1.04, _f("impact_volume_db", 0.0))
	return model


## Плеер со случайным из вариантов звука (без повторов подряд) и разбросом высоты.
func _player(files: Variant, pitch: float, volume: float) -> AudioStreamPlayer:
	if not (files is Array) or (files as Array).is_empty():
		return null
	var rnd := AudioStreamRandomizer.new()
	rnd.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rnd.random_pitch = pitch
	rnd.random_volume_offset_db = 1.5
	for f: Variant in files:
		var st: AudioStream = _mod.sound(str(f))
		if st != null:
			rnd.add_stream(-1, st)
	if rnd.streams_count == 0:
		return null
	var p := AudioStreamPlayer.new()           # не 3D: у SubViewport локации нет своего слушателя
	p.stream = rnd
	p.volume_db = volume
	model.add_child(p)
	return p


## После того как модель в дереве (вне дерева AnimationPlayer не играет).
func start() -> void:
	anim = _find_anim(model)
	if anim == null:
		return
	for n: String in LOOPS:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n: String in ONCE:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_NONE
	anim.animation_finished.connect(_on_finished)
	anim.play("Idle")
	_make_cape()
	_show_sword()


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c: Node in n.get_children():
		var a := _find_anim(c)
		if a != null:
			return a
	return null


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c: Node in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


func _f(k: String, d: float) -> float:
	return float(cfg.get(k, d))


## Значение по клипу из словаря настроек ({"Attack1": 0.4, ...}) или общее.
func _per(k: String, clip: String, d: float) -> float:
	var v: Variant = cfg.get(k, d)
	if v is Dictionary:
		return float((v as Dictionary).get(clip, d))
	return float(v)


func has(n: String) -> bool:
	return anim != null and anim.has_animation(n)


func locks_move() -> bool:
	return action != "" and action != "Jump"


# ---------- плащ: пружинные кости ----------

func _make_cape() -> void:
	var chains: Variant = (meta.get("cape", {}) as Dictionary).get("chains", [])
	if not (chains is Array) or (chains as Array).is_empty() or not ClassDB.class_exists("SpringBoneSimulator3D"):
		return
	var sk := _find_skeleton(model)
	if sk == null:
		return
	_cape = ClassDB.instantiate("SpringBoneSimulator3D")
	sk.add_child(_cape)
	var n := (chains as Array).size()
	_cape.call("set_setting_count", n)
	for i in n:
		var ch: Array = chains[i]
		_cape.call("set_root_bone_name", i, str(ch[0]))
		_cape.call("set_end_bone_name", i, str(ch[1]))
		_cape.call("set_extend_end_bone", i, true)
		_cape.call("set_end_bone_length", i, _f("cape_end_length", 0.25))
		_cape.call("set_radius", i, _f("cape_radius", 0.05))
		_cape.call("set_stiffness", i, _f("cape_stiffness", 0.35))
		_cape.call("set_drag", i, _f("cape_drag", 0.35))
		_cape.call("set_gravity", i, _f("cape_gravity", 1.2))
		_cape.call("set_gravity_direction", i, Vector3.DOWN)
	# тело, о которое бьётся плащ: шары на тазу, бёдрах, коленях
	var cls := "SpringBoneCollisionSphere3D" if ClassDB.class_exists("SpringBoneCollisionSphere3D") else ""
	if cls != "":
		for b: Variant in [["Hips", 0.2], ["LeftUpLeg", 0.15], ["RightUpLeg", 0.15], ["LeftLeg", 0.13],
				["RightLeg", 0.13], ["Spine01", 0.2]]:
			if sk.find_bone(str(b[0])) < 0:
				continue
			var s: Node = ClassDB.instantiate(cls)
			s.call("set_bone_name", str(b[0]))
			s.call("set_radius", float(b[1]))
			_cape.add_child(s)


## Ветер от бега: плащ отлетает назад по скорости (world — скорость тела в мире).
func cape_wind(velocity: Vector3) -> void:
	if _cape == null:
		return
	var v := Vector3(velocity.x, 0.0, velocity.z)
	_cape.call("set_external_force", -v * _f("cape_wind", 0.12) + Vector3(0.0, 0.0, 0.0))


# ---------- команды ----------

func toggle_sword(on_floor: bool) -> void:
	if anim == null or action != "" or not on_floor:
		return
	var n := "Sheathe" if armed else "Draw"
	if not has(n):
		armed = not armed
		_show_sword()
		return
	_play_once(n)


func attack(on_floor: bool) -> void:
	if anim == null or not has("Attack1"):
		return
	if action == "" and on_floor:
		if not armed:
			toggle_sword(on_floor)          # меч за спиной — сперва достать
			return
		_play_once("Attack1")
	elif action in ATTACKS and action != ATTACKS[-1]:
		_queued = true                      # следующий удар — сразу после взмаха этого


## Прыжок: анимация с момента отрыва (без долгого приседа), отрыв — сразу (tick вернёт jump).
func jump(on_floor: bool) -> bool:
	if anim == null or not on_floor or (action != "" and action != "Jump"):
		return false
	if has("Jump"):
		_play_once("Jump")
		anim.seek(_f("jump_skip", 0.3), true)
	_airborne = false
	return true


func _play_once(n: String, skip := 0.0) -> void:
	action = n
	_queued = false
	_prev_off = Vector2.ZERO
	_swing_done = false
	_impact_done = false
	anim.speed_scale = _per("attack_speed", n, 1.0) if n in ATTACKS else 1.0
	anim.play(n, _per("blend_in", n, 0.15))
	if skip > 0.0:
		anim.seek(skip, true)
		_prev_off = _root_at(skip)


func _on_finished(n: StringName) -> void:
	if String(n) == action:
		_end_action()


func _end_action() -> void:
	if action == "Draw":
		armed = true
	elif action == "Sheathe":
		armed = false
	action = ""


func _pos() -> float:
	return anim.current_animation_position if anim != null and anim.current_animation != "" else 0.0


func _frac() -> float:
	if anim == null or anim.current_animation == "":
		return 1.0
	return _pos() / maxf(anim.current_animation_length, 0.001)


# ---------- кадр ----------

## Возвращает {"root": Vector3 — смещение за кадр в осях модели (модель смотрит на +Z)}.
func tick(_delta: float, moving: bool, speed: float, running: bool, on_floor: bool) -> Dictionary:
	var out := {"root": Vector3.ZERO}
	if anim == null:
		return out
	if action != "" and not anim.is_playing():
		_end_action()                        # сигнал конца не пришёл — не застрять
	if action in ATTACKS:
		var i := ATTACKS.find(action)
		# комбо: следующий удар — с точки отмены, и сразу с замаха, без долгой подготовки
		if _queued and _frac() >= _per("combo_cancel", action, 0.4) and i + 1 < ATTACKS.size() and has(ATTACKS[i + 1]):
			var nxt: String = ATTACKS[i + 1]
			_play_once(nxt, _per("combo_skip", nxt, 0.0))
		elif not _queued and _frac() >= _per("attack_end", action, 0.5):
			_end_action()                    # без продолжения — сразу в стойку, управление вернулось
	if action == "Jump":
		if not on_floor:
			_airborne = true
		elif _airborne:
			_end_action()                    # приземлился — дальше ходьба или стойка
	if action != "":
		_sounds()
		out.root = _root_step()
	else:
		_loop(moving, speed, running)
	_show_sword()
	return out


func _loop(moving: bool, speed: float, running: bool) -> void:
	var want := "IdleArmed" if armed and has("IdleArmed") else "Idle"
	var stride := 1.0
	if moving:
		if running:
			want = "RunArmed" if armed and has("RunArmed") else "Run"
			stride = _f("stride_run_armed", 3.2) if want == "RunArmed" else _f("stride_run", 4.0)
		else:
			want = "WalkArmed" if armed and has("WalkArmed") else "Walk"
			stride = _f("stride_walk_armed", 1.3) if want == "WalkArmed" else _f("stride_walk", 1.5)
	if anim.current_animation != want or not anim.is_playing():
		anim.play(want, _f("blend_loop", 0.3))
	anim.speed_scale = clampf(speed / stride, 0.5, 2.0) if moving else 1.0


func _sounds() -> void:
	var peaks: Dictionary = cfg.get("swing_peaks", {})
	if _swing != null and not _swing_done and peaks.has(action) \
			and _pos() >= float(peaks[action]) - _f("swing_lead", 0.55):
		_swing_done = true
		_swing.volume_db = _f("swing_volume_db", -4.0) + (0.0 if action in ATTACKS else -6.0)
		_swing.play()
	var imp: Dictionary = meta.get("impact", {})
	if _impact != null and not _impact_done and imp.has(action) and _pos() >= float(imp[action]):
		_impact_done = true
		_impact.play()


func _root_at(t: float) -> Vector2:
	var rm: Dictionary = meta.get("root_motion", {})
	if not rm.has(action):
		return Vector2.ZERO
	var clip: Dictionary = rm[action]
	var off: Array = clip.get("offset", [])
	if off.is_empty():
		return Vector2.ZERO
	var x := t * float(clip.get("fps", 30))
	var i := clampi(int(x), 0, off.size() - 1)
	var j := mini(i + 1, off.size() - 1)
	var a: Array = off[i]
	var b: Array = off[j]
	var k := x - float(i)
	return Vector2(lerpf(float(a[0]), float(b[0]), k), lerpf(float(a[1]), float(b[1]), k))


## Смещение тела за кадр из root motion клипа.
func _root_step() -> Vector3:
	var cur := _root_at(_pos())
	var d := cur - _prev_off
	_prev_off = cur
	var s := _per("root_motion_scale", action, 0.8)
	return Vector3(d.x * s * _f("root_motion_lateral", 0.5), 0.0, d.y * s)


## Меч там, где он сейчас: на спине, в руке или волочится в беге.
func _show_sword() -> void:
	if _sword_back == null or _sword_hand == null:
		return
	var sw: Dictionary = meta.get("sword_switch", {})
	var in_hand := armed
	if action == "Draw":
		in_hand = _pos() >= float((sw.get("Draw", {}) as Dictionary).get("time", 0.45))
	elif action == "Sheathe":
		in_hand = _pos() < float((sw.get("Sheathe", {}) as Dictionary).get("time", 0.9))
	elif action in ATTACKS:
		in_hand = true
	var drag := in_hand and action == "" and anim != null and anim.current_animation == "RunArmed" and _sword_drag != null
	_sword_hand.visible = in_hand and not drag
	_sword_back.visible = not in_hand
	if _sword_drag != null:
		_sword_drag.visible = drag
