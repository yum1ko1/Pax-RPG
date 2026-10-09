extends RefCounted
## Герой локации: модель (config/hero.json → models/*.glb) и её состояние — меч на спине, в руке или волочится
## по земле в беге, доставание и убирание, комбо из трёх тяжёлых ударов, прыжок, плащ на пружинных костях.
## Удары ведёт root motion (смещение таза вынуто при сборке — pax_rpg/dev/blender/knight/*.py → *_anim.json):
## инерция меча тянет персонажа. Удар без продолжения кончается сразу после взмаха и плавно уходит в стойку.
## location.gd каждый кадр зовёт tick() и двигает CharacterBody3D по тому, что тот вернул.

const ATTACKS := ["Attack1", "Attack2", "Attack3"]
const LOOPS := ["Idle", "IdleArmed", "Walk", "Run", "RunArmed", "WalkArmed"]
const ONCE := ["Draw", "Sheathe", "DrawWalk", "SheatheWalk", "Jump", "Attack1", "Attack2", "Attack3", "Dodge",
	"DodgeArmed"]
const ON_THE_GO := ["DrawWalk", "SheatheWalk"]   # меч достают и убирают на ходу — ноги шагают, управление не забрано

var cfg: Dictionary = {}
var meta: Dictionary = {}           # *_anim.json: root_motion, sword_switch, impact, cape
var model: Node3D
var anim: AnimationPlayer
var armed := false
var action := ""                    # разовый клип: Draw / Sheathe / Jump / AttackN; "" — ходьба и стойки
var _queued := false                # удар нажат во время текущего — следующий удар комбо
var _combo_next := ""               # удар кончился — ещё combo_grace с нажатие продолжает комбо этим ударом
var _combo_left := 0.0
var _airborne := false
var _sword_back: Node3D
var _sword_hand: Node3D
var _sword_drag: Node3D            # только как цель: где меч в беге; виден всегда _sword_hand
var _hand_rest := Transform3D.IDENTITY
var _drag_rest := Transform3D.IDENTITY
var _tip := Vector3.ZERO            # остриё в осях меча (из габаритов сетки)
var _drag_w := 0.0                  # 0 — меч в руке как в стойке, 1 — волочится; между — плавный переход
var _on_floor := true
var _sword_q := Quaternion.IDENTITY   # поворот волочащегося меча с отставанием — он тяжёлый
var _sword_lag := false
var _prev_off := Vector2.ZERO       # root motion: смещение клипа на прошлом кадре
var _swing: AudioStreamPlayer       # свист меча (sounds/swing_*.wav)
var _impact: AudioStreamPlayer      # удар о землю (sounds/impact_*.wav)
var _swing_done := false
var _impact_done := false
var _skel: Skeleton3D
var _cloth: SoftBody3D              # плащ — ткань (models/*_cape.glb), пришита к груди, бьётся о тело
var _cloth_anchors: Array = []      # [Node3D, кость] — грудь и плечи в мире, к ним пришит верх плаща
var _cloth_pin_left := 0            # кадров до пришивания (тело ткани создаёт сервер физики не сразу)
var _colliders: Array = []          # [AnimatableBody3D, кость от, кость до] — капсулы тела для ткани
var _trail_mesh: ImmediateMesh      # след взмаха — видно, куда достаёт меч
var _trail_mat: StandardMaterial3D
var _trail: Array = []              # [время, у гарды, остриё]
var _clock := 0.0
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
	if _sword_hand != null:
		_hand_rest = _sword_hand.transform
		_tip = _tip_of(_sword_hand)
	if _sword_drag != null:
		_drag_rest = _sword_drag.transform
		_sword_drag.visible = false
	_swing = _player(cfg.get("swing_files", []), _f("swing_pitch_spread", 1.06), _f("swing_volume_db", -4.0))
	_impact = _player(cfg.get("impact_files", []), 1.04, _f("impact_volume_db", 0.0))
	return model


## Остриё: дальняя от хвата точка габаритов сетки меча (в осях узла меча).
static func _tip_of(n: Node3D) -> Vector3:
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi == null:
		for c: Node in n.find_children("*", "MeshInstance3D", true, false):
			mi = c as MeshInstance3D
			break
	if mi == null or mi.mesh == null:
		return Vector3.ZERO
	var box := mi.mesh.get_aabb()
	var to_node := Transform3D.IDENTITY          # сетка в осях меча — по локальным, модель ещё не в дереве
	var c: Node = mi
	while c != n and c is Node3D:
		to_node = (c as Node3D).transform * to_node
		c = c.get_parent()
	var best := Vector3.ZERO
	for i: int in 8:
		var p := to_node * box.get_endpoint(i)
		if p.length() > best.length():
			best = p
	var ax := best.abs().max_axis_index()        # остриё — по длинной оси, посередине ширины
	var tip := Vector3.ZERO
	tip[ax] = best[ax]
	return tip


const CLOTH_LAYER := 1 << 4           # слой капсул тела: с ними сталкивается только ткань


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
func start(owner_body: PhysicsBody3D = null) -> void:
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
	_make_cloth(owner_body)
	_make_trail()
	_show_sword(0.0)


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
	return action != "" and action != "Jump" and action not in ON_THE_GO


## Достаёт или убирает меч на ходу — бежать нельзя, только шаг.
func walk_only() -> bool:
	return action in ON_THE_GO


# ---------- плащ: пружинные кости ----------

func _bone_world(idx: int, rest := false) -> Transform3D:
	var t := _skel.get_bone_global_rest(idx) if rest else _skel.get_bone_global_pose(idx)
	var g := _skel.global_transform * t
	return Transform3D(g.basis.orthonormalized(), g.origin)


## Плащ — ткань SoftBody3D из отдельной сетки (поза покоя модели): верхняя полоса пришита к груди, ниже — свободна
## и сталкивается с капсулами тела (таз, бёдра, голени, спина) и с землёй, но не с капсулой персонажа.
func _make_cloth(owner_body: PhysicsBody3D) -> void:
	var cape: Dictionary = meta.get("cape", {})
	var path := str(cape.get("cloth", ""))
	_skel = _find_skeleton(model)
	if path == "" or _skel == null:
		return
	var src := _mod.model(path)
	if src == null:
		return
	var mi: MeshInstance3D = null
	for c: Node in src.find_children("*", "MeshInstance3D", true, false):
		mi = c as MeshInstance3D
		break
	if mi == null or mi.mesh == null:
		src.free()
		return
	var local := Transform3D.IDENTITY
	var n: Node = mi
	while n != src and n is Node3D:
		local = (n as Node3D).transform * local
		n = n.get_parent()
	var mesh := mi.mesh
	src.free()
	var sb := SoftBody3D.new()
	sb.mesh = mesh
	sb.top_level = true
	sb.transform = model.global_transform * local
	sb.collision_layer = 0
	sb.collision_mask = 1 | CLOTH_LAYER
	sb.simulation_precision = int(_f("cape_precision", 6))
	sb.total_mass = _f("cape_mass", 1.2)
	sb.linear_stiffness = _f("cape_stiffness", 0.6)
	sb.damping_coefficient = _f("cape_damping", 0.04)
	sb.drag_coefficient = _f("cape_drag", 0.02)
	sb.pressure_coefficient = 0.0
	model.add_child(sb)
	if owner_body != null:
		sb.add_collision_exception_with(owner_body)
	_cloth = sb
	for bn: Variant in cape.get("pin_bones", ["Spine02", "LeftShoulder", "RightShoulder", "neck"]):
		var bi := _skel.find_bone(str(bn))
		if bi < 0:
			continue
		var an := Node3D.new()
		an.top_level = true
		model.add_child(an)
		an.global_transform = _bone_world(bi, true)    # пришиваем в позе покоя — как сетка
		_cloth_anchors.append([an, bi])
	if _cloth_anchors.is_empty():
		return
	_cloth_pin_left = 1
	for d: Array in [["Hips", "Spine01", 0.17], ["Spine01", "Spine02", 0.17], ["Spine02", "neck", 0.15],
			["LeftUpLeg", "LeftLeg", 0.1], ["RightUpLeg", "RightLeg", 0.1],
			["LeftLeg", "LeftFoot", 0.08], ["RightLeg", "RightFoot", 0.08]]:
		var ia := _skel.find_bone(str(d[0]))
		var ib := _skel.find_bone(str(d[1]))
		if ia < 0 or ib < 0:
			continue
		var body := AnimatableBody3D.new()
		body.top_level = true
		body.sync_to_physics = false
		body.collision_layer = CLOTH_LAYER
		body.collision_mask = 0
		var sh := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var len_ := (_bone_world(ib, true).origin - _bone_world(ia, true).origin).length()
		cap.radius = float(d[2]) * _f("cape_body_scale", 1.0)
		cap.height = len_ + cap.radius * 2.0
		sh.shape = cap
		body.add_child(sh)
		model.add_child(body)
		_colliders.append([body, ia, ib])
	_move_colliders()


## Верх плаща пришивается по всей ширине: сетка делится на полосы по X, в каждой — точки у её верхнего края (верх
## плаща у плеч ниже, чем у шеи: один общий порог пришил бы только середину). Каждая точка — к ближней из костей
## груди, плеч и шеи. Номера точек — как их сваривает сервер физики (одинаковые позиции — одна точка, по порядку).
func _pin_cloth() -> void:
	var cape: Dictionary = meta.get("cape", {})
	var verts: PackedVector3Array = _cloth.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var seen := {}
	var pts := PackedVector3Array()
	for v: Vector3 in verts:
		if not seen.has(v):
			seen[v] = pts.size()
			pts.append(v)
	var strip := _f("cape_pin_strip", 0.05)
	var band := float(cape.get("pin_band", 0.08))
	var tops := {}
	for p: Vector3 in pts:
		var k := int(floor(p.x / strip))
		tops[k] = maxf(float(tops.get(k, -INF)), p.y)
	var to_world := _cloth.global_transform
	var n_pinned := 0
	for i: int in pts.size():
		var p := pts[i]
		if p.y < float(tops[int(floor(p.x / strip))]) - band:
			continue
		var w := to_world * p
		var best: Node3D = null
		var bd := INF
		for an: Array in _cloth_anchors:
			var node: Node3D = an[0]
			var d := node.global_position.distance_to(w)
			if d < bd:
				bd = d
				best = node
		_cloth.set_point_pinned(i, true, _cloth.get_path_to(best))
		n_pinned += 1
	_mod.log_info("Pax RPG: cape pinned %d of %d points" % [n_pinned, pts.size()])


func _move_colliders() -> void:
	for c: Array in _colliders:
		var body: AnimatableBody3D = c[0]
		var a := _bone_world(int(c[1])).origin
		var b := _bone_world(int(c[2])).origin
		var dir := b - a
		if dir.length() < 0.001:
			continue
		body.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir.normalized())), (a + b) * 0.5)


func _cloth_tick() -> void:
	if _cloth == null or not _cloth.is_inside_tree():
		return
	if _cloth_pin_left > 0:
		_cloth_pin_left -= 1
		if _cloth_pin_left == 0:
			_pin_cloth()
		return
	for an: Array in _cloth_anchors:
		(an[0] as Node3D).global_transform = _bone_world(int(an[1]))
	_move_colliders()


## Ткань сама тянется за телом — ветер больше не нужен (оставлено для location.gd).
func cape_wind(_velocity: Vector3) -> void:
	pass


# ---------- след взмаха ----------

func _make_trail() -> void:
	if _sword_hand == null:
		return
	_trail_mesh = ImmediateMesh.new()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = _trail_mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mi)


## Полоса между четвертью клинка и остриём за последние trail_life с — только в ударах и только пока меч летит
## быстро: видно дугу, которую накрывает удар.
func _trail_tick(delta: float) -> void:
	if _trail_mesh == null:
		return
	_clock += delta
	var life := _f("trail_life", 0.2)
	if action in ATTACKS and _sword_hand.visible and _sword_hand.is_inside_tree() and delta > 0.0:
		var g := _sword_hand.global_transform
		var tip := g * _tip
		var base := g * (_tip * 0.25)
		var fast := true
		if not _trail.is_empty():
			var last: Array = _trail[-1]
			fast = (tip - (last[2] as Vector3)).length() / delta > _f("trail_speed", 4.0)
		if fast:
			_trail.append([_clock, base, tip])
	while not _trail.is_empty() and _clock - float((_trail[0] as Array)[0]) > life:
		_trail.pop_front()
	_trail_mesh.clear_surfaces()
	if _trail.size() < 2:
		return
	var col: Array = cfg.get("trail_color", [0.8, 0.45, 1.0])
	var c := Color(float(col[0]), float(col[1]), float(col[2]))
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	for p: Array in _trail:
		var k := clampf(1.0 - (_clock - float(p[0])) / life, 0.0, 1.0)
		_trail_mesh.surface_set_color(Color(c, 0.05 * k))
		_trail_mesh.surface_add_vertex(p[1])
		_trail_mesh.surface_set_color(Color(c, _f("trail_alpha", 0.6) * k * k))
		_trail_mesh.surface_add_vertex(p[2])
	_trail_mesh.surface_end()


# ---------- удар о землю: кольцо и пыль под героем ----------

func _ground_burst() -> void:
	if not model.is_inside_tree():
		return
	var at := model.global_position + Vector3(0.0, 0.03, 0.0)
	var col: Array = cfg.get("trail_color", [0.8, 0.45, 1.0])
	var c := Color(float(col[0]), float(col[1]), float(col[2]))
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.5
	tor.rings = 48
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(c, 0.8)
	ring.material_override = rm
	ring.top_level = true
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(ring)
	ring.global_transform = Transform3D(Basis().scaled(Vector3(1.0, 0.15, 1.0)), at)
	var r := _f("burst_radius", 3.0)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(r, 0.15, r), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(rm, "albedo_color", Color(c, 0.0), 0.45)
	t.chain().tween_callback(ring.queue_free)
	var dust := CPUParticles3D.new()
	dust.top_level = true
	dust.one_shot = true
	dust.explosiveness = 0.95
	dust.amount = 48
	dust.lifetime = 0.8
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = 0.6
	dust.emission_ring_inner_radius = 0.2
	dust.emission_ring_height = 0.05
	dust.direction = Vector3(0.0, 1.0, 0.0)
	dust.spread = 75.0
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 4.5
	dust.gravity = Vector3(0.0, -6.0, 0.0)
	dust.damping_min = 2.0
	dust.damping_max = 4.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	dust.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	q.material = dm
	dust.mesh = q
	dust.color = Color(0.55, 0.5, 0.62, 0.55)
	model.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	dust.finished.connect(dust.queue_free)


# ---------- команды ----------

func toggle_sword(on_floor: bool, moving := false) -> void:
	if anim == null or action != "" or not on_floor:
		return
	var n := "Sheathe" if armed else "Draw"
	if moving and has(n + "Walk"):
		n += "Walk"
	if not has(n):
		armed = not armed
		_show_sword(0.0)
		return
	_play_once(n)


func attack(on_floor: bool) -> void:
	if anim == null or not has("Attack1"):
		return
	if action == "" and on_floor:
		if not armed:
			toggle_sword(on_floor)          # меч за спиной — сперва достать
			return
		if _combo_left > 0.0 and _combo_next != "" and has(_combo_next):
			_play_once(_combo_next, _per("combo_skip", _combo_next, 0.0))   # успел после конца удара
		else:
			_play_once("Attack1")
	elif action in ATTACKS and action != ATTACKS[-1]:
		_queued = true                      # следующий удар — сразу после взмаха этого


## Уворот (Alt): кувырок туда, куда смотрит герой (location.gd разворачивает его по направлению ввода).
## С мечом — свой клип, тяжелее и дальше.
func dodge(on_floor: bool) -> bool:
	if anim == null or not on_floor or action != "":
		return false
	var n := "DodgeArmed" if armed and has("DodgeArmed") else "Dodge"
	if not has(n):
		return false
	_play_once(n)
	return true


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
	anim.speed_scale = _per("attack_speed", n, 1.0) if n in ATTACKS else _per("clip_speed", n, 1.0)
	anim.play(n, _per("blend_in", n, 0.15))
	if skip > 0.0:
		anim.seek(skip, true)
		_prev_off = _root_at(skip)


func _on_finished(n: StringName) -> void:
	if String(n) == action:
		_end_action()


func _end_action() -> void:
	if action.begins_with("Draw"):
		armed = true
	elif action.begins_with("Sheathe"):
		armed = false
	var i := ATTACKS.find(action)
	if i >= 0 and i + 1 < ATTACKS.size():
		_combo_next = ATTACKS[i + 1]
		_combo_left = _f("combo_grace", 0.45)
	else:
		_combo_left = 0.0
	action = ""


func _pos() -> float:
	return anim.current_animation_position if anim != null and anim.current_animation != "" else 0.0


func _frac() -> float:
	if anim == null or anim.current_animation == "":
		return 1.0
	return _pos() / maxf(anim.current_animation_length, 0.001)


# ---------- кадр ----------

## Возвращает {"root": Vector3 — смещение за кадр в осях модели (модель смотрит на +Z)}.
func tick(delta: float, moving: bool, speed: float, running: bool, on_floor: bool) -> Dictionary:
	var out := {"root": Vector3.ZERO}
	if anim == null:
		return out
	_combo_left = maxf(0.0, _combo_left - delta)
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
	if action in ATTACKS:
		# прыжок удара (air: [с, по, во сколько медленнее]) — герой дольше висит в воздухе
		var air: Variant = (cfg.get("air", {}) as Dictionary).get(action, [])
		if air is Array and (air as Array).size() == 3:
			var t := _pos()
			var a0 := float(air[0])
			var a1 := float(air[1])
			var k := smoothstep(a0, a0 + 0.12, t) * (1.0 - smoothstep(a1 - 0.12, a1, t))
			anim.speed_scale = _per("attack_speed", action, 1.0) * lerpf(1.0, float(air[2]), k)
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
	_on_floor = on_floor
	_show_sword(delta)
	_trail_tick(delta)
	_cloth_tick()
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
		var bl := _f("blend_loop", 0.3)
		if want == "RunArmed" or anim.current_animation == "RunArmed":
			bl = _f("blend_run_armed", 0.5)      # рука с мечом уходит вниз-назад — не рывком
		anim.play(want, bl)
	anim.speed_scale = clampf(speed / stride, 0.5, 2.0) if moving else 1.0


func _sounds() -> void:
	var peaks: Dictionary = cfg.get("swing_peaks", {})
	var base := action.trim_suffix("Walk")
	if _swing != null and not _swing_done and peaks.has(base) \
			and _pos() >= float(peaks[base]) - _f("swing_lead", 0.55):
		_swing_done = true
		_swing.volume_db = _f("swing_volume_db", -4.0) + (0.0 if action in ATTACKS else -6.0)
		_swing.play()
	var imp: Dictionary = meta.get("impact", {})
	if _impact != null and not _impact_done and imp.has(action) \
			and _pos() >= float(imp[action]) - _f("impact_lead", 0.05) * anim.speed_scale:
		_impact_done = true
		_impact.play()
		_ground_burst()


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


## Меч там, где он сейчас: на спине или в руке. В беге он плавно перекладывается в «волочится» (цель — узел
## Sword_Drag) и в любом клипе не уходит в землю: если остриё ниже пола — меч поворачивается на хвате вверх.
func _show_sword(delta: float) -> void:
	if _sword_back == null or _sword_hand == null:
		return
	var sw: Dictionary = meta.get("sword_switch", {})
	var in_hand := armed
	if action.begins_with("Draw"):
		in_hand = _pos() >= float((sw.get("Draw", {}) as Dictionary).get("time", 0.45))
	elif action.begins_with("Sheathe"):
		in_hand = _pos() < float((sw.get("Sheathe", {}) as Dictionary).get("time", 0.9))
	elif action in ATTACKS:
		in_hand = true
	_sword_hand.visible = in_hand
	_sword_back.visible = not in_hand
	if not in_hand:
		_drag_w = 0.0
		return
	var drag := action == "" and anim != null and anim.current_animation == "RunArmed" and _sword_drag != null
	var dur := maxf(0.05, _f("blend_run_armed", 0.5))
	_drag_w = move_toward(_drag_w, 1.0 if drag else 0.0, delta / dur) if delta > 0.0 else (1.0 if drag else 0.0)
	_sword_hand.transform = _hand_rest
	if _drag_w > 0.0 and _sword_drag != null and _sword_drag.is_inside_tree():
		var k := smoothstep(0.0, 1.0, _drag_w)
		var a := _sword_hand.global_transform
		var b := _sword_drag.get_parent_node_3d().global_transform * _drag_rest
		var qa := a.basis.get_rotation_quaternion()
		var qb := b.basis.get_rotation_quaternion()
		var sc := a.basis.get_scale()
		var q := qa.slerp(qb, k)
		if _sword_lag and delta > 0.0:
			if _sword_q.dot(q) < 0.0:
				q = -q
			q = _sword_q.slerp(q, 1.0 - exp(-delta * _f("sword_follow", 7.0)))   # меч догоняет руку с запозданием
		_sword_q = q
		_sword_lag = true
		_sword_hand.global_transform = Transform3D(Basis(q).scaled(sc), a.origin.lerp(b.origin, k))
	else:
		_sword_lag = false
	_keep_above_floor()


func _keep_above_floor() -> void:
	if not _on_floor or _tip == Vector3.ZERO or not _sword_hand.is_inside_tree():
		return
	var g := _sword_hand.global_transform
	var floor_y := model.global_position.y + _f("sword_floor", 0.04)
	var tip := g * _tip
	if tip.y >= floor_y:
		return
	var v := tip - g.origin
	var n := v.length()
	if n < 0.01:
		return
	var vz := clampf((floor_y - g.origin.y) / n, -0.999, 0.999)
	var h := Vector2(v.x, v.z)
	if h.length() < 0.001:
		h = Vector2(0.0, 1.0)
	h = h.normalized() * sqrt(1.0 - vz * vz)
	var v2 := Vector3(h.x, vz, h.y)
	var q := Quaternion(v / n, v2)
	_sword_hand.global_transform = Transform3D(Basis(q) * g.basis, g.origin)
