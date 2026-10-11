extends RefCounted
## Герой локации: модель (config/hero.json → models/*.glb) и её состояние — меч на спине, в руке или волочится
## по земле в беге, доставание и убирание, комбо из трёх тяжёлых ударов, прыжок, увороты; надетые вещи (плащ-ткань).
## Удары ведёт root motion (смещение таза вынуто при сборке — pax_rpg/dev/blender/knight/*.py → *_anim.json):
## инерция меча тянет персонажа. Удар без продолжения кончается сразу после взмаха и плавно уходит в стойку.
## location.gd каждый кадр зовёт tick() и двигает CharacterBody3D по тому, что тот вернул.

const ATTACKS := ["Attack1", "Attack2", "Attack3"]
const LOOPS := ["Idle", "IdleArmed", "Walk", "Run", "RunArmed", "WalkArmed", "GuardStrafeL", "GuardStrafeR",
	"GuardBack", "StrafeL", "StrafeR", "WalkBack", "Block", "BlockWalkF", "BlockWalkB", "BlockWalkL", "BlockWalkR"]
const ONCE := ["Draw", "Sheathe", "DrawWalk", "SheatheWalk", "Jump", "Attack1", "Attack2", "Attack3", "Dodge",
	"DodgeArmed", "Hurt", "Parry", "Deathblow"]
const ON_THE_GO := ["DrawWalk", "SheatheWalk"]   # меч достают и убирают на ходу — ноги шагают, управление не забрано

var cfg: Dictionary = {}
var meta: Dictionary = {}           # *_anim.json: root_motion, sword_switch, impact, cape
var model: Node3D
var anim: AnimationPlayer
var armed := false
var move_dir := Vector2.ZERO        # куда идём в осях героя (x — вправо, y — вперёд): location.gd ставит перед tick
var blocking := false               # держит блок (ПКМ)
var _block_t := 0.0                 # с, сколько держит блок: в начале — окно парирования
var _dir_sector := "F"              # направление шага (F/B/L/R) — с запасом, чтобы клипы не дёргались на диагонали
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
var _hit_done := false              # удар этого взмаха уже нанесён (tick вернул hit)
var _skel: Skeleton3D
var _owner_body: PhysicsBody3D       # капсула персонажа — с ней ткань не сталкивается
var _items: Dictionary = {}          # config/items.json → items: что вообще можно надеть
var _worn: Dictionary = {}           # слот → надетый предмет (см. equip)
var _last_in_slot: Dictionary = {}   # слот → что в нём было — «C» надевает обратно
var _colliders: Array = []           # [AnimatableBody3D, кость от, кость до] — капсулы тела для тканей
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
	var old_cape := model.find_child("Knight_cape", true, false)   # плащ модели снят — плащ теперь вещь (items.json)
	if old_cape != null:
		old_cape.get_parent().remove_child(old_cape)
		old_cape.free()
	_sword_back = model.find_child("Sword_Back", true, false) as Node3D
	_sword_hand = model.find_child("Sword_Hand", true, false) as Node3D
	_sword_drag = model.find_child("Sword_Drag", true, false) as Node3D
	if _sword_hand != null:
		_hand_rest = _sword_hand.transform
		_tip = _tip_of(_sword_hand)
	if _sword_drag != null:
		_drag_rest = _sword_drag.transform
		_sword_drag.visible = false
	var ip: Variant = JSON.parse_string(mod.read_text(str(cfg.get("items", "config/items.json"))))
	if ip is Dictionary:
		_items = (ip as Dictionary).get("items", {})
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
	_skel = _find_skeleton(model)
	_owner_body = owner_body
	for id: Variant in cfg.get("equipped", []):
		equip(str(id))
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
	return action != "" and action != "Jump" and action != "Hurt" and action not in ON_THE_GO


## Достаёт или убирает меч на ходу — бежать нельзя, только шаг.
func walk_only() -> bool:
	return action in ON_THE_GO


# ---------- предметы: надеть / снять ----------
# Предмет (config/items.json) сделан в позе покоя модели героя, в её осях. Виды:
#   cloth — ткань SoftBody3D (плащ): верх пришит к костям pin_bones, ниже — свободна, бьётся о капсулы тела и землю;
#   rigid — жёсткая вещь (шлем, наплечник): едет за костью bone.
#   cape — плащ со своей тканью (как Max Distance в Unreal / Skinned Cloth в Unity): у каждой точки есть место на
#          анимированном теле, к нему её тянет пружина, и дальше max_dist от него она не уходит — у плеч 0, к подолу
#          больше. Движется только грубая решётка coarse (5 × 7 точек), сетка плаща гладко повторяет её — ткань
#          тяжёлая, отдельные «пиксели» не болтаются. Бьётся о капсулы тела и землю.
# В слоте — одна вещь: надеть новую — старая снимается.

func _bone_world(idx: int, rest := false) -> Transform3D:
	var t := _skel.get_bone_global_rest(idx) if rest else _skel.get_bone_global_pose(idx)
	var g := _skel.global_transform * t
	return Transform3D(g.basis.orthonormalized(), g.origin)


func worn(slot: String) -> String:
	return str((_worn.get(slot, {}) as Dictionary).get("id", ""))


func equip(id: String) -> bool:
	var it: Dictionary = _items.get(id, {})
	if it.is_empty() or _skel == null or not model.is_inside_tree():
		return false
	var slot := str(it.get("slot", id))
	unequip(slot)
	var w := {"id": id, "item": it, "nodes": [], "anchors": [], "cloth": null, "pin_left": 0}
	var ok := false
	match str(it.get("kind", "rigid")):
		"cape":
			ok = _wear_cape(it, w)
		"cloth":
			ok = _wear_cloth(it, w)
		_:
			ok = _wear_rigid(it, w)
	if not ok:
		for n: Node in w.nodes:
			n.queue_free()
		_mod.log_warning("Pax RPG: item %s did not load" % id)
		return false
	_worn[slot] = w
	_last_in_slot[slot] = id
	return true


func unequip(slot: String) -> void:
	var w: Dictionary = _worn.get(slot, {})
	for n: Node in w.get("nodes", []):
		if is_instance_valid(n):
			n.queue_free()
	_worn.erase(slot)


## «C»: снять вещь со слота или надеть ту, что в нём была (или первую из надетых при старте).
func toggle_slot(slot: String) -> void:
	if _worn.has(slot):
		unequip(slot)
		return
	var id := str(_last_in_slot.get(slot, ""))
	if id == "":
		for e: Variant in cfg.get("equipped", []):
			if str((_items.get(str(e), {}) as Dictionary).get("slot", "")) == slot:
				id = str(e)
	if id != "":
		equip(id)


## Сетка предмета из glb и её положение в осях сцены glb.
func _load_mesh(path: String) -> Array:
	var src := _mod.model(path)
	if src == null:
		return []
	var mi: MeshInstance3D = null
	for c: Node in src.find_children("*", "MeshInstance3D", true, false):
		mi = c as MeshInstance3D
		break
	if mi == null or mi.mesh == null:
		src.free()
		return []
	var local := Transform3D.IDENTITY
	var n: Node = mi
	while n != src and n is Node3D:
		local = (n as Node3D).transform * local
		n = n.get_parent()
	var mesh := mi.mesh
	src.free()
	return [mesh, local]


func _iv(it: Dictionary, k: String, d: float) -> float:
	return float(it.get(k, d))


func _wear_cloth(it: Dictionary, w: Dictionary) -> bool:
	var ml := _load_mesh(str(it.get("model", "")))
	if ml.is_empty():
		return false
	var sb := SoftBody3D.new()
	sb.mesh = ml[0]
	sb.top_level = true
	sb.transform = model.global_transform * (ml[1] as Transform3D)
	w.xform = sb.transform
	sb.collision_layer = 0
	sb.collision_mask = 1 | CLOTH_LAYER
	sb.simulation_precision = int(_iv(it, "precision", 12))
	sb.total_mass = _iv(it, "mass", 0.7)
	sb.linear_stiffness = _iv(it, "stiffness", 0.35)
	sb.damping_coefficient = _iv(it, "damping", 0.012)
	sb.drag_coefficient = _iv(it, "drag", 0.02)
	sb.pressure_coefficient = 0.0
	model.add_child(sb)
	if _owner_body != null:
		sb.add_collision_exception_with(_owner_body)
	w.cloth = sb
	(w.nodes as Array).append(sb)
	for bn: Variant in it.get("pin_bones", ["Spine02", "LeftShoulder", "RightShoulder", "neck"]):
		var bi := _skel.find_bone(str(bn))
		if bi < 0:
			continue
		var an := Node3D.new()
		an.top_level = true
		model.add_child(an)
		an.global_transform = _bone_world(bi, true)    # пришиваем в позе покоя — как сетка
		(w.anchors as Array).append([an, bi])
		(w.nodes as Array).append(an)
	if (w.anchors as Array).is_empty():
		return false
	w.pin_left = 1
	if _colliders.is_empty():
		_make_body_colliders()
	return true


func _wear_cape(it: Dictionary, w: Dictionary) -> bool:
	var parsed: Variant = JSON.parse_string(_mod.read_text(str(it.get("grid", ""))))
	if not (parsed is Dictionary):
		return false
	var g: Dictionary = parsed
	var nx := int(g.get("nx", 0))
	var nz := int(g.get("nz", 0))
	var pts: Array = g.get("points", [])
	if nx < 2 or nz < 2 or pts.size() != nx * nz:
		return false
	var top_b := _skel.find_bone(str(it.get("top_bone", "Spine")))
	var low_b := _skel.find_bone(str(it.get("low_bone", "Hips")))
	var sides: Array = it.get("side_bones", ["LeftShoulder", "RightShoulder"])   # +X — левое плечо рыцаря
	var left_b := _skel.find_bone(str(sides[0]))
	var right_b := _skel.find_bone(str(sides[1]))
	if top_b < 0 or low_b < 0:
		return false
	var rest := PackedVector3Array()
	for p: Variant in pts:
		var a: Array = p
		rest.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
	var shade := PackedFloat32Array()
	for v: Variant in g.get("shade", []):
		shade.append(float(v))
	var cs: Array = it.get("coarse", [5, 7])
	var cx := int(cs[0])
	var cz := int(cs[1])
	# грубая решётка: точки сетки на равных шагах
	var c_idx := PackedInt32Array()
	for j: int in cz:
		for i: int in cx:
			c_idx.append(roundi(float(j) / (cz - 1) * (nz - 1)) * nx + roundi(float(i) / (cx - 1) * (nx - 1)))
	var mesh := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	var mat := StandardMaterial3D.new()
	var col: Array = g.get("color", [0.2, 0.16, 0.24])
	mat.albedo_color = Color(float(col[0]), float(col[1]), float(col[2]))
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.92
	model.add_child(mi)
	(w.nodes as Array).append(mi)
	var half := 0.0
	for i: int in nx:
		half = maxf(half, absf(rest[i].x))
	w.cape = {"nx": nx, "nz": nz, "rest": rest, "shade": shade, "cx": cx, "cz": cz, "c_idx": c_idx,
		"top_b": top_b, "low_b": low_b, "left_b": left_b, "right_b": right_b, "half": maxf(half, 0.1),
		"mesh": mesh, "mat": mat,
		"x": PackedVector3Array(), "prev": PackedVector3Array(), "len_h": 0.0, "len_v": 0.0}
	var c: Dictionary = w.cape
	var tg := _cape_targets(c, c_idx)
	c.x = tg.duplicate()
	c.prev = tg.duplicate()
	c.len_h = (rest[c_idx[1]] - rest[c_idx[0]]).length()
	c.len_v = (rest[c_idx[cx]] - rest[c_idx[0]]).length()
	if _colliders.is_empty():
		_make_body_colliders()
	return true


## Где точки плаща сейчас «на теле»: верх посередине едет с грудью, углы верха — с плечами, низ — с тазом.
func _cape_targets(c: Dictionary, idx: PackedInt32Array) -> PackedVector3Array:
	var rest: PackedVector3Array = c.rest
	var nz: int = c.nz
	var nx: int = c.nx
	var mg := model.global_transform
	var t_top := _bone_world(int(c.top_b)) * _bone_world(int(c.top_b), true).affine_inverse()
	var t_low := _bone_world(int(c.low_b)) * _bone_world(int(c.low_b), true).affine_inverse()
	var t_l := t_top
	var t_r := t_top
	if int(c.left_b) >= 0 and int(c.right_b) >= 0:
		t_l = _bone_world(int(c.left_b)) * _bone_world(int(c.left_b), true).affine_inverse()
		t_r = _bone_world(int(c.right_b)) * _bone_world(int(c.right_b), true).affine_inverse()
	var half: float = c.half
	var out := PackedVector3Array()
	out.resize(idx.size())
	for k: int in idx.size():
		var p := mg * rest[idx[k]]
		var row := floorf(float(idx[k]) / nx) / float(nz - 1)
		var wl := smoothstep(0.15, 0.9, row)
		var u := rest[idx[k]].x / half
		var ws := smoothstep(0.3, 1.0, absf(u)) * (1.0 - smoothstep(0.0, 0.35, row))
		var up := (t_top * p).lerp((t_l if u > 0.0 else t_r) * p, ws)
		out[k] = up.lerp(t_low * p, wl)
	return out


func _cape_tick(w: Dictionary, delta: float) -> void:
	var c: Dictionary = w.cape
	var it: Dictionary = w.item
	var cx: int = c.cx
	var cz: int = c.cz
	var tg := _cape_targets(c, c.c_idx)
	var x: PackedVector3Array = c.x
	var prev: PackedVector3Array = c.prev
	var dt := clampf(delta, 0.001, 0.05)
	var damp := _iv(it, "damping", 0.9)
	var grav := Vector3(0.0, -_iv(it, "gravity", 9.8), 0.0) * dt * dt
	var follow := _iv(it, "follow", 0.12)
	var max_d := _iv(it, "max_dist", 0.5)
	var floor_y := model.global_position.y + 0.03
	for k: int in x.size():
		var row := floorf(float(k) / cx) / float(cz - 1)
		if k < cx:                                   # верхний ряд пришит
			x[k] = tg[k]
			prev[k] = tg[k]
			continue
		var v := (x[k] - prev[k]) * damp
		prev[k] = x[k]
		x[k] += v + grav
		x[k] += (tg[k] - x[k]) * follow * lerpf(1.0, _iv(it, "follow_hem", 0.12), row)   # верх держит форму, низ — инерция
	for _it: int in int(_iv(it, "iterations", 4)):
		for j: int in cz:
			for i: int in cx:
				var k := j * cx + i
				if i + 1 < cx and j > 0:
					_cape_link(x, k, k + 1, float(c.len_h), false)
				if j + 1 < cz:
					_cape_link(x, k, k + cx, float(c.len_v), j == 0)
		for k: int in range(cx, x.size()):
			var row := floorf(float(k) / cx) / float(cz - 1)
			var lim := max_d * pow(row, 1.15)
			var d := x[k] - tg[k]
			if d.length() > lim:
				x[k] = tg[k] + d.normalized() * lim
			x[k] = _push_out(x[k])
			x[k].y = maxf(x[k].y, floor_y)
	c.x = x
	c.prev = prev
	_cape_draw(c, tg)


## Связь двух соседних точек решётки: длина как в покое (верхний ряд не двигается).
static func _cape_link(x: PackedVector3Array, a: int, b: int, rest_len: float, a_pinned: bool) -> void:
	var d := x[b] - x[a]
	var n := d.length()
	if n < 0.0001:
		return
	var corr := d * ((n - rest_len) / n)
	if a_pinned:
		x[b] -= corr
	else:
		x[a] += corr * 0.5
		x[b] -= corr * 0.5


func _push_out(p: Vector3) -> Vector3:
	for cl: Array in _colliders:
		var body: AnimatableBody3D = cl[0]
		var cap: CapsuleShape3D = (body.get_child(0) as CollisionShape3D).shape
		var axis := body.global_transform.basis.y
		var half := cap.height * 0.5 - cap.radius
		var rel := p - body.global_position
		var along := clampf(rel.dot(axis), -half, half)
		var nearest := body.global_position + axis * along
		var off := p - nearest
		var dist := off.length()
		var r := cap.radius + 0.03
		if dist < r and dist > 0.0001:
			p = nearest + off / dist * r
	return p


## Сетка плаща: смещение каждой её точки от «места на теле» — билинейно по грубой решётке.
func _cape_draw(c: Dictionary, tg: PackedVector3Array) -> void:
	var nx: int = c.nx
	var nz: int = c.nz
	var cx: int = c.cx
	var cz: int = c.cz
	var x: PackedVector3Array = c.x
	var all_idx := PackedInt32Array()
	all_idx.resize(nx * nz)
	for k: int in nx * nz:
		all_idx[k] = k
	var base := _cape_targets(c, all_idx)
	var pos := PackedVector3Array()
	pos.resize(nx * nz)
	for j: int in nz:
		var fv := float(j) / (nz - 1) * (cz - 1)
		var j0 := mini(int(fv), cz - 2)
		var tv := fv - j0
		for i: int in nx:
			var fu := float(i) / (nx - 1) * (cx - 1)
			var i0 := mini(int(fu), cx - 2)
			var tu := fu - i0
			var k00 := j0 * cx + i0
			var o00 := x[k00] - tg[k00]
			var o10 := x[k00 + 1] - tg[k00 + 1]
			var o01 := x[k00 + cx] - tg[k00 + cx]
			var o11 := x[k00 + cx + 1] - tg[k00 + cx + 1]
			var off := o00.lerp(o10, tu).lerp(o01.lerp(o11, tu), tv)
			pos[j * nx + i] = base[j * nx + i] + off
	var nrm := PackedVector3Array()
	nrm.resize(nx * nz)
	for j: int in nz:
		for i: int in nx:
			var l := pos[j * nx + maxi(i - 1, 0)]
			var r := pos[j * nx + mini(i + 1, nx - 1)]
			var u := pos[maxi(j - 1, 0) * nx + i]
			var d := pos[mini(j + 1, nz - 1) * nx + i]
			nrm[j * nx + i] = (r - l).cross(d - u).normalized()
	var shade: PackedFloat32Array = c.shade
	var mesh: ImmediateMesh = c.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, c.mat)
	for j: int in nz - 1:
		for i: int in nx - 1:
			var a := j * nx + i
			for k: int in [a, a + nx, a + 1, a + 1, a + nx, a + nx + 1]:
				var s := shade[k] if k < shade.size() else 1.0
				mesh.surface_set_color(Color(s, s, s))
				mesh.surface_set_normal(nrm[k])
				mesh.surface_add_vertex(pos[k])
	mesh.surface_end()


func _wear_rigid(it: Dictionary, w: Dictionary) -> bool:
	var bi := _skel.find_bone(str(it.get("bone", "Head")))
	var src := _mod.model(str(it.get("model", "")))
	if src == null or bi < 0:
		if src != null:
			src.free()
		return false
	var follow := Node3D.new()
	follow.top_level = true
	model.add_child(follow)
	follow.add_child(src)
	w.bone = bi
	w.rel = _bone_world(bi, true).affine_inverse() * model.global_transform   # вещь сделана в позе покоя модели
	follow.global_transform = _bone_world(bi) * (w.rel as Transform3D)
	w.follow = follow
	(w.nodes as Array).append(follow)
	return true


## Капсулы тела (таз, спина, бёдра, голени) — о них бьётся ткань; персонажа и мир они не трогают.
func _make_body_colliders() -> void:
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
		cap.radius = float(d[2]) * _f("cloth_body_scale", 1.5)
		cap.height = len_ + cap.radius * 2.0
		sh.shape = cap
		body.add_child(sh)
		model.add_child(body)
		_colliders.append([body, ia, ib])
	_move_colliders()


## Верх ткани пришивается по всей ширине: точки делятся на полосы по X, в каждой пришиваются те, что у её верхнего
## края, — каждая к ближней из костей pin_bones. Позиции берутся у самих точек мягкого тела (не по номерам вершин —
## сервер физики мог сварить их по-своему). false — точки ещё не готовы.
func _pin_cloth(w: Dictionary) -> bool:
	var sb: SoftBody3D = w.cloth
	var it: Dictionary = w.item
	var xf: Transform3D = w.xform
	var n := (sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var raw := PackedVector3Array()
	var c := Vector3.ZERO
	for i: int in n:
		var p: Vector3 = sb.get_point_transform(i)
		raw.append(p)
		c += p
	if n == 0 or c == Vector3.ZERO:
		return false
	c /= float(n)
	# точки — в мире или в осях узла: что ближе к телу, то и верно
	var global := c.distance_to(model.global_position) < (xf * c).distance_to(model.global_position)
	var to_local := xf.affine_inverse()
	var strip := _iv(it, "pin_strip", 0.05)
	var band := _iv(it, "pin_band", 0.08)
	var loc := PackedVector3Array()
	var tops := {}
	for p: Vector3 in raw:
		var l := to_local * p if global else p
		loc.append(l)
		var k := int(floor(l.x / strip))
		tops[k] = maxf(float(tops.get(k, -INF)), l.y)
	var pinned := 0
	for i: int in n:
		var l := loc[i]
		if l.y < float(tops[int(floor(l.x / strip))]) - band:
			continue
		var wp := xf * l
		var best: Node3D = null
		var bd := INF
		for an: Array in w.anchors:
			var node: Node3D = an[0]
			var d := node.global_position.distance_to(wp)
			if d < bd:
				bd = d
				best = node
		sb.set_point_pinned(i, true, sb.get_path_to(best))
		pinned += 1
	_mod.log_info("Pax RPG: %s pinned %d of %d points" % [w.id, pinned, n])
	return true


func _move_colliders() -> void:
	for c: Array in _colliders:
		var body: AnimatableBody3D = c[0]
		var a := _bone_world(int(c[1])).origin
		var b := _bone_world(int(c[2])).origin
		var dir := b - a
		if dir.length() < 0.001:
			continue
		body.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir.normalized())), (a + b) * 0.5)


func _items_tick(delta: float) -> void:
	if _skel == null or not model.is_inside_tree():
		return
	var any_cloth := false
	for w: Dictionary in _worn.values():
		if w.has("cape"):
			any_cloth = true
		elif w.cloth != null:
			any_cloth = true
			if int(w.pin_left) > 0:
				w.pin_left = int(w.pin_left) - 1
				if int(w.pin_left) == 0 and not _pin_cloth(w):
					w.pin_left = 1              # точки мягкого тела ещё не созданы — через кадр
				continue
			for an: Array in w.anchors:
				(an[0] as Node3D).global_transform = _bone_world(int(an[1]))
		elif w.has("follow"):
			(w.follow as Node3D).global_transform = _bone_world(int(w.bone)) * (w.rel as Transform3D)
	if any_cloth:
		_move_colliders()
	for w: Dictionary in _worn.values():
		if w.has("cape"):
			_cape_tick(w, delta)


## Ткань сама тянется за телом — ветер не нужен (оставлено для location.gd).
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
	_cancel_hurt()
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


## Реакция на удар (Hurt) — только картинка: любое действие или шаг её прерывают, управление не отнимается.
func _cancel_hurt() -> void:
	if action == "Hurt":
		action = ""


func attack(on_floor: bool) -> void:
	_cancel_hurt()
	blocking = false
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
	_cancel_hurt()
	if anim == null or not on_floor or action != "":
		return false
	var n := "DodgeArmed" if armed and has("DodgeArmed") else "Dodge"
	if not has(n):
		return false
	_play_once(n, _per("clip_skip", n, 0.0))   # без раскачки перед кувырком — уворот срабатывает сразу
	return true


## Во время кувырка удары проходят мимо (i-frames).
func invulnerable() -> bool:
	return action in ["Dodge", "DodgeArmed"]


## Получил удар: клип Hurt (если есть в модели) — короткая реакция, не сбивает уворот и удар финала.
func hurt() -> void:
	if anim == null or not has("Hurt") or action != "":
		return                                   # удар, уворот, доставание не сбиваются
	_play_once("Hurt")


## Прыжок: анимация с момента отрыва (без долгого приседа), отрыв — сразу (tick вернёт jump).
func jump(on_floor: bool) -> bool:
	_cancel_hurt()
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
	_hit_done = false
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
	if blocking:
		_block_t += delta
	if action == "Hurt" and moving:
		_end_action()                        # пошёл — реакция на удар обрывается, ходьба сливается плавно
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
		_hit(out)
		out.root = _root_step()
	else:
		_loop(moving, speed, running)
	_on_floor = on_floor
	_show_sword(delta)
	_trail_tick(delta)
	_items_tick(delta)
	return out


func _loop(moving: bool, speed: float, running: bool) -> void:
	var want := "IdleArmed" if armed and has("IdleArmed") else "Idle"
	var stride := 1.0
	if blocking and has("Block"):
		# блок: меч двумя руками поперёк перед собой; на ходу — ноги шагают, руки держат блок
		want = "Block"
		if moving:
			_update_sector()
			want = "BlockWalk" + _dir_sector
			stride = _f("stride_back", 1.0) if _dir_sector == "B" else (_f("stride_strafe", 1.0)
				if _dir_sector in ["L", "R"] else _f("stride_walk_armed", 1.3))
			if not has(want):
				want = "Block"
		if anim.current_animation != want or not anim.is_playing():
			anim.play(want, _f("block_blend", 0.1))
		anim.speed_scale = clampf(speed / stride, 0.5, 2.0) if moving and want != "Block" else 1.0
		return
	if moving:
		if running:
			want = "RunArmed" if armed and has("RunArmed") else "Run"
			stride = _f("stride_run_armed", 3.2) if want == "RunArmed" else _f("stride_run", 4.0)
		else:
			_update_sector()
			match _dir_sector:
				"B":
					want = "GuardBack" if armed else "WalkBack"
					stride = _f("stride_back", 1.0)
				"L":
					want = "GuardStrafeL" if armed else "StrafeL"
					stride = _f("stride_strafe", 1.0)
				"R":
					want = "GuardStrafeR" if armed else "StrafeR"
					stride = _f("stride_strafe", 1.0)
				_:
					want = ""
			if want == "" or not has(want):
				want = "WalkArmed" if armed and has("WalkArmed") else "Walk"
				stride = _f("stride_walk_armed", 1.3) if want == "WalkArmed" else _f("stride_walk", 1.5)
	if anim.current_animation != want or not anim.is_playing():
		var bl := _f("blend_loop", 0.3)
		if want == "RunArmed" or anim.current_animation == "RunArmed":
			bl = _f("blend_run_armed", 0.5)      # рука с мечом уходит вниз-назад — не рывком
		anim.play(want, bl)
	anim.speed_scale = clampf(speed / stride, 0.5, 2.0) if moving else 1.0


## Направление шага по move_dir: ближайшее из вперёд / вправо / назад / влево, но меняется, только когда новое
## заметно ближе (на диагонали клип не мигает).
func _update_sector() -> void:
	var ang := rad_to_deg(atan2(move_dir.x, move_dir.y))   # 0 — вперёд, 90 — вправо, ±180 — назад
	var centers := {"F": 0.0, "R": 90.0, "B": 180.0, "L": -90.0}
	var best := _dir_sector
	var best_d := absf(wrapf(ang - float(centers[_dir_sector]), -180.0, 180.0)) - 20.0
	for k: String in centers:
		var d := absf(wrapf(ang - float(centers[k]), -180.0, 180.0))
		if d < best_d:
			best_d = d
			best = k
	_dir_sector = best


## ПКМ: нажал — блок (и первые parry_window с — парирование, как в Sekiro), отпустил — снял.
func set_block(on: bool) -> void:
	if on and not blocking:
		_cancel_hurt()
		if not armed or (action != "" and action not in ["Jump"]):
			return
		blocking = true
		_block_t = 0.0
		if has("Block"):
			anim.play("Block", _f("block_blend", 0.1))   # меч поднимается в блок быстро — иначе не успеть
			anim.speed_scale = 1.0
	elif not on:
		blocking = false


func parry_window() -> bool:
	return blocking and _block_t <= _f("parry_window", 0.25)


## Парировал: меч вздрагивает в блоке (как от удара о сталь). Окно парирования не продлевается — следующий удар
## надо ловить новым нажатием, как в Sekiro.
func deflect() -> void:
	if anim != null and anim.current_animation == "Block":
		anim.seek(0.0, true)


## Добивание (враг без равновесия): свой клип, двигаться нельзя. true — началось.
func deathblow() -> bool:
	_cancel_hurt()
	if anim == null or not armed or action != "" or not has("Deathblow"):
		return false
	blocking = false
	_play_once("Deathblow")
	return true


## Миг удара: середина взмаха (swing_peaks), у финального — касание земли (impact). tick вернёт
## {"hit": {"range": м, "arc": косинус полуугла перед героем (-1 — круг)}} — location.gd бьёт по врагам.
func _hit(out: Dictionary) -> void:
	if _hit_done or action not in ATTACKS:
		return
	var imp: Dictionary = meta.get("impact", {})
	var at := float(imp[action]) if imp.has(action) else float((cfg.get("swing_peaks", {}) as Dictionary).get(action, 0.5))
	if _pos() < at:
		return
	_hit_done = true
	var ground := imp.has(action)
	out["hit"] = {"range": _per("hit_range", action, 2.6), "arc": -1.0 if ground else 0.2,
		"damage": _per("hit_damage", action, 15.0)}


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
