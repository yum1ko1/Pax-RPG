extends Node
## Звуки локации кроме боя: шаги героя и бряцание снаряжения (по пройденному пути), фоновый гул города (петля
## sounds/city_bed.ogg — синтез pax_rpg/dev/sfx/city_ambience.py) и редкие бытовые звуки вдали (кузня, котлы,
## монеты, двери). Шаги и снаряжение — Kenney RPG Audio / Impact Sounds (CC0, sounds/LICENSE_kenney.txt).

const STEPS := 10
const GEAR := 7
const CITY := 13

var _step
var _gear
var _bed: AudioStreamPlayer
var _far
var _impact
var _walked := 0.0
var soft := false                     # location.gd: под ногами песок/земля (лес, яма арены) — мягкий шаг
var _sand
var puddle := false                   # location.gd: герой стоит в луже — шаг хлюпает
var _splash
var _next_far := 4.0
var _left := false
var city := false


var _mod: PaxMod
var _at: Node3D                       # где звучат шаги и ткань — герой (3D: громче, когда камера ближе)
var _cloth       # резкий хлопок ткани (взмах, уклон)
var _whoosh                         # свист оружия в воздухе на ударе (sounds/swing_N.wav) — у героев с sfx_whoosh
var _step_db := 0.0                   # поправка громкости шага героя (каблуки тише)
var _rustle      # шорох одежды на шаге
var _skirt       # юбка — тихо, «издалека» (запись у микрофона: срез верхов, эхо)
var _land_db := -4.0
var walk_stride := 0.78               # м на шаг (звук); у героя — sfx_stride_walk из конфига


func setup(mod: PaxMod, in_city: bool) -> void:
	_mod = mod
	name = "PaxRpgSfx"
	city = in_city
	_step = _rand(mod, "sounds/step_%d.ogg", STEPS, 0.12, -9.0)
	_splash = _rand(mod, "sounds/puddle_step_%d.wav", 9, 0.1, -8.0)
	_sand = _rand(mod, "sounds/sand_step_%d.wav", 8, 0.1, -9.0)     # шаг по песку и земле (нарезка sand_dry_barefoot)   # шаг по луже (нарезка idm-po-lujam)
	_gear = _rand(mod, "sounds/armor_step_%d.wav", 10, 0.1, -14.0)   # лязг доспеха — по шагу (нарезка knight-in-armor)
	if _gear == null:
		_gear = _rand(mod, "sounds/gear_%d.ogg", GEAR, 0.15, -17.0)
	_far = _rand(mod, "sounds/city_%d.ogg", CITY, 0.2, -26.0)
	_impact = _rand(mod, "sounds/impact_%d.wav", 4, 0.1, -2.0)          # impact_1..3 (0 нет — пропустится)
	if city:
		var bed: AudioStream = mod.sound("sounds/city_bed.ogg")
		if bed is AudioStreamOggVorbis:
			(bed as AudioStreamOggVorbis).loop = true
		if bed != null:
			_bed = AudioStreamPlayer.new()
			_bed.stream = bed
			_bed.volume_db = -15.0
			_bed.bus = "PaxRpgSfx"
			add_child(_bed)
			_bed.play()


func _rand(mod: PaxMod, pattern: String, n: int, pitch: float, volume: float) -> Node:
	var rnd := AudioStreamRandomizer.new()
	rnd.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	rnd.random_pitch = 1.0 + pitch
	rnd.random_volume_offset_db = 2.0
	for i: int in n:
		var st: AudioStream = mod.sound(pattern % i)
		if st != null:
			rnd.add_stream(-1, st)
	if rnd.streams_count == 0:
		return null
	var p = _player()
	p.stream = rnd
	p.volume_db = volume
	p.max_polyphony = 3
	p.bus = "PaxRpgSfx"
	add_child(p)
	return p


## 3D-плеер: слышит камера локации (audio_listener_enable_3d), громкость падает с расстоянием.
## 3D-звук шагов и ткани (настройка sfx_3d; выключить — обычный плоский звук).
func _player() -> Node:
	if not bool(_mod.get_setting("sfx_3d", true)):
		return AudioStreamPlayer.new()
	var p := AudioStreamPlayer3D.new()
	_place(p)
	return p


func _place(p: AudioStreamPlayer3D) -> void:
	p.unit_size = 5.0
	p.max_distance = 70.0
	p.attenuation_filter_cutoff_hz = 9000.0          # издалека — глуше
	p.attenuation_filter_db = -12.0


## Звуки героя из его конфига: sfx_steps "heel" — каблуки (камень / мягкий грунт), sfx_gear false — без лязга
## доспеха, sfx_cloth — шорох одежды на шаге и хлопки ткани на взмахах.
func hero(cfg: Dictionary, at: Node3D) -> void:
	_at = at
	if str(cfg.get("sfx_steps", "")) == "heel":
		for p: Node in [_step, _sand]:
			if p != null:
				p.queue_free()
		_step = _rand(_mod, "sounds/heel_step_%d.wav", 10, 0.06, -9.0)    # нарезка «на каблуках по каменному полу»
		_sand = _rand(_mod, "sounds/heel_soft_%d.wav", 10, 0.08, -9.0)    # тот же каблук глуше + хруст песка
		_land_db = -9.0
		_step_db = -3.0
		for p: Variant in [_step, _sand]:                 # свои шаги — без «издалека глуше»: фильтр 3D срезал щелчок
			if p is AudioStreamPlayer3D:                  # каблука (он весь выше 3 кГц), и камень звучал как земля
				(p as AudioStreamPlayer3D).attenuation_filter_db = 0.0
				(p as AudioStreamPlayer3D).unit_size = 12.0
	walk_stride = float(cfg.get("sfx_stride_walk", 0.78))
	if not bool(cfg.get("sfx_gear", true)) and _gear != null:
		_gear.queue_free()
		_gear = null
	if bool(cfg.get("sfx_whoosh", false)):
		_whoosh = _rand(_mod, "sounds/swing_%d.wav", 7, 0.12, -6.0)
	if bool(cfg.get("sfx_cloth", false)):
		_cloth = _rand(_mod, "sounds/cloth_snap_%d.wav", 6, 0.1, -6.0)
		if bool(cfg.get("sfx_rustle", false)):        # шорох одежды на каждом шаге — шершавый, по умолчанию выключен
			_rustle = _rand(_mod, "sounds/cloth_rustle_%d.wav", 8, 0.1, -20.0)
		if bool(cfg.get("sfx_skirt", false)):         # шорох юбки на шаге — по желанию героя (у Тянь Лун выключен)
			_skirt = _rand(_mod, "sounds/skirt_%d.wav", 8, 0.08, -16.0)


## Резкий хлопок ткани (взмах копья, уклон) — у героев с sfx_cloth.
func cloth(db: float) -> void:
	if _cloth != null:
		_cloth.volume_db = db + randf_range(-2.0, 0.0)
		_cloth.play()


## Свист копья на ударе.
func whoosh() -> void:
	if _whoosh != null:
		_whoosh.volume_db = randf_range(-7.0, -4.0)
		_whoosh.play()


## Приземление в ударе (step_times клипа): каблук о землю, чуть громче шага.
func land_step() -> void:
	var p = _sand if soft and _sand != null else _step
	if p != null:
		p.volume_db = _land_db
		p.play()
	if _rustle != null:
		_rustle.volume_db = -16.0
		_rustle.play()


## Каждый кадр физики: сколько герой прошёл по земле. Шаг — каждые stride м; бряцание — на каждый второй шаг
## (с мечом и на бегу — на каждый).
func walk(dist: float, running: bool, armed: bool, on_floor: bool) -> void:
	if not on_floor:
		return
	_walked += dist
	var stride := 1.45 if running else walk_stride
	if _walked < stride:
		return
	_walked = 0.0
	_left = not _left
	if puddle and _splash != null:                       # в луже — хлюпает вместо шага по камню
		_splash.volume_db = -5.0 if running else -8.0
		_splash.play()
	elif soft and _sand != null:
		_sand.volume_db = (-6.0 if running else -9.0) + _step_db
		_sand.play()
	elif _step != null:
		_step.volume_db = (-6.0 if running else -9.0) + _step_db
		_step.play()
	if _rustle != null:
		_rustle.volume_db = -17.0 if running else -21.0
		_rustle.play()
	if _skirt != null and _left:                         # юбка — на каждый второй шаг, тихо
		_skirt.volume_db = -14.0 if running else -17.0
		_skirt.play()
	if _gear != null:                                    # доспех лязгает на каждом шаге — в такт ногам
		_gear.volume_db = (-9.0 if running else -13.0) + (1.5 if armed else 0.0)
		_gear.pitch_scale = 1.08 if running else 1.0
		_gear.play()


## Приземление после прыжка — двойной шаг.
## Удар о землю (волна «Земного разлома»): низкий тяжёлый звук.
func impact() -> void:
	if _smash == null:
		_smash = _one("sounds/ground_smash.wav", -2.0)             # меч о землю: удар и крошево
	if _smash != null:
		_smash.pitch_scale = randf_range(0.9, 1.05)
		_smash.play()
	if _impact != null:
		_impact.pitch_scale = randf_range(0.55, 0.7)
		_impact.play()


var _land_armor
var _smash


func _one(mod_path: String, db: float) -> Node:
	var st: AudioStream = _mod.sound(mod_path) if _mod != null else null
	if st == null:
		return null
	var p = _player()
	p.stream = st
	p.volume_db = db
	p.bus = "PaxRpgSfx"
	p.max_polyphony = 3
	add_child(p)
	return p


func land() -> void:
	if _land_armor == null:
		_land_armor = _one("sounds/armor_land.wav", -6.0)          # доспех ударился о землю
	if _land_armor != null:
		_land_armor.pitch_scale = randf_range(0.95, 1.05)
		_land_armor.play()
	if _step != null:
		_step.volume_db = _land_db
		_step.play()
	if _gear != null:
		_gear.play()


func _process(delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("sfx._process")
	if is_instance_valid(_at):                       # плееры — дети простого Node: позиция = мировая
		var pos := _at.global_position
		for c: Node in get_children():
			if c is AudioStreamPlayer3D:
				(c as AudioStreamPlayer3D).position = pos
	if not city or _far == null:
		return
	_next_far -= delta
	if _next_far <= 0.0:
		_next_far = randf_range(2.5, 9.0)
		_far.volume_db = randf_range(-30.0, -22.0)
		_far.play()
