extends Control
## Лут с повергнутых врагов: сферы разлетаются из тела, падают, затем сами притягиваются к герою и подбираются.
## Золотая — золото (gold_picked), розовая — опыт (xp_picked: дальше мана летит в шкалу опыта, как раньше), радужная
## (переливается, config/loot.json → rainbow_chance) улетает в правый нижний угол и запускает прокрутку (roll.gd).
## Несколько радужных сразу — прокрутки встают друг над другом (до ROLLS), остальные ждут, пока какая-то освободится.
## Сферы живут в мире (Vector3), рисуются поверх экрана по проекции камеры; размер — по расстоянию.

signal gold_picked(n: int)
signal xp_picked(v: float, at: Vector2)

const Equip := preload("res://mods/pax_rpg/src/location/inv/equip.gd")
const Ui := preload("res://mods/pax_rpg/src/location/inv/ui.gd")
const Roll := preload("res://mods/pax_rpg/src/location/loot/roll.gd")
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const GRAV := 14.0
const FLY := 0.8                     # полёт радужной сферы в угол, с
const ROLLS := 3                     # прокруток на экране одновременно
const BAG_H := 112.0                 # высота сумки, px макета
const ROLL_STEP := 172.0             # шаг прокруток вверх, px макета (при roll_scale 1)
const SIZE := {"gold": 0.34, "xp": 0.3, "rainbow": 0.6}   # поперечник в мире, м

var mod: PaxMod
var cfg: Dictionary = {}
var eq := Equip.new()
var ui := Ui.new()
var _cam: Camera3D
var _hero: Node3D
var _orbs: Array = []               # {kind, p: Vector3, v: Vector3, t, hold, ground, amount}
var _flights: Array = []            # радужные в полёте к прокрутке: {from: Vector2, t, slot, r}
var _pending: Array = []             # редкости прокруток в очереди (−1 — по шансам)
var _rolls: Array = []               # Roll по местам снизу вверх
var _lvl := 1
var _gate: Array = []                # очередь окон характеристик крупных вещей (общая для прокруток)
var _bag: Control
var _bag_art := -1                   # есть ли арт сумки (−1 — ещё не смотрели)
var _rb: Control                    # слой радужных сфер — со своим шейдером перелива
var _snd: Dictionary = {}


func setup(m: PaxMod) -> void:
	mod = m
	var p: Variant = JSON.parse_string(mod.read_text("config/loot.json"))
	cfg = p if p is Dictionary else {}
	eq.load_data(mod)
	ui.setup(mod)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_rb = Control.new()
	_rb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rb.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh: Shader = mod.shader("shaders/loot_rainbow.gdshader")
	if sh != null:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_rb.material = mat
	_rb.draw.connect(_draw_rainbow)
	add_child(_rb)
	for i: int in ROLLS:
		var roll := Roll.new()
		roll.setup(mod, eq, ui, cfg)
		roll.set_katana(Assets.model(mod, "models/weapons/katana.glb"))
		roll.gate = _gate
		add_child(roll)
		_rolls.append(roll)
	_bag = Control.new()                                      # одна сумка на все прокрутки — поверх них
	_bag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bag.draw.connect(_draw_bag)
	add_child(_bag)


## Враг повергнут: сферы из точки at (ноги врага). xp и gold делятся между сферами своего цвета; lvl — уровень героя
## (статы вещи в окне характеристик).
func drop(at: Vector3, cam: Camera3D, hero: Node3D, xp: float, gold: int, lvl: int) -> void:
	_cam = cam
	_hero = hero
	_lvl = lvl
	var go: Array = cfg.get("gold_orbs", [2, 4])
	var xo: Array = cfg.get("xp_orbs", [3, 5])
	var ng := mini(randi_range(int(go[0]), int(go[1])), maxi(gold, 1))
	var nx := randi_range(int(xo[0]), int(xo[1]))
	for i: int in ng:
		_spawn("gold", at, float(gold / ng + (1 if i < gold % ng else 0)))
	for i: int in nx:
		_spawn("xp", at, xp / nx)
	if randf() < float(cfg.get("rainbow_chance", 0.3)):
		_spawn("rainbow", at, -1.0)


## Проверка (команда rpg_roll): радужная сфера сразу перед героем; r ≥ 0 — редкость выигрыша.
func test(cam: Camera3D, hero: Node3D, lvl: int, r := -1) -> void:
	_cam = cam
	_hero = hero
	_lvl = lvl
	var fwd := -hero.global_transform.basis.z if is_instance_valid(hero) else Vector3.FORWARD
	if is_instance_valid(cam):
		fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	_spawn("rainbow", hero.global_position + fwd.normalized() * 3.0, float(r))   # у радужной amount — редкость выигрыша


func _spawn(kind: String, at: Vector3, amount: float) -> void:
	var a := randf() * TAU
	var sp := randf_range(1.6, 3.6)
	_orbs.append({"kind": kind, "p": at + Vector3(0.0, 0.9, 0.0), "v": Vector3(cos(a) * sp, randf_range(3.5, 5.5), sin(a) * sp),
		"t": 0.0, "hold": randf_range(0.55, 0.85), "ground": at.y, "amount": amount, "seed": randf() * TAU})


func _process(delta: float) -> void:
	var live := is_instance_valid(_hero) and is_instance_valid(_cam) and _hero.is_inside_tree()
	if not live:
		_orbs.clear()
	var target := _hero.global_position + Vector3(0.0, 1.0, 0.0) if live else Vector3.ZERO
	var keep: Array = []
	for o: Dictionary in _orbs:
		o.t = float(o.t) + delta
		var p: Vector3 = o.p
		var v: Vector3 = o.v
		if float(o.t) < float(o.hold):                       # разлёт и отскок от земли
			v.y -= GRAV * delta
			p += v * delta
			var floor_y := float(o.ground) + 0.22
			if p.y < floor_y:
				p.y = floor_y
				v = Vector3(v.x * 0.55, -v.y * 0.35, v.z * 0.55)
		else:                                                # притяжение к герою, всё быстрее
			var to := target - p
			var speed := minf(3.0 + (float(o.t) - float(o.hold)) * 24.0, 28.0)
			v = v.lerp(to.normalized() * speed, minf(1.0, delta * 7.0))
			p += v * delta
			if to.length() < 0.5:
				_pick(o)
				continue
		o.p = p
		o.v = v
		keep.append(o)
	_orbs = keep
	var fl: Array = []
	for f: Dictionary in _flights:
		f.t = float(f.t) + delta
		if float(f.t) < FLY:
			fl.append(f)
		elif int(f.slot) >= 0:
			_start(int(f.slot), int(f.r))
		else:
			_pending.append(int(f.r))
	_flights = fl
	if not _pending.is_empty():
		var i := _free_slot()
		if i >= 0:
			_start(i, int(_pending.pop_front()))
	queue_redraw()
	_rb.queue_redraw()
	_bag.queue_redraw()


func _pick(o: Dictionary) -> void:
	var at := _cam.unproject_position(o.p)
	match str(o.kind):
		"gold":
			gold_picked.emit(int(o.amount))
			_play("loot_tick.ogg", -23.0, randf_range(1.5, 1.7))
		"xp":
			xp_picked.emit(float(o.amount), at)
			_play("loot_tick.ogg", -25.0, randf_range(1.15, 1.3))
		"rainbow":
			_flights.append({"from": at, "t": 0.0, "slot": _free_slot() if _pending.is_empty() else -1, "r": int(o.amount)})
			_play("loot_ink.ogg", -19.0, 1.3)


func _start(i: int, r: int) -> void:
	var roll: Roll = _rolls[i]
	roll.anchor = _corner(i)
	roll.hero_lvl = _lvl
	roll.start(r)


## Свободное место: прокрутка не идёт и к нему не летит сфера; −1 — все заняты.
func _free_slot() -> int:
	for i: int in _rolls.size():
		if (_rolls[i] as Roll).busy():
			continue
		var taken := false
		for f: Dictionary in _flights:
			if int(f.slot) == i:
				taken = true
		if not taken:
			return i
	return -1


## Центр прокрутки i в px макета (высота 1080): между панелью приёмов и сумкой в правом нижнем углу, следующие — выше.
func _corner(i := 0) -> Vector2:
	var w := size.x / maxf(size.y / 1080.0, 0.001)
	var k := float(cfg.get("roll_scale", 0.68))
	return Vector2(w - 120.0 - 350.0 * k, 1080.0 - 140.0 * k - i * ROLL_STEP * k)


func _screen_r(o: Dictionary) -> float:
	var d := _cam.global_position.distance_to(o.p)
	var vh := get_viewport_rect().size.y
	var r := float(SIZE[str(o.kind)]) * 0.5 * vh / (maxf(d, 0.3) * 2.0 * tan(deg_to_rad(_cam.fov) * 0.5))
	return clampf(r, 4.0, 70.0)


func _draw() -> void:
	if not is_instance_valid(_cam):
		return
	var now := Time.get_ticks_msec() * 0.001
	for o: Dictionary in _orbs:
		if str(o.kind) == "rainbow" or _cam.is_position_behind(o.p):
			continue
		var c := _cam.unproject_position(o.p)
		var r := _screen_r(o) * (1.0 + 0.06 * sin(now * 5.0 + float(o.seed)))
		var gold := str(o.kind) == "gold"
		var col := Color(1.0, 0.78, 0.35) if gold else Color(1.0, 0.4, 0.78)
		for g: int in 3:
			draw_circle(c, r * (1.3 + g * 0.35), Color(col, 0.09))
		var tex := ui.tex("textures/loot/orb_gold.png" if gold else "textures/loot/orb_pink.png")
		draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)


## Радужные: в мире — крутятся и дышат; в полёте к углу — по дуге, уменьшаясь, со шлейфом искр.
func _draw_rainbow() -> void:
	if not is_instance_valid(_cam):
		return
	var now := Time.get_ticks_msec() * 0.001
	var tex := ui.tex("textures/loot/orb_rainbow.png")
	for o: Dictionary in _orbs:
		if str(o.kind) != "rainbow" or _cam.is_position_behind(o.p):
			continue
		var c := _cam.unproject_position(o.p)
		var r := _screen_r(o) * (1.0 + 0.08 * sin(now * 4.0))
		_orb_at(tex, c, r, now)
	var s := size.y / 1080.0
	for f: Dictionary in _flights:
		var to := _corner(maxi(0, int(f.slot))) * s
		var k := clampf(float(f.t) / FLY, 0.0, 1.0)
		var p0: Vector2 = f.from
		var ctrl := p0.lerp(to, 0.5) + Vector2(0.0, -260.0 * s)
		for j: int in range(6, 0, -1):
			var tp := _bez(p0, ctrl, to, maxf(0.0, k - j * 0.03))
			_rb.draw_circle(tp, (14.0 - j * 1.6) * s, Color(1.0, 0.9, 0.6, 0.06 * (7 - j)))
		_orb_at(tex, _bez(p0, ctrl, to, k), lerpf(46.0, 30.0, k) * s, now)


## Сумка в правом нижнем углу — одна: видна, пока в неё летит хоть одна вещь; открывается к каждому прилёту.
## Арт — bag_closed / bag_open; без него — клякса с золотым кругом.
func _draw_bag() -> void:
	var st := Vector3.ZERO
	for r: Roll in _rolls:
		var b := r.bag_state()
		st = Vector3(maxf(st.x, b.x), maxf(st.y, b.y), maxf(st.z, b.z))
	if st.x <= 0.0:
		return
	var s := size.y / 1080.0
	var pos := (_rolls[0] as Roll).bag_pos()
	_bag.draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	if _bag_art < 0:
		_bag_art = 0 if mod.read_bytes("textures/loot/bag_closed.png").is_empty() else 1
	if _bag_art == 1:
		var bt := ui.tex("textures/loot/bag_open.png" if st.y > 0.5 else "textures/loot/bag_closed.png")
		var bh := BAG_H * st.z
		var bw := bt.get_width() * bh / bt.get_height()
		_bag.draw_texture_rect(bt, Rect2(pos - Vector2(bw * 0.5, bh * 0.5), Vector2(bw, bh)), false, Color(1, 1, 1, st.x))
	else:
		var bs := 120.0 * st.z
		_bag.draw_texture_rect(ui.tex("textures/loot/blot_2.png"), Rect2(pos - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false, Color(1, 1, 1, st.x))
		_bag.draw_arc(pos, 34.0 * st.z, 0.0, TAU, 48, Color(0.79, 0.64, 0.36, st.x), 2.0, true)


func _orb_at(tex: Texture2D, c: Vector2, r: float, now: float) -> void:
	for g: int in 3:
		_rb.draw_circle(c, r * (1.1 + g * 0.3), Color(1.0, 0.55, 0.85, 0.07))
	_rb.draw_set_transform(c, now * 0.9, Vector2.ONE)
	_rb.draw_texture_rect(tex, Rect2(-r, -r, r * 2.0, r * 2.0), false)
	_rb.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _bez(p0: Vector2, c: Vector2, p1: Vector2, k: float) -> Vector2:
	var e := k * k * (3.0 - 2.0 * k)
	return p0.lerp(c, e).lerp(c.lerp(p1, e), e)


func _play(name: String, db: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _snd.get(name)
	if p == null:
		var st: AudioStream = mod.sound("sounds/" + name)
		if st == null:
			return
		p = AudioStreamPlayer.new()
		p.stream = st
		p.bus = "PaxRpgSfx"
		p.max_polyphony = 6
		add_child(p)
		_snd[name] = p
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
