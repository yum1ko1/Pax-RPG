extends Node
## Фоновая музыка локации: днём в городе — «Marketplace of the Brave» и «Steppe Horizon» по очереди,
## ночью — «Glowing Mana Lullaby»; вне города — степь. Смена — плавным перекрёстным затуханием.

const DAY := ["sounds/music/marketplace.ogg", "sounds/music/steppe_horizon.ogg"]
const NIGHT := "sounds/music/mana_lullaby.ogg"
const FIELD := "sounds/music/steppe_horizon.ogg"
const FADE := 3.0

var mod: PaxMod
var daynight: Node                  # daynight.gd (hour) — или null вне города
var city := false
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _now := ""
var _day_i := 0


func setup(m: PaxMod, in_city: bool) -> void:
	mod = m
	city = in_city
	name = "PaxRpgMusic"
	process_mode = Node.PROCESS_MODE_ALWAYS          # играет и в паузе
	for i: int in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "PaxRpgMusic"
		p.volume_db = -80.0
		p.finished.connect(_on_finished)
		add_child(p)
		if i == 0:
			_a = p
		else:
			_b = p


func _process(_delta: float) -> void:
	var want := _want()
	if want != _now and not (want == "" and _now != ""):
		_play(want)


func _night() -> bool:
	if daynight == null or not is_instance_valid(daynight):
		return false
	var h := float(daynight.get("hour"))
	return h >= 20.5 or h < 5.0


func _want() -> String:
	if not city:
		return FIELD
	if _night():
		return NIGHT
	return _now if _now in DAY else str(DAY[_day_i % DAY.size()])


func _on_finished() -> void:                     # трек кончился — следующий (днём — другой)
	if _now in DAY:
		_day_i += 1
		_play(str(DAY[_day_i % DAY.size()]))
	else:
		_play(_now, true)


func _play(path: String, force := false) -> void:
	if path == _now and not force:
		return
	var st: AudioStream = mod.sound(path)
	if st == null:
		return
	_now = path
	var old := _a
	_a = _b
	_b = old
	_a.stream = st
	_a.volume_db = -40.0
	_a.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(_a, "volume_db", 0.0, FADE).set_trans(Tween.TRANS_SINE)
	if _b.playing:
		tw.tween_property(_b, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(_b.stop)
