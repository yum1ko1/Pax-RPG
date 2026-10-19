extends CharacterBody3D
## Мирный житель (гоблин): ходит по маршрутам улиц из планировки города («paths»: ломаные XZ), иногда
## останавливается поглазеть; на героя не нападает, обходить его не умеет — просто ждёт, если упёрся.
## Модель и клипы — как у гоблина-врага (models/goblin/), без боя.
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
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
# кто это (разговор через нейросеть — talk.gd): имя, ремесло, характер, отношение к герою 0..100
const NAMES := ["Гракх", "Зугба", "Мырт", "Шнырь", "Каргаш", "Ульба", "Бзык", "Трокх", "Ырза", "Хряп", "Сквирт", "Дорна",
	"Гнилоглаз", "Курба", "Пырх", "Ярга", "Щербач", "Мокла", "Згрит", "Нахра"]
const ROLES := ["merchant", "guard", "herder", "shaman", "smith", "beggar", "cook", "porter"]
const TEMPERS := ["жадный и хитрый", "угрюмый и подозрительный", "болтливый и любопытный", "трусливый, но услужливый",
	"гордый и вспыльчивый", "добродушный простак", "мрачный, говорит загадками", "насмешливый и дерзкий"]
var npc_name := ""
var role := ""
var temper := ""
var relation := 50
var npc_index := -1                 # номер жителя в городе (задания и отношения — по нему, quest.gd)
var talking := false
var _prompt: Label3D
# уровень детализации (как LOD у сеток, только для движения и анимации): рядом и в кадре — каждый кадр, как раньше;
# дальше FAR м — анимация 15 раз в секунду (с 30+ м глаз разницы не видит); за кадром — не рисуется, анимация стоит, шаг пути —
# раз в PHYS_SKIP тактов физики с накопленным временем (маршрут тот же, просто реже считается)
const FAR := 30.0
const PHYS_SKIP := 4
var _anim_acc := 0.0
var _phys_acc := 0.0
var _tick := 0
var _seen := true
var _far := false


func setup(m: PaxMod, path: PackedVector3Array, start_i: int, seed_v: int) -> void:
	mod = m
	_path = path
	_i = clampi(start_i, 0, path.size() - 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_speed = SPEED * rng.randf_range(0.8, 1.25)
	_dir = 1 if rng.randf() < 0.5 else -1
	npc_name = NAMES[rng.randi() % NAMES.size()]
	role = ROLES[rng.randi() % ROLES.size()]
	temper = TEMPERS[rng.randi() % TEMPERS.size()]
	relation = rng.randi_range(35, 65)
	_prompt = Label3D.new()                           # «E — поговорить», когда герой рядом (location.gd → show_prompt)
	_prompt.text = "E · " + npc_name
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.font_size = 40
	_prompt.outline_size = 10
	_prompt.pixel_size = 0.004
	_prompt.position = Vector3(0.0, 1.55, 0.0)
	_prompt.no_depth_test = true
	_prompt.modulate = Color(1.0, 0.9, 0.75)
	_prompt.visible = false
	add_child(_prompt)
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
	_model = Assets.model(mod, DIR + "goblin_rigged.glb")
	if _model == null:
		return
	_model.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)
	add_child(_model)
	for g: Node in _model.find_children("*", "GeometryInstance3D", true, false):   # дальше 80 м жителя не видно в дымке
		(g as GeometryInstance3D).visibility_range_end = 80.0
		(g as GeometryInstance3D).visibility_range_end_margin = 5.0
	Assets.track(DIR + "goblin_rigged.glb", _model)
	_anim = _find(_model)
	if _anim != null:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # ведёт _process (LOD)
	if _anim != null:
		var lib: AnimationLibrary = _anim.get_animation_library("") if _anim.has_animation_library("") else AnimationLibrary.new()
		for clip: String in ["walk", "idle"]:
			var src := Assets.model(mod, DIR + clip + ".glb")
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
	_tick += 1
	_phys_acc += delta
	if _seen or _tick % PHYS_SKIP == get_instance_id() % PHYS_SKIP:   # за кадром — реже, такты разнесены по жителям
		_phys(_phys_acc)
		_phys_acc = 0.0
	Prof.add("NPC", t0)


func _process(delta: float) -> void:
	if _anim == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := global_position + Vector3(0.0, 0.6, 0.0)
		_seen = true                                    # шар 1 м вокруг жителя хоть краем в кадре — виден
		var fr := Engine.get_process_frames()
		if fr != _fr_frame:                             # пирамида камеры — одна на кадр для всех жителей (раньше
			_fr_frame = fr                              # каждый житель собирал свой массив плоскостей)
			_frustum = cam.get_frustum()
		for pl: Plane in _frustum:
			if pl.distance_to(p) > 1.0:
				_seen = false
				break
		_far = p.distance_to(cam.global_position) > FAR
		if _model != null and _model.visible != _seen:
			_model.visible = _seen                      # вне кадра не рисуется совсем (и тень не считается)
	_anim_acc += delta
	if not _seen:
		return                                          # за кадром поза не нужна; время копится — шаг не дёрнется
	if _far and _anim_acc < 1.0 / 15.0:
		return
	_anim.advance(minf(_anim_acc, 0.5))
	_anim_acc = 0.0


const _foot_off := 0.0               # начало тела — у ступней (капсула поднята на 0.55)
var _ground_t := 0.0
var _ground_y := 0.1
var _block_t := 0.0


## Высота земли под жителем (пандусы и ступени): один луч вниз.
func _probe_ground() -> void:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var p := global_position
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 0), p - Vector3(0, 3.0, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_ground_y = (hit.position as Vector3).y + _foot_off
	else:
		_ground_y = p.y


## Впереди на шаг кто-то стоит (герой, другой житель, телега) — луч на уровне груди.
func _blocked(d: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return false
	var p := global_position + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(p, p + d * 0.7)
	q.exclude = [get_rid()]
	return not space.intersect_ray(q).is_empty()


static var _frustum: Array[Plane] = []
static var _fr_frame := -1


var _giver: Label3D


## Над жителем, давшим задание, — золотой ❖ с именем (видно издалека, quest.gd).
func set_giver(on: bool) -> void:
	if on and _giver == null:
		_giver = Label3D.new()
		_giver.text = "❖ " + npc_name
		_giver.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_giver.font_size = 56
		_giver.outline_size = 12
		_giver.pixel_size = 0.004
		_giver.position = Vector3(0.0, 1.9, 0.0)
		_giver.modulate = Color(1.0, 0.8, 0.35)
		add_child(_giver)
	if _giver != null:
		_giver.visible = on


func show_prompt(on: bool) -> void:
	if _prompt != null and _prompt.visible != on:
		_prompt.visible = on


## Житель на месте (убранство улиц, location.gd): лицом по yaw (рад), своё ремесло, рост (хобгоблин-стражник крупнее).
func stand(yaw: float, as_role: String, size := 1.0) -> void:
	if as_role != "":
		role = as_role
	if _model != null:
		_model.rotation.y = yaw
		_model.scale = Vector3.ONE * size
	_play("idle")


## Разговор: стоит и смотрит на героя (look — куда).
func talk(on: bool, look := Vector3.ZERO) -> void:
	talking = on
	if on:
		show_prompt(false)
		_play("idle")
		if _model != null:
			var d := look - global_position
			_model.rotation.y = atan2(d.x, d.z)


## Настроение ответа (talk.gd): пока — только отношение; позы под настроение — когда будут клипы.
func react(_mood: String) -> void:
	pass


func _phys(delta: float) -> void:
	if talking:
		velocity = Vector3.ZERO
		return
	if _path.size() < 2:                              # стоит на посту (стража, зазывала, караванщик) — покой
		_play("idle")
		return
	# кинематика, как у толп в больших играх: позиция — напрямую по маршруту, без move_and_slide (полный расчёт
	# столкновений на каждого жителя каждый такт). Земля — луч вниз раз в 0.2 с, «упёрся» — луч вперёд раз в 0.25 с.
	_ground_t -= delta
	if _ground_t <= 0.0:
		_ground_t = 0.2
		_probe_ground()
	if absf(global_position.y - _ground_y) > 0.002:
		global_position.y = move_toward(global_position.y, _ground_y, delta * 6.0)
	velocity = Vector3.ZERO
	if _wait > 0.0:
		_wait -= delta
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
	_block_t -= delta
	if _block_t <= 0.0:
		_block_t = 0.25
		if _blocked(d):                              # упёрся (в героя, в соседа) — постоять, потом назад
			_stuck += 1
			_wait = 0.8
			if _stuck >= 3:
				_stuck = 0
				_dir = -_dir
				_i = clampi(_i + _dir, 0, _path.size() - 1)
			return
		_stuck = 0
	global_position += Vector3(d.x, 0.0, d.z) * _speed * delta
	_play("walk")
	if _model != null:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(d.x, d.z), minf(1.0, delta * 6.0))
