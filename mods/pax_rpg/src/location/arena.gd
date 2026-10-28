extends Node
## Арена города (центр — config/<город>.json → "arena": [x, z, радиус ямы, сторона главного входа]).
## Пять этапов — фундамент боевой системы (ДИЗДОК — бой): 1) один гоблин — удары и концентрация; 2) двое — блок
## и парирование; 3) трое — несколько целей, переключение захвата мышью; 4) ветеран (блокирует и парирует героя)
## с двумя гоблинами; 5) Гхаррок, орк-чемпион — босс: задержки, финты, удары без парирования, серии, три слома —
## три фазы. Вход в яму — с первого этапа; ←/→ — выбрать любой открытый (arena_stage — сколько открыто).
## После победы решётки поднимаются — можно уйти пешком или начать следующий бой (E); отошёл от ямы — трибуны
## пустеют, выбор снова с первого. Пока идёт бой, время суток стоит (location.gd → daynight.frozen).
## Вход в бой: затемнение и мини-загрузка, на трибунах зрители, выходы закрыты решётками; герой — у южного
## входа, бойцы — напротив. Выход (X) или поражение: затемнение, пустые трибуны, решётки подняты.
## Прогресс — в настройке мода arena_stage (сколько этапов открыто: 0 — только первый).

const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")
const Vfx := preload("res://mods/pax_rpg/src/location/vfx.gd")
const STAGES := [["goblin"], ["goblin", "goblin"], ["goblin", "goblin", "goblin"], ["veteran", "goblin", "goblin"],
	["orc"]]                                    # кто выходит на каждом этапе
const LADDER := [1, 2, 3, 3, 0]               # совместимость: бойцов на этапе (0 — чемпион)
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
## Новая арена Гхарна (models/gharn/central/central_plaza.glb ставит город, pax_rpg/dev/gharn/arena_central.py): пол ямы —
## на уровне земли, вокруг парапет, три яруса трибун и галерея на +1.8 м; проходы в яму — с юга и севера (x = 0).
## Пятое число арены в планировке — глубина пола: 0 — эта арена (старой чаши и выреза в земле нет), иначе — старая яма.
const FLAT_SEATS := [[14.6, 1.34], [15.6, 1.57], [16.6, 1.8]]   # ярусы трибун: радиус, высота
const FLAT_OUT := 27.0                       # куда выходит герой после боя — площадь за южной лестницей
var _depth := DEPTH
var _flat := false
var fighting := false
var last_result := ""                        # чем кончился последний бой: won / lost / left (строка боя в лог)
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
var _pick := 0                                # выбранный этап (0 — первый)


func setup(m: PaxMod, view: Node, ui: Node, arena: Array, player: Node3D, spawn_foe: Callable, heal: Callable) -> void:
	mod = m
	name = "PaxRpgArena"
	center = Vector3(float(arena[0]), 0.0, float(arena[1]))
	pit = float(arena[2])
	_depth = float(arena[4]) if arena.size() >= 5 else DEPTH
	_flat = _depth < 0.5
	if not _flat:
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


## Затемнение с подписью этапа живёт в интерфейсе локации (ui), а не под ареной: уходит вместе с ареной — раньше
## каждый вход в город оставлял на локации ещё один невидимый ColorRect с Label.
func _exit_tree() -> void:
	if is_instance_valid(_fade):
		_fade.queue_free()


## Выбранный этап (0…4).
func stage() -> int:
	return clampi(_pick, 0, STAGES.size() - 1)


## Сколько этапов открыто (последний открытый — индекс).
func unlocked() -> int:
	return clampi(int(mod.get_setting("arena_stage", 0)), 0, STAGES.size() - 1)


## ←/→ в яме: выбрать этап (с первого до последнего открытого).
func pick(d: int) -> void:
	_pick = clampi(_pick + d, 0, unlocked())
	toast.emit(_prompt_text())


func _prompt_text() -> String:
	var t := mod.tr_key("pax_rpg_arena_prompt") % _foe_text(stage())
	if unlocked() > 0:
		t += "  ·  " + mod.tr_key("pax_rpg_arena_pick")
	return t


func _foe_text(i: int) -> String:
	return mod.tr_key("pax_rpg_arena_stage_%d" % (i + 1))


## Каждый кадр (location.gd): подсказки, конец боя.
func tick() -> void:
	if not is_instance_valid(_player) or _busy:
		return
	var dist := Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length()
	var inside := dist < pit and _player.global_position.y < -_depth + (1.0 if _flat else 3.0)   # в яме (на решётке сверху — нет)
	var near := dist < RIM + 6.0 and not inside
	if near and not _near_hint and not fighting:
		toast.emit(mod.tr_key("pax_rpg_arena_way_down"))   # где спуск
	if not near and not inside and _near_hint and not fighting:
		_pick = 0                                    # ушёл от арены — в следующий раз снова с первого этапа
	_near_hint = near
	if inside and not _inside and not fighting:
		toast.emit(_prompt_text())
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
		var south := center + Vector3(0, -_depth + 0.3, pit - 3.0)
		_player.global_position = south
		var far := center + Vector3(0, -_depth + 0.3, -pit * 0.45)
		var who: Array = STAGES[i]
		var n := who.size()
		for k: int in n:
			var off := Vector3((float(k) - (n - 1) * 0.5) * 2.6, 0.0, -absf(float(k) - (n - 1) * 0.5) * 0.9)
			_foes.append(_spawn_foe.call(str(who[k]), far + off))
		for f: Variant in _foes:
			if is_instance_valid(f):
				(f as Goblin).respawns = false
		fighting = true
	_transition(mod.tr_key("pax_rpg_arena_round") % [i + 1, LADDER.size(), _foe_text(i)], begin,
		mod.tr_key("pax_rpg_arena_fight"))


func _win() -> void:
	last_result = "won"
	fighting = false
	_foes.clear()
	var i := stage()
	var last := i >= STAGES.size() - 1
	if not last:
		mod.set_setting("arena_stage", maxi(unlocked(), i + 1))
		_pick = i + 1                                # E — следующий этап
	_open(true)                                        # решётки поднимаются: выход свободен, E — следующий бой
	var txt := mod.tr_key("pax_rpg_arena_champion") if last else (mod.tr_key("pax_rpg_arena_next") % _foe_text(i + 1))
	toast.emit(txt)


## X — покинуть арену; поражение — тоже уход (без потери прогресса).
func leave(lost := false) -> void:
	if _busy or (not fighting and _root.get_child_count() == 0):
		return
	last_result = "lost" if lost else "left"
	var out := func() -> void:
		for f: Variant in _foes:
			if is_instance_valid(f):
				(f as Node).queue_free()
		_foes.clear()
		fighting = false
		_fill_crowd(false)
		_open(true)
		_heal.call()
		_player.global_position = center + (Vector3(0, 0.3, FLAT_OUT) if _flat else Vector3(0, 0.3, RIM + 3.0))   # наверх, за забор
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
	var lib: AnimationLibrary = null                   # одна библиотека на всех зрителей, а не своя у каждого
	if idle != null:
		lib = AnimationLibrary.new()
		lib.add_animation("idle", idle)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1047
	var tiers: Array = FLAT_SEATS if _flat else [[15.3, 0.05], [16.4, 0.05]]   # трибуны (старая яма — обод у забора)
	for ti: int in tiers.size():
		var rr := float(tiers[ti][0])
		var h := float(tiers[ti][1])
		var step := deg_to_rad(9.0 + ti)
		var a := rng.randf_range(0.0, step)
		while a < TAU:
			var deg := fposmod(rad_to_deg(a), 360.0)
			var gap := (minf(deg, 360.0 - deg) > 14.0 and absf(deg - 180.0) > 14.0) if _flat \
				else (absf(deg - 68.0) > 14.0 and absf(deg - 292.0) > 14.0)
			if gap and rng.randf() < 0.6:                  # не в проходах к лестницам
				var g := src.duplicate() as Node3D
				# толпа без теней: ~55 скинов в каскадах солнца стоили дороже всех бойцов арены
				for gi: Node in g.find_children("*", "GeometryInstance3D", true, false):
					(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				g.position = center + Vector3(sin(a) * rr, h, cos(a) * rr)
				g.rotation.y = a + PI                      # лицом к яме
				_crowd.add_child(g)
				var ap2 := _find_anim(g)
				if ap2 != null and lib != null:
					if ap2.has_animation_library(""):
						ap2.remove_animation_library("")
					ap2.add_animation_library("", lib)
					ap2.play("idle")
					ap2.speed_scale = rng.randf_range(0.8, 1.25)
					ap2.seek(rng.randf_range(0.0, 2.0), true)
					ap2.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # Crowd двигает сам
				(_crowd as Crowd).fans.append([g, g.position.y, rng.randf() * TAU, ap2 if lib != null else null])
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
	var spots: Array = []                              # решётки внизу обеих лестниц: [место, ширина]
	if _flat:
		for zs: float in [1.0, -1.0]:                  # проходы парапета — юг и север
			spots.append([center + Vector3(0.0, 0.0, zs * (pit + 0.3)), 4.6])
	else:
		for xs: float in [1.0, -1.0]:
			spots.append([center + Vector3(xs * STX, -DEPTH, ST_BOT - 0.6), 2.6])
	for sp: Array in spots:
		var at: Vector3 = sp[0]
		var gw := float(sp[1])
		var body := StaticBody3D.new()
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(gw, 3.6, 0.5)
		sh.shape = bs
		body.add_child(sh)
		body.position = at + Vector3(0, 1.8, 0)
		_gates.add_child(body)
		var nb := int(round(gw / 0.48)) + 1
		for k: int in nb:                                  # прутья и две перекладины
			var bar := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.045
			cm.height = 3.4
			cm.material = mat
			bar.mesh = cm
			bar.position = at + Vector3(-gw * 0.5 + 0.1 + k * (gw - 0.2) / float(nb - 1), 1.7, 0)
			_gates.add_child(bar)
		for y: float in [0.8, 2.6]:
			var cross := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(gw, 0.12, 0.12)
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
	m.position = center + Vector3(0.0, 0.02, 0.0)       # кольцо мостовой у края — над землёй города, без мерцания
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
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if nm.begins_with("roof") or nm.begins_with("rail") 			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON           # тени тонких прутьев рябят — без них
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
				_lamp_flame(lt)
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
			_lamp_flame(lb)
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
		var d := Assets.dds_tex(mod, "textures/arena/%s_diff.dds" % t[0])
		var n := Assets.dds_tex(mod, "textures/arena/%s_nor.dds" % t[0])
		if d != null:
			sm.albedo_texture = d
		if n != null:
			sm.normal_enabled = true
			sm.normal_texture = n
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


## Толпа: зрители подпрыгивают — каждый в своём ритме. Анимация (скелет и скин) — у трети зрителей за кадр по кругу,
## с тройным шагом: ~55 скинов каждый кадр стоили несколько мс, а для покачивания на месте 20 Гц хватает.
class Crowd extends Node3D:
	var fans: Array = []
	var _t := 0.0
	var _phase := 0

	func _process(delta: float) -> void:
		_t += delta
		var cam := get_viewport().get_camera_3d()          # толпу дальше 70 м не качаем — подскок 12 см не виден
		if cam != null and cam.global_position.distance_squared_to(global_position) > 4900.0:
			return
		_phase = (_phase + 1) % 3
		for i: int in fans.size():
			var f: Array = fans[i]
			var n: Node3D = f[0]
			if not is_instance_valid(n):
				continue
			n.position.y = float(f[1]) + maxf(0.0, sin(_t * 5.0 + float(f[2]))) * 0.12
			if i % 3 == _phase and f[3] != null:
				(f[3] as AnimationPlayer).advance(delta * 3.0)


## Огонёк в каменном фонаре (сердцевина фонаря сплошная — огонь выдвинут к камере, как в городе).
var _vfx: Vfx
func _lamp_flame(lamp: Node3D) -> void:
	if _vfx == null:
		_vfx = Vfx.new(mod)
	_vfx.flame(lamp, Vector3(0, 1.19, 0), 0.3, 0.22)
