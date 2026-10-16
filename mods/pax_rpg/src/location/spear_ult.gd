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
var hero: Node                     # hero.gd
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


func start(l: Node, h: Node, tgt: Node3D, p0: Vector3, fwd: Vector3) -> void:
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
	if is_instance_valid(target):
		target.set("cine", false)
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


## Время сцены — по клипу героя (замирания и замедления клипа — и у сцены).
func tick(delta: float) -> void:
	if not _on:
		return
	if _freeze > 0.0:
		_freeze -= delta
		if _freeze <= 0.0 and hero.get("anim") != null:
			(hero.get("anim") as AnimationPlayer).speed_scale = 1.0
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


func _finish() -> void:
	if is_instance_valid(target) and target.has_method("is_alive") and bool(target.call("is_alive")):
		target.set("cine", false)
		target.set("velocity", _fwd * 7.0 + Vector3.UP * 3.0)   # удар в спину: отлетает вперёд
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
	else:
		d = 6.8
		_face(_fwd)                                      # встаёт спиной к герою
	target.global_position = _p0 + _fwd * d + Vector3(0.0, _ground - _p0.y + up, 0.0)


func _face(dir: Vector3) -> void:
	if not is_instance_valid(target) or dir.length() < 0.01:
		return
	target.rotation.y = atan2(-dir.x, -dir.z)


func _hits() -> void:
	var base := float(loc.call("_hf", "spear_ult_damage", 45.0)) * float(loc.call("_dmg_mult"))
	if _t >= T_STUN and not _done.has("stun"):
		_done["stun"] = true
		_hit(base * 0.35, false, "hurt", 0.09, 0.35)
		loc.call("_sfx_once", "sounds/katana_hit_0.ogg", -1.0)
	if _t >= T_SPIN and not _done.has("spin"):
		_done["spin"] = true
		_hit(base * 0.6, true, "knockdown", 0.12, 0.6)
		loc.call("_sfx_once", "sounds/impact_2.wav", 0.0)
		loc.call("_sfx_once", "sounds/air_whoosh.wav", -3.0)
	if _t >= T_TRIP and not _done.has("trip"):
		_done["trip"] = true
		_hit(base * 0.2, false, "knockdown", 0.06, 0.3)
		loc.call("_sfx_once", "sounds/kick_hit.wav", 0.0)
	if _t >= T_TRIP + 0.25 and not _done.has("fall"):
		_done["fall"] = true
		loc.call("_sfx_once", "sounds/body_fall.ogg", -2.0)
	if _t >= T_GETUP and not _done.has("getup"):
		_done["getup"] = true
		if is_instance_valid(target) and target.has_method("cine_state"):
			target.call("cine_state", "getup")
	if _t >= T_BACK and not _done.has("back"):
		_done["back"] = true
		_hit(base * 1.5, true, "knockdown", 0.2, 1.0)
		loc.call("_sfx_once", "sounds/deathblow.wav", 0.0)
		loc.call("_sfx_once", "sounds/impact_3.wav", 0.0)
		_vignette()


## Попадание: урон (цифры, как у обычных ударов), состояние цели, замирание клипа, тряска, вспышка, искры.
func _hit(dmg: float, heavy: bool, state: String, stop_t: float, shake: float) -> void:
	_freeze = stop_t
	if hero.get("anim") != null:
		(hero.get("anim") as AnimationPlayer).speed_scale = 0.04
	loc.set("_shake", maxf(float(loc.get("_shake")), shake))
	_flash_now(0.45 if heavy else 0.28)
	if not is_instance_valid(target) or not bool(target.call("is_alive")):
		return
	target.call("take_damage", dmg, _hero_pos(), false)
	if target.has_method("hitstop"):
		target.call("hitstop", stop_t)
	if target.has_method("cine_state") and bool(target.call("is_alive")):
		target.call("cine_state", state)
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


## Камера: [позиция, точка взгляда]. Планы со склейками на ударах, в каждом — лёгкий наезд.
func camera() -> Array:
	var h := _hero_pos()
	var up := Vector3.UP
	var tg := target.global_position if is_instance_valid(target) else h + _fwd * 2.0
	var head := h + up * 1.35
	if _t < T_STUN:                                    # крупно: лицо и копьё, медленный наезд
		var k := _t / T_STUN
		return [h + _fwd * lerpf(2.1, 1.6, k) + _right * 0.9 + up * 1.45, head + _fwd * 0.2]
	if _t < T_SPIN:                                    # сбоку широко: укол и разворот
		var k2 := (_t - T_STUN) / (T_SPIN - T_STUN)
		return [h + _right * lerpf(3.6, 3.1, k2) + _fwd * 1.0 + up * 1.3, h.lerp(tg, 0.5) + up * 1.0]
	if _t < 1.8:                                       # из-за спины: цель улетает
		return [h - _fwd * 3.2 + _right * 1.4 + up * 1.7, tg + up * 0.8]
	if _t < T_BACK - 0.25:                             # низко сбоку: скольжение и подножка
		return [h + _right * 2.4 + _fwd * 0.6 + up * 0.45, h + _fwd * 1.6 + up * 0.5]
	var k3 := clampf((_t - (T_BACK - 0.25)) / 0.6, 0.0, 1.0)   # сверху сзади: удар в спину
	return [h - _fwd * lerpf(2.6, 3.4, k3) - _right * 1.2 + up * lerpf(2.6, 3.0, k3), tg + up * 0.7]


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
