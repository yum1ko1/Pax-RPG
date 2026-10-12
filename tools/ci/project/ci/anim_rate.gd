extends SceneTree
var mod: Node
var loc: Node
var frame := 0
var p0 := 0.0
var t0 := 0.0
var phys := 0
func _initialize() -> void:
	root.size = Vector2i(640, 480)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)
	physics_frame.connect(func() -> void: phys += 1)
func _tick() -> void:
	frame += 1
	var h: Object = loc.get("_hero")
	var a: AnimationPlayer = h.get("anim")
	if frame == 60:
		p0 = a.current_animation_position; t0 = Time.get_ticks_msec() / 1000.0; phys = 0
		print("anim ", a.current_animation, " len ", a.current_animation_length, " speed_scale ", a.speed_scale, " cb ", a.callback_mode_process, " time_scale ", Engine.time_scale, " ticks ", Engine.physics_ticks_per_second)
	if frame == 120:
		var dt := Time.get_ticks_msec() / 1000.0 - t0
		print("pos ", p0, " -> ", a.current_animation_position, " real dt ", dt, " phys ticks ", phys, " (60 кадров при fixed-fps 30 = 2 c)")
		quit()
