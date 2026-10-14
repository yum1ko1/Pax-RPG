extends Node
## Арена города (центр — config/<город>.json → "arena": [x, z, радиус ямы, сторона главного входа]).
## Лестница боёв: 1 гоблин → 2 → 3 → 5 → Гхаррок, чемпион арены. После победы решётки поднимаются — можно уйти
## пешком или начать следующий бой (E); отошёл от ямы — трибуны пустеют. Пока идёт бой, время суток стоит
## (location.gd → daynight.frozen).
## Вход в бой: затемнение и мини-загрузка, на трибунах зрители, выходы закрыты решётками; герой — у южного
## входа, бойцы — напротив. Выход (X) или поражение: затемнение, пустые трибуны, решётки подняты.
## Прогресс — в настройке мода arena_stage (сколько ступеней пройдено).

const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")
const LADDER := [1, 2, 3, 5, 0]               # гоблинов в бою; 0 — чемпион
const CROWD_DIR := "models/goblin/"
const ORC := "orc"
const GOBLIN := "goblin"

signal toast(text: String)

var mod: PaxMod
var center := Vector3.ZERO
var pit := 13.5
var fighting := false
var _root: Node3D                             # трибуны со зрителями, решётки
var _crowd: Node3D
var _gates: Node3D
var _foes: Array = []
var _player: Node3D
var _spawn_foe: Callable                      # (kind: "goblin" | "orc", pos: Vector3) -> Node
var _heal: Callable                           # () -> void
var _fade: ColorRect
var _fade_label: Label
var _busy := false
var _inside := false


func setup(m: PaxMod, view: Node, ui: Node, arena: Array, player: Node3D, spawn_foe: Callable, heal: Callable) -> void:
	mod = m
	name = "PaxRpgArena"
	center = Vector3(float(arena[0]), 0.0, float(arena[1]))
	pit = float(arena[2])
	_player = player
	_spawn_foe = spawn_foe
	_heal = heal
	_root = Node3D.new()
	_root.name = "ArenaStage"
	view.add_child(_root)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(_fade)
	_fade_label = Label.new()
	_fade_label.set_anchors_preset(Control.PRESET_CENTER)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.add_theme_font_size_override("font_size", 34)
	_fade_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.92, 0.0))
	_fade.add_child(_fade_label)


func stage() -> int:
	return clampi(int(mod.get_setting("arena_stage", 0)), 0, LADDER.size() - 1)


func _foe_text(i: int) -> String:
	var n: int = LADDER[i]
	return mod.tr_key("pax_rpg_orc") if n == 0 else mod.tr_key("pax_rpg_arena_goblins_n") % n


## Каждый кадр (location.gd): подсказки, конец боя.
func tick() -> void:
	if not is_instance_valid(_player) or _busy:
		return
	var inside := Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length() < pit
	if inside and not _inside and not fighting:
		toast.emit(mod.tr_key("pax_rpg_arena_prompt") % _foe_text(stage()))
	_inside = inside
	if not fighting:
		if _crowd != null and not inside and Vector2(_player.global_position.x - center.x,
				_player.global_position.z - center.z).length() > pit + 4.0:
			_fill_crowd(false)                         # ушёл после победы — представление окончено
		return
	for f: Variant in _foes:
		if is_instance_valid(f) and not (f as Goblin).dead:
			return
	_win()


## E: вызов (в яме, без боя).
func can_start() -> bool:
	return _inside and not fighting and not _busy


func start() -> void:
	var i := stage()
	var begin := func() -> void:
		_open(false)
		_fill_crowd(true)
		_heal.call()
		var south := center + Vector3(0, 0.2, pit - 2.5)
		_player.global_position = south
		var far := center + Vector3(0, 0.2, -pit * 0.5)
		var n: int = LADDER[i]
		if n == 0:
			_foes.append(_spawn_foe.call(ORC, far))
		else:
			for k: int in n:
				var off := Vector3((float(k) - (n - 1) * 0.5) * 2.4, 0.0, -absf(float(k) - (n - 1) * 0.5) * 0.8)
				_foes.append(_spawn_foe.call(GOBLIN, far + off))
		for f: Variant in _foes:
			if is_instance_valid(f):
				(f as Goblin).respawns = false
		fighting = true
	_transition(mod.tr_key("pax_rpg_arena_round") % [i + 1, LADDER.size(), _foe_text(i)], begin,
		mod.tr_key("pax_rpg_arena_fight"))


func _win() -> void:
	fighting = false
	_foes.clear()
	var i := stage()
	var last := i >= LADDER.size() - 1
	if not last:
		mod.set_setting("arena_stage", i + 1)
	_open(true)                                        # решётки поднимаются: выход свободен, E — следующий бой
	var txt := mod.tr_key("pax_rpg_arena_champion") if last else (mod.tr_key("pax_rpg_arena_next") % _foe_text(i + 1))
	toast.emit(txt)


## X — покинуть арену; поражение — тоже уход (без потери прогресса).
func leave(lost := false) -> void:
	if _busy or (not fighting and _root.get_child_count() == 0):
		return
	var out := func() -> void:
		for f: Variant in _foes:
			if is_instance_valid(f):
				(f as Node).queue_free()
		_foes.clear()
		fighting = false
		_fill_crowd(false)
		_open(true)
		_heal.call()
		_player.global_position = center + Vector3(0, 0.2, pit + 7.0)
	_transition(mod.tr_key("pax_rpg_arena_lost" if lost else "pax_rpg_arena_leave"), out, "")


func in_show() -> bool:
	return fighting or (_crowd != null and _crowd.visible)


## Затемнение: 0.45 с в чёрное, подпись, смена сцены в темноте, 0.6 с обратно.
func _transition(text: String, middle: Callable, after: String) -> void:
	_busy = true
	_fade_label.text = text
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45)
	tw.parallel().tween_property(_fade_label, "theme_override_colors/font_color:a", 1.0, 0.45)
	tw.tween_callback(middle)
	tw.tween_interval(0.9)
	tw.tween_property(_fade_label, "theme_override_colors/font_color:a", 0.0, 0.3)
	tw.tween_property(_fade, "color:a", 0.0, 0.6)
	tw.tween_callback(func() -> void:
		_busy = false
		_inside = Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length() < pit
		if after != "":
			toast.emit(after))


## Зрители на трёх ярусах трибун (лицом к яме), кроме проходов; покачиваются в такт — «живая» толпа.
func _fill_crowd(on: bool) -> void:
	if not on:
		if _crowd != null:
			_crowd.queue_free()
			_crowd = null
		return
	if _crowd != null:
		return
	_crowd = Crowd.new()
	_root.add_child(_crowd)
	var src := Assets.model(mod, CROWD_DIR + "goblin_rigged.glb")
	if src == null:
		return
	var anim_src := Assets.model(mod, CROWD_DIR + "idle.glb")
	var idle: Animation = null
	if anim_src != null:
		var ap := _find_anim(anim_src)
		if ap != null and ap.get_animation_list().size() > 0:
			idle = ap.get_animation(ap.get_animation_list()[0]).duplicate()
			idle.loop_mode = Animation.LOOP_LINEAR
		anim_src.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1047
	var tiers := [[14.85, 0.7], [15.95, 1.4], [17.05, 2.1]]
	for ti: int in tiers.size():
		var rr := float(tiers[ti][0])
		var h := float(tiers[ti][1])
		var step := deg_to_rad(9.0 + ti)
		var a := rng.randf_range(0.0, step)
		while a < TAU:
			var deg := fposmod(rad_to_deg(a), 360.0)
			if absf(fposmod(deg + 180.0, 360.0) - 180.0) > 12.0 and absf(deg - 180.0) > 12.0 and rng.randf() < 0.6:
				var g := src.duplicate() as Node3D
				g.position = center + Vector3(sin(a) * rr, h, cos(a) * rr)
				g.rotation.y = a + PI                      # лицом к яме
				g.scale = Vector3.ONE * rng.randf_range(0.85, 1.1)
				_crowd.add_child(g)
				var ap2 := _find_anim(g)
				if ap2 != null and idle != null:
					var lib := AnimationLibrary.new()
					lib.add_animation("idle", idle)
					if ap2.has_animation_library(""):
						ap2.remove_animation_library("")
					ap2.add_animation_library("", lib)
					ap2.play("idle")
					ap2.speed_scale = rng.randf_range(0.8, 1.25)
					ap2.seek(rng.randf_range(0.0, 2.0), true)
				(_crowd as Crowd).fans.append([g, g.position.y, rng.randf() * TAU])
			a += step * rng.randf_range(0.8, 1.2)
	src.free()


## Решётки в проходах (север, юг): закрыты — коллизия и прутья; открыты — нет ничего.
func _open(on: bool) -> void:
	if on:
		if _gates != null:
			_gates.queue_free()
			_gates = null
		return
	if _gates != null:                                 # уже закрыты (после победы — следующий бой)
		return
	_gates = Node3D.new()
	_root.add_child(_gates)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.14, 0.15)
	mat.metallic = 0.8
	mat.roughness = 0.45
	for zs: float in [1.0, -1.0]:
		var at := center + Vector3(0, 0, zs * (pit + 0.4))
		var body := StaticBody3D.new()
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(7.0, 3.6, 0.5)
		sh.shape = bs
		body.add_child(sh)
		body.position = at + Vector3(0, 1.8, 0)
		_gates.add_child(body)
		for k: int in 15:                                  # прутья и две перекладины
			var bar := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.045
			cm.height = 3.4
			cm.material = mat
			bar.mesh = cm
			bar.position = at + Vector3(-3.3 + k * 0.47, 1.7, 0)
			_gates.add_child(bar)
		for y: float in [0.8, 2.6]:
			var cross := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(6.9, 0.12, 0.12)
			bm.material = mat
			cross.mesh = bm
			cross.position = at + Vector3(0, y, 0)
			_gates.add_child(cross)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c: Node in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


## Толпа: зрители подпрыгивают — каждый в своём ритме.
class Crowd extends Node3D:
	var fans: Array = []
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		for f: Array in fans:
			var n: Node3D = f[0]
			if is_instance_valid(n):
				n.position.y = float(f[1]) + maxf(0.0, sin(_t * 5.0 + float(f[2]))) * 0.12
