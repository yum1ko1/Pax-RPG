extends Node3D
## Ролик приёма для подсказки инвентаря: Тянь Лун на тёмной площадке, клип приёма с root motion, камера сбоку-спереди.
##   godot --path . --write-movie out/frames.png --fixed-fps 30 -- sunset|iai
const MODEL := "res://pax/models/heroes/tian_long/model.glb"
const META := "res://pax/models/heroes/tian_long/anim.json"
var hero: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var cam: Camera3D
var rm := {}
var seq: Array = []          # [[клип, скорость]]
var step := -1
var t := 0.0
var total := 0.0
var skill := "sunset"
var tint: ColorRect
var cuts: Control
var katana: Node3D
var blade: Node3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		skill = args[0]
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(META))
	rm = (meta as Dictionary).get("root_motion", {})
	_stage()
	hero = (load(MODEL) as PackedScene).instantiate()
	add_child(hero)
	anim = hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skel = hero.find_child("*", true, false) as Skeleton3D
	for n in hero.find_children("*", "Skeleton3D", true, false):
		skel = n
	var cape := hero.find_child("Knight_cape", true, false)
	if cape: cape.queue_free()
	if skill == "sunset":
		seq = [["IdleArmed", 0.6], ["UltSpear", 3.0], ["IdleArmed", 0.8]]
		(hero.find_child("Sword_Back", true, false) as Node3D).visible = false
	else:
		seq = [["Idle", 0.5], ["IaiKneel", -1.0], ["IaiHold", 2.2], ["IaiSheathe", -1.0], ["IaiRise", -1.0], ["Idle", 0.5]]
		(hero.find_child("Sword_Hand", true, false) as Node3D).visible = false
		_attach_katana()
	for s in seq:
		total += _len(s)
	_next()

func _len(s: Array) -> float:
	return float(s[1]) if float(s[1]) > 0.0 else anim.get_animation(s[0]).length

func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.035, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.42, 0.45)
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.16, 0.06, 0.07)
	e.fog_density = 0.035
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 35, 0)
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.86, 0.8)
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 1.4
	rim.light_color = Color(1.0, 0.25, 0.22) if skill == "sunset" else Color(0.75, 0.6, 1.0)
	add_child(rim)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.06, 0.035, 0.04)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var disk := MeshInstance3D.new()                  # круг под героем — цветом приёма
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4; cm.bottom_radius = 1.4; cm.height = 0.01
	disk.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.5, 0.08, 0.07) if skill == "sunset" else Color(0.32, 0.22, 0.48)
	dm.emission_enabled = true
	dm.emission = dm.albedo_color
	dm.emission_energy_multiplier = 0.35
	disk.material_override = dm
	disk.position.y = 0.006
	add_child(disk)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	var ui := CanvasLayer.new()
	add_child(ui)
	tint = ColorRect.new()                            # Иай: сиреневый монохром остановки времени
	tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.62, 0.5, 0.95, 0.0)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(tint)
	cuts = Control.new()
	cuts.set_anchors_preset(Control.PRESET_FULL_RECT)
	cuts.draw.connect(_draw_cuts)
	ui.add_child(cuts)

func _attach_katana() -> void:                        # как в iai.gd: ножны у левого бедра, рукоять вперёд-вверх
	var bi := skel.find_bone("Hips")
	if bi < 0: return
	var ba := BoneAttachment3D.new()
	ba.bone_name = "Hips"
	skel.add_child(ba)
	katana = Node3D.new()
	ba.add_child(katana)
	await get_tree().process_frame
	var want := Transform3D(Basis(Vector3.UP, deg_to_rad(-8.0)) * Basis(Vector3.RIGHT, deg_to_rad(-15.0)), Vector3(0.17, 0.0, 0.0))
	var m := hero.global_transform.basis.orthonormalized()
	katana.global_transform = Transform3D(m * want.basis, ba.global_transform.origin + m * (want.origin + Vector3(0, -0.04, 0.13)))
	var saya: Variant = load("res://pax/models/weapons/katana_saya.glb")
	if saya: katana.add_child((saya as PackedScene).instantiate())
	blade = Node3D.new()
	katana.add_child(blade)
	var bl: Variant = load("res://pax/models/weapons/katana.glb")
	if bl: blade.add_child((bl as PackedScene).instantiate())

var _clip_t := 0.0
func _next() -> void:
	step += 1
	_clip_t = 0.0
	if step >= seq.size():
		get_tree().quit()
		return
	var name: String = seq[step][0]
	var a := anim.get_animation(name)
	a.loop_mode = Animation.LOOP_LINEAR if name.begins_with("Idle") else Animation.LOOP_NONE
	anim.play(name, 0.15)

func _root(name: String, tt: float) -> Vector2:
	if not rm.has(name): return Vector2.ZERO
	var off: Array = rm[name].get("offset", [])
	if off.is_empty(): return Vector2.ZERO
	var x := tt * float(rm[name].get("fps", 30))
	var i := clampi(int(x), 0, off.size() - 1)
	var j := mini(i + 1, off.size() - 1)
	var k := x - float(i)
	return Vector2(lerpf(off[i][0], off[j][0], k), lerpf(off[i][1], off[j][1], k))

var _base := Vector3.ZERO
func _process(delta: float) -> void:
	t += delta
	_clip_t += delta
	var s: Array = seq[step]
	var name: String = s[0]
	var r := _root(name, _clip_t)
	hero.position = _base + Vector3(r.x, 0, r.y)
	if _clip_t >= _len(s):
		_base = hero.position
		hero.position = _base
		_next()
		if step >= seq.size(): return
	# камера: спереди-сбоку, следит за героем
	var focus := hero.position + Vector3(0, 1.05, 0)
	var off := Vector3(3.2, 1.5, 4.6) if skill == "sunset" else Vector3(2.4, 1.3, 3.4)
	cam.global_position = cam.global_position.lerp(focus + off, 1.0 if t < 0.05 else 0.08)
	cam.look_at(focus + Vector3(0, -0.15, 0), Vector3.UP)
	if skill == "iai":
		var hold := name == "IaiHold"
		tint.color.a = lerpf(tint.color.a, 0.32 if hold else 0.0, 0.12)
		if blade: blade.position.z = lerpf(blade.position.z, 0.05 if hold else 0.0, 0.2)
		cuts.queue_redraw()

func _draw_cuts() -> void:
	if skill != "iai" or step < 0 or seq[step][0] != "IaiHold": return
	var sz := cuts.size
	var n := int(clampf((_clip_t - 0.3) / 1.6, 0.0, 1.0) * 12.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var c := Vector2(rng.randf_range(0.25, 0.85) * sz.x, rng.randf_range(0.25, 0.75) * sz.y)
		var d := Vector2.from_angle(rng.randf_range(-0.9, 0.9)) * rng.randf_range(80, 170)
		cuts.draw_line(c - d, c + d, Color(1, 0.92, 1, 0.9), 2.0, true)
