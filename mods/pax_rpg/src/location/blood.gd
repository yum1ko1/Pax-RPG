extends Node
## Кровожадная атака (ДИЗДОК — бой): концентрация врага на нуле — ЛКМ рядом с ним. Короткая кат-сцена: герой входит
## выпадом (клип Bloodthirsty — укол Attack1 с другим ходом времени; у рыцаря — Deathblow), на миг удара — почти
## стоп-кадр, вспышка и кровь, копьё в теле, рывок назад — враг падает: рядовой гибнет, босс теряет треть здоровья
## (goblin.gd / orc.gd → bloodthirsty). Камера — сбоку и низко, к удару ближе, после — отъезд; полосы кино.
## Враг на время сцены «в кадре» (cine): своя физика и решения стоят, его ведёт сцена.

const Goblin := preload("res://mods/pax_rpg/src/location/goblin.gd")

const CRIMSON := Color(0.72, 0.02, 0.05)
const REACH := 2.05                 # м от героя до врага в начале (выпад клипа — ~0.8 м, копьё — ~1.3 м)

var loc: Node                       # location.gd
var hero: Object                    # hero.gd
var target: Node3D                  # goblin.gd / orc.gd
var _on := false
var _t := 0.0
var _hit_at := 0.82                 # с клипа: оружие в теле
var _pull_at := 1.55                # с клипа: рывок назад
var _len := 2.15
var _clip := ""
var _p0 := Vector3.ZERO
var _fwd := Vector3.FORWARD
var _right := Vector3.RIGHT
var _side := 1.0
var _t_from := Vector3.ZERO
var _done := {}
var _ui: CanvasLayer
var _bars: Array = []
var _flash: ColorRect
var _title: Label
var _cam_t := 0.0


func active() -> bool:
	return _on


## Локация уходит — сцену оборвать (враг отпущен).
func stop() -> void:
	_finish()


func start(l: Node, h: Object, tgt: Node3D, hit_at: float) -> void:
	loc = l
	hero = h
	target = tgt
	_on = true
	_t = 0.0
	_cam_t = 0.0
	_done = {}
	_clip = str(hero.get("action"))
	_hit_at = hit_at
	var an: Object = hero.get("anim")
	_len = float(an.get("current_animation_length")) if an != null else 2.0
	_pull_at = 1.55 if _clip == "Bloodthirsty" else minf(_len - 0.2, _hit_at + 0.45)
	var pl: Node3D = loc.get("_player")
	_p0 = pl.global_position
	var to := target.global_position - _p0
	to.y = 0.0
	_fwd = to.normalized() if to.length() > 0.05 else Vector3.FORWARD
	_right = _fwd.cross(Vector3.UP).normalized()
	_side = 1.0 if randf() < 0.5 else -1.0
	_t_from = target.global_position
	target.set("cine", true)
	target.set("velocity", Vector3.ZERO)
	_build_ui()
	loc.call("_sfx_once", "sounds/iai_timestop.wav", -9.0)


## Скорость клипа героя: подход — почти обычный, у удара — стоп-кадр, копьё в теле — медленно, рывок — быстро.
func _speed(t: float) -> float:
	if t < _hit_at - 0.08:
		return 0.95
	if t < _hit_at + 0.12:
		return 0.1
	if t < _pull_at:
		return 0.55
	return 1.15


func tick(delta: float) -> void:
	if not _on:
		return
	_cam_t += delta
	var an: Object = hero.get("anim")
	if an == null or str(hero.get("action")) != _clip:
		_finish()
		return
	_t = float(an.get("current_animation_position"))
	an.set("speed_scale", _speed(_t))
	if is_instance_valid(target):
		var k := smoothstep(0.0, 0.3, _t)                 # враг — на длину выпада перед героем, лицом к нему
		var want := _p0 + _fwd * REACH
		var p := _t_from.lerp(Vector3(want.x, _t_from.y, want.z), k)
		target.global_position = p
		_face_target(-_fwd)
	if _t >= _hit_at and not _done.has("hit"):
		_done["hit"] = true
		_impact()
	if _t >= _pull_at and not _done.has("pull"):
		_done["pull"] = true
		_pull()
	_ui_tick(delta)
	if _t >= _len - 0.04 or _cam_t > 8.0:
		_finish()


func _face_target(dir: Vector3) -> void:
	if not is_instance_valid(target):
		return
	var m: Variant = target.get("_model")
	if m is Node3D:
		(m as Node3D).rotation.y = atan2(dir.x, dir.z)     # модели врагов смотрят по +Z


## Копьё в теле: кровь фонтаном, вспышка, звук, тряска, цифра урона; враг замирает в реакции.
func _impact() -> void:
	loc.call("_sfx_once", "sounds/deathblow.wav", 1.0)
	loc.call("_sfx_once", "sounds/impact_3.wav", -1.0)
	loc.set("_shake", maxf(float(loc.get("_shake")), 0.35))
	loc.set("_shake_amp", 0.07)
	if is_instance_valid(_flash):
		_flash.color = Color(1.0, 0.25, 0.22, 0.55)
	if not is_instance_valid(target):
		return
	var at := target.global_position + Vector3(0.0, 1.0 if not bool(target.get("boss")) else 1.35, 0.0)
	if target.has_method("_burst"):
		target.call("_burst", at, -_fwd + Vector3.UP * 0.4, CRIMSON, 70, 6.5, 9.0, 0.8, 0.07)
		target.call("_burst", at, _fwd + Vector3.UP * 0.2, Color(0.5, 0.0, 0.03), 40, 4.0, 9.0, 0.6, 0.05)
	if target.has_method("cine_anim"):
		target.call("cine_anim", "hurt")
	if target.has_method("hitstop"):
		target.call("hitstop", 0.5)
	var boss := bool(target.get("boss"))
	var dmg := float(target.get("max_hp")) / 3.0 if boss else float(target.get("hp"))
	var nums: Array = loc.get("_numbers")
	nums.append({"pos": target.global_position + Vector3(0.0, 1.6 if boss else 1.3, 0.0), "v": int(dmg), "crit": true, "t": 0.0})


## Рывок назад: оружие вышло — рядовой падает замертво, босс теряет треть здоровья и встаёт с колена.
func _pull() -> void:
	if not is_instance_valid(target):
		return
	var parent := target.get_parent()
	if parent != null:
		Goblin.blood_decal(parent, target.global_position)
	target.set("_last_away", _fwd)
	if target.has_method("bloodthirsty"):
		target.call("bloodthirsty")
	if not bool(target.call("is_alive")):
		target.set("velocity", _fwd * 3.0 + Vector3.UP * 1.5)
	var st: Object = loc.get("_style")
	if st != null:
		st.call("hit", "Bloodthirsty")
	loc.call("_sfx_once", "sounds/body_fall.ogg", -3.0)


func _finish() -> void:
	if not _on:
		return
	_on = false
	var an: Object = hero.get("anim") if hero != null else null
	if an != null:
		an.set("speed_scale", 1.0)
	if is_instance_valid(target) and bool(target.get("cine")):
		target.set("cine", false)                         # жив (босс): своя физика снова его
		if target.has_method("cine_release") and bool(target.call("is_alive")) and not _done.has("pull"):
			target.call("cine_release", Vector3.ZERO)
	target = null
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


## Камера: [позиция, точка взгляда]. Сбоку от линии удара, низко; к удару — ближе и ниже, после рывка — отъезд.
func camera() -> Array:
	var pl: Node3D = loc.get("_player")
	var h := pl.global_position if pl != null else _p0
	var tg := target.global_position if is_instance_valid(target) else h + _fwd * REACH
	var mid := h.lerp(tg, 0.5)
	var near := smoothstep(_hit_at - 0.5, _hit_at, _t) * (1.0 - smoothstep(_pull_at, _pull_at + 0.5, _t))
	var dist := lerpf(3.6, 2.3, near) + smoothstep(_pull_at, _len, _t) * 1.4
	var height := lerpf(1.45, 1.05, near) + smoothstep(_pull_at, _len, _t) * 0.5
	var ang := deg_to_rad(lerpf(80.0, 62.0, smoothstep(0.0, _len, _t)))   # от «сбоку» к «сбоку-спереди героя»
	var dir := (_right * _side * sin(ang) - _fwd * cos(ang) * 0.6).normalized()
	return [mid + dir * dist + Vector3.UP * height, mid + Vector3.UP * lerpf(1.0, 1.15, near)]


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 90
	add_child(_ui)
	_bars = []
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
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.2, 0.2, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_flash)
	var m: PaxMod = loc.get("mod")
	_title = Label.new()
	_title.text = m.tr_key("pax_rpg_bloodthirsty")
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.84))
	_title.add_theme_color_override("font_outline_color", Color(0.45, 0.0, 0.03))
	_title.add_theme_constant_override("outline_size", 12)
	_title.anchor_left = 0.08
	_title.anchor_top = 0.74
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_title)


func _ui_tick(delta: float) -> void:
	if not is_instance_valid(_ui):
		return
	var vp := _ui.get_viewport().get_visible_rect().size
	var bar := vp.y * 0.09 * smoothstep(0.0, 0.2, _cam_t) * (1.0 - smoothstep(_len - 0.25, _len, _t))
	(_bars[0] as ColorRect).offset_bottom = bar
	(_bars[1] as ColorRect).offset_top = -bar
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 2.5)
	var a := smoothstep(0.0, 0.25, _cam_t) * (1.0 - smoothstep(_pull_at, _pull_at + 0.4, _t))
	_title.modulate.a = a
	_title.offset_left = (1.0 - smoothstep(0.0, 0.3, _cam_t)) * -80.0
