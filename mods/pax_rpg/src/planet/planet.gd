extends Node
const Trace := preload("res://mods/pax_rpg/src/trace.gd")
## Юрума вместо Земли и города на ней. Свой шейдер ставится на материал домашней планеты игры (её узел, сетка и
## провинции остаются игровыми — меняется только то, как она нарисована); облачная оболочка Земли прячется —
## облака маны уже нарисованы на карте Юрумы. Города — экранные подписи того же вида, что подписи игры на
## глобусе (шрифт, размер, обводка берутся у её подписи), над точками-якорями — детьми узла планеты: крутятся
## вместе с ней и прячутся за ней. Щелчок по подписи — сигнал city_chosen (дальше travel.gd).

signal city_chosen(city: Dictionary)

const DayNight := preload("res://mods/pax_rpg/src/location/daynight.gd")
const Quest := preload("res://mods/pax_rpg/src/location/quest.gd")

const CHECK_EVERY := 1.0           # с. Игра может заново выдать планете материал — проверяем и ставим свой снова
const CLICK_PX := 18.0             # насколько близко к значку надо щёлкнуть, пикселей
const MARKER_LIFT := 1.004         # якорь чуть над поверхностью (радиус узла — 1)
const FONT_SIZE := 14              # если подписи игры не нашлось
const OUTLINE := 4

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
var _markers: Array[Node3D] = []   # якоря городов на планете
var _labels: Array[Label] = []     # их подписи на экране, по тем же индексам
var _layer: CanvasLayer
var _clouds: Dictionary = {}       # облачная оболочка игры → её прежние layers
var _check := 0.0
var _orig_params: Dictionary = {}     # параметры родного шейдера планеты (климат, вода, рельеф…) до подмены
var _map_feed := 0.0
var _water_task := -1                 # фоновая сборка маски воды для плоской карты
var _water_img: Image                 # готовая маска: белое — вода (провинции с id 0)
var _albedo_img: Image
var _ocean_tex: Texture2D
var _albedo_tex: Texture2D
var _loc_cfg: Dictionary = {}         # config/location.json — часы мира (start_hour, day_minutes)
var _tip: Label                       # подсказка над городом под курсором: часть суток и час в нём


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
	var lp: Variant = JSON.parse_string(m.read_text("config/location.json"))
	_loc_cfg = lp if lp is Dictionary else {}
	if _shader == null or _surface == null:
		m.log_error("Pax RPG: shaders/yuruma.gdshader or textures/yuruma_surface.png did not load")


func start(g: PaxGame) -> void:
	game = g
	_check = 0.0


func _process(delta: float) -> void:
	if game == null:
		return
	if Engine.get_process_frames() % 30 == 0:
		Trace.mark("planet: frame")           # кадры идут — если след оборвался после этого, упало вне мода
	_check -= delta
	if _check <= 0.0:
		_check = CHECK_EVERY
		Trace.mark("planet: attach")
		_attach()
		Trace.mark("planet: feed map")
		_feed_flat_map()          # заранее, чтобы карта открылась уже правильной
		Trace.mark("planet: feed done")
	_hide_clouds()
	_map_feed -= delta
	if _map_feed <= 0.0 and _flat_map_open():
		_map_feed = 0.25
		_feed_flat_map()
	_show_markers(enabled and game.focused_body() == game.home_body() and not _flat_map_open())
	_update_tip()


## Навёл мышь на город — рядом табличка «Утро · 07:40»: какое время суток застанешь, войдя в него.
func _update_tip() -> void:
	var mk: Node3D = null
	if enabled and is_instance_valid(_layer):
		mk = _city_at(get_viewport().get_mouse_position())
	if mk == null:
		if is_instance_valid(_tip):
			_tip.visible = false
		return
	if not is_instance_valid(_tip):
		_tip = Label.new()
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.14, 0.92)
		sb.border_color = Color(0.86, 0.66, 0.34, 0.9)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(7)
		_tip.add_theme_stylebox_override("normal", sb)
		_tip.add_theme_color_override("font_color", Color(0.96, 0.9, 0.78))
		_tip.add_theme_font_size_override("font_size", 14)
		_layer.add_child(_tip)
	var city: Dictionary = mk.get_meta(&"pax_rpg_city", {})
	var now := DayNight.world_hour(_loc_cfg)
	if bool(city.get("player", false)):
		_tip.text = "%s\n%s" % [mod.tr_key("pax_rpg_map_here"), DayNight.label(mod, now)]
	else:                                                 # путь занимает время: когда герой будет на месте
		var pp := player_pos()
		var deg := rad_to_deg(dir_of(pp.x, pp.y).angle_to(dir_of(float(city.get("lat", 0.0)), float(city.get("lon", 0.0)))))
		var hrs := clampf(deg * 0.6, 0.25, 8.0)
		_tip.text = "%s\n%s\n%s" % [mod.tr_key("pax_rpg_city_" + str(city.get("id", ""))),
			mod.tr_key("pax_rpg_map_travel") % hrs, DayNight.label(mod, fmod(now + hrs, 24.0))]
	_tip.reset_size()
	_tip.position = (get_viewport().get_mouse_position() + Vector2(16, 18)).round()
	_tip.visible = true


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
	# planet_skin (пока выкл.): после обновления игры 0.31.4 она падает через 1–2 с после подмены шейдера планеты.
	if mat_v is ShaderMaterial and (mat_v as ShaderMaterial).shader != _shader and bool(mod.get_setting("planet_skin", false)):
		_mat = mat_v
		_orig_shader = _mat.shader
		_orig_params.clear()
		for u: Dictionary in _orig_shader.get_shader_uniform_list():
			var v: Variant = _mat.get_shader_parameter(u.name)
			if v != null:
				_orig_params[u.name] = v
		_mat.shader = _shader
		_mat.set_shader_parameter("surface_map", _surface)
		mod.log_info("Pax RPG: Yuruma is on the planet")
		Trace.mark("planet: shader swapped")
	if node != _node or _markers.is_empty():
		_node = node
		Trace.mark("planet: markers")
		_make_markers()
	Trace.mark("planet: clouds")
	_find_clouds(node)


## Облака Земли — отдельная сфера чуть больше планеты с шейдером облаков игры, рядом с узлом планеты (сосед
## под Main) или его ребёнок. visible игра ставит сама каждый кадр, поэтому прячем слоями отрисовки.
func _find_clouds(node: Node3D) -> void:
	var cands: Array[Node] = node.get_children()
	if node.get_parent() != null:
		cands.append_array(node.get_parent().get_children())
	for c: Node in cands:
		if not (c is MeshInstance3D) or _clouds.has(c) or c == node:
			continue
		var mi: MeshInstance3D = c
		var m: Material = mi.material_override
		if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			m = mi.get_active_material(0)
		if not (m is ShaderMaterial) or (m as ShaderMaterial).shader == null:
			continue
		var sp := (m as ShaderMaterial).shader.resource_path.to_lower()
		if not sp.contains("cloud") or sp.contains("atmosph"):
			continue
		if mi.get_parent() != node and mi.global_position.distance_to(node.global_position) > 0.05 * maxf(node.scale.x, 0.001):
			continue                          # облака другой планеты
		_clouds[mi] = mi.layers


func _hide_clouds() -> void:
	for mi: Variant in _clouds.keys():
		if not is_instance_valid(mi):
			_clouds.erase(mi)
		elif (mi as MeshInstance3D).layers != 0:
			(mi as MeshInstance3D).layers = 0


## Плоская карта (M) рисует поверхность своим шейдером по параметрам планеты: климат, вода,
## рельеф берутся из материала планеты. После подмены шейдера их там нет — карта получала
## значения по умолчанию (холодный мёртвый мир: всё во льду, розово-фиолетовое). Отдаём ей
## параметры родного шейдера, а снимок Земли и её маску океана заменяем своими — по провинциям Юрумы.
const _MAP_OWN := {"map_albedo": true, "use_map": true, "map_ocean": true, "use_ocean": true,
		"map_height": true, "use_height": true, "height_mode": true}
## Если у планеты нет своих чисел климата — тёплый мокрый мир, чтобы море было морем, а не льдом.
const _WARM := {"temperature": 0.5, "water": 0.7, "biomass": 0.45, "radiation": 0.1, "atmosphere": 0.6}
const WATER_W := 1024                 # маска воды в половинном разрешении карты провинций
const WATER_H := 512
const SEA_COL := Color(0.06, 0.16, 0.34)
const LAND_COL := Color(0.38, 0.42, 0.30)

func _feed_flat_map() -> void:
	if not is_instance_valid(_mat):
		return
	var main := _main()
	if main == null:
		return
	var pm: Variant = main.get("political_map")
	if not (pm is Node):
		return
	var sm_v: Variant = (pm as Node).get("surface_material")
	if not (sm_v is ShaderMaterial) or (sm_v as ShaderMaterial).shader == null:
		return
	var sm: ShaderMaterial = sm_v
	var changed := false
	for u: Dictionary in sm.shader.get_shader_uniform_list():
		var n: String = u.name
		if _MAP_OWN.has(n) or sm.get_shader_parameter(n) != null:
			continue
		var v: Variant = _mat.get_shader_parameter(n)       # игра могла обновить (сезон, вода)
		if v == null:
			v = _orig_params.get(n, _WARM.get(n))
		if v != null:
			sm.set_shader_parameter(n, v)
			changed = true
	changed = _feed_water(sm) or changed
	if changed:
		var vp: Variant = (pm as Node).get("vp")
		if vp is SubViewport:
			(vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


## Вода на плоской карте: маска океана из карты провинций Юрумы (id 0 — море) и простая
## подложка «суша/море». Собирается один раз в фоне, потом отдаётся шейдеру поверхности.
func _feed_water(sm: ShaderMaterial) -> bool:
	if _ocean_tex == null:
		if _water_img != null:
			_ocean_tex = ImageTexture.create_from_image(_water_img)
			_albedo_tex = ImageTexture.create_from_image(_albedo_img)
		elif _water_task < 0:
			var rm: Variant = sm.get_shader_parameter("region_map")
			if not (rm is Texture2D):
				return false
			Trace.mark("planet: region_map.get_image")
			var src := (rm as Texture2D).get_image()
			Trace.mark("planet: get_image done %s" % ("null" if src == null else str(src.get_size())))
			if src == null or src.is_empty():
				return false
			_water_task = WorkerThreadPool.add_task(_build_water.bind(src), false, "pax_rpg water mask")
			return false
		else:
			return false
	if sm.get_shader_parameter("map_ocean") == _ocean_tex:
		return false
	sm.set_shader_parameter("map_ocean", _ocean_tex)
	sm.set_shader_parameter("use_ocean", 1.0)
	sm.set_shader_parameter("map_albedo", _albedo_tex)
	sm.set_shader_parameter("use_map", 1.0)
	sm.set_shader_parameter("use_height", 0.0)
	return true


## В потоке: id провинции — R + G·256; ноль — вода.
func _build_water(src: Image) -> void:
	Trace.mark("planet: water mask start")
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(WATER_W, WATER_H, Image.INTERPOLATE_NEAREST)
	var data := img.get_data()
	var ocean := PackedByteArray()
	ocean.resize(WATER_W * WATER_H)
	var alb := PackedByteArray()
	alb.resize(WATER_W * WATER_H * 3)
	var sea := [int(SEA_COL.r * 255), int(SEA_COL.g * 255), int(SEA_COL.b * 255)]
	var land := [int(LAND_COL.r * 255), int(LAND_COL.g * 255), int(LAND_COL.b * 255)]
	for i in WATER_W * WATER_H:
		var wet := data[i * 4] == 0 and data[i * 4 + 1] == 0
		ocean[i] = 255 if wet else 0
		var c: Array = sea if wet else land
		alb[i * 3] = c[0]
		alb[i * 3 + 1] = c[1]
		alb[i * 3 + 2] = c[2]
	var o := Image.create_from_data(WATER_W, WATER_H, false, Image.FORMAT_L8, ocean)
	var a := Image.create_from_data(WATER_W, WATER_H, false, Image.FORMAT_RGB8, alb)
	Trace.mark("planet: water mask done")
	_set_water.call_deferred(o, a)


func _set_water(o: Image, a: Image) -> void:
	_albedo_img = a
	_water_img = o
	if _water_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_water_task)
	_water_task = -1


## Земля как была (мод выключают).
func restore() -> void:
	var main: Node = _main() if game != null else null
	var pm: Variant = main.get("political_map") if main != null else null
	var sm: Variant = (pm as Node).get("surface_material") if pm is Node else null
	if sm is ShaderMaterial and _ocean_tex != null and (sm as ShaderMaterial).get_shader_parameter("map_ocean") == _ocean_tex:
		for k: String in ["map_ocean", "use_ocean", "map_albedo", "use_map", "use_height"]:
			(sm as ShaderMaterial).set_shader_parameter(k, null)
	if is_instance_valid(_mat) and _orig_shader != null:
		_mat.shader = _orig_shader
	for mi: Variant in _clouds.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).layers = int(_clouds[mi])
	_clouds.clear()
	_free_markers()
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null


func _free_markers() -> void:
	for n: Node in _markers:
		if is_instance_valid(n):
			n.queue_free()
	for n: Node in _labels:
		if is_instance_valid(n):
			n.queue_free()
	_markers.clear()
	_labels.clear()


var _main_node: Node


## Корень сцены игры (PaxGame.main) — один раз: свойство устаревшее и ругается при каждом чтении.
func _main() -> Node:
	if not is_instance_valid(_main_node):
		_main_node = game.main
	return _main_node


## Плоская карта игры (M) открыта — города на глобусе не показываем.
func _flat_map_open() -> bool:
	var main := _main()
	if main == null:
		return false
	var pm: Variant = main.get("political_map")
	return pm is CanvasLayer and is_instance_valid(pm) and (pm as CanvasLayer).visible


# ---------- города ----------

static func dir_of(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	# обратное к sph_uv шейдера: u = atan(x, z), v — от полюса по y
	return Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))


func _make_markers() -> void:
	_free_markers()
	var src := _game_label()
	if not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "PaxRpgCityLabels"
		_layer.layer = src.get_canvas_layer_node().layer if src != null and src.get_canvas_layer_node() != null else 1
		add_child(_layer)
	var list: Array = cities.duplicate()
	var q := Quest.get_q(mod)
	if str(q.get("state", "")) == "active":             # точка задания: лес у города (щелчок — туда)
		list.append({"id": "forest", "seed": int(q.get("seed", 0)), "lat": float(q.get("lat", 0.0)),
			"lon": float(q.get("lon", 0.0)), "quest": true})
	elif str(q.get("state", "")) == "found":             # вещь найдена — вернуть её в город жителя
		for c0: Variant in cities:
			if c0 is Dictionary and str((c0 as Dictionary).get("id", "")) == str(q.get("city", "")):
				var back: Dictionary = (c0 as Dictionary).duplicate()
				back["quest_back"] = true
				back["lat"] = float(back.get("lat", 0.0)) - 1.2   # чуть ниже подписи города
				list.append(back)
	var pp := player_pos()                               # индикатор героя: где он сейчас (щелчком не выбирается)
	list.append({"id": "player", "lat": pp.x, "lon": pp.y, "player": true})
	for c: Variant in list:
		if not (c is Dictionary):
			continue
		var city: Dictionary = c
		var anchor := Node3D.new()
		anchor.position = dir_of(float(city.get("lat", 0.0)), float(city.get("lon", 0.0))) * MARKER_LIFT
		anchor.set_meta(&"pax_rpg_city", city)
		_node.add_child(anchor)
		_markers.append(anchor)
		var lb := Label.new()
		var capital := bool(city.get("capital", false))
		lb.text = ("◆ " if capital else "• ") + mod.tr_key("pax_rpg_city_" + str(city.get("id", "")))
		if bool(city.get("player", false)):
			lb.text = "▲ " + mod.tr_key("pax_rpg_map_you")
		if bool(city.get("quest_back", false)):
			lb.text = "❖ " + mod.tr_key("pax_rpg_quest_back") % [mod.tr_key("pax_rpg_qitem_" + str(q.get("item", ""))),
				str(q.get("npc_name", ""))]
		if bool(city.get("quest", false)):
			lb.text = "❖ " + mod.tr_key("pax_rpg_quest_marker") % mod.tr_key("pax_rpg_qitem_" + str(q.get("item", "")))
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_style(lb, src, Color(0.55, 1.0, 0.75) if bool(city.get("player", false)) else Color(1.0, 0.8, 0.35) if bool(city.get("quest", false)) or bool(city.get("quest_back", false)) else
			Color.from_string(str(colors.get(str(city.get("empire", "")), "#ffffff")), Color.WHITE))
		lb.visible = false
		_layer.add_child(lb)
		lb.reset_size()
		lb.set_meta(&"pax_rpg_dot", _dot_half(lb))
		_labels.append(lb)


## Где герой на глобусе (настройка «player_pos»; новая игра — столица Гхарн): lat, lon.
func player_pos() -> Vector2:
	var p: Variant = mod.get_setting("player_pos", [])
	if p is Array and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	for c: Variant in cities:
		if c is Dictionary and str((c as Dictionary).get("id", "")) == "gharn":
			return Vector2(float(c.get("lat", 0.0)), float(c.get("lon", 0.0)))
	return Vector2.ZERO


## Задание выдано или сдано — значки заново (точка задания появилась или пропала).
func refresh_quest() -> void:
	if is_instance_valid(_node):
		_make_markers()


## Подпись страны/провинции игры на глобусе — образец вида; null, если её нет.
func _game_label() -> Label:
	var main := _main()
	if main == null:
		return null
	for k: String in ["labels", "подписи"]:
		var v: Variant = main.get(k)
		if v is Array:
			for l: Variant in v:
				if l is Label and is_instance_valid(l):
					return l
	return null


## Половина ширины значка в начале подписи — чтобы значок стоял точно на городе.
static func _dot_half(lb: Label) -> float:
	var font: Font = lb.label_settings.font if lb.label_settings != null and lb.label_settings.font != null else lb.get_theme_font("font")
	var fs: int = lb.label_settings.font_size if lb.label_settings != null else lb.get_theme_font_size("font_size")
	if font == null:
		return 6.0
	return font.get_string_size(lb.text.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5


static func _style(lb: Label, src: Label, color: Color) -> void:
	if src != null and src.label_settings != null:
		var ls: LabelSettings = src.label_settings.duplicate()
		ls.font_color = color
		lb.label_settings = ls
		return
	if src != null:
		lb.add_theme_font_override("font", src.get_theme_font("font"))
		lb.add_theme_font_size_override("font_size", src.get_theme_font_size("font_size"))
		lb.add_theme_constant_override("outline_size", src.get_theme_constant("outline_size"))
		lb.add_theme_color_override("font_outline_color", src.get_theme_color("font_outline_color"))
		lb.add_theme_color_override("font_shadow_color", src.get_theme_color("font_shadow_color"))
	else:
		lb.add_theme_font_size_override("font_size", FONT_SIZE)
		lb.add_theme_constant_override("outline_size", OUTLINE)
		lb.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.12))
	lb.add_theme_color_override("font_color", color)


## Подписи видны на ближней к камере стороне планеты и стоят над своими якорями.
func _show_markers(on: bool) -> void:
	var cam := game.camera()
	var centre := _node.global_position if is_instance_valid(_node) else Vector3.ZERO
	for i in _markers.size():
		var mk := _markers[i]
		var lb: Label = _labels[i] if i < _labels.size() else null
		if not is_instance_valid(mk) or not is_instance_valid(lb):
			continue
		var p := mk.global_position
		var see := on and cam != null and not cam.is_position_behind(p) and (p - centre).dot(cam.global_position - p) > 0.0
		if see:
			# значок (◆/•) — ровно на месте города, текст — справа от него, как у подписей игры
			var dot := float(lb.get_meta(&"pax_rpg_dot", 6.0))
			lb.position = (cam.unproject_position(p) - Vector2(dot, lb.size.y * 0.5)).round()
		if lb.visible != see:
			lb.visible = see


## Город под курсором — по его подписи на экране (она видна только на нашей стороне планеты), или null.
func _city_at(screen: Vector2) -> Node3D:
	var cam := game.camera()
	if cam == null or not is_instance_valid(_node):
		return null
	var best: Node3D = null
	var best_d := INF
	for i in mini(_markers.size(), _labels.size()):
		var mk := _markers[i]
		var lb := _labels[i]
		if not is_instance_valid(mk) or not is_instance_valid(lb) or not lb.visible:
			continue
		var r := Rect2(lb.position, lb.size).grow(4.0)
		var d := (r.get_center()).distance_to(screen)
		if (r.has_point(screen) or d < CLICK_PX) and d < best_d:
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
	if bool(city.get("player", false)):
		return                                           # «Вы» — индикатор, не место
	city_chosen.emit(city)
