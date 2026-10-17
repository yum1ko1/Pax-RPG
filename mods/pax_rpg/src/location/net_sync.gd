extends Node
## Сетевая игра Pax RPG через серверы игры (Pax.net: лобби, вход, пересылка сообщений модов — хост разносит).
## Каждая копия мода 15 раз в секунду шлёт, где её герой: город, позиция, поворот, клип и его время, достан ли
## меч, кто это (персонаж). Остальные рисуют его «куклой» в том же городе: та же модель героя, тот же клип,
## позиция и поворот сглажены (интерполяция между пакетами). Кукла пропадает, если игрок ушёл из города или
## молчит дольше LOST с. Бой, враги и мир пока у каждого свои — это первый шаг (видеть друг друга вживую).

const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const POSE := "pax_rpg.pose"
const BYE := "pax_rpg.bye"
const RATE := 1.0 / 15.0
const LOST := 3.0

var mod: PaxMod
var _pose: Callable                  # location.gd → net_pose(): {} — не в городе
var _cfg_of: Callable                # location.gd → hero_cfg_of(id персонажа)
var _view: Node
var _send_t := 0.0
var _puppets := {}                   # id игрока → {node, anim, from, to, yaw_from, yaw_to, k, t, clip, city, hero, armed, back, hand}


func setup(m: PaxMod, pose: Callable, cfg_of: Callable) -> void:
	mod = m
	_pose = pose
	_cfg_of = cfg_of
	name = "PaxRpgNet"
	Pax.net.on(POSE, _on_pose)
	Pax.net.on(BYE, _on_bye)


func enter(view: Node) -> void:
	_view = view
	_clear()


func leave() -> void:
	if Pax.net.active():
		Pax.net.send(BYE, {})
	_clear()
	_view = null


func _clear() -> void:
	for id: Variant in _puppets:
		var n: Node = (_puppets[id] as Dictionary).node
		if is_instance_valid(n):
			n.queue_free()
	_puppets.clear()


func _process(delta: float) -> void:
	if not Pax.net.active() or _view == null or not is_instance_valid(_view):
		return
	_send_t += delta
	if _send_t >= RATE:
		_send_t = 0.0
		var me: Dictionary = _pose.call() as Dictionary
		if not me.is_empty():
			Pax.net.send(POSE, me)
	var now := Time.get_ticks_msec() / 1000.0
	for id: Variant in _puppets.keys():
		var p: Dictionary = _puppets[id]
		if now - float(p.t) > LOST:
			_drop(int(id))
			continue
		_animate(p, delta)


func _on_bye(from: int, _data: Dictionary) -> void:
	_drop(from)


func _drop(id: int) -> void:
	if _puppets.has(id):
		var n: Node = (_puppets[id] as Dictionary).node
		if is_instance_valid(n):
			n.queue_free()
		_puppets.erase(id)


func _on_pose(from: int, d: Dictionary) -> void:
	if _view == null or not is_instance_valid(_view):
		return
	var me: Dictionary = _pose.call() as Dictionary
	if me.is_empty() or str(d.get("city", "")) != str(me.get("city", "")):
		_drop(from)                                  # в другом городе — не рисуем
		return
	var p: Dictionary = _puppets.get(from, {})
	if p.is_empty() or str(p.hero) != str(d.get("hero", "")):
		_drop(from)
		p = _spawn(from, d)
		if p.is_empty():
			return
	var pos := Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	var node: Node3D = p.node
	p.from = node.global_position
	p.to = pos
	p.yaw_from = node.rotation.y
	p.yaw_to = float(d.get("yaw", 0.0))
	p.k = 0.0
	p.t = Time.get_ticks_msec() / 1000.0
	p.armed = bool(d.get("armed", false))
	var clip := str(d.get("clip", ""))
	var at := float(d.get("at", 0.0))
	var ap: AnimationPlayer = p.anim
	if ap != null and clip != "" and ap.has_animation(clip):
		if ap.current_animation != clip:
			ap.play(clip, 0.15)
			ap.seek(at, true)
		elif absf(ap.current_animation_position - at) > 0.25:
			ap.seek(at, true)                        # разошлись — догнать
	_puppets[from] = p


func _spawn(id: int, d: Dictionary) -> Dictionary:
	var cfg: Dictionary = _cfg_of.call(str(d.get("hero", ""))) as Dictionary
	var model := Assets.model(mod, str(cfg.get("model", "models/knight.glb")))
	if model == null:
		return {}
	var root := Node3D.new()
	root.name = "PaxRpgPeer%d" % id
	model.position = Vector3(0.0, -float(cfg.get("capsule_height", 1.8)) / 2.0, 0.0)
	model.rotation.y = PI
	root.add_child(model)
	_view.add_child(root)
	root.global_position = Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	root.rotation.y = float(d.get("yaw", 0.0))
	var ap: AnimationPlayer = null
	for n: Node in model.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap != null:
		for loop: String in ["Idle", "IdleArmed", "Walk", "WalkArmed", "Run", "RunArmed", "CombatIdle"]:
			if ap.has_animation(loop):
				ap.get_animation(loop).loop_mode = Animation.LOOP_LINEAR
	var tag := Label3D.new()                         # имя игрока над головой
	tag.text = _name_of(id)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0.0, 1.25, 0.0)
	tag.font_size = 28
	tag.outline_size = 8
	tag.no_depth_test = true
	root.add_child(tag)
	return {"node": root, "anim": ap, "from": root.global_position, "to": root.global_position,
		"yaw_from": root.rotation.y, "yaw_to": root.rotation.y, "k": 1.0, "t": Time.get_ticks_msec() / 1000.0,
		"hero": str(d.get("hero", "")), "armed": false,
		"back": model.find_child("Sword_Back", true, false), "hand": model.find_child("Sword_Hand", true, false)}


func _name_of(id: int) -> String:
	for p: Variant in Pax.net.players():
		if p is Dictionary and int((p as Dictionary).get("id", -1)) == id:
			return str((p as Dictionary).get("name", "#%d" % id))
	return "#%d" % id


func _animate(p: Dictionary, delta: float) -> void:
	var node: Node3D = p.node
	if not is_instance_valid(node):
		return
	p.k = minf(1.0, float(p.k) + delta / RATE)       # за время до следующего пакета — ровно к цели
	node.global_position = (p.from as Vector3).lerp(p.to as Vector3, float(p.k))
	node.rotation.y = lerp_angle(float(p.yaw_from), float(p.yaw_to), float(p.k))
	var hand: Node3D = p.hand as Node3D
	var back: Node3D = p.back as Node3D
	if hand != null:
		hand.visible = bool(p.armed)
	if back != null:
		back.visible = not bool(p.armed)
