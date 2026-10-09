extends Node3D
var game := PaxGame.new()
var mod: PaxMod
var t := 0.0
var step := 0
func _ready() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 1.0; sm.height = 2.0
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	var sh := Shader.new(); sh.code = "shader_type spatial; uniform vec3 sun_dir; void fragment(){ ALBEDO = vec3(0.5); }"
	mat.shader = sh
	mi.material_override = mat
	mi.scale = Vector3.ONE * 6.0
	add_child(mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 0, 22)   # look along -Z: we see the planet's +Z side (lon 0)
	cam.current = true
	game.node = mi; game.mat = mat; game.cam = cam
	mod = load("res://mods/pax_rpg/main.gd").new()
	add_child(mod)
	mod._mod_loaded()
	mod._world_ready(game)
func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new(); e.physical_keycode = k; e.keycode = k; e.pressed = down
	Input.parse_input_event(e)
func _physics_process(d: float) -> void:
	t += d
	var travel = mod.get("travel"); var loc = mod.get("location"); var pl = mod.get("planet")
	match step:
		0:
			if t > 1.5:
				print("shader swapped: ", game.mat.shader == pl.get("_shader"), "  markers: ", (pl.get("_markers") as Array).size())
				# rotate planet so a city faces the camera: Gharn lat 0 lon 51.9 → turn by -51.9° about Y
				game.node.rotation.y = deg_to_rad(-51.9)
				game.mat.set_shader_parameter("sun_dir", Vector3(0.95, 0.35, 0.25))
				step = 1; t = 0
		1:
			if t > 0.3:
				get_viewport().get_texture().get_image().save_png("/tmp/pax_rpg_shot_globe.png")
				var best: Label3D = null
				for mk in pl.get("_markers"):
					if (mk as Label3D).get_meta("pax_rpg_city")["id"] == "gharn": best = mk
				var sp := game.cam.unproject_position(best.global_position)
				print("gharn on screen at ", sp, " behind=", game.cam.is_position_behind(best.global_position))
				var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = sp
				Input.parse_input_event(e)
				step = 2; t = 0
		2:
			if t > 0.9 and t < 0.95 + d:
				get_viewport().get_texture().get_image().save_png("/tmp/pax_rpg_shot_loading.png")
			if t > 3.0:
				print("in location: ", loc.get("active"), "  world speed: ", game.speed, "  planet markers on: ", pl.get("enabled"))
				var p0: Vector3 = loc.get("_player").position
				print("player start ", p0)
				_key(KEY_W, true)
				set_meta("p0", p0)
				step = 3; t = 0
		3:
			if t > 1.0:
				_key(KEY_W, false)
				get_viewport().get_texture().get_image().save_png("/tmp/pax_rpg_shot_location.png")
				var p1: Vector3 = loc.get("_player").position
				print("player after 1s W ", p1, " moved ", (p1 - (get_meta("p0") as Vector3)).length())
				_key(KEY_SPACE, true); step = 4; t = 0
		4:
			if t > 0.25:
				print("player y mid-jump ", loc.get("_player").position.y)
				_key(KEY_SPACE, false)
				var gp: Vector3 = loc.get("_gate_pos")
				loc.get("_player").position = gp + Vector3(0, 1.2, 1.0)
				step = 5; t = 0
		5:
			if t > 0.8:
				get_viewport().get_texture().get_image().save_png("/tmp/pax_rpg_shot_gate.png")
				print("near gate: ", loc.get("_near_gate"), " hud: ", (loc.get("_hud") as Label).text.replace("\n", " | "))
				_key(KEY_E, true); _key(KEY_E, false)
				step = 6; t = 0
		6:
			if t > 2.5:
				print("back on map: location active=", loc.get("active"), " markers on=", pl.get("enabled"), " loading busy=", mod.get("loading").busy())
				get_tree().quit()
