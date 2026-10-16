extends Node
## Ультимейт копья Тян Луна «Алый Закат» (G) — кат-сцена в духе ульт Genshin: клип UltSpear (3 с) ведёт героя
## (root motion), а этот узел — цель, камеру и оформление. По клипу: укол — микростан (STUN), удар с разворота —
## цель отлетает (SPIN), герой скользит, цепляя копьём пол, — подножка (TRIP), цель падает и встаёт —
## удар в спину (BACK). Цель на время сцены ведётся по пути (goblin.gd → cine), свою физику не считает.
## Камера — планы со склейками на ударах; полосы кино, имя приёма, вспышки, замирания на ударах, алые искры.

const T_STUN := 0.55
const T_SPIN := 1.1
const T_LAND := 1.72
const T_TRIP := 1.97
const T_GETUP := 2.3
const T_BACK := 2.63
const LENGTH := 3.0
const CRIMSON := Color(1.0, 0.16, 0.12)

var loc: Node                      # location.gd (его поля — без типов: свой класс там не объявлен)
var hero: Object                   # hero.gd (не узел)
var target: Node3D                 # враг (goblin.gd) или null
var _t := 0.0
var _on := false
var _p0 := Vector3.ZERO            # где герой начал
var _fwd := Vector3.FORWARD        # куда смотрит (в мире, по земле)
var _right := Vector3.RIGHT
var _ground := 0.0
var _t_from := Vector3.ZERO        # откуда цель подтягивается в начале
var _done := {}                    # какие удары уже были
var _ui: CanvasLayer
var _bars: Array = []
var _title: Label
var _sub: Label
var _flash: ColorRect
var _vign: ColorRect
var _scrape_t := 0.0
var _freeze := 0.0


func active() -> bool:
	return _on


func start(l: Node, h: Object, tgt: Node3D, p0: Vector3, fwd: Vector3) -> void:
	loc = l
	hero = h
	target = tgt
	_p0 = p0
	_fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	_right = _fwd.cross(Vector3.UP).normalized()
	_ground = p0.y
	_t = 0.0
	_on = true
	_done = {}
	if is_instance_valid(target):
		target.set("cine", true)
		target.set("velocity", Vector3.ZERO)
		_t_from = target.global_position
	_build_ui()
	loc.call("_sfx_once", "sounds/iai_timestop.wav", -4.0)


func stop() -> void:
	if not _on:
		return
	_on = false
	if is_instance_valid(target) and target.has_method("cine_release"):
		target.call("cine_release", Vector3.ZERO)
	target = null
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


## Время сцены — по клипу героя (замирания и замедления клипа — и у сцены).
func tick(delta: float) -> void:
	if not _on:
		return
	var ap: AnimationPlayer = hero.get("anim")
	if _freeze > 0.0:
		_freeze -= delta
	elif ap != null:
		ap.speed_scale = _speed(_t)                    # замедления на ударах — видно каждый момент
	var t_clip: float = hero.call("ult_time")
	_t = maxf(_t, t_clip)
	if str(hero.get("action")) != "Ultimate" or _t >= LENGTH:
		_finish()
		return
	_target_path()
	_hits()
	_ui_tick(delta)
	if _t > 1.35 and _t < 2.05:                       # скольжение: копьё цепляет пол — искры и скрежет
		_scrape_t -= delta
		if _scrape_t <= 0.0:
			_scrape_t = 0.05
			_sparks(_spear_tip(), -_fwd + Vector3.UP * 0.6, Color(1.0, 0.55, 0.2), 10, 4.0, 0.25)
		if not _done.has("scrape"):
			_done["scrape"] = true
			loc.call("_sfx_once", "sounds/katana_scrape.wav", -2.0)


## Скорость клипа: вся сцена чуть медленнее, у каждого удара — слоу-мо (вход перед ударом, выход после).
func _speed(t: float) -> float:
	var s := float(loc.call("_hf", "spear_ult_speed", 0.55))
	var slow := float(loc.call("_hf", "spear_ult_slowmo", 0.12))
	for h: float in [T_STUN, T_SPIN, T_TRIP, T_BACK]:
		var k := smoothstep(h - 0.2, h - 0.04, t) * (1.0 - smoothstep(h + 0.25, h + 0.5, t))
		s = lerpf(s, slow, k)
	return s


## Конец сцены: цель отпущена — своя физика и решения снова её, без замирания, лежит после удара в спину и встаёт сама.
func _finish() -> void:
	var ap: AnimationPlayer = hero.get("anim")
	if ap != null:
		ap.speed_scale = 1.0
	if is_instance_valid(target) and target.has_method("cine_release"):
		target.call("cine_release", _fwd * 6.0 + Vector3.UP * 2.0)
	target = null
	stop()


func _hero_pos() -> Vector3:
	var p: Node3D = loc.get("_player")
	return p.global_position if p != null else _p0


## Путь цели: подтянуть к копью → стоит (микростан) → летит дугой → спотыкается → подножка — падает → встаёт
## спиной к герою → после удара в спину отпущена с разгоном (_finish).
func _target_path() -> void:
	if not is_instance_valid(target):
		return
	var d := 1.6
	var up := 0.0
	if _t < T_SPIN:
		var k := smoothstep(0.0, 0.3, _t)
		var want := _p0 + _fwd * d
		var pos := _t_from.lerp(want, k)
		target.global_position = Vector3(pos.x, _ground, pos.z)
		_face(-_fwd)
		return
	if _t < T_LAND:
		var u := (_t - T_SPIN) / (T_LAND - T_SPIN)
		d = lerpf(1.6, 5.2, 1.0 - pow(1.0 - u, 2.0))
		up = 4.0 * 1.1 * u * (1.0 - u)
	elif _t < T_TRIP:
		var u2 := (_t - T_LAND) / (T_TRIP - T_LAND)
		d = lerpf(5.2, 5.9, u2)                        # спотыкается, гасит отлёт
	elif _t < T_GETUP:
		var u3 := (_t - T_TRIP) / (T_GETUP - T_TRIP)
		d = lerpf(5.9, 6.8, 1.0 - pow(1.0 - u3, 2.0))  # подсекли — падает вперёд
	elif _t < T_BACK:
		d = 6.8
		_face(_fwd)                                      # встаёт спиной к герою
	else:
		var u4 := clampf((_t - T_BACK) / (LENGTH - T_BACK), 0.0, 1.0)
		d = lerpf(6.8, 8.6, 1.0 - pow(1.0 - u4, 2.0))   # удар в спину — летит вперёд
		up = 4.0 * 0.5 * u4 * (1.0 - u4)
	target.global_position = _p0 + _fwd * d + Vector3(0.0, _ground - _p0.y + up, 0.0)


func _face(dir: Vector3) -> void:
	if not is_instance_valid(target) or dir.length() < 0.01:
		return
	target.rotation.y = atan2(-dir.x, -dir.z)


func _hits() -> void:
	var base := float(loc.call("_hf", "spear_ult_damage", 45.0)) * float(loc.call("_dmg_mult"))
	if _t >= T_STUN and not _done.has("stun"):
		_done["stun"] = true
		_hit(base * 0.35, false, "hurt", 0.12, 0.35)
		loc.call("_sfx_once", "sounds/katana_hit_0.ogg", -1.0)
	if _t >= T_SPIN and not _done.has("spin"):
		_done["spin"] = true
		_hit(base * 0.6, true, "knock", 0.16, 0.6)
		loc.call("_sfx_once", "sounds/impact_2.wav", 0.0)
		loc.call("_sfx_once", "sounds/air_whoosh.wav", -3.0)
	if _t >= T_TRIP and not _done.has("trip"):
		_done["trip"] = true
		_hit(base * 0.2, false, "fall", 0.1, 0.3)
		loc.call("_sfx_once", "sounds/kick_hit.wav", 0.0)
	if _t >= T_TRIP + 0.25 and not _done.has("fall"):
		_done["fall"] = true
		loc.call("_sfx_once", "sounds/body_fall.ogg", -2.0)
	if _t >= T_GETUP and not _done.has("getup"):
		_done["getup"] = true
		if is_instance_valid(target) and target.has_method("cine_anim"):
			target.call("cine_anim", "getup")
	if _t >= T_BACK and not _done.has("back"):
		_done["back"] = true
		_hit(base * 1.5, true, "hurt", 0.25, 1.0)
		loc.call("_sfx_once", "sounds/deathblow.wav", 0.0)
		loc.call("_sfx_once", "sounds/impact_3.wav", 0.0)
		_vignette()
	if _t >= T_BACK + 0.12 and not _done.has("back_fall"):
		_done["back_fall"] = true
		if is_instance_valid(target) and target.has_method("cine_anim"):
			target.call("cine_anim", "fall")


## Попадание: урон (цифры, как у обычных ударов), состояние цели, замирание клипа, тряска, вспышка, искры.
func _hit(dmg: float, heavy: bool, state: String, stop_t: float, shake: float) -> void:
	_freeze = stop_t
	var ap: AnimationPlayer = hero.get("anim")
	if ap != null:
		ap.speed_scale = 0.04
	loc.set("_shake", maxf(float(loc.get("_shake")), shake))
	_flash_now(0.45 if heavy else 0.28)
	if not is_instance_valid(target) or not bool(target.call("is_alive")):
		return
	target.set("_state", "hurt")                      # в сцене не блокирует и не в гиперброне
	target.set("_atk", "")
	target.call("take_damage", dmg, _hero_pos(), false)
	if target.has_method("hitstop"):
		target.call("hitstop", stop_t)
	if target.has_method("cine_anim") and bool(target.call("is_alive")):
		target.call("cine_anim", state)
	var nums: Array = loc.get("_numbers")
	nums.append({"pos": target.global_position + Vector3(randf_range(-0.3, 0.3), 1.3, 0.0), "v": int(dmg), "crit": heavy, "t": 0.0})
	var at := target.global_position + Vector3(0.0, 1.0, 0.0)
	_sparks(at, -_fwd, CRIMSON, 46 if heavy else 26, 7.0 if heavy else 4.5, 0.45)


func _sparks(at: Vector3, dir: Vector3, c: Color, n: int, speed: float, life: float) -> void:
	if is_instance_valid(target) and target.has_method("_burst"):
		target.call("_burst", at, dir.normalized(), c, n, speed, 5.0, life, 0.05, true)


func _spear_tip() -> Vector3:
	var sw: Node3D = hero.get("_sword_hand")
	var tip: Vector3 = hero.get("_tip")
	if sw == null:
		return _hero_pos() + _fwd
	return sw.global_transform * tip


## Камера: [позиция, точка взгляда]. Сбоку от схватки, медленный облёт вокруг середины между героем и врагом:
## начало — сбоку-спереди и ближе, отлёт и скольжение — широкий боковой план, удар в спину — низко сбоку.
func camera() -> Array:
	var h := _hero_pos()
	var tg := target.global_position if is_instance_valid(target) else h + _fwd * 2.5
	var mid := h.lerp(tg, 0.5)
	var u := clampf(_t / LENGTH, 0.0, 1.0)
	var ang := lerpf(deg_to_rad(55.0), deg_to_rad(115.0), smoothstep(0.0, 1.0, u))   # от «сбоку-спереди» до «сбоку-сзади»
	var span := (tg - h).length()
	var radius := clampf(span * 0.9 + 3.2, 3.6, 7.0)
	var height := 1.5
	if _t < T_STUN:
		radius = 3.0
	if _t > T_BACK - 0.3:
		height = 0.9                                     # удар в спину — ниже, драматичнее
	var dir := (_right * sin(ang) + _fwd * cos(ang)).normalized()
	return [mid + dir * radius + Vector3.UP * height, mid + Vector3.UP * 0.95]


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 90
	add_child(_ui)
	for i: int in 2:
		var b := ColorRect.new()
		b.color = Color(0, 0, 0, 1)
		b.anchor_right = 1.0
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 1:
			b.anchor_top = 1.0
			b.anchor_bottom = 1.0
		_ui.add_child(b)
		_bars.append(b)
	_vign = ColorRect.new()
	_vign.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vign.color = Color(CRIMSON, 0.0)
	_vign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_vign)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.85, 0.8, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)
	var m: PaxMod = loc.get("mod")
	_title = Label.new()
	_title.text = m.tr_key("pax_rpg_ult_spear_name")
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.88))
	_title.add_theme_color_override("font_outline_color", Color(0.55, 0.02, 0.05))
	_title.add_theme_constant_override("outline_size", 14)
	_title.anchor_left = 0.55
	_title.anchor_top = 0.62
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_title)
	_sub = Label.new()
	_sub.text = m.tr_key("pax_rpg_ult_spear_sub")
	_sub.add_theme_font_size_override("font_size", 24)
	_sub.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	_sub.anchor_left = 0.56
	_sub.anchor_top = 0.72
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_sub)


func _ui_tick(delta: float) -> void:
	if not is_instance_valid(_ui):
		return
	var vp := _ui.get_viewport().get_visible_rect().size
	var bar := vp.y * 0.11 * smoothstep(0.0, 0.25, _t) * (1.0 - smoothstep(LENGTH - 0.25, LENGTH, _t))
	(_bars[0] as ColorRect).offset_bottom = bar
	(_bars[1] as ColorRect).offset_top = -bar
	# имя приёма: выезжает справа и гаснет (как в Genshin)
	var a := smoothstep(0.05, 0.3, _t) * (1.0 - smoothstep(0.9, 1.25, _t))
	var slide := (1.0 - smoothstep(0.05, 0.35, _t)) * 160.0
	_title.modulate.a = a
	_sub.modulate.a = a
	_title.offset_left = slide
	_sub.offset_left = slide * 1.4
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 3.5)
	_vign.color.a = maxf(0.0, _vign.color.a - delta * 0.9)


func _flash_now(a: float) -> void:
	if is_instance_valid(_flash):
		_flash.color.a = maxf(_flash.color.a, a)


func _vignette() -> void:
	if is_instance_valid(_vign):
		_vign.color.a = 0.32
