extends RefCounted
## Тело павшего врага (goblin.gd / orc.gd → _die):
##  • рэгдолл — физические кости (PhysicalBoneSimulator3D) по главным костям скелета Meshy/Mixamo: падает от силы
##    последнего удара, конечности болтаются, бьются о землю; размеры костей — в единицах скелета (сантиметры
##    Mixamo, масштаб 0.01 узла Armature переводит их в метры);
##  • растворение в ману — shaders/body_fx.gdshader (dissolve): тело выгорает пятнами, край светится маной;
##  • разрез иаем — снимок позы (bake_mesh_from_current_skeleton_pose) двумя половинами по плоскости удара; каждая —
##    RigidBody3D, разлетаются и падают, срез светится маной изнутри, потом растворяются.

const SHADER := "shaders/body_fx.gdshader"
const LAYER := 1 << 5               # слой 6 — тела и половинки: сами с собой и с живыми не сталкиваются
const MASK := 1                     # только мир (земля, стены)

## [кость, радиус капсулы (доля длины), кость, к которой тянется (конец капсулы), масса]
const BONES := [["Hips", 0.55, "Spine01", 9.0], ["Spine01", 0.6, "neck", 8.0], ["Head", 0.6, "head_end", 3.0],
	["LeftArm", 0.28, "LeftForeArm", 2.0], ["LeftForeArm", 0.24, "LeftHand", 1.5],
	["RightArm", 0.28, "RightForeArm", 2.0], ["RightForeArm", 0.24, "RightHand", 1.5],
	["LeftUpLeg", 0.3, "LeftLeg", 4.0], ["LeftLeg", 0.25, "LeftFoot", 3.0],
	["RightUpLeg", 0.3, "RightLeg", 4.0], ["RightLeg", 0.25, "RightFoot", 3.0]]


static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c: Node in n.get_children():
		var s := find_skeleton(c)
		if s != null:
			return s
	return null


## Рэгдолл из текущей позы; impulse — толчок тазу (м/с·масса). null — скелет не подошёл (нет нужных костей).
static func ragdoll(skel: Skeleton3D, impulse: Vector3) -> PhysicalBoneSimulator3D:
	if skel == null or skel.find_bone("Hips") < 0:
		return null
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	skel.add_child(sim)
	var hips: PhysicalBone3D = null
	for b: Array in BONES:
		var bi := skel.find_bone(str(b[0]))
		var ti := skel.find_bone(str(b[2]))
		if bi < 0:
			continue
		var bp := skel.get_bone_global_pose(bi)
		var length := 12.0
		if ti >= 0:
			length = maxf(4.0, bp.origin.distance_to(skel.get_bone_global_pose(ti).origin))
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + str(b[0])
		pb.bone_name = str(b[0])
		pb.mass = float(b[3])
		pb.collision_layer = LAYER
		pb.collision_mask = MASK
		pb.linear_damp = 0.4
		pb.angular_damp = 2.0
		pb.friction = 0.9
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		pb.set("joint_constraints/swing_span", 35.0 if str(b[0]).begins_with("Spine") else 55.0)
		pb.set("joint_constraints/twist_span", 20.0)
		pb.body_offset = Transform3D(Basis(), Vector3(0.0, length * 0.5, 0.0))   # капсула вдоль кости (+Y у Mixamo)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = maxf(2.0, length * float(b[1]) * 0.5)
		cap.height = maxf(cap.radius * 2.0 + 0.5, length)
		cs.shape = cap
		pb.add_child(cs)
		sim.add_child(pb)
		pb.global_transform = skel.global_transform * bp * pb.body_offset
		if str(b[0]) == "Hips":
			hips = pb
	sim.physical_bones_start_simulation()
	if hips != null:
		hips.apply_central_impulse(impulse * hips.mass)
	return sim


static func stop_ragdoll(skel: Skeleton3D) -> void:
	if skel == null:
		return
	var sim := skel.get_node_or_null("Ragdoll") as PhysicalBoneSimulator3D
	if sim != null:
		sim.physical_bones_stop_simulation()
		sim.queue_free()
	skel.reset_bone_poses()


## Материалы растворения вместо материалов модели (снять — clear). Вернёт их — тянуть dissolve 0 → 1.
static func dissolve_mats(mod: PaxMod, model: Node3D) -> Array:
	var out: Array = []
	var sh: Shader = mod.shader(SHADER)
	if sh == null or model == null:
		return out
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si: int in mi.mesh.get_surface_count():
			var m := _fx_mat(sh, mi.get_active_material(si))
			mi.set_surface_override_material(si, m)
			out.append(m)
	return out


static func clear(model: Node3D) -> void:
	if model == null:
		return
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si: int in mi.mesh.get_surface_count():
			mi.set_surface_override_material(si, null)


static func _fx_mat(sh: Shader, src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	var bm := src as BaseMaterial3D
	if bm != null:
		if bm.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", bm.albedo_texture)
		m.set_shader_parameter("albedo_col", bm.albedo_color)
		m.set_shader_parameter("roughness", bm.roughness)
	return m


## Тело тает в ману за seconds; потом зовётся done (спрятать модель). Мана — искры вверх (parent — куда их ставить).
static func dissolve(mod: PaxMod, model: Node3D, seconds: float, done: Callable) -> void:
	var mats := dissolve_mats(mod, model)
	if mats.is_empty():
		if done.is_valid():
			done.call()
		return
	mana_puff(model.get_parent(), model.global_position + Vector3(0.0, 0.6, 0.0), seconds)
	var tw := model.create_tween()
	tw.tween_method(func(v: float) -> void:
		for m: Variant in mats:
			(m as ShaderMaterial).set_shader_parameter("dissolve", v), 0.0, 1.0, seconds).set_ease(Tween.EASE_IN)
	if done.is_valid():
		tw.tween_callback(done)


## Разрез: снимок позы → две половины по плоскости (нормаль n и точка p — в мире), разлетаются от удара push.
## Модель врага прячет зовущий. Половинки лежат linger секунд, потом растворяются в ману и исчезают.
static func slice(mod: PaxMod, model: Node3D, parent: Node, n: Vector3, p: Vector3, push: Vector3, linger: float) -> bool:
	var sh: Shader = mod.shader(SHADER)
	if sh == null or model == null or parent == null:
		return false
	var made := false
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var baked: ArrayMesh = null
		if mi.skin != null:
			baked = mi.bake_mesh_from_current_skeleton_pose()    # поза в миг удара — в обычную сетку
		else:
			baked = mi.mesh as ArrayMesh
		if baked == null:
			continue
		var xf := mi.global_transform
		var scl := xf.basis.get_scale()
		var nl := (xf.basis.transposed() * n).normalized()           # нормаль плоскости — в оси сетки
		var dl := nl.dot(xf.affine_inverse() * p)
		var bb := baked.get_aabb()
		for side: float in [1.0, -1.0]:
			var rb := RigidBody3D.new()
			rb.collision_layer = LAYER
			rb.collision_mask = MASK
			rb.mass = 6.0
			rb.angular_damp = 1.5
			parent.add_child(rb)
			rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
			var vis := MeshInstance3D.new()
			vis.mesh = baked
			vis.scale = scl
			vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var mats: Array = []
			for si: int in baked.get_surface_count():
				var m := _fx_mat(sh, mi.get_active_material(si))
				m.set_shader_parameter("clip_on", true)
				m.set_shader_parameter("clip", Vector4(nl.x * side, nl.y * side, nl.z * side, dl * side))
				vis.set_surface_override_material(si, m)
				mats.append(m)
			rb.add_child(vis)
			var cs := CollisionShape3D.new()                         # коробка половины: рамка, сдвинутая по нормали
			var box := BoxShape3D.new()
			var half := bb.size * Vector3(0.75, 0.55, 0.75)
			box.size = (half * scl).clamp(Vector3.ONE * 0.08, Vector3.ONE * 3.0)
			cs.shape = box
			cs.position = (bb.get_center() + nl * side * absf(nl.dot(bb.size)) * 0.22) * scl
			rb.add_child(cs)
			rb.linear_velocity = push + n * side * 2.2 + Vector3(0.0, 1.6, 0.0)
			rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4))
			var tw := rb.create_tween()
			tw.tween_interval(linger)
			tw.tween_callback(func() -> void: mana_puff(parent, rb.global_position + Vector3(0.0, 0.3, 0.0), 1.4))
			tw.tween_method(func(v: float) -> void:
				for m: Variant in mats:
					(m as ShaderMaterial).set_shader_parameter("dissolve", v), 0.0, 1.0, 1.4).set_ease(Tween.EASE_IN)
			tw.tween_callback(rb.queue_free)
			made = true
	return made


## Мана из тающего тела: розово-сиреневые искры поднимаются seconds секунд.
static func mana_puff(parent: Node, at: Vector3, seconds: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.amount = 60
	p.lifetime = 1.4
	p.one_shot = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0.0, 1.2, 0.0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.6, 0.8, 2.0, 0.0))
	ramp.add_point(0.2, Color(1.6, 0.8, 2.0, 0.9))
	ramp.set_color(1, Color(0.9, 0.5, 1.4, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(1.6)
	tw.tween_callback(p.queue_free)
