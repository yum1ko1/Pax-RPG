extends SceneTree
## Комореби (И-54): пятна солнца под кронами огненных деревьев — полдень и 16:00, с пятнами и без, сбоку и сверху.
## Декали есть только в Forward+ (Compatibility их не рисует) — без видеокарты нужен lavapipe (mesa-vulkan-drivers):
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run godot --path tools/ci/project --rendering-driver vulkan \
##     --rendering-method forward_plus --fixed-fps 60 -s res://ci/preview_komorebi.gd -- --out=DIR
var mod: Node
var out_dir := "/tmp"
var frame := 0
var loc: Node


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(960, 720)
	(load("res://mods/pax_rpg/src/location/weather.gd") as GDScript).set("forced", "clear")
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	process_frame.connect(_tick)


# кадр: [час, яркость пятен, имя, ракурс]; час ставится один раз за 90 кадров до снимков — солнце успевает
# довернуться (daynight.gd ведёт его твином 1 с), иначе тени — от прежнего часа, а пятна — уже от нового
const SH := {240: [12.0, 0.35, "noon_on", 0], 255: [12.0, 0.0, "noon_off", 0], 270: [12.0, 0.35, "top_noon_on", 1],
	380: [16.0, 0.35, "late_on", 0], 395: [16.0, 0.0, "late_off", 0], 410: [16.0, 0.35, "top_late_on", 1], 425: [16.0, 0.0, "top_late_off", 1]}
const HOURS := {150: 12.0, 290: 16.0}
const CAMS := [[[-54.0, 7.0, 20.0], [-61.0, 0.5, 9.0]], [[-56.0, 26.0, 6.0], [-56.0, 0.0, 5.9]]]


func _tick() -> void:
	frame += 1
	if frame == 5:
		loc.call("build", {"id": "gharn"})
	var mm: Variant = mod.get("_mm")
	if mm is CanvasItem or mm is CanvasLayer:
		(mm as Object).set("visible", false)            # своё главное меню мода — поверх локации
	if HOURS.has(frame):
		loc.call("set_hour", float(HOURS[frame]))
	for f: int in SH:
		if frame >= f - 8 and frame <= f:
			var dn: Variant = loc.get("_daynight")
			if dn != null:
				(dn as Object).set("spot_k", float(SH[f][1]))
				(dn as Object).call("apply_spots")
			loc.set("_cine", CAMS[int(SH[f][3])])
		if frame == f:
			var sun: Variant = loc.get("_sun")
			print("komorebi: %s sun -Z %s" % [SH[f][2], -(sun as Node3D).global_transform.basis.z if sun != null else Vector3.ZERO])
			_shot(str(SH[f][2]))
	if frame >= 430:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
