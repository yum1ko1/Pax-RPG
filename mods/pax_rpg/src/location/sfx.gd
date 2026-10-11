extends Node
## Звуки локации кроме боя: шаги героя и бряцание снаряжения (по пройденному пути), фоновый гул города (петля
## sounds/city_bed.ogg — синтез pax_rpg/dev/sfx/city_ambience.py) и редкие бытовые звуки вдали (кузня, котлы,
## монеты, двери). Шаги и снаряжение — Kenney RPG Audio / Impact Sounds (CC0, sounds/LICENSE_kenney.txt).

const STEPS := 10
const GEAR := 7
const CITY := 13

var _step: AudioStreamPlayer
var _gear: AudioStreamPlayer
var _bed: AudioStreamPlayer
var _far: AudioStreamPlayer
var _walked := 0.0
var _next_far := 4.0
var _left := false
var city := false


func setup(mod: PaxMod, in_city: bool) -> void:
	name = "PaxRpgSfx"
	city = in_city
	_step = _rand(mod, "sounds/step_%d.ogg", STEPS, 0.12, -9.0)
	_gear = _rand(mod, "sounds/gear_%d.ogg", GEAR, 0.15, -17.0)
	_far = _rand(mod, "sounds/city_%d.ogg", CITY, 0.2, -26.0)
	if city:
		var bed: AudioStream = mod.sound("sounds/city_bed.ogg")
		if bed is AudioStreamOggVorbis:
			(bed as AudioStreamOggVorbis).loop = true
		if bed != null:
			_bed = AudioStreamPlayer.new()
			_bed.stream = bed
			_bed.volume_db = -15.0
			add_child(_bed)
			_bed.play()


func _rand(mod: PaxMod, pattern: String, n: int, pitch: float, volume: float) -> AudioStreamPlayer:
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
	var p := AudioStreamPlayer.new()
	p.stream = rnd
	p.volume_db = volume
	p.max_polyphony = 3
	add_child(p)
	return p


## Каждый кадр физики: сколько герой прошёл по земле. Шаг — каждые stride м; бряцание — на каждый второй шаг
## (с мечом и на бегу — на каждый).
func walk(dist: float, running: bool, armed: bool, on_floor: bool) -> void:
	if not on_floor:
		return
	_walked += dist
	var stride := 1.45 if running else 0.78
	if _walked < stride:
		return
	_walked = 0.0
	_left = not _left
	if _step != null:
		_step.volume_db = -6.0 if running else -9.0
		_step.play()
	if _gear != null and (armed or running or _left):
		_gear.volume_db = (-12.0 if running else -16.0) + (2.0 if armed else 0.0)
		_gear.play()


## Приземление после прыжка — двойной шаг.
func land() -> void:
	if _step != null:
		_step.volume_db = -4.0
		_step.play()
	if _gear != null:
		_gear.play()


func _process(delta: float) -> void:
	if not city or _far == null:
		return
	_next_far -= delta
	if _next_far <= 0.0:
		_next_far = randf_range(2.5, 9.0)
		_far.volume_db = randf_range(-30.0, -22.0)
		_far.play()
