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
const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const HERO_HP := 100.0
const HERO_POSTURE := 100.0

var mod: PaxMod
var cfg: Dictionary = {}
var active := false

var _box: SubViewportContainer
var _view: SubViewport
var _player: CharacterBody3D
var _body_mesh: Node3D
var _cam: Camera3D
var _hud: Hud                      # HUD «Сакура и сталь» (hud.gd)
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
var _alt_down := false             # уворот — по нажатию Alt, не по удержанию
var game: PaxGame                  # задаёт travel.gd: пока мы на локации, время мира стоит
var test_mode := false             # тестовая арена из главного меню (герой + гоблин), выход — обратно в меню
var _goblins: Array = []
var _hp := HERO_HP
var _posture := 0.0                # концентрация героя (Sekiro): блоки копят, переполнилась — стойка сломана
var _since_hit := 99.0
var _stagger := 0.0                # с, сломанная стойка — управление на миг отнято
var _lock: Node3D                  # захваченный враг (Q): камера держит его, герой стоит к нему лицом
var _lock_mark: MeshInstance3D
var _rmb := false
var _cam_lock := 0.0               # 0 — свободная камера, 1 — за плечом при захвате (плавно между)
var _lock_point := Vector3.ZERO
var _kills := 0
var _mana := 0                     # мана из повергнутых врагов (распыляются в ману)
var _xp := 0.0                     # доля до следующего уровня
var _level := 1
var _flask := 3                    # заряды эликсира (R)
var _hp_ghost := 1.0               # розовый «след» недавней потери здоровья на полосе
var _numbers: Array = []           # цифры урона: {pos: Vector3, v, crit, t}
var _toast: Dictionary = {}        # уведомление слева: {text, t}
var _hint_t := 25.0                # с, сколько ещё видна подсказка управления (H — показать снова)
var _dead_seen: Dictionary = {}    # id гоблина → уже засчитан повергнутым
var _map_rects: Array = []         # [центр XZ, размер XZ, цвет] — платформы для миникарты
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

## Кнопка «Тест» главного меню: арена — та же площадка, герой и гоблин; ворота возвращают в меню.
func build_test() -> void:
	build({"id": "test"})
	test_mode = true
	_city_name = mod.tr_key("pax_rpg_menu_test")
	_update_hud()


## Гоблины локации (config/location.json → goblins): полукругом перед героем, между ним и воротами.
func _spawn_goblins(n: int) -> void:
	for i: int in n:
		var g := Goblin.new()
		var a := (float(i) - (n - 1) * 0.5) * 0.6
		g.setup(mod, _player, _on_hero_hit, START + Vector3(sin(a) * 9.0, -1.0, -cos(a) * 9.0), _hero_attacking,
			_hero_blocking)
		_view.add_child(g)
		_goblins.append(g)


func build(city: Dictionary) -> void:
	clear()
	test_mode = false
	_hp = HERO_HP
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
	_map_rects.clear()
	_make_sky()
	_make_ground()
	_make_gate()
	_make_player()
	_spawn_goblins(int(cfg.get("goblins", 1)))
	_cam = Camera3D.new()
	_cam.fov = 65.0
	_view.add_child(_cam)
	_cam.current = true
	_hud = Hud.new()
	_hud.setup(mod, mod.texture(str(hero_cfg.get("enemy_portrait", "models/goblin/portrait.png"))))
	add_child(_hud)
	_yaw = 0.0
	_near_gate = false
	_flask = int(_hf("flask_charges", 3.0))
	_hp_ghost = 1.0
	_numbers.clear()
	_toast = {}
	_hint_t = 25.0
	_dead_seen.clear()
	_lock_mark = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1.0, 1.0, 1.0)
	lmat.no_depth_test = true
	lm.material = lmat
	_lock_mark.mesh = lm
	_lock_mark.visible = false
	_view.add_child(_lock_mark)
	_lock = null
	_posture = 0.0
	_stagger = 0.0
	_update_hud()
	visible = true
	active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED     # камера — мышью, без зажатой кнопки (ПКМ — блок)


func clear() -> void:
	if active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	active = false
	visible = false
	_turning = false
	for n: Node in [_box, _hud]:
		if is_instance_valid(n):
			n.queue_free()
	_goblins.clear()
	test_mode = false
	_lock = null
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
	var big := size.x >= 20.0
	_map_rects.append([Vector2(pos.x, pos.z), Vector2(size.x, size.z),
		Color(0.11, 0.16, 0.35) if big else Color(0.2, 0.27, 0.55)])
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
	_stagger = maxf(0.0, _stagger - delta)
	_since_hit += delta
	_regen_posture(delta)
	if _hero != null:
		_hero.combat = _hud_enemy() != null
	if _lock != null and (not is_instance_valid(_lock) or not (_lock as Goblin).is_alive()
			or _lock.global_position.distance_to(_player.global_position) > 22.0):
		_set_lock(null)
	if _lmb_queued and _hero != null and _stagger <= 0.0:
		if not _try_deathblow():
			if _hero.action == "":
				var tg := _attack_target()
				_face_now(_yaw_to(tg) if tg != null else _aim_yaw())   # удар — во врага рядом, иначе куда камера
			_hero.attack(on_floor)
	_lmb_queued = false
	if _hero != null:
		_hero.set_block(_rmb and _stagger <= 0.0)
	var locked := _hero != null and (_hero.locks_move() or _stagger > 0.0)
	var input := Vector2.ZERO
	if not _typing() and not locked:
		input = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var forward := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, _yaw)
	var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, _yaw)
	var move := right * input.x - forward * input.y
	if move.length() > 1.0:
		move = move.normalized()
	# уворот (Alt): развернуть героя по вводу (без ввода — куда смотрит) и кувырок; дальше его ведёт root motion
	var alt := Input.is_physical_key_pressed(KEY_ALT) and not _typing()
	if alt and not _alt_down and not locked and _hero != null:
		var wish := right * input.x - forward * input.y
		if _hero.dodge(on_floor):
			if wish.length() > 0.01:
				_body_mesh.rotation.y = atan2(-wish.x, -wish.z)
			locked = true
	_alt_down = alt
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and not (_hero != null and (_hero.walk_only()
		or _hero.blocking))
	var speed := _hf("run_speed", 5.0) if running else _hf("walk_speed", 2.4)
	if _hero != null and (_hero.armed or _hero.walk_only()):
		speed *= _hf("armed_run_factor", 0.8) if running else _hf("armed_speed_factor", 1.0)
	if _hero != null and _hero.blocking:
		speed *= _hf("block_speed_factor", 0.55)
	elif _lock != null and not running:
		speed *= _hf("lock_speed_factor", 0.75)          # в поединке — осторожный шаг
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
	# куда стоит лицом: в захваченного врага; на бегу — по ходу; шагом — туда же, куда камера
	# без оружия и без захвата — идёт лицом по ходу (как Sekiro вне захвата); боком и спиной — только с мечом, в блоке, в захвате
	var free_walk := moving and _hero != null and not _hero.armed and not _hero.blocking and _lock == null \
		and not bool(cfg.get("strafe_unarmed", false))
	if not locked:
		var face := INF
		if _lock != null and not running:
			face = _aim_yaw()
		elif moving and (running or free_walk):
			face = atan2(-move.x, -move.z)
		elif moving or (_hero != null and _hero.blocking):
			face = _yaw
		if face != INF:
			_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, face, minf(1.0, delta * 12.0))
	# магнит ударов: каждый удар комбо доворачивает к врагу, шаг удара не проносит сквозь него
	var mag: Goblin = _attack_target() if _hero_attacking() else null
	if mag != null:
		_body_mesh.rotation.y = lerp_angle(_body_mesh.rotation.y, _yaw_to(mag), minf(1.0, delta * _hf("magnet_turn", 14.0)))
	if _hero != null:
		var by := _body_mesh.rotation.y
		var bf := Vector3(-sin(by), 0.0, -cos(by))
		var br := Vector3(cos(by), 0.0, -sin(by))
		_hero.move_dir = Vector2(0.0, 1.0) if free_walk else Vector2(move.dot(br), move.dot(bf))
	if _hero != null:
		var r: Dictionary = _hero.tick(delta, moving, speed * move.length(), running, on_floor)
		var step: Vector3 = r.root
		if r.has("hit"):
			_strike(r.hit)
		if step != Vector3.ZERO and delta > 0.0:
			# смещение клипа — в осях модели; модель повёрнута вместе с _body_mesh (и на PI внутри него)
			var w := _body_mesh.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI) * step
			vel.x = w.x / delta
			vel.z = w.z / delta
		if mag != null:
			vel = _magnet_pull(vel, mag, delta)
	_player.velocity = vel
	_player.move_and_slide()
	if _hero != null:
		_hero.cape_wind(_player.velocity)
	if _lock != null:
		var d := _lock.global_position - _player.global_position
		_yaw = lerp_angle(_yaw, atan2(-d.x, -d.z), minf(1.0, delta * 6.0))
	if is_instance_valid(_lock_mark):
		_lock_mark.visible = false                   # прицел захвата рисует HUD
	if _player.position.y < FALL_Y:
		_player.position = START
		_player.velocity = Vector3.ZERO
	_follow_camera(delta)
	var near := Vector2(_player.position.x - _gate_pos.x, _player.position.z - _gate_pos.z).length() < GATE_RADIUS
	if near != _near_gate:
		_near_gate = near
		_update_hud()


## Камера: свободная — сзади и сверху; при захвате врага плавно подлетает к герою и встаёт за правым плечом,
## глядя на середину между героем и врагом — обоих видно, удобно читать замахи.
func _follow_camera(delta := 0.0) -> void:
	if not is_instance_valid(_cam):
		return
	var want := 1.0 if (_lock != null and is_instance_valid(_lock)) else 0.0
	_cam_lock = move_toward(_cam_lock, want, delta * _f("lock_camera_speed", 2.5)) if delta > 0.0 else want
	var k := smoothstep(0.0, 1.0, _cam_lock)
	var target := _player.position + Vector3(0.0, 0.9, 0.0)
	var free_pos := target + Vector3(0.0, _f("camera_height", 3.5), _f("camera_distance", 7.0)).rotated(Vector3.UP, _yaw)
	var look := target
	var pos := free_pos
	if k > 0.0:
		var back := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, _yaw)
		var right := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, _yaw)
		var shoulder := _player.position + Vector3(0.0, _f("lock_camera_height", 1.75), 0.0) \
			+ right * _f("lock_camera_side", 0.9) + back * _f("lock_camera_distance", 3.2)
		var enemy := _lock_point if want == 0.0 else _lock.global_position + Vector3(0.0, 0.9, 0.0)
		if want > 0.0:
			_lock_point = enemy
		var lock_look := (_player.position + Vector3(0.0, 1.4, 0.0)).lerp(enemy, 0.55)
		pos = free_pos.lerp(shoulder, k)
		look = target.lerp(lock_look, k)
	_cam.position = pos
	_cam.look_at(look, Vector3.UP)


## Удар героя по врагам рядом: в пределах range и перед ним (arc — косинус полуугла; -1 — по кругу, удар о землю).
func _strike(hit: Dictionary) -> void:
	var fwd := -_body_mesh.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var to := gob.global_position - _player.global_position
		to.y = 0.0
		var d := to.length()
		if d > float(hit.range) + 0.35:
			continue
		if d > 0.3 and fwd.dot(to / d) < float(hit.arc):
			continue
		gob.take_damage(float(hit.damage), _player.global_position, bool(hit.get("knock", false)))
		_numbers.append({"pos": gob.global_position + Vector3(randf_range(-0.3, 0.3), 1.3, 0.0),
			"v": int(hit.damage), "crit": bool(hit.get("knock", false)), "t": 0.0})


# ---------- бой как в Sekiro ----------

## Куда целиться: в захваченного врага, иначе — туда, куда смотрит камера.
func _aim_yaw() -> float:
	if _lock != null:
		var d := _lock.global_position - _player.global_position
		return atan2(-d.x, -d.z)
	return _yaw


## Подтяг удара к врагу: до мига удара герой доходит (у финального — долетает) до дистанции reach, чтобы клинок
## попал по врагу, а не по воздуху; ближе reach шаг клипа не несёт — не влезает во врага.
func _magnet_pull(vel: Vector3, mag: Goblin, delta: float) -> Vector3:
	var to := mag.global_position - _player.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.01 or delta <= 0.0:
		return vel
	var dir := to / dist
	var reach := _hero.attack_reach()
	var gap := dist - reach
	var along := vel.x * dir.x + vel.z * dir.z
	var tl := _hero.hit_time_left()
	if tl >= 0.0 and _hero.pull_on() and gap > 0.0:
		var need := minf(gap / maxf(tl, 0.06), _hf("magnet_pull_max", 8.0))
		if need > along:
			vel.x += dir.x * (need - along)
			vel.z += dir.z * (need - along)
			along = need
	if along > 0.0 and along * delta > gap:                  # за кадр не проскочить ближе reach
		var cut := along - maxf(gap, 0.0) / delta
		vel.x -= dir.x * cut
		vel.z -= dir.z * cut
	return vel


## Цель удара: захваченный враг, иначе ближайший живой в magnet_range перед камерой (в пределах magnet_angle),
## а вплотную (magnet_close) — с любой стороны.
func _attack_target() -> Goblin:
	if _lock != null and is_instance_valid(_lock) and (_lock as Goblin).is_alive():
		return _lock as Goblin
	var best: Goblin = null
	var bd := _hf("magnet_range", 5.0)
	var cone := deg_to_rad(_hf("magnet_angle", 75.0))
	var ref := _body_mesh.rotation.y if _hero != null and _hero.action in Hero.ATTACKS else _yaw
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		if not gob.is_alive():
			continue
		var d := gob.global_position.distance_to(_player.global_position)
		if d < bd and (d < _hf("magnet_close", 3.0) or absf(angle_difference(ref, _yaw_to(gob))) < cone):
			bd = d
			best = gob
	return best


func _yaw_to(n: Node3D) -> float:
	var d := n.global_position - _player.global_position
	return atan2(-d.x, -d.z)


func _face_now(yaw: float) -> void:
	_body_mesh.rotation.y = yaw


func _hero_attacking() -> bool:
	return _hero != null and _hero.action in Hero.ATTACKS


func _hero_blocking() -> bool:
	return _hero != null and _hero.blocking


## Q: захватить ближнего врага перед камерой (до 16 м) / отпустить.
func _toggle_lock() -> void:
	if _lock != null:
		_set_lock(null)
		return
	var cam_f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var best: Node3D = null
	var best_s := INF
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var to := gob.global_position - _player.global_position
		to.y = 0.0
		var d := to.length()
		if d > 16.0:
			continue
		var score := d * (2.0 - cam_f.dot(to / maxf(d, 0.01)))   # ближе и прямее перед камерой — лучше
		if score < best_s:
			best_s = score
			best = gob
	_set_lock(best)


func _set_lock(t: Node3D) -> void:
	_lock = t
	if is_instance_valid(_lock_mark):
		_lock_mark.visible = false


## ЛКМ рядом с врагом без равновесия (красная метка) — добивание вместо удара.
func _try_deathblow() -> bool:
	if _hero == null:
		return false
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		if not gob.can_deathblow():
			continue
		var to := gob.global_position - _player.global_position
		to.y = 0.0
		if to.length() > _hf("deathblow_range", 2.8):
			continue
		_face_now(atan2(-to.x, -to.z))
		if _hero.deathblow():
			get_tree().create_timer(_hf("deathblow_hit", 1.1)).timeout.connect(gob.deathblow)
			return true
	return false


## Удар гоблина по герою: кувырок — мимо; парирование в первые доли секунды блока — отбит, у врага сбита
## концентрация; блок — урона нет, но копится своя концентрация (переполнилась — стойка сломана); иначе — урон.
func _on_hero_hit(damage: float, attacker: Node3D = null) -> void:
	if _hero != null and _hero.invulnerable():
		return
	var fwd := Vector3(-sin(_body_mesh.rotation.y), 0.0, -cos(_body_mesh.rotation.y))
	var facing := true
	if attacker != null:
		var to := attacker.global_position - _player.global_position
		to.y = 0.0
		facing = to.length() < 0.01 or fwd.dot(to.normalized()) > 0.2
	var spark_at := _player.global_position + fwd * 0.7 + Vector3(0.0, 1.2, 0.0)
	if _hero != null and facing and _hero.parry_window():
		_hero.deflect()
		_posture = minf(HERO_POSTURE, _posture + 4.0)
		_sparks(spark_at, Color(1.0, 0.8, 0.35), 40, 5.0)
		if attacker is Goblin:
			(attacker as Goblin).deflected(_player.global_position)
		return
	if _hero != null and facing and _hero.blocking:
		_posture = minf(HERO_POSTURE, _posture + damage * 2.2)
		_since_hit = 0.0
		_sparks(spark_at, Color(1.0, 0.6, 0.25), 14, 3.0)
		_player.velocity -= fwd * 3.0
		if attacker is Goblin:
			(attacker as Goblin).blocked()
		if _posture >= HERO_POSTURE:
			_posture = HERO_POSTURE * 0.35
			_stagger = _hf("guard_break_time", 1.2)
			_hero.set_block(false)
			_hero.hurt()
		return
	_hp = maxf(0.0, _hp - damage)
	_posture = minf(HERO_POSTURE, _posture + damage * 0.8)
	_since_hit = 0.0
	if _hero != null:
		_hero.hurt()
	if _hp <= 0.0 and is_instance_valid(_player):
		_hp = HERO_HP
		_hp_ghost = 1.0
		_posture = 0.0
		_flask = int(_hf("flask_charges", 3.0))
		_player.position = START
		_player.velocity = Vector3.ZERO
	_update_hud()


func _regen_posture(delta: float) -> void:
	if _since_hit < 1.0 or _posture <= 0.0:
		return
	var rate := _hf("posture_regen_block", 10.0) if (_hero != null and _hero.blocking) else _hf("posture_regen", 22.0)
	_posture = maxf(0.0, _posture - rate * delta)


## Искры: блок и парирование.
func _sparks(at: Vector3, color: Color, amount: int, speed: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.35
	p.spread = 70.0
	p.direction = Vector3.UP
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -9.0, 0.0)
	var q := SphereMesh.new()
	q.radius = 0.018
	q.height = 0.036
	q.radial_segments = 4
	q.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	q.material = m
	p.mesh = q
	_view.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


func _hud_enemy() -> Goblin:
	if _lock != null and is_instance_valid(_lock) and (_lock as Goblin).is_alive():
		return _lock as Goblin
	var best: Goblin = null
	var bd := 15.0
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		if not gob.in_combat():
			continue
		var d := gob.global_position.distance_to(_player.global_position)
		if d < bd:
			bd = d
			best = gob
	return best


func _update_hud() -> void:
	if is_instance_valid(_hud):
		_hud_tick(0.0)


## Эликсир (R): лечит, зарядов мало — пополняются, когда герой пал и вернулся на старт.
func _drink() -> void:
	if _flask <= 0 or _hp >= HERO_HP or _stagger > 0.0 or not is_instance_valid(_player):
		return
	_flask -= 1
	_hp = minf(HERO_HP, _hp + _hf("flask_heal", 45.0))
	_sparks(_player.global_position + Vector3(0.0, 1.0, 0.0), Color(1.0, 0.55, 0.78), 30, 2.5)


func _process(delta: float) -> void:
	if active and is_instance_valid(_hud):
		_hud_tick(delta)


## Состояние HUD на кадр: герой, компас, миникарта, враг, цифры урона, мана и опыт за повергнутых.
func _hud_tick(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_cam):
		return
	for g: Variant in _goblins:
		if not is_instance_valid(g):
			continue
		var gob: Goblin = g
		var id := gob.get_instance_id()
		if not gob.is_alive() and not bool(_dead_seen.get(id, false)):
			_dead_seen[id] = true
			_kills += 1
			var gain := int(_hf("mana_per_kill", 25.0))
			_mana += gain
			_xp += _hf("xp_per_kill", 0.34)
			_toast = {"text": mod.tr_key("pax_rpg_hud_got") % [mod.tr_key("pax_rpg_hud_mana_item"), gain], "t": 0.0}
			if _xp >= 1.0:
				_xp -= 1.0
				_level += 1
				_toast = {"text": mod.tr_key("pax_rpg_hud_level_up") % _level, "t": 0.0}
		elif gob.is_alive():
			_dead_seen[id] = false
	var hp := _hp / HERO_HP
	if hp >= _hp_ghost:
		_hp_ghost = hp
	elif _since_hit > 0.6:
		_hp_ghost = move_toward(_hp_ghost, hp, delta * 0.6)
	_hint_t = maxf(0.0, _hint_t - delta)
	var st := {"hp": hp, "hp_ghost": _hp_ghost, "hp_abs": _hp, "hp_max": HERO_HP, "posture": _posture / HERO_POSTURE,
		"level": _level, "xp": _xp, "mana": _mana, "flask": _flask, "flask_max": int(_hf("flask_charges", 3.0)),
		"yaw": _yaw, "body_yaw": _body_mesh.rotation.y if _body_mesh != null else _yaw, "kills": _kills,
		"me": Vector2(_player.global_position.x, _player.global_position.z), "map_rects": _map_rects,
		"gate": Vector2(_gate_pos.x, _gate_pos.z), "near_gate": _near_gate, "place": _city_name,
		"hint": mod.tr_key("pax_rpg_controls"), "hint_a": clampf(_hint_t, 0.0, 1.0),
		"gate_hint": mod.tr_key("pax_rpg_gate_hint") if _near_gate else ""}
	var targets: Array = []
	var enemies: Array = []
	for g: Variant in _goblins:
		if not is_instance_valid(g) or not (g as Goblin).is_alive():
			continue
		var gob: Goblin = g
		var d := gob.global_position.distance_to(_player.global_position)
		var locked := gob == _lock
		enemies.append({"pos": Vector2(gob.global_position.x, gob.global_position.z), "locked": locked})
		if d < 45.0:
			targets.append({"yaw": _yaw_to(gob), "dist": d, "color": Color(1.0, 0.36, 0.56) if locked
				else Color(1.0, 0.55, 0.78)})
	targets.append({"yaw": atan2(-(_gate_pos.x - _player.global_position.x), -(_gate_pos.z - _player.global_position.z)),
		"dist": Vector2(_gate_pos.x - _player.global_position.x, _gate_pos.z - _player.global_position.z).length(),
		"color": Color(0.47, 0.84, 1.0), "ring": true})
	st["targets"] = targets
	st["enemies"] = enemies
	var e := _hud_enemy()
	if e != null:
		st["enemy"] = {"name": mod.tr_key("pax_rpg_goblin"), "hp": e.hp / Goblin.MAX_HP,
			"posture": e.posture / Goblin.MAX_POSTURE, "broken": e.can_deathblow()}
		st["ult"] = e.posture / Goblin.MAX_POSTURE if not e.can_deathblow() else 1.0
		st["ult_ready"] = e.can_deathblow()
	if _lock != null and is_instance_valid(_lock):
		var lp := _lock.global_position + Vector3(0.0, 0.85, 0.0)
		if not _cam.is_position_behind(lp):
			st["lock_screen"] = _cam.unproject_position(lp)
			st["lock_broken"] = (_lock as Goblin).can_deathblow()
	var nums: Array = []
	for i: int in range(_numbers.size() - 1, -1, -1):
		var n: Dictionary = _numbers[i]
		n.t = float(n.t) + delta
		if float(n.t) > 1.1:
			_numbers.remove_at(i)
			continue
		var wp: Vector3 = n.pos + Vector3(0.0, float(n.t) * 0.7, 0.0)
		if _cam.is_position_behind(wp):
			continue
		nums.append({"p": _cam.unproject_position(wp), "v": n.v, "crit": n.crit,
			"a": 1.0 - smoothstep(0.65, 1.1, float(n.t))})
	st["numbers"] = nums
	if not _toast.is_empty():
		_toast.t = float(_toast.t) + delta
		if float(_toast.t) > 3.5:
			_toast = {}
		else:
			st["toast"] = {"text": _toast.text, "a": 1.0 - smoothstep(2.8, 3.5, float(_toast.t))}
	var act := _hero.action if _hero != null else ""
	st["skills"] = [
		{"k": "斬", "key": mod.tr_key("pax_rpg_key_lmb"), "label": mod.tr_key("pax_rpg_hud_attack"),
			"on": act in Hero.ATTACKS, "color": Color(1.0, 0.55, 0.78)},
		{"k": "盾", "key": mod.tr_key("pax_rpg_key_rmb"), "label": mod.tr_key("pax_rpg_hud_block"),
			"on": _hero != null and _hero.blocking, "color": Color(0.47, 0.84, 1.0)},
		{"k": "風", "key": "Alt", "label": mod.tr_key("pax_rpg_hud_dodge"), "on": act in ["Dodge", "DodgeArmed"],
			"color": Color(0.47, 0.84, 1.0)},
		{"k": "鎖", "key": "Q", "label": mod.tr_key("pax_rpg_hud_lock"), "on": _lock != null,
			"color": Color(1.0, 0.55, 0.78)}]
	_hud.st = st
	_hud.refresh()


const KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_E, KEY_F, KEY_Q, KEY_SPACE, KEY_SHIFT, KEY_ALT, KEY_C, KEY_R, KEY_H]


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # вернуть мышь камере (Esc её отпускал)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = mb.pressed                       # блок; первые доли секунды — парирование
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			_toggle_lock()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_lmb_queued = true                   # удар; повтор во время удара — следующий удар комбо
		get_viewport().set_input_as_handled()   # колесо и щелчки — не камере игры под локацией
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and _lock == null:
			_yaw -= (event as InputEventMouseMotion).relative.x * _f("turn_speed", 0.004)
		return
	if event is InputEventKey and not _typing():
		var key: InputEventKey = event
		if key.physical_keycode in KEYS or key.keycode in KEYS:
			get_viewport().set_input_as_handled()   # горячие клавиши игры молчат, пока герой ходит
		if key.pressed and not key.echo and key.physical_keycode == KEY_E and _near_gate:
			exit_requested.emit()
		if key.pressed and not key.echo and key.physical_keycode == KEY_Q:
			_toggle_lock()                           # захват цели (как в Sekiro)
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if key.pressed and not key.echo and key.physical_keycode == KEY_R:
			_drink()                                 # эликсир
		if key.pressed and not key.echo and key.physical_keycode == KEY_H:
			_hint_t = 0.0 if _hint_t > 0.0 else 25.0  # подсказка управления
		if key.pressed and not key.echo and key.physical_keycode == KEY_C and _hero != null:
			_hero.toggle_slot("back")                # снять / надеть плащ
		if key.pressed and not key.echo and (key.physical_keycode == KEY_F or key.keycode == KEY_F):
			_f_queued = true
