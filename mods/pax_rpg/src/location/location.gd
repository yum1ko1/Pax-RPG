extends CanvasLayer
## Локация города — прототип механики. Свой 3D-мир в SubViewport поверх игры (own_world_3d: своя физика и свет,
## мир игры его не видит): платформа, несколько блоков, ворота выхода и герой (config/hero.json: модель, скорости,
## комбо; логика анимаций — hero.gd; нет модели — овал). WASD — ходьба относительно камеры, Shift — бег, Пробел —
## прыжок, F — достать / убрать меч, ЛКМ — удар (три подряд — комбо), правая кнопка мыши + движение — поворот
## камеры, E у ворот — назад на карту мира (сигнал exit_requested, дальше travel.gd).

signal exit_requested

const GATE_RADIUS := 2.6           # м, насколько близко к воротам E работает
const FALL_Y := -20.0              # упал с платформы — обратно на старт
const START := Vector3(0.0, 1.2, 8.0)
const Hero := preload("res://mods/pax_rpg/src/location/hero.gd")

var mod: PaxMod
var cfg: Dictionary = {}
var active := false

var _box: SubViewportContainer
var _view: SubViewport
var _player: CharacterBody3D
var _body_mesh: Node3D
var _cam: Camera3D
var _hud: Label
var _gate_pos := Vector3.ZERO
var _city_name := ""
var _yaw := 0.0
var _turning := false
var _near_gate := false
var hero_cfg: Dictionary = {}      # config/hero.json
var _hero: Hero                    # модель и её анимации; null — герой-овал
var _f_down := false               # F была нажата в прошлом кадре — достаём меч по нажатию, не по удержанию
var _f_queued := false             # нажатие F пришло событием (короткое — опрос мог его не застать)
var _lmb_queued := false           # удар (ЛКМ) — до следующего кадра физики
var _space_down := false
var game: PaxGame                  # задаёт travel.gd: пока мы на локации, время мира стоит
var _hold_pause := 0.0             # с; пробел — прыжок, а игра ловит его как «пуск времени» — снова ставим паузу


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgLocation"
	layer = 100
	visible = false
	var parsed: Variant = JSON.parse_string(m.read_text("config/location.json"))
	cfg = parsed if parsed is Dictionary else {}
	var hp: Variant = JSON.parse_string(m.read_text("config/hero.json"))
	hero_cfg = hp if hp is Dictionary else {}


func _f(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# ---------- построить и убрать ----------

func build(city: Dictionary) -> void:
	clear()
	_city_name = mod.tr_key("pax_rpg_city_" + str(city.get("id", "")))
	_box = SubViewportContainer.new()
	_box.stretch = true
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_STOP   # щелчки по локации не доходят до окон игры под ней
	add_child(_box)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_box.add_child(_view)
	_make_sky()
	_make_ground()
	_make_gate()
	_make_player()
	_cam = Camera3D.new()
	_cam.fov = 65.0
	_view.add_child(_cam)
	_cam.current = true
	_hud = Label.new()
	_hud.position = Vector2(24, 20)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color(1.0, 0.92, 0.98))
	_hud.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.12))
	_hud.add_theme_constant_override("outline_size", 6)
	add_child(_hud)
	_yaw = 0.0
	_near_gate = false
	_update_hud()
	visible = true
	active = true


func clear() -> void:
	active = false
	visible = false
	_turning = false
	for n: Node in [_box, _hud]:
		if is_instance_valid(n):
			n.queue_free()
	_box = null
	_view = null
	_player = null
	_cam = null
	_hud = null


func _make_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.85)
	sky_mat.sky_horizon_color = Color(1.0, 0.62, 0.86)     # розовая мановая атмосфера Юрумы
	sky_mat.ground_horizon_color = Color(0.85, 0.55, 0.8)
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_view.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.97)
	sun.shadow_enabled = true
	_view.add_child(sun)


func _solid(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	_view.add_child(body)
	return body


func _make_ground() -> void:
	var s := _f("platform_size", 40.0)
	_solid(Vector3(s, 1.0, s), Vector3(0.0, -0.5, 0.0), Color(0.16, 0.45, 0.58))
	# блоки и ступени — проверить ходьбу, прыжок и упор в стену
	_solid(Vector3(3.0, 1.0, 3.0), Vector3(-8.0, 0.5, 2.0), Color(0.36, 0.38, 0.62))
	_solid(Vector3(3.0, 2.0, 3.0), Vector3(-8.0, 1.0, -1.0), Color(0.42, 0.42, 0.7))
	_solid(Vector3(3.0, 3.0, 3.0), Vector3(-8.0, 1.5, -4.0), Color(0.5, 0.46, 0.78))
	_solid(Vector3(6.0, 2.5, 1.0), Vector3(7.0, 1.25, 0.0), Color(0.3, 0.55, 0.75))
	_solid(Vector3(1.5, 4.0, 1.5), Vector3(9.0, 2.0, 8.0), Color(0.85, 0.85, 0.95))


func _make_gate() -> void:
	var s := _f("platform_size", 40.0)
	_gate_pos = Vector3(0.0, 0.0, -s * 0.5 + 4.0)
	var pillar := Color(0.55, 0.5, 0.8)
	_solid(Vector3(1.0, 4.5, 1.0), _gate_pos + Vector3(-2.2, 2.25, 0.0), pillar)
	_solid(Vector3(1.0, 4.5, 1.0), _gate_pos + Vector3(2.2, 2.25, 0.0), pillar)
	_solid(Vector3(5.4, 0.8, 1.0), _gate_pos + Vector3(0.0, 4.9, 0.0), pillar)
	var glow := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(3.4, 4.4)
	glow.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.45, 0.85, 0.55)
	glow.material_override = mat
	glow.position = _gate_pos + Vector3(0.0, 2.2, 0.0)
	_view.add_child(glow)
	var gate_label := Label3D.new()
	gate_label.text = mod.tr_key("pax_rpg_gate")
	gate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gate_label.font_size = 64
	gate_label.outline_size = 12
	gate_label.position = _gate_pos + Vector3(0.0, 6.0, 0.0)
	_view.add_child(gate_label)


func _make_player() -> void:
	_player = CharacterBody3D.new()
	_player.position = START
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = float(hero_cfg.get("capsule_radius", 0.4))
	cap.height = float(hero_cfg.get("capsule_height", 1.8))
	shape.shape = cap
	_player.add_child(shape)
	_body_mesh = Node3D.new()
	_player.add_child(_body_mesh)
	_hero = Hero.new()
	var model := _hero.load_model(mod, hero_cfg)
	if model != null:
		model.position = Vector3(0.0, -cap.height / 2.0, 0.0)   # ступни — на низ капсулы
		model.rotation.y = PI                                    # glb смотрит на +Z, вперёд у героя — -Z
		_body_mesh.add_child(model)
		_view.add_child(_player)            # сначала в дерево: вне дерева AnimationPlayer не играет
		_hero.start(_player)
		return
	_hero = null
	mod.log_warning("Pax RPG: %s did not load — the hero is an oval" % str(hero_cfg.get("model", "?")))
	# Запасной герой — овал (вытянутая сфера) и «нос» спереди, чтобы видеть, куда он смотрит.
	var oval := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	oval.mesh = sphere
	oval.scale = Vector3(0.8, 1.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.95, 1.0)
	oval.material_override = mat
	_body_mesh.add_child(oval)
	var nose := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.18, 0.18, 0.3)
	nose.mesh = nb
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(1.0, 0.4, 0.8)
	nose.material_override = nmat
	nose.position = Vector3(0.0, 0.45, -0.42)
	_body_mesh.add_child(nose)
	_view.add_child(_player)


func _hf(key: String, fallback: float) -> float:
	return float(hero_cfg.get(key, cfg.get(key, fallback)))


# ---------- управление ----------

func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _physics_process(delta: float) -> void:
	if not active or not is_instance_valid(_player):
		return
	var on_floor := _player.is_on_floor()
	# F и пробел опрашиваем здесь, а не в _input: игра может забрать нажатие раньше нас
	var f := (Input.is_physical_key_pressed(KEY_F) or Input.is_key_pressed(KEY_F)) and not _typing()
	if (_f_queued or (f and not _f_down)) and _hero != null:
		var wasd := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_A) \
			or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_D)
		_hero.toggle_sword(on_floor, wasd)
	_f_queued = false
	_f_down = f
	if _lmb_queued and _hero != null:
		_hero.attack(on_floor)
	_lmb_queued = false
	var locked := _hero != null and _hero.locks_move()
	var input := Vector2.ZERO
	if not _typing() and not locked:
		input = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var forward := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _yaw)
	var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, _yaw)
	var move := right * input.x - forward * input.y
	if move.length() > 1.0:
		move = move.normalized()
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and not (_hero != null and _hero.walk_only())
	var speed := _hf("run_speed", 5.0) if running else _hf("walk_speed", 2.4)
	if _hero != null and (_hero.armed or _hero.walk_only()):
		speed *= _hf("armed_run_factor", 0.8) if running else _hf("armed_speed_factor", 1.0)
	var vel := _player.velocity
	vel.x = move.x * speed
	vel.z = move.z * speed
	var space := Input.is_physical_key_pressed(KEY_SPACE) and not _typing()
	if on_floor:
		if space and not _space_down and not locked:
			if _hero == null or _hero.jump(on_floor):
				vel.y = _hf("jump_speed", 7.0)   # отрыв сразу; анимация прыжка — с момента отрыва
	else:
		vel.y -= _f("gravity", 20.0) * delta
	_space_down = space
	# игра слушает пробел раньше нас и запускает время — пока пробел нажат и чуть после, держим паузу
	if space:
		_hold_pause = 0.3
	if _hold_pause > 0.0:
		_hold_pause -= delta
		if game != null and bool(cfg.get("pause_world", true)):
			game.set_speed(0)
	var moving := move.length() > 0.01 and on_floor
	if _hero != null:
		var r: Dictionary = _hero.tick(delta, moving, speed * move.length(), running, on_floor)
		var step: Vector3 = r.root
		if step != Vector3.ZERO and delta > 0.0:
			# смещение клипа — в осях модели; модель повёрнута вместе с _body_mesh (и на PI внутри него)
			var w := _body_mesh.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI) * step
			vel.x = w.x / delta
			vel.z = w.z / delta
	_player.velocity = vel
	_player.move_and_slide()
	if _hero != null:
		_hero.cape_wind(_player.velocity)
	if move.length() > 0.01 and not locked:
		var want := atan2(-move.x, -move.z)   # «нос» смотрит по -Z
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, want, minf(1.0, delta * 12.0))
	if _player.position.y < FALL_Y:
		_player.position = START
		_player.velocity = Vector3.ZERO
	_follow_camera()
	var near := Vector2(_player.position.x - _gate_pos.x, _player.position.z - _gate_pos.z).length() < GATE_RADIUS
	if near != _near_gate:
		_near_gate = near
		_update_hud()


func _follow_camera() -> void:
	if not is_instance_valid(_cam):
		return
	var target := _player.position + Vector3(0.0, 0.9, 0.0)
	var offset := Vector3(0.0, _f("camera_height", 3.5), _f("camera_distance", 7.0)).rotated(Vector3.UP, _yaw)
	_cam.position = target + offset
	_cam.look_at(target, Vector3.UP)


func _update_hud() -> void:
	if not is_instance_valid(_hud):
		return
	var lines := PackedStringArray([_city_name, mod.tr_key("pax_rpg_controls")])
	if _near_gate:
		lines.append(mod.tr_key("pax_rpg_gate_hint"))
	_hud.text = "\n".join(lines)


const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_F, KEY_Q, KEY_SPACE, KEY_SHIFT]


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_turning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_lmb_queued = true                   # удар; повтор во время удара — следующий удар комбо
		get_viewport().set_input_as_handled()   # колесо и щелчки — не камере игры под локацией
		return
	if event is InputEventMouseMotion:
		if _turning:
			_yaw -= (event as InputEventMouseMotion).relative.x * _f("turn_speed", 0.006)
		return
	if event is InputEventKey and not _typing():
		var key: InputEventKey = event
		if key.physical_keycode in KEYS or key.keycode in KEYS:
			get_viewport().set_input_as_handled()   # горячие клавиши игры молчат, пока герой ходит
		if key.pressed and not key.echo and key.physical_keycode == KEY_E and _near_gate:
			exit_requested.emit()
		if key.pressed and not key.echo and (key.physical_keycode == KEY_F or key.keycode == KEY_F):
			_f_queued = true
