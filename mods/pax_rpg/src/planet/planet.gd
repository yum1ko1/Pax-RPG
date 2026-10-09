extends Node
## Юрума вместо Земли и города на ней. Свой шейдер ставится на материал домашней планеты игры (её узел, сетка и
## провинции остаются игровыми — меняется только то, как она нарисована). Города — значки Label3D, дети узла
## планеты: крутятся вместе с ней и прячутся за ней. Щелчок по значку — сигнал city_chosen (дальше travel.gd).

signal city_chosen(city: Dictionary)

const CHECK_EVERY := 1.0           # с. Игра может заново выдать планете материал — проверяем и ставим свой снова
const CLICK_PX := 18.0             # насколько близко к значку надо щёлкнуть, пикселей
const MARKER_LIFT := 1.004         # значок чуть над поверхностью (радиус узла — 1)
const PIXEL_CAPITAL := 0.00045     # размер подписи на экране (fixed_size): столицы крупнее
const PIXEL_TOWN := 0.00035

var mod: PaxMod
var game: PaxGame
var cities: Array = []
var colors: Dictionary = {}
var enabled := true                # false — пока игрок в локации: значки скрыты, щелчки не ловятся

var _shader: Shader
var _surface: Texture2D
var _mat: ShaderMaterial
var _orig_shader: Shader
var _node: Node3D
var _markers: Array[Label3D] = []
var _check := 0.0


func setup(m: PaxMod) -> void:
	mod = m
	name = "PaxRpgPlanet"
	_shader = m.shader("shaders/yuruma.gdshader")
	_surface = m.texture("textures/yuruma_surface.png")
	var parsed: Variant = JSON.parse_string(m.read_text("config/cities.json"))
	var cfg: Dictionary = parsed if parsed is Dictionary else {}
	var list: Variant = cfg.get("cities", [])
	cities = list if list is Array else []
	var cols: Variant = cfg.get("empire_colors", {})
	colors = cols if cols is Dictionary else {}
	if _shader == null or _surface == null:
		m.log_error("Pax RPG: shaders/yuruma.gdshader or textures/yuruma_surface.png did not load")


func start(g: PaxGame) -> void:
	game = g
	_check = 0.0


func _process(delta: float) -> void:
	if game == null:
		return
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_EVERY
		_attach()
	_show_markers(enabled and game.focused_body() == game.home_body())


# ---------- планета ----------

static func _pick(d: Dictionary, keys: Array) -> Variant:
	for k: Variant in keys:
		if d.has(k):
			return d[k]
	return null


func _attach() -> void:
	if _shader == null:
		return
	var body: Dictionary = game.body(game.home_body())
	if body.is_empty():
		return
	var node_v: Variant = _pick(body, ["node", "узел"])
	if not (node_v is Node3D) or not is_instance_valid(node_v):
		return
	var node: Node3D = node_v
	var mat_v: Variant = _pick(body, ["material", "мат", "mat"])
	if not (mat_v is ShaderMaterial) and node is MeshInstance3D:
		mat_v = (node as MeshInstance3D).material_override
	if mat_v is ShaderMaterial and (mat_v as ShaderMaterial).shader != _shader:
		_mat = mat_v
		_orig_shader = _mat.shader
		_mat.shader = _shader
		_mat.set_shader_parameter("surface_map", _surface)
		mod.log_info("Pax RPG: Yuruma is on the planet")
	if node != _node or _markers.is_empty():
		_node = node
		_make_markers()


## Земля как была (мод выключают).
func restore() -> void:
	if is_instance_valid(_mat) and _orig_shader != null:
		_mat.shader = _orig_shader
	for mk in _markers:
		if is_instance_valid(mk):
			mk.queue_free()
	_markers.clear()


# ---------- города ----------

static func dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	# обратное к sph_uv шейдера: u = atan(x, z), v — от полюса по y
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


func _make_markers() -> void:
	for mk in _markers:
		if is_instance_valid(mk):
			mk.queue_free()
	_markers.clear()
	for c: Variant in cities:
		if not (c is Dictionary):
			continue
		var city: Dictionary = c
		var mk := Label3D.new()
		var capital := bool(city.get("capital", false))
		mk.text = ("◆ " if capital else "• ") + mod.tr_key("pax_rpg_city_" + str(city.get("id", "")))
		mk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mk.fixed_size = true
		mk.pixel_size = PIXEL_CAPITAL if capital else PIXEL_TOWN
		mk.font_size = 32
		mk.outline_size = 10
		mk.outline_modulate = Color(0.04, 0.03, 0.12)
		mk.no_depth_test = true          # плоскость подписи режет сферу; дальнюю сторону прячет _show_markers
		mk.render_priority = 10
		mk.modulate = Color.from_string(str(colors.get(str(city.get("empire", "")), "#ffffff")), Color.WHITE)
		mk.position = dir_of(float(city.get("lat", 0.0)), float(city.get("lon", 0.0))) * MARKER_LIFT
		mk.set_meta(&"pax_rpg_city", city)
		_node.add_child(mk)
		_markers.append(mk)


## Значки видны на ближней к камере стороне планеты: подпись шире самой точки, и с дальней стороны её
## края торчали бы из-за диска.
func _show_markers(on: bool) -> void:
	var cam := game.camera()
	var centre := _node.global_position if is_instance_valid(_node) else Vector3.ZERO
	for mk in _markers:
		if not is_instance_valid(mk):
			continue
		var p := mk.global_position
		var see := on and cam != null and (p - centre).dot(cam.global_position - p) > 0.0
		if mk.visible != see:
			mk.visible = see


## Значок под курсором, видимый с камеры (на нашей стороне планеты), или null.
func _city_at(screen: Vector2) -> Label3D:
	var cam := game.camera()
	if cam == null or not is_instance_valid(_node):
		return null
	var centre := _node.global_position
	var best: Label3D = null
	var best_d := CLICK_PX
	for mk in _markers:
		if not is_instance_valid(mk) or not mk.visible:
			continue
		var p := mk.global_position
		if cam.is_position_behind(p) or (p - centre).dot(cam.global_position - p) <= 0.0:
			continue
		var d := cam.unproject_position(p).distance_to(screen)
		if d < best_d:
			best_d = d
			best = mk
	return best


func _input(event: InputEvent) -> void:
	if not enabled or game == null or not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var mk := _city_at(mb.position)
	if mk == null:
		return
	get_viewport().set_input_as_handled()   # щелчок по городу не уходит игре (выбор провинции)
	var city: Dictionary = mk.get_meta(&"pax_rpg_city", {})
	city_chosen.emit(city)
