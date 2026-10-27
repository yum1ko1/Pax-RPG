extends Control
## Прокрутка лута (как кейсы CS:GO, в туши): в правом нижнем углу растекается полоса туши, на ней — кляксы с вещами в ряд,
## указатель — золотая черта. Вещь, что выпадет, известна заранее: когда ряд ещё едет (пройдено CUT1_U пути), появляется
## наша катана в 3D (models/weapons/katana.glb, свой SubViewport) — рукоятью к игроку, встаёт клинком вниз и на ходу
## обрубает путь прямо перед выпавшей вещью: всё впереди улетает дальше и падает, вещь с хвостом доезжает до центра.
## На остановке второй взмах отсекает хвост; оставшуюся вещь обводит тушевое кольцо в цвет редкости.
## Легендарная и выше или пропитанная маной: вещь уходит влево-вверх, рядом открываются её характеристики и по очереди
## прокручиваются усиленные статы (item_tip.gd → start_rolls). Затем вещь сжимается в сферу и улетает в сумку.
## Выпавшее — в настройку inv_loot (вещь появляется в выборе своего слота в инвентаре, TAB).
## Рисуется в координатах макета (высота 1080), центр полосы — anchor; done — когда всё погасло.

signal done(id: String)

const Equip := preload("res://mods/pax_rpg/src/location/inv/equip.gd")
const Ui := preload("res://mods/pax_rpg/src/location/inv/ui.gd")
const ItemTip := preload("res://mods/pax_rpg/src/location/inv/item_tip.gd")
const DIR := "textures/loot/"
const STRIP_W := 700.0
const GLOW_PAD := 60.0               # поля ink_glow.png вокруг полосы, px картинки полосы
const GLOW := Color(0.96, 0.88, 0.72, 0.32)   # тёплый «рисовая бумага» свет под тушью: читается и ночью
const CELL := 118.0
const BLOT := 140.0
const ICON := 80.0
const RING := 200.0
const KAT_H := 400.0                 # высота кадра катаны, px макета
const KAT_M := 1.18 / 400.0          # метров сцены катаны на px макета
const MOVE_OFF := Vector2(-250, -300)   # куда уходит крупная вещь (от центра полосы); не выше 180 px от верха
const TIP_K := 0.75                  # масштаб окна характеристик
# время от начала, с
const T_SPIN := 0.75
const CUT1_U := 0.8                  # первый взмах — на ходу, когда пройдено 80 % пути (вещь ещё подъезжает)
const STROKE := 0.13                 # один взмах
const CUT2_AFTER := 0.55             # второй взмах — когда вещь встала: катана приходит заново уже после остановки
const KAT_LEAD := 0.45               # катана появляется раньше первого взмаха
const REVEAL_AFTER := 0.45
const FLY := 0.75

var mod: PaxMod
var eq: Equip                       # данные вещей (config/equipment.json)
var ui: Ui                          # шрифты и кэш картинок
var cfg: Dictionary = {}
var anchor := Vector2(1560, 910)     # центр полосы, px макета
var hero_lvl := 1
var K := 0.7                         # масштаб прокрутки (config/loot.json → roll_scale): полоса, вещи, катана, кольцо
var _items: Array = []              # {id, set, k, r, mana, blot, rot}
var _win := 0
var _spin := 3.6
var _off0 := 0.0
var _off1 := 0.0
var _t := 0.0
var _tick_i := -999
var _cut_played := false
var _cut2_played := false
var _revealed := false
var _big := false
var _tip: ItemTip
var _tip_at := -1.0                  # когда открыто окно характеристик
var _tip_len := 0.0                  # сколько оно открыто
var _move_at := -1.0                 # когда крупная вещь пошла к окну характеристик (−1 — ждёт очереди)
## Очередь окон характеристик — общая для всех прокруток (loot.gd): статы показывает одна вещь за раз, по порядку.
var gate: Array = []
var _orb_at := 0.0                   # вещь сжимается в сферу и летит в сумку
var _icons: Dictionary = {}
var _snd: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _xf := Transform2D.IDENTITY     # преобразование текущего куска (draw_set_transform обратно не читается)
var _vp: SubViewport
var _kat: Node3D                    # опора катаны (центр клинка с рукоятью)
var _key: DirectionalLight3D        # блик бежит по клинку, пока ряд крутится


func setup(m: PaxMod, equip: Equip, fonts: Ui, c: Dictionary) -> void:
	mod = m
	eq = equip
	ui = fonts
	cfg = c
	K = float(cfg.get("roll_scale", 0.68))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.randomize()
	_vp = SubViewport.new()
	_vp.size = Vector2i(512, 640)                             # шире кадра — клинок наискось не обрезается
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.7
	var sky := ProceduralSkyMaterial.new()                    # фон прозрачный, а металлу есть что отражать
	sky.sky_top_color = Color(0.55, 0.6, 0.75)
	sky.sky_horizon_color = Color(0.95, 0.85, 0.8)
	sky.ground_bottom_color = Color(0.32, 0.3, 0.34)
	sky.ground_horizon_color = Color(0.8, 0.72, 0.7)
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = sky
	env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_vp.add_child(env)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 0, 2.2)
	_vp.add_child(cam)
	_key = DirectionalLight3D.new()
	var key := _key
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -150, 0)
	rim.light_color = Color(1.0, 0.75, 0.85)
	rim.light_energy = 1.2
	_vp.add_child(rim)
	_kat = Node3D.new()
	_vp.add_child(_kat)


## Модель катаны (из Assets.model — с текстурами игры); клинок модели — вдоль −Z, середина длины — в опору.
func set_katana(model: Node3D) -> void:
	if model == null:
		return
	for c: Node in _kat.get_children():
		c.queue_free()
	model.position = Vector3(0.0, -0.03, 0.25)
	_kat.add_child(model)


func busy() -> bool:
	return not _items.is_empty()


## Начать: force_r ≥ 0 — редкость выигрыша (для проверки), иначе по весам rarity_w.
func start(force_r := -1) -> void:
	var n := int(cfg.get("items", 36))
	_win = clampi(int(cfg.get("win_at", 30)), 3, n - 3)
	_spin = float(cfg.get("spin_time", 3.6))
	_items = []
	for i: int in n:
		_items.append(_random_item(force_r if i == _win else -1))
	_off0 = 2.0 * CELL
	_off1 = _win * CELL                                            # встаёт ровно на выпавшей вещи
	_t = 0.0
	_tick_i = -999
	_cut_played = false
	_cut2_played = false
	_revealed = false
	var w := winner()
	_big = int(w["r"]) >= 4 or bool(w["mana"])
	_tip_at = -1.0
	_tip_len = 0.0
	_move_at = -1.0
	_orb_at = 1.0e9 if _big else _reveal_t() + 1.5             # крупная — в сумку только после своего окна характеристик
	if is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null
	_play("loot_ink.ogg", -13.0)                              # прокрутки частые — обычные звуки тихие; громко — только редкая вещь
	queue_redraw()


func winner() -> Dictionary:
	return _items[_win] if _win < _items.size() else {}


func _stop_t() -> float:
	return T_SPIN + _spin


func _c1() -> float:
	return T_SPIN + _spin * CUT1_U


func _c2() -> float:
	return _stop_t() + CUT2_AFTER


func _reveal_t() -> float:
	return _c2() + REVEAL_AFTER


func _random_item(force_r: int) -> Dictionary:
	var w: Array = cfg.get("rarity_w", [46, 28, 14, 8, 3.2, 0.8])
	var r := force_r
	if r < 0:
		var total := 0.0
		for x: Variant in w:
			total += float(x)
		var roll := _rng.randf() * total
		r = 0
		for i: int in w.size():
			roll -= float(w[i])
			if roll <= 0.0:
				r = i
				break
	r = clampi(r, 0, eq.rar.size() - 1)
	var sets: Array = cfg.get("sets", ["samurai"])
	var key := str(sets[_rng.randi_range(0, sets.size() - 1)])
	var k := _rng.randi_range(0, eq.slots.size() - 1)
	var mana := _rng.randf() < float(cfg.get("mana_chance", 0.04))
	var id := "%d:%s-%d%s#%d%03d" % [k, key, r, "-m" if mana else "", Time.get_unix_time_from_system(), _rng.randi_range(0, 999)]
	return {"id": id, "set": key, "k": k, "r": r, "mana": mana, "blot": _rng.randi_range(0, 5), "rot": _rng.randf_range(-0.5, 0.5)}


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	_t += delta
	if _t >= T_SPIN and _t < _c1():                         # тик — каждая вещь, прошедшая под указателем
		var i := floori((_offset() + CELL * 0.5) / CELL)
		if i != _tick_i:
			if _tick_i != -999:
				_play("loot_tick.ogg", -17.0, _rng.randf_range(0.95, 1.08))
			else:
				_play("loot_spin.ogg", -15.0)
			_tick_i = i
	if _t >= _c1() - 0.04 and not _cut_played:
		_cut_played = true
		_play("loot_slash.ogg", -11.0)
	if _t >= _c2() - 0.04 and not _cut2_played:
		_cut2_played = true
		_play("loot_slash.ogg", -14.0, 1.08)
	var reveal := _reveal_t()
	if _t >= reveal and not _revealed:
		_revealed = true
		var it := winner()
		_play("loot_reveal_epic.ogg" if _big else "loot_reveal.ogg", -3.0 if _big else -12.0)
		var loot: Variant = mod.get_setting("inv_loot", [])
		var list: Array = (loot as Array).duplicate() if loot is Array else []
		list.append(str(it["id"]))
		mod.set_setting("inv_loot", list)
	if _big and _move_at < 0.0 and _t >= reveal + 0.8:       # своя очередь — вещь уходит влево-вверх, потом окно
		if not gate.has(self):
			gate.append(self)
		if gate[0] == self:
			_move_at = _t
	if _move_at >= 0.0 and _tip_at < 0.0 and _t >= _move_at + 0.4:
		_open_tip()
	if _tip_at >= 0.0 and _t >= _tip_at + _tip_len + 0.3:    # окно закрылось — очередь следующей вещи
		gate.erase(self)
	if is_instance_valid(_tip):
		_place_tip()
	if _t > _c2() + 0.6 or _t < _kat_t() - 0.1:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_pose_katana()
	var arrive := _orb_at + 0.3 + FLY                       # сфера в сумку: свист, крышка открывается к прилёту и закрывается
	for ev: Array in [[_orb_at, "loot_to_bag.ogg", -14.0, 1.0], [arrive - 0.12, "loot_bag_lid.ogg", -15.0, 1.0], [arrive + 0.4, "loot_bag_lid.ogg", -18.0, 0.88]]:
		if _t >= float(ev[0]) and _t - delta < float(ev[0]):
			_play(str(ev[1]), float(ev[2]), float(ev[3]))
	if _t >= _orb_at + 0.3 + FLY + 0.9:
		var id := str(winner()["id"])
		gate.erase(self)
		_items = []
		if is_instance_valid(_tip):
			_tip.queue_free()
		_tip = null
		queue_redraw()
		done.emit(id)
		return
	queue_redraw()


## Сдвиг ряда (px) в миг t: разгон сразу, затем плавное замедление (ease-out) ровно до выпавшей вещи.
func _off_at(t: float) -> float:
	if t < T_SPIN:
		return _off0
	var u := clampf((t - T_SPIN) / _spin, 0.0, 1.0)
	return lerpf(_off0, _off1, 1.0 - pow(1.0 - u, 3.0))


func _offset() -> float:
	return _off_at(_t)


## Где режет первый взмах (px от центра полосы): промежуток прямо перед выпавшей вещью в миг взмаха.
func _gap1() -> float:
	return _off1 - _off_at(_c1()) - CELL * 0.5


## Скорость ряда в миг первого взмаха, px/с: срезанный путь улетает с ней.
func _v1() -> float:
	return (_off1 - _off0) * 3.0 * pow(1.0 - CUT1_U, 2.0) / _spin


static func _ease(u: float) -> float:
	return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)


static func _back(u: float) -> float:
	var x := clampf(u, 0.0, 1.0) - 1.0
	return 1.0 + 2.2 * x * x * x + 1.2 * x * x


# ---------- катана (3D) ----------

## Катана приходит дважды и на вещи не стоит никогда. Лезвие смотрит на то, что режет: клинок уходит от рукояти
## вглубь и наискось, режущая кромка — вниз, к полосе; остриё — к отрезаемому (первый раз — влево, к пути перед вещью,
## второй — вправо, к хвосту). Каждый раз: появляется рукоятью к игроку (клинок вглубь), разворачивается наискось,
## замах вверх и рубящий удар вниз сквозь полосу, уходит — снова рукоятью к игроку, вглубь. Первый раз — на ходу,
## по промежутку перед вещью; второй — после остановки, у её правого края. По полосе катану ведёт _kat_x.
func _pose_katana() -> void:
	var t0 := _kat_cut()
	var yaw_to := deg_to_rad(35.0) * (1.0 if t0 == _c1() else -1.0)
	var ready := deg_to_rad(-20.0)
	var lift := deg_to_rad(-5.0)
	var chop := deg_to_rad(-50.0)
	var u := clampf((_t - t0 + KAT_LEAD) / 0.35, 0.0, 1.0)
	var yaw := lerpf(0.0, yaw_to, _ease(u))
	var pitch := lerpf(0.0, ready, _back(u))
	var y := lerpf(0.05, 0.15, _ease(u)) + sin(_t * 2.0) * 0.008
	var z := lerpf(-0.3, 0.0, _ease(u))
	var sc := lerpf(0.55, 1.0, _ease(u))
	if _t >= t0 - 0.1 and _t < t0:                           # замах вверх
		var p := _ease((_t - t0 + 0.1) / 0.1)
		y = lerpf(0.15, 0.3, p)
		pitch = lerpf(ready, lift, p)
	elif _t >= t0 and _t < t0 + STROKE:                       # рубящий удар вниз — кромкой сквозь полосу
		var p := (_t - t0) / STROKE
		y = lerpf(0.3, -0.22, p * p)
		pitch = lerpf(lift, chop, p)
	var e := clampf((_t - t0 - STROKE) / 0.35, 0.0, 1.0)
	if e > 0.0:                                              # ушла: рукоятью к игроку, вглубь
		y = lerpf(-0.22, 0.05, _ease(e))
		z = lerpf(0.0, -0.6, e)
		pitch = lerpf(chop, 0.0, _ease(e))
		yaw = lerpf(yaw_to, 0.0, _ease(e))
		sc = lerpf(1.0, 0.6, e)
	_kat.position = Vector3(0.0, y, z)
	_key.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(35.0 + 50.0 * sin(_t * 1.7)), 0.0)
	_kat.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, deg_to_rad(-90.0)) \
		* Basis.from_scale(Vector3(sc, sc, sc))                 # кромка (у модели — к +X) — вниз


## Катана появляется заранее — до первого взмаха.
func _kat_t() -> float:
	return _c1() - KAT_LEAD


## Взмах текущего прихода катаны: первый, пока он не кончился (и уход тоже), потом — второй.
func _kat_cut() -> float:
	return _c1() if _t < _c1() + STROKE + 0.45 else _c2()


## Где катана на полосе (px от центра): у промежутка перед вещью; во второй раз — у её правого края.
func _kat_x() -> float:
	return _gap1() if _kat_cut() == _c1() else CELL * 0.5


func _katana_alpha() -> float:
	var t0 := _kat_cut()
	return clampf((_t - t0 + KAT_LEAD) / 0.15, 0.0, 1.0) * (1.0 - clampf((_t - t0 - STROKE - 0.15) / 0.25, 0.0, 1.0))


# ---------- окно характеристик ----------

func _open_tip() -> void:
	var w := winner()
	var it := eq.from_id(str(w["id"]), hero_lvl)
	if it.is_empty():
		_tip_at = _t
		return
	var loot: Variant = mod.get_setting("inv_loot", [])       # сумка и надетое — как в инвентаре (сет в окне считает надетое)
	eq.build_bag(hero_lvl, loot if loot is Array else [])
	var saved: Variant = mod.get_setting("inv_equipped", [])
	eq.equipped = []
	for k: int in eq.slots.size():
		eq.equipped.append(str((saved as Array)[k]) if saved is Array and k < (saved as Array).size() else "")
	_tip = ItemTip.new()
	add_child(_tip)
	_tip.build(ui, eq, it, int(w["k"]), hero_lvl, eq.d.get("passive", {}))
	_tip.on_roll = _on_stat_roll
	_tip.modulate.a = 0.0
	_play("loot_tip_open.ogg", -6.0)
	_tip_at = _t
	_tip_len = 0.35 + _tip.start_rolls() + 1.4
	_orb_at = _tip_at + _tip_len + 0.3


## Звуки роллов: стук бусин счётов, пока число крутится; встал — кото (легендарная и выше — ниже и глубже), мана — хрусталь.
func _on_stat_roll(_i: int, landed: bool, mana: bool) -> void:
	if not landed:
		_play("loot_stat_spin.ogg", -8.0, _rng.randf_range(0.96, 1.06))
	elif mana:
		_play("loot_stat_mana.ogg", -5.0)
	else:
		_play("loot_stat_land.ogg", -4.0, 0.86 if int(winner()["r"]) >= 4 else 1.0)


## Окно — слева от вещи, по высоте вокруг неё (в пределах экрана); проявляется и гаснет.
func _place_tip() -> void:
	var s := size.y / 1080.0
	var item := anchor + _move_off()
	var h := _tip.size.y * TIP_K
	var x := item.x - RING * 0.5 * K - 14.0 - _tip.size.x * TIP_K
	var y := clampf(item.y - h * 0.45, 20.0, 1060.0 - h)
	var a := clampf((_t - _tip_at) / 0.3, 0.0, 1.0) * (1.0 - clampf((_t - _tip_at - _tip_len) / 0.3, 0.0, 1.0))
	_tip.scale = Vector2(TIP_K, TIP_K) * s
	_tip.position = Vector2(x + (1.0 - a) * 16.0, y) * s
	_tip.modulate.a = a


# ---------- рисование ----------

func _group_off() -> Vector2:
	if not _big:
		return Vector2.ZERO
	return _move_off() * _ease((_t - _move_at) / 0.5) if _move_at >= 0.0 else Vector2.ZERO


func _move_off() -> Vector2:
	return Vector2(MOVE_OFF.x * K, maxf(MOVE_OFF.y * K, 180.0 - anchor.y))


## Преобразование куска: local — от центра полосы в её единицах (до масштаба K), rot — поворот.
func _set_xf(local: Vector2, rot: float, s: float) -> void:
	_xf = Transform2D(rot, Vector2(s * K, s * K), 0.0, (anchor + local * K) * s)
	draw_set_transform_matrix(_xf)


func _draw() -> void:
	if _items.is_empty():
		return
	var s := size.y / 1080.0
	var c1 := _c1()
	var c2 := _c2()
	var g := _group_off()
	var orb := clampf((_t - _orb_at) / 0.3, 0.0, 1.0)       # вещь сжимается в сферу
	var n := _items.size()
	if _t < c1:
		_set_xf(Vector2.ZERO, 0.0, s)
		_draw_strip_full()
		_draw_items(0, n, _offset(), 1.0)
	else:
		var off1 := _off_at(c1)
		var ce1 := clampf((_t - c1) / 0.8, 0.0, 1.0)
		if ce1 < 1.0:                                        # путь перед вещью срезан на ходу: летит дальше и падает
			_set_xf(Vector2(-_v1() * (_t - c1) * (1.0 - 0.4 * ce1), 90.0 * ce1 * ce1), -0.1 * ce1, s)
			_draw_strip_part(-STRIP_W * 0.5, _gap1(), 0.0, 1.0 - ce1, true, false)
			_draw_items(0, _win, off1, 1.0 - ce1)
		var d := 0.0                                         # остаток полосы стоит: край разреза — там, где рубанула катана
		if _t < c2:
			_set_xf(Vector2.ZERO, 0.0, s)
			_draw_strip_part(_gap1(), STRIP_W * 0.5, d, 1.0, false, true)
			_draw_items(_win, n, _offset(), 1.0)
		else:
			var split := CELL * 0.5 - d                        # второй взмах — у правого края вещи (в координатах полосы)
			var ce2 := clampf((_t - c2) / 0.7, 0.0, 1.0)
			if ce2 < 1.0:                                    # хвост — вправо и вниз
				_set_xf(Vector2(90.0 * ce2, 80.0 * ce2 * ce2), 0.1 * ce2, s)
				_draw_strip_part(split, STRIP_W * 0.5, d, 1.0 - ce2, false, true)
				_draw_items(_win + 1, n, _offset(), 1.0 - ce2)
			_set_xf(g / K, 0.0, s)                           # кусок под вещью тает — остаётся её клякса
			_draw_strip_part(_gap1(), split, d, (1.0 - orb) * (1.0 - clampf((_t - c2 - 0.3) / 0.4, 0.0, 1.0)), false, false)
			_draw_items(_win, _win + 1, _offset(), 1.0 - orb)
	_set_xf(Vector2.ZERO, 0.0, s)
	_draw_marker()
	var ka := _katana_alpha()
	if ka > 0.0:
		draw_texture_rect(_vp.get_texture(), Rect2(_kat_x() - KAT_H * 0.4, -KAT_H * 0.5 - 30.0, KAT_H * 0.8, KAT_H), false, Color(1, 1, 1, ka))
	if _t >= c1:
		_draw_cut()
	if _t >= _reveal_t() - 0.05:
		_set_xf(g / K, 0.0, s)
		_draw_reveal(_reveal_t(), 1.0 - orb)
	_draw_orb(s)


## Полоса туши до разреза: растекается из центра — растёт вширь и проявляется; под ней — тёплый свет.
func _draw_strip_full() -> void:
	var tex := _tex("ink_strip.png")
	var k := STRIP_W / tex.get_width()
	var h := tex.get_height() * k
	var grow := _ease(_t / 0.5)
	var w := STRIP_W * lerpf(0.25, 1.0, grow)
	var hh := h * lerpf(0.7, 1.0, grow)
	var fa := clampf(_t / 0.25, 0.0, 1.0)
	var gp := GLOW_PAD * k * Vector2(w / STRIP_W, hh / h)
	draw_texture_rect(_tex("ink_glow.png"), Rect2(-w * 0.5 - gp.x, -hh * 0.5 - gp.y, w + gp.x * 2.0, hh + gp.y * 2.0), false, Color(GLOW, GLOW.a * fa))
	draw_texture_rect(tex, Rect2(-w * 0.5, -hh * 0.5, w, hh), false, Color(1, 1, 1, fa))


## Кусок полосы [x0, x1] (px от центра целой полосы), сдвинутый на shift; свет — с запасом у внешних краёв.
func _draw_strip_part(x0: float, x1: float, shift: float, a: float, glow_l: bool, glow_r: bool) -> void:
	if a <= 0.01 or x1 <= x0:
		return
	var tex := _tex("ink_strip.png")
	var k := STRIP_W / tex.get_width()
	var h := tex.get_height() * k
	var gp := GLOW_PAD * k
	var gx0 := x0 - (gp if glow_l else 0.0)
	var gx1 := x1 + (gp if glow_r else 0.0)
	var gt := _tex("ink_glow.png")
	draw_texture_rect_region(gt, Rect2(gx0 + shift, -h * 0.5 - gp, gx1 - gx0, h + gp * 2.0),
		Rect2(GLOW_PAD + (gx0 + STRIP_W * 0.5) / k, 0.0, (gx1 - gx0) / k, gt.get_height()), Color(GLOW, GLOW.a * a))
	var src := Rect2((x0 + STRIP_W * 0.5) / k, 0.0, (x1 - x0) / k, tex.get_height())
	draw_texture_rect_region(tex, Rect2(x0 + shift, -h * 0.5, x1 - x0, h), src, Color(1, 1, 1, a))


## Вещи [from, to) при сдвиге ряда off: кляксы выпрыгивают от центра к краям, к краям полосы — гаснут.
func _draw_items(from: int, to: int, off: float, a: float) -> void:
	for i: int in range(from, to):
		var x := i * CELL - off
		var d := absf(x) / CELL
		if d > 3.0:
			continue
		var pop := clampf((_t - 0.3 - d * 0.07) / 0.25, 0.0, 1.0)
		if pop <= 0.0:
			continue
		var sc := _back(pop)
		var vis := a * (1.0 - smoothstep(2.0, 2.75, d)) * minf(1.0, pop * 2.0)
		if vis <= 0.01:
			continue
		var it: Dictionary = _items[i]
		var col := eq.rc(int(it["r"]))
		var p := Vector2(x, 0.0)
		var bt := _tex("blot_%d.png" % int(it["blot"]))
		var bs := BLOT * sc
		draw_set_transform_matrix(_xf * Transform2D(float(it["rot"]), p))
		draw_texture_rect(bt, Rect2(-bs * 0.5, -bs * 0.5, bs, bs), false, Color(1, 1, 1, vis))
		draw_set_transform_matrix(_xf * Transform2D(0.0, p))
		for g: int in 4:                                     # свечение редкости под вещью
			draw_circle(Vector2.ZERO, ICON * 0.5 * sc * (1.05 + g * 0.12), Color(col, 0.10 * vis))
		var ic := _icon(str(it["set"]), int(it["k"]), int(it["r"]))
		var isz := ICON * sc
		draw_texture_rect(ic, Rect2(-isz * 0.5, -isz * 0.5, isz, isz), false, Color(1, 1, 1, vis))
		draw_arc(Vector2.ZERO, isz * 0.5 + 1.5, 0.0, TAU, 40, Color(col, 0.75 * vis), 1.6, true)
		if bool(it["mana"]):
			draw_arc(Vector2.ZERO, isz * 0.5 + 4.5, 0.0, TAU, 40, Color(1.0, 0.37, 0.82, 0.7 * vis), 1.2, true)
		draw_set_transform_matrix(_xf)


## Указатель, пока ряд крутится: тонкая золотая черта с остриями сверху и снизу (как стрелки шкалы); гаснет,
## когда появляется катана.
func _draw_marker() -> void:
	var a := clampf((_t - 0.55) / 0.25, 0.0, 1.0) * (1.0 - clampf((_t - _kat_t()) / 0.15, 0.0, 1.0))
	if a <= 0.0:
		return
	var gold := Color(0.88, 0.7, 0.4)
	var top := -88.0
	var bot := 88.0
	for g: int in 3:                                         # мягкое свечение
		draw_line(Vector2(0, top), Vector2(0, bot), Color(1.0, 0.85, 0.55, 0.08 * a), 4.0 + g * 4.0)
	draw_line(Vector2(0, top), Vector2(0, bot), Color(1.0, 0.93, 0.75, 0.9 * a), 1.6, true)
	for sd: float in [-1.0, 1.0]:
		var y := top if sd < 0.0 else bot
		var tip := PackedVector2Array([Vector2(-9, y + sd * 12.0), Vector2(9, y + sd * 12.0), Vector2(0, y - sd * 4.0)])   # остриё — к вещи
		var o := PackedVector2Array([tip[0] + Vector2(-2, sd * 1.5), tip[1] + Vector2(2, sd * 1.5), tip[2] + Vector2(0, -sd * 2.5)])
		draw_colored_polygon(o, Color(0.05, 0.03, 0.03, 0.8 * a))
		draw_colored_polygon(tip, Color(gold, a))


## Разрезы: за каждым взмахом — штрих туши сверху вниз по линии взмаха и брызги наружу (первый — влево, по ходу
## ряда; второй — вправо); каждый гаснет сам.
func _draw_cut() -> void:
	var sl := _tex("slash.png")
	var h := 300.0
	var w := sl.get_width() * h / sl.get_height()
	for n: int in 2:
		var t0 := _c1() if n == 0 else _c2()
		var u := clampf((_t - t0) / STROKE, 0.0, 1.0)
		var a := 1.0 - clampf((_t - t0) / 0.8, 0.0, 1.0) if n == 0 else 1.0 - clampf((_t - t0 - 0.4) / 0.35, 0.0, 1.0)
		if u <= 0.0 or a <= 0.0:                             # первый разрез стоит на месте и гаснет вместе с отрезанным
			continue
		var x := _gap1() if n == 0 else CELL * 0.5
		var src := Rect2(0, 0, sl.get_width(), sl.get_height() * u)
		draw_texture_rect_region(sl, Rect2(x - w * 0.5, -h * 0.5, w, h * u), src, Color(1, 1, 1, a))
		var sp := clampf((_t - t0 - 0.05) / 0.25, 0.0, 1.0)
		if sp <= 0.0:
			continue
		var st := _tex("splat_l.png" if n == 0 else "splat_r.png")
		var sw := 190.0 * (0.6 + 0.4 * sp)
		var sh := st.get_height() * sw / st.get_width()
		draw_texture_rect(st, Rect2(x - sw if n == 0 else x, 30.0 - sh * 0.5, sw, sh), false, Color(1, 1, 1, a))


## Остаток — вещь на своей кляксе в тушевом кольце цвета редкости; ниже имя и редкость (гаснут, когда вещь уходит
## к окну характеристик или сжимается в сферу).
func _draw_reveal(reveal: float, fade: float) -> void:
	var it := winner()
	var col := eq.rc(int(it["r"]))
	var u := clampf((_t - reveal) / 0.35, 0.0, 1.0)
	var e := _ease(u)
	var ring := _tex("ink_ring.png")
	var rs := RING * lerpf(1.5, 1.0, e)
	var rh := ring.get_height() * rs / ring.get_width()
	var a := u * fade
	if a <= 0.0:
		return
	for g: int in 5:
		draw_circle(Vector2.ZERO, RING * 0.36 + g * 9.0, Color(col, 0.07 * a))
	draw_texture_rect(ring, Rect2(-rs * 0.5, -rh * 0.5, rs, rh), false, Color(col.lerp(Color.WHITE, 0.15), a))
	var ta := a * (1.0 - clampf((_t - _move_at) / 0.3, 0.0, 1.0)) if _big and _move_at >= 0.0 else a
	if ta <= 0.01:
		return
	var full := eq.from_id(str(it["id"]), hero_lvl)
	var name_s := str(full.get("name", ""))
	var rname := str((eq.rar[int(it["r"])] as Dictionary).get("name", ""))
	if bool(it["mana"]):
		rname += " · пропитано маной"
	var y := RING * 0.5 + 18.0
	var fs := ui.px(ui.serif, 24)
	var fs2 := ui.px(ui.body, 15)
	draw_string_outline(ui.serif, Vector2(-300, y + fs * 0.8), name_s, HORIZONTAL_ALIGNMENT_CENTER, 600, fs, 6, Color(0, 0, 0, 0.75 * ta))
	draw_string(ui.serif, Vector2(-300, y + fs * 0.8), name_s, HORIZONTAL_ALIGNMENT_CENTER, 600, fs, Color(col.lerp(Color.WHITE, 0.2), ta))
	var t2 := rname + "  ·  " + str(cfg.get("got", "%s")) % str((eq.slots[int(it["k"])] as Dictionary).get("type", ""))
	draw_string_outline(ui.body, Vector2(-300, y + fs + fs2 + 2), t2, HORIZONTAL_ALIGNMENT_CENTER, 600, fs2, 5, Color(0, 0, 0, 0.7 * ta))
	draw_string(ui.body, Vector2(-300, y + fs + fs2 + 2), t2, HORIZONTAL_ALIGNMENT_CENTER, 600, fs2, Color(0.93, 0.87, 0.80, ta))


## Сумка для этой вещи: (видимость, открыта ли, «подпрыгивание» к прилёту) — рисует её loot.gd, одну на все прокрутки.
func bag_state() -> Vector3:
	if _items.is_empty():
		return Vector3.ZERO
	var arrive := _orb_at + 0.3 + FLY
	var ba := clampf((_t - _orb_at + 0.2) / 0.3, 0.0, 1.0) * (1.0 - clampf((_t - arrive - 0.5) / 0.4, 0.0, 1.0))
	var open := 1.0 if _t >= arrive - 0.12 and _t < arrive + 0.4 else 0.0
	return Vector3(ba, open, 1.0 + 0.12 * maxf(0.0, 1.0 - absf(_t - arrive) / 0.25))


## Где сумка, px макета: правый нижний угол, правее прокруток (центр; сумка 112 px — loot.gd BAG_H).
func bag_pos() -> Vector2:
	return Vector2(size.x / maxf(size.y / 1080.0, 0.001) - 78.0, 1080.0 - 74.0)


## Сфера вещи, летящая в сумку (сумка рисуется поверх — сфера в неё «входит»).
func _draw_orb(s: float) -> void:
	var t0 := _orb_at
	var arrive := t0 + 0.3 + FLY
	if _t < t0 or _t > arrive:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var bag := bag_pos()
	var it := winner()
	var col := eq.rc(int(it["r"]))
	var from := anchor + _group_off()
	var k := clampf((_t - t0 - 0.3) / FLY, 0.0, 1.0)
	var shrink := clampf((_t - t0) / 0.3, 0.0, 1.0)
	var ctrl := from.lerp(bag, 0.5) + Vector2(40.0, -180.0)
	var p := _bez(from, ctrl, bag, k)
	var r := lerpf(40.0, 14.0, shrink) * lerpf(1.0, 0.7, k) * K
	for j: int in range(6, 0, -1):                          # шлейф
		if k <= 0.0:
			break
		var tp := _bez(from, ctrl, bag, maxf(0.0, k - j * 0.035))
		draw_circle(tp, r * (1.0 - j * 0.12), Color(col, 0.06 * (7 - j)))
	for g: int in 4:
		draw_circle(p, r * (1.3 + g * 0.35), Color(col, 0.12))
	draw_circle(p, r, col.lerp(Color.WHITE, 0.35))
	draw_circle(p, r * 0.55, Color(1, 1, 1, 0.95))
	if shrink < 1.0:
		var isz := ICON * K * (1.0 - shrink)
		draw_texture_rect(_icon(str(it["set"]), int(it["k"]), int(it["r"])), Rect2(p - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false,
			Color(1, 1, 1, 1.0 - shrink))


static func _bez(p0: Vector2, c: Vector2, p1: Vector2, k: float) -> Vector2:
	var e := k * k * (3.0 - 2.0 * k)
	return p0.lerp(c, e).lerp(c.lerp(p1, e), e)


func _tex(name: String) -> Texture2D:
	return ui.tex(DIR + name)


## Иконка вещи на кляксе: ячейка листа сета, края уходят в прозрачность (круг) — без квадратной плитки.
func _icon(set_key: String, k: int, r: int) -> Texture2D:
	var key := "%s:%d:%d" % [set_key, k, r]
	if _icons.has(key):
		return _icons[key]
	var sheet := ui.tex(str((eq.sets[set_key] as Dictionary)["sheet"]))
	var cell := eq.cell(set_key, k, r)
	var side := minf(cell.size.x, cell.size.y)
	var src := Rect2i(Vector2i(cell.position + (cell.size - Vector2(side, side)) * 0.5), Vector2i(int(side), int(side)))
	var img := sheet.get_image().get_region(src)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	for y: int in 128:
		for x: int in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 64.0
			var px := img.get_pixel(x, y)
			px.a = 1.0 - smoothstep(0.78, 1.0, d)
			img.set_pixel(x, y, px)
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


func _play(name: String, db: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _snd.get(name)
	if p == null:
		var st: AudioStream = mod.sound("sounds/" + name)
		if st == null:
			return
		p = AudioStreamPlayer.new()
		p.stream = st
		p.bus = "PaxRpgSfx"
		p.max_polyphony = 4
		add_child(p)
		_snd[name] = p
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
