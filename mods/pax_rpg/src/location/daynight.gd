extends Node
const Vfx := preload("res://mods/pax_rpg/src/location/vfx.gd")
## Смена суток в локации: час идёт (config/location.json → day_minutes — длина суток в минутах, start_hour),
## солнце ходит по дуге (восход 6:00, закат 18:00), ночью тот же свет — луна, голубая и слабая; небо
## (shaders/sky.gdshader: day, dusk), окружение и туман следуют; ночью фонари, костры и кристаллы разгораются,
## окна светятся тёплым. Консоль F8: rpg_time <час>.
const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")

var hour := 17.0
var day_minutes := 20.0
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var lights: Array = []             # [OmniLight3D, энергия ночью]
var glass: Array = []              # материалы окон
var paper: Array = []              # бумажные фонари — свечение мягче окон
const SUN_STEP := 5.0               # градусов: на столько солнце уходит, прежде чем тени пересчитаются
var _sun_set := false
var _sun_tw: Tween
var fog_day := Color(0.9, 0.7, 0.84)          # мана в дымке — розовая, но не заливает весь кадр


func setup(e: Environment, s: DirectionalLight3D, sm: ShaderMaterial, cfg: Dictionary) -> void:
	name = "PaxRpgDayNight"
	env = e
	sun = s
	sky_mat = sm
	hour = world_hour(cfg)
	day_minutes = maxf(1.0, float(cfg.get("day_minutes", 20.0)))
	frozen = true                                     # пока игрок в городе, время стоит: тени не перерисовываются
	apply()


## Часы мира: час суток по системному времени (start_hour в полночь по UTC 1970, сутки — day_minutes минут);
## одни и те же для глобуса (подсказка над городом, planet.gd) и для города при входе.
static func world_hour(cfg: Dictionary) -> float:
	var dm := maxf(1.0, float(cfg.get("day_minutes", 20.0)))
	var days := Time.get_unix_time_from_system() / (dm * 60.0)
	return fmod(float(cfg.get("start_hour", 17.0)) + fmod(days, 1.0) * 24.0, 24.0)


## Ключ перевода части суток: pax_rpg_tod_night / morning / day / evening.
static func phase_key(h: float) -> String:
	if h >= 5.0 and h < 10.0:
		return "pax_rpg_tod_morning"
	if h >= 10.0 and h < 17.0:
		return "pax_rpg_tod_day"
	if h >= 17.0 and h < 21.0:
		return "pax_rpg_tod_evening"
	return "pax_rpg_tod_night"


## «Утро · 07:40».
static func label(mod: PaxMod, h: float) -> String:
	return "%s · %02d:%02d" % [mod.tr_key(phase_key(h)), int(h), int(fmod(h, 1.0) * 60.0)]


var _since := 0.0


## Солнце, небо, туман и огни — не каждый кадр: смена неба заставляет Godot пересчитывать освещение от неба
## (radiance), сдвиг солнца — тени. Раз в STEP секунд глаз разницы не видит (за 2 с солнце сдвигается на 0.6°).
const STEP := 2.0


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_proc(delta)
	Prof.add("день/ночь", t0)


var frozen := true                 # время суток стоит, пока игрок в городе (часы мира идут на глобусе)


func _proc(delta: float) -> void:
	if frozen:
		return
	hour = fmod(hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	_since += delta
	if _since >= STEP:
		_since = 0.0
		apply()


func apply() -> void:
	var a := (hour - 6.0) / 12.0 * PI                     # 0 — восход, PI — закат
	var elev := sin(a)                                    # > 0 — солнце над горизонтом
	var day := smoothstep(-0.12, 0.3, elev)
	var dusk := clampf(1.0 - smoothstep(0.0, 0.3, absf(elev)), 0.0, 1.0)   # у горизонта — закат / рассвет
	if is_instance_valid(sun):
		var up := elev >= -0.05
		var ang := a if up else a - PI                    # ночью — луна по той же дуге
		var e := maxf(sin(ang), 0.06)
		var want := Vector3(-asin(clampf(e, 0.06, 1.0)), deg_to_rad(90.0) + ang, 0.0)
		# тени перерисовываются, только когда солнце ушло на SUN_STEP (а не каждые 2 с), и плавно за секунду
		var jump := absf(angle_difference(sun.rotation.y, want.y)) > PI * 0.5 or not _sun_set
		if jump:
			sun.rotation = want
			_sun_set = true
		elif absf(angle_difference(sun.rotation.y, want.y)) + absf(sun.rotation.x - want.x) > deg_to_rad(SUN_STEP):
			if _sun_tw != null and _sun_tw.is_valid():
				_sun_tw.kill()
			_sun_tw = create_tween()
			_sun_tw.tween_property(sun, "rotation", want, 1.0).set_trans(Tween.TRANS_SINE)
		if up:
			sun.light_color = Color(1.0, 0.92, 0.82).lerp(Color(1.0, 0.68, 0.48), dusk)
			sun.light_energy = lerpf(0.0, 1.1, smoothstep(-0.05, 0.45, elev)) * lerpf(1.0, 0.8, dusk)   # утром и вечером мягче
		else:
			sun.light_color = Color(0.5, 0.58, 0.95)
			sun.light_energy = 0.16 * smoothstep(0.05, 0.35, -elev)
	if sky_mat != null:
		sky_mat.set_shader_parameter("day", day)
		sky_mat.set_shader_parameter("dusk", dusk)
	if env != null:
		env.ambient_light_energy = lerpf(0.06, 0.42, day)
		var fog_night := Color(0.18, 0.14, 0.32)
		env.fog_light_color = fog_night.lerp(fog_day, day).lerp(Color(1.0, 0.56, 0.46), dusk * 0.4)
		env.tonemap_exposure = lerpf(0.95, 0.9, day)
	var night := 1.0 - day
	for l: Array in lights:
		var ol: OmniLight3D = l[0]
		if is_instance_valid(ol):
			var e := float(l[1]) * lerpf(0.0, 0.6, night)   # днём огни не светят — их не видно на солнце
			if ol is Vfx.Flicker:
				(ol as Vfx.Flicker).base = e                  # огонь мерцает вокруг этой энергии
			else:
				ol.light_energy = e
	for pm: Variant in paper:
		var m2 := pm as BaseMaterial3D
		if m2 != null:
			m2.emission_energy_multiplier = lerpf(0.15, 0.9, night)
	for g: Variant in glass:
		var m := g as BaseMaterial3D
		if m != null:
			m.emission_energy_multiplier = lerpf(0.1, 1.3, night)
