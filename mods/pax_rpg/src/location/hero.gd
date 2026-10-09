extends RefCounted
## Герой локации: модель (config/hero.json → models/*.glb), её анимации и состояние — меч на спине или в руке,
## доставание и убирание, комбо из трёх тяжёлых ударов, прыжок. Тело в ударах ведёт root motion: смещение таза
## вынуто из клипов при сборке (pax_rpg/dev/blender/knight/assemble_knight.py → models/*_anim.json), и персонажа
## двигает игра — инерция меча тянет его вперёд, удары комбо переходят один в другой без рывка назад.
## location.gd каждый кадр зовёт tick() и двигает CharacterBody3D по тому, что тот вернул.

const ATTACKS := ["Attack1", "Attack2", "Attack3"]
const LOOPS := ["Idle", "Walk", "Run", "WalkArmed"]
const ONCE := ["Draw", "Sheathe", "Jump", "Attack1", "Attack2", "Attack3"]

var cfg: Dictionary = {}
var meta: Dictionary = {}           # *_anim.json: root_motion, sword_switch, fps
var model: Node3D
var anim: AnimationPlayer
var armed := false
var action := ""                    # идёт разовый клип: Draw / Sheathe / Jump / AttackN; "" — ходьба и стойка
var _queued := false                # удар нажат во время прошлого — следующий удар комбо
var _armed_pose := false
var _jump_done := false
var _sword_back: Node3D
var _sword_hand: Node3D
var _prev_off := Vector2.ZERO       # root motion: смещение клипа на прошлом кадре


func load_model(mod: PaxMod, c: Dictionary) -> Node3D:
	cfg = c
	model = mod.model(str(cfg.get("model", "models/hero_simple.glb")))
	if model == null:
		return null
	var mp := str(cfg.get("anim_meta", ""))
	if mp != "":
		var parsed: Variant = JSON.parse_string(mod.read_text(mp))
		meta = parsed if parsed is Dictionary else {}
	_sword_back = model.find_child("Sword_Back", true, false) as Node3D
	_sword_hand = model.find_child("Sword_Hand", true, false) as Node3D
	return model


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
	_show_sword()


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c: Node in n.get_children():
		var a := _find_anim(c)
		if a != null:
			return a
	return null


func _f(k: String, d: float) -> float:
	return float(cfg.get(k, d))


func has(n: String) -> bool:
	return anim != null and anim.has_animation(n)


func locks_move() -> bool:
	return action != "" and action != "Jump"


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
		if _pos_frac() >= _f("combo_window", 0.3):
			_queued = true                  # нажал вовремя — после этого удара пойдёт следующий


## true — начать прыжок сейчас (анимация уже пошла; отрыв — через jump_takeoff секунд, в tick).
func jump(on_floor: bool) -> void:
	if anim == null or not on_floor or (action != "" and action != "Jump"):
		return
	if has("Jump"):
		_play_once("Jump")
		_jump_done = false


func _play_once(n: String) -> void:
	action = n
	_queued = false
	_armed_pose = false
	_prev_off = Vector2.ZERO
	anim.speed_scale = 1.0
	anim.play(n, _f("blend", 0.15))


func _on_finished(n: StringName) -> void:
	if String(n) != action:
		return
	if action == "Draw":
		armed = true
	elif action == "Sheathe":
		armed = false
	action = ""
	_armed_pose = false


func _pos_frac() -> float:
	if anim == null or anim.current_animation == "":
		return 1.0
	return anim.current_animation_position / maxf(anim.current_animation_length, 0.001)


# ---------- кадр ----------

## Возвращает {"root": Vector3 — смещение за кадр в осях модели (x, 0, z; модель смотрит на +Z),
##             "jump": bool — оторваться от земли сейчас}.
func tick(delta: float, moving: bool, speed: float, running: bool) -> Dictionary:
	var out := {"root": Vector3.ZERO, "jump": false}
	if anim == null:
		return out
	if action != "" and not anim.is_playing() and not _armed_pose:
		_on_finished(StringName(action))      # сигнал конца не пришёл — не застрять
	# комбо: следующий удар — с точки отмены текущего
	if action in ATTACKS and _queued and _pos_frac() >= _f("combo_cancel", 0.62):
		var i := ATTACKS.find(action)
		if i + 1 < ATTACKS.size() and has(ATTACKS[i + 1]):
			_play_once(ATTACKS[i + 1])
	if action == "Jump" and not _jump_done and anim.current_animation_position >= _f("jump_takeoff", 0.3):
		_jump_done = true
		out.jump = true
	if action != "":
		out.root = _root_step()
	else:
		_idle_or_walk(moving, speed, running)
	_show_sword()
	return out


func _idle_or_walk(moving: bool, speed: float, running: bool) -> void:
	if not moving:
		if armed and has("Draw"):           # стойка с мечом — последний кадр Draw
			if not _armed_pose:
				anim.play("Draw", _f("blend", 0.15))
				anim.seek(anim.get_animation("Draw").length, true)
				anim.pause()
				_armed_pose = true
			return
		_armed_pose = false
		if anim.current_animation != "Idle" or not anim.is_playing():
			anim.play("Idle", _f("blend", 0.15))
		anim.speed_scale = 1.0
		return
	_armed_pose = false
	var want := "Run" if running else ("WalkArmed" if armed and has("WalkArmed") else "Walk")
	var stride := _f("stride_run", 4.0) if want == "Run" else (_f("stride_walk_armed", 1.3) if want == "WalkArmed" else _f("stride_walk", 1.5))
	if anim.current_animation != want or not anim.is_playing():
		anim.play(want, _f("blend", 0.15))
	anim.speed_scale = clampf(speed / stride, 0.5, 2.0)


## Смещение тела за кадр из root motion клипа (то, что вынуто из анимации при сборке).
func _root_step() -> Vector3:
	var rm: Dictionary = meta.get("root_motion", {})
	if not rm.has(action):
		return Vector3.ZERO
	var clip: Dictionary = rm[action]
	var off: Array = clip.get("offset", [])
	if off.is_empty():
		return Vector3.ZERO
	var t := anim.current_animation_position * float(clip.get("fps", 30))
	var i := clampi(int(t), 0, off.size() - 1)
	var j := mini(i + 1, off.size() - 1)
	var a: Array = off[i]
	var b: Array = off[j]
	var k := t - float(i)
	var cur := Vector2(lerpf(float(a[0]), float(b[0]), k), lerpf(float(a[1]), float(b[1]), k))
	var d := cur - _prev_off
	_prev_off = cur
	var s := _f("root_motion_scale", 0.8)
	return Vector3(d.x * s * _f("root_motion_lateral", 0.5), 0.0, d.y * s)


## Меч там, где он сейчас: на спине или в руке (смена — на кадре, где рука у рукояти, из *_anim.json).
func _show_sword() -> void:
	if _sword_back == null or _sword_hand == null:
		return
	var sw: Dictionary = meta.get("sword_switch", {})
	var in_hand := armed
	var p := anim.current_animation_position if anim != null and anim.current_animation != "" else 0.0
	if action == "Draw":
		in_hand = p >= float((sw.get("Draw", {}) as Dictionary).get("time", 1.0))
	elif action == "Sheathe":
		in_hand = p < float((sw.get("Sheathe", {}) as Dictionary).get("time", 1.0))
	elif action in ATTACKS:
		in_hand = true
	_sword_hand.visible = in_hand
	_sword_back.visible = not in_hand
