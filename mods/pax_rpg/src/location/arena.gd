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
const DEPTH := 4.0                            # пол ямы ниже земли (models/gharn/arena_pit.glb, pax_rpg/dev — bl_arena.py)
const STX := 12.3                             # лестницы: хорды у стены при x = ±STX, верх у z = +5, низ у z = −4
const ST_TOP := 5.0
const ST_BOT := -4.0
const RIM := 17.5
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
var _near_hint := false


func setup(m: PaxMod, view: Node, ui: Node, arena: Array, player: Node3D, spawn_foe: Callable, heal: Callable) -> void:
	mod = m
	name = "PaxRpgArena"
	center = Vector3(float(arena[0]), 0.0, float(arena[1]))
	pit = float(arena[2])
	_build_bowl.call_deferred(view)
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
	var dist := Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length()
	var inside := dist < pit and _player.global_position.y < -1.0      # в яме (на решётке сверху — нет)
	var near := dist < RIM + 6.0 and not inside
	if near and not _near_hint and not fighting:
		toast.emit(mod.tr_key("pax_rpg_arena_way_down"))   # где спуск
	_near_hint = near
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
		var south := center + Vector3(0, -DEPTH + 0.3, pit - 3.0)
		_player.global_position = south
		var far := center + Vector3(0, -DEPTH + 0.3, -pit * 0.45)
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
		_player.global_position = center + Vector3(0, 0.3, RIM + 3.0)   # наверх, за забор
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
	var tiers := [[15.3, 0.05], [16.4, 0.05]]                      # на ободе у забора, смотрят вниз сквозь решётку
	for ti: int in tiers.size():
		var rr := float(tiers[ti][0])
		var h := float(tiers[ti][1])
		var step := deg_to_rad(9.0 + ti)
		var a := rng.randf_range(0.0, step)
		while a < TAU:
			var deg := fposmod(rad_to_deg(a), 360.0)
			if absf(deg - 68.0) > 14.0 and absf(deg - 292.0) > 14.0 and rng.randf() < 0.6:   # не в проходах к лестницам
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
	for xs: float in [1.0, -1.0]:                      # решётки внизу обеих лестниц
		var at := center + Vector3(xs * STX, -DEPTH, ST_BOT - 0.6)
		var body := StaticBody3D.new()
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.6, 3.6, 0.5)
		sh.shape = bs
		body.add_child(sh)
		body.position = at + Vector3(0, 1.8, 0)
		_gates.add_child(body)
		for k: int in 6:                                   # прутья и две перекладины
			var bar := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.045
			cm.height = 3.4
			cm.material = mat
			bar.mesh = cm
			bar.position = at + Vector3(-1.2 + k * 0.48, 1.7, 0)
			_gates.add_child(bar)
		for y: float in [0.8, 2.6]:
			var cross := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.6, 0.12, 0.12)
			bm.material = mat
			cross.mesh = bm
			cross.position = at + Vector3(0, y, 0)
			_gates.add_child(cross)


## Чаша арены: модель (пол, стена, обод, лестницы, забор, решётка на уровне земли), материалы — текстуры арены (DDS),
## коллизия — по сетке; под ступенями — невидимые пандусы (шагом по ступеням 0.4 м герой не поднимется).
func _build_bowl(view: Node) -> void:
	if not is_instance_valid(view):
		return
	var m := Assets.model(mod, "models/gharn/arena_pit.glb")
	if m == null:
		mod.log_warning("Pax RPG arena: no models/gharn/arena_pit.glb")
		return
	m.position = center
	view.add_child(m)
	for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		var nm := String(g.name)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		if nm.begins_with("grate_col"):
			cs.shape = g.mesh.create_trimesh_shape()   # по решётке ходят; сама плоскость не рисуется
			g.visible = false
		elif nm.begins_with("stairs") or nm.begins_with("roof") or nm.begins_with("edge"):
			cs.shape = null
		else:
			cs.shape = g.mesh.create_trimesh_shape()
		if cs.shape != null:
			body.add_child(cs)
			g.add_child(body)
		var key := ""                                     # материал — по имени части (имена материалов glb не доходят)
		for pair: Array in [["floor", "arena_sand"], ["wall", "arena_wall"], ["rim", "arena_seat"], ["stairs", "arena_wall"],
				["edge", "arena_seat"],
				["fence", "wood"], ["roof", "iron"], ["rail", "iron"]]:
			if nm.begins_with(str(pair[0])):
				key = str(pair[1])
		for si: int in g.mesh.get_surface_count():
			var mat := _bowl_mat(key)
			if mat != null:
				g.set_surface_override_material(si, mat)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for xs: float in [1.0, -1.0]:                      # каменные фонари у проходов к лестницам — спуск видно издалека
		var dir := Vector3(xs * STX, 0.0, ST_TOP).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		for k: float in [-1.0, 1.0]:
			var lt := Assets.model(mod, "models/gharn/props/stone_lantern.glb")
			if lt != null:
				lt.position = center + dir * (RIM + 0.6) + side * k * 1.8
				view.add_child(lt)
				var ol := OmniLight3D.new()
				ol.light_color = Color(1.0, 0.7, 0.4)
				ol.light_energy = 0.8
				ol.omni_range = 5.0
				ol.light_volumetric_fog_energy = 0.0
				ol.position = Vector3(0, 1.2, 0)
				lt.add_child(ol)
	for xs: float in [1.0, -1.0]:                      # фонари внизу у лестниц — видно глубину ямы
		var lb := Assets.model(mod, "models/gharn/props/stone_lantern.glb")
		if lb != null:
			lb.position = center + Vector3(xs * (STX - 1.9), -DEPTH, ST_BOT - 0.9)
			view.add_child(lb)
			var ol2 := OmniLight3D.new()
			ol2.light_color = Color(1.0, 0.62, 0.32)
			ol2.light_energy = 1.4
			ol2.omni_range = 7.0
			ol2.light_volumetric_fog_energy = 0.0
			ol2.position = Vector3(0, 1.2, 0)
			lb.add_child(ol2)
	var run := ST_TOP - ST_BOT
	for xs: float in [1.0, -1.0]:
		var ramp := StaticBody3D.new()
		var rs := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = Vector3(2.2, 0.2, sqrt(run * run + DEPTH * DEPTH))
		rs.shape = rb
		ramp.add_child(rs)
		ramp.transform = Transform3D(Basis(Vector3.RIGHT, -atan2(DEPTH, run)),
			center + Vector3(xs * STX, -DEPTH * 0.5 - 0.05, (ST_TOP + ST_BOT) * 0.5))
		view.add_child(ramp)


var _bowl_mats := {}


func _bowl_mat(key: String) -> Material:
	if _bowl_mats.has(key):
		return _bowl_mats[key]
	var sm := StandardMaterial3D.new()
	sm.roughness = 0.92
	var tex := {"arena_sand": ["dense_sand", 0.22], "arena_wall": ["japanese_stone_wall", 0.33],
		"arena_seat": ["large_sandstone_blocks", 0.4]}
	if tex.has(key):
		var t: Array = tex[key]
		var d := Assets._dds(mod, "textures/arena/%s_diff.dds" % t[0])
		var n := Assets._dds(mod, "textures/arena/%s_nor.dds" % t[0])
		if d != null:
			sm.albedo_texture = ImageTexture.create_from_image(d)
		if n != null:
			sm.normal_enabled = true
			sm.normal_texture = ImageTexture.create_from_image(n)
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_scale = Vector3.ONE * float(t[1])
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	elif key == "wood":
		var wt := mod.texture("models/gharn/tex/ground.jpg")
		sm.albedo_color = Color(0.45, 0.32, 0.22)
		if wt != null:
			sm.albedo_texture = wt
			sm.uv1_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.8
	elif key == "iron":
		sm.albedo_color = Color(0.14, 0.13, 0.14)
		sm.metallic = 0.85
		sm.roughness = 0.5
	else:
		_bowl_mats[key] = null
		return null
	_bowl_mats[key] = sm
	return sm


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
