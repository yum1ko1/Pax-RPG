extends SkeletonModifier3D
## IK ног героя на неровной земле (ступени, склоны, камни): луч вниз под каждую стопу, таз опускается к нижней
## ноге, колено — аналитический двухкостный IK (бедро — голень), стопа сохраняет поворот клипа. В прыжке и в
## воздухе гаснет плавно. Поправки — в осях скелета, мир — через его global_transform (модель может быть в масштабе).
## Настройки героя (hero_*.json): foot_ik (вкл.), foot_ik_reach (м вверх/вниз), foot_ik_hip (м, насколько таз
## может опуститься).

var body: CharacterBody3D            # герой: исключается из лучей, is_on_floor() — включать ли IK
var feet_root: Node3D                # узел модели: его высота — уровень ровной земли под героем
var reach := 0.45                    # м: дальше этого ступень не тянем (обрыв — не ступень)
var hip_max := 0.35                  # м: насколько таз опускается к нижней ноге
var legs := [["LeftUpLeg", "LeftLeg", "LeftFoot"], ["RightUpLeg", "RightLeg", "RightFoot"]]

var _ids: Array = []                 # [[бедро, голень, стопа], …]
var _hips := -1
var _off := [0.0, 0.0]               # сглаженная высота земли под стопой (м, от уровня модели)
var _hip := 0.0                      # сглаженное опускание таза (м, ≤ 0)
var _w := 0.0                        # вес IK: 0 в воздухе, 1 на земле


func _ready() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	_hips = sk.find_bone("Hips")
	for l: Array in legs:
		var ids := [sk.find_bone(str(l[0])), sk.find_bone(str(l[1])), sk.find_bone(str(l[2]))]
		if ids.has(-1):
			_ids.clear()
			return
		_ids.append(ids)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _ids.size() != 2 or _hips < 0 or not is_instance_valid(body) or not is_instance_valid(feet_root):
		return
	var dt := get_process_delta_time() if not Engine.is_in_physics_frame() else get_physics_process_delta_time()
	var grounded := body.is_on_floor()
	_w = move_toward(_w, 1.0 if grounded else 0.0, dt * 6.0)
	var xf := sk.global_transform
	var inv := xf.affine_inverse()
	var floor_y := feet_root.global_position.y
	var space := sk.get_world_3d().direct_space_state
	# 1. высота земли под каждой стопой (стопа клипа: её подъём над полом сохраняется)
	var want := [0.0, 0.0]
	for i: int in 2:
		var foot_w := xf * sk.get_bone_global_pose(_ids[i][2]).origin
		if grounded:
			var q := PhysicsRayQueryParameters3D.create(Vector3(foot_w.x, floor_y + reach, foot_w.z),
				Vector3(foot_w.x, floor_y - reach, foot_w.z))
			q.exclude = [body.get_rid()]
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit.normal as Vector3).y > 0.55:
				want[i] = clampf((hit.position as Vector3).y - floor_y, -reach, reach)
		_off[i] = lerpf(float(_off[i]), float(want[i]), clampf(dt * 14.0, 0.0, 1.0))
	var h := clampf(minf(minf(float(_off[0]), float(_off[1])), 0.0), -hip_max, 0.0)
	_hip = lerpf(_hip, h, clampf(dt * 10.0, 0.0, 1.0))
	if _w <= 0.001:
		return
	var up_s := (inv.basis * Vector3.UP)                # вверх в осях скелета (длина = 1/масштаб)
	# 2. таз вниз — к нижней ноге (иначе нога на ступени вниз не достаёт)
	var hp := sk.get_bone_global_pose(_hips)
	hp.origin += up_s * _hip * _w
	sk.set_bone_global_pose(_hips, hp)
	# 3. каждая нога: стопа клипа + подъём земли под ней
	for i: int in 2:
		var ids: Array = _ids[i]
		var foot0 := sk.get_bone_global_pose(ids[2])
		var lift := (float(_off[i]) - _hip) * _w
		if absf(lift) < 0.002:
			continue
		_two_bone(sk, ids[0], ids[1], ids[2], foot0.origin + up_s * lift, foot0.basis)


## Двухкостный IK в осях скелета: бедро a → колено b → стопа c к цели t; колено гнётся туда же, куда в клипе.
static func _two_bone(sk: Skeleton3D, ia: int, ib: int, ic: int, t: Vector3, foot_basis: Basis) -> void:
	var pa := sk.get_bone_global_pose(ia)
	var pb := sk.get_bone_global_pose(ib)
	var pc := sk.get_bone_global_pose(ic)
	var a := pa.origin
	var b := pb.origin
	var c := pc.origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 1e-4 or l2 < 1e-4:
		return
	var at := t - a
	var d := clampf(at.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var dir := at.normalized()
	var knee_side := (b - a) - dir * (b - a).dot(dir)   # куда смотрит колено в клипе (поперёк линии бедро—цель)
	if knee_side.length_squared() < 1e-8:
		return
	knee_side = knee_side.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var b2 := a + (dir * cos_a + knee_side * sqrt(1.0 - cos_a * cos_a)) * l1
	# бедро: поворот (b − a) → (b2 − a)
	var r1 := _arc((b - a).normalized(), (b2 - a).normalized())
	pa.basis = Basis(r1) * pa.basis
	sk.set_bone_global_pose(ia, pa)
	# голень: после бедра — от нового колена к цели
	pb = sk.get_bone_global_pose(ib)
	var c1 := sk.get_bone_global_pose(ic).origin
	var r2 := _arc((c1 - pb.origin).normalized(), (a + dir * d - pb.origin).normalized())
	pb.basis = Basis(r2) * pb.basis
	sk.set_bone_global_pose(ib, pb)
	# стопа — поворот клипа (не заваливается вместе с голенью)
	pc = sk.get_bone_global_pose(ic)
	pc.basis = foot_basis
	sk.set_bone_global_pose(ic, pc)


static func _arc(u: Vector3, v: Vector3) -> Quaternion:
	var cr := u.cross(v)
	var dt := u.dot(v)
	if dt < -0.9999:
		return Quaternion.IDENTITY
	return Quaternion(cr.x, cr.y, cr.z, 1.0 + dt).normalized()
