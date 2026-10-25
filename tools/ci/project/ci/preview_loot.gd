extends SceneTree
## Кадры прокрутки лута (для проверки глазами) без игры: --out=<папка> [--r=4] → loot_*.png.
## Запуск: xvfb-run … --fixed-fps 60 -s res://ci/preview_loot.gd -- --out=…

var roll: Control
var loot_node: Control
var multi := false                   # --multi: три прокрутки друг над другом (старт с разницей 0,7 с)
var out_dir := "/tmp"
var frame := 0
var SHOTS := {120: "loot_d_spin", 177: "loot_e_katin", 189: "loot_f_stand", 193: "loot_g_prep1", 199: "loot_h_cut1", 216: "loot_i_after1", 252: "loot_j_slide", 265: "loot_k_prep2", 271: "loot_l_cut2", 288: "loot_m_after2", 312: "loot_n_reveal", 372: "loot_o_move", 480: "loot_p_rolls"}


func _initialize() -> void:
	var r := 4
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--kat="):
			kat_dir = a.trim_prefix("--kat=")
		elif a == "--multi":
			multi = true
		elif a.begins_with("--r="):
			r = int(a.trim_prefix("--r="))
	root.size = Vector2i(1920, 1080)
	var mod: Node = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.40, 0.38)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var loot: Control = (load("res://mods/pax_rpg/src/location/loot/loot.gd") as GDScript).new()
	loot.call("setup", mod)
	root.add_child(loot)
	roll = (loot.get("_rolls") as Array)[0]
	loot_node = loot
	roll.set("anchor", Vector2(1920 - 480, 1080 - 175))
	var doc := GLTFDocument.new()                        # катана: в CI заглушка mod.model() пустая — грузим .glb сами
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path("res://mods/pax_rpg/models/weapons/katana.glb"), st) == OK:
		var kat := doc.generate_scene(st) as Node3D
		_dds_textures(kat, "res://mods/pax_rpg/models/weapons/katana.tex/")
		roll.call("set_katana", kat)
	roll.set("hero_lvl", 20)
	roll.call("start", r)
	process_frame.connect(_tick)


var _orb_shots := false
var kat_dir := ""                    # --kat=<папка>: кадры катаны (её SubViewport) от появления до ухода — для HTML-версии
var _kat_n := 0


func _tick() -> void:
	frame += 1
	if multi:
		if frame == 40 or frame == 82:
			loot_node.call("_start", 1 if frame == 40 else 2, 2)
		if frame in [150, 330, 420]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out_dir.path_join("multi_%d.png" % frame))
		if frame > 430:
			quit(0)
		return
	if kat_dir != "":
		var t := float(roll.get("_t"))
		var k0 := float(roll.call("_kat_t"))
		if t >= k0 and t < k0 + 2.2:
			await RenderingServer.frame_post_draw
			var vp: SubViewport = roll.get("_vp")
			vp.get_texture().get_image().save_png(kat_dir.path_join("k_%03d.png" % _kat_n))
			_kat_n += 1
		elif t >= k0 + 2.2:
			print("katana frames: ", _kat_n)
			quit(0)
		return
	if not _orb_shots and float(roll.get("_tip_at")) > 0.0:   # кадры сферы — от времени, когда закрылось окно
		_orb_shots = true
		var t := float(roll.get("_t"))
		var at := float(roll.get("_orb_at"))
		for d: Array in [[0.15, "loot_r_shrink"], [0.65, "loot_s_fly"], [1.02, "loot_t_bag"], [1.3, "loot_u_bag2"]]:
			SHOTS[frame + roundi((at - t + float(d[0])) * 60.0)] = d[1]
	if SHOTS.has(frame):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join(str(SHOTS[frame]) + ".png"))
		print("shot ", SHOTS[frame])
	if frame > 1100:
		quit(0)


## Как Assets._textures: картинки glb — заглушки 1×1, настоящие — t<N>.dds по порядку обхода.
func _dds_textures(m: Node3D, dir: String) -> void:
	const SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
		BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION,
		BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]
	var seen: Array = []
	for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		for si: int in inst.mesh.get_surface_count():
			var mat := inst.get_surface_override_material(si)
			if mat == null:
				mat = inst.mesh.surface_get_material(si)
			if not (mat is BaseMaterial3D):
				continue
			for slot: int in SLOTS:
				var t: Texture2D = (mat as BaseMaterial3D).get_texture(slot)
				if t == null or seen.has(t):
					continue
				seen.append(t)
				var img := Image.new()
				if img.load_dds_from_buffer(FileAccess.get_file_as_bytes(dir + "t%d.dds" % (seen.size() - 1))) != OK:
					continue
				var it := ImageTexture.create_from_image(img)
				for sl: int in SLOTS:
					if (mat as BaseMaterial3D).get_texture(sl) == t:
						(mat as BaseMaterial3D).set_texture(sl, it)
