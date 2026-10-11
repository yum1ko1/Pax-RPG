extends Control
## Заставка входа в город: чуть выше центра слева со звоном влетает катана, замирает посередине, на клинке
## проступает название места; через несколько секунд надпись тает, и катана со звоном улетает вправо.

const Katana := preload("res://mods/pax_rpg/src/ui/katana.gd")
const Hud := preload("res://mods/pax_rpg/src/location/hud.gd")
const HOLD := 5.0

var _name := ""
var _x := -1.0                     # положение: −1 — за левым краем, 0 — середина, 1 — за правым
var _text_a := 0.0
var _glint := -1.0                 # блик по клинку при остановке (0..1)
var _font: Font
var _snd: AudioStreamPlayer


func setup(mod: PaxMod, place: String) -> void:
	name = "PaxRpgCityTitle"
	_name = place
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Hud._sys(["Yu Mincho", "Cormorant Garamond", "Georgia", "Times New Roman"], 700)
	var rnd := AudioStreamRandomizer.new()
	rnd.random_pitch = 1.05
	for i: int in 3:
		var st: AudioStream = mod.sound("sounds/katana_fly_%d.ogg" % i)
		if st != null:
			rnd.add_stream(-1, st)
	if rnd.streams_count > 0:
		_snd = AudioStreamPlayer.new()
		_snd.bus = "PaxRpgSfx"
		_snd.stream = rnd
		_snd.volume_db = -3.0
		add_child(_snd)


func play(delay := 0.4) -> void:
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(_ring)
	tw.tween_property(self, "_x", 0.0, 0.42).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_glint", 1.0, 0.5)
	tw.parallel().tween_property(self, "_text_a", 1.0, 0.7)
	tw.tween_interval(HOLD)
	tw.tween_property(self, "_text_a", 0.0, 0.8)
	tw.tween_callback(_ring)
	tw.tween_property(self, "_x", 1.0, 0.38).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _ring() -> void:
	if _snd != null:
		_snd.play()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var length := minf(vs.x * 0.62, vs.y * 1.15)
	var cx := vs.x * 0.5 + _x * (vs.x * 0.5 + length)
	var y := vs.y * 0.36
	var tip := Vector2(cx + length * 0.5, y)               # острие — вперёд, вправо
	var fs := int(length * 0.034 * 0.95)
	Katana.draw(self, tip, PI, length, 1.0, 0.0, _name, _font, fs, _text_a, true)
	if _glint > 0.0 and _glint < 1.0:                       # блик бежит по клинку
		var gx := tip.x - length * 0.7 * _glint
		var a := sin(_glint * PI)
		draw_line(Vector2(gx - 18, y - 14), Vector2(gx + 18, y + 10), Color(1, 1, 1, 0.8 * a), 3.0, true)
	if absf(_x) > 0.02:                                     # след в воздухе
		var back := tip.x - length if _x < 0.0 else tip.x
		var dir := -1.0 if _x < 0.0 else 1.0
		for i: int in 6:
			var yy := y - 6 + i * 3.0
			draw_line(Vector2(back - dir * 40.0 * (i + 1), yy), Vector2(back, yy), Color(1.0, 0.7, 0.9, 0.12), 2.0)
