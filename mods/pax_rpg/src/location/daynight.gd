extends Node
## Смена суток в локации: час идёт (config/location.json → day_minutes — длина суток в минутах, start_hour),
## солнце ходит по дуге (восход 6:00, закат 18:00), ночью тот же свет — луна, голубая и слабая; небо
## (shaders/sky.gdshader: day, dusk), окружение и туман следуют; ночью фонари, костры и кристаллы разгораются,
## окна светятся тёплым. Консоль F8: rpg_time <час>.

var hour := 17.0
var day_minutes := 20.0
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var lights: Array = []             # [OmniLight3D, энергия ночью]
var glass: Array = []              # материалы окон
var paper: Array = []              # бумажные фонари — свечение мягче окон
var fog_day := Color(0.95, 0.62, 0.8)


func setup(e: Environment, s: DirectionalLight3D, sm: ShaderMaterial, cfg: Dictionary) -> void:
	name = "PaxRpgDayNight"
	env = e
	sun = s
	sky_mat = sm
	hour = float(cfg.get("start_hour", 17.0))
	day_minutes = maxf(1.0, float(cfg.get("day_minutes", 20.0)))
	apply()


func _process(delta: float) -> void:
	hour = fmod(hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
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
		sun.rotation = Vector3(-asin(clampf(e, 0.06, 1.0)), deg_to_rad(90.0) + ang, 0.0)
		if up:
			sun.light_color = Color(1.0, 0.86, 0.72).lerp(Color(1.0, 0.55, 0.35), dusk)
			sun.light_energy = lerpf(0.0, 1.35, smoothstep(-0.05, 0.25, elev))
		else:
			sun.light_color = Color(0.5, 0.58, 0.95)
			sun.light_energy = 0.16 * smoothstep(0.05, 0.35, -elev)
	if sky_mat != null:
		sky_mat.set_shader_parameter("day", day)
		sky_mat.set_shader_parameter("dusk", dusk)
	if env != null:
		env.ambient_light_energy = lerpf(0.07, 0.55, day)
		var fog_night := Color(0.18, 0.14, 0.32)
		env.fog_light_color = fog_night.lerp(fog_day, day).lerp(Color(1.0, 0.5, 0.42), dusk * 0.6)
		env.tonemap_exposure = lerpf(1.0, 1.05, day)
	var night := 1.0 - day
	for l: Array in lights:
		var ol: OmniLight3D = l[0]
		if is_instance_valid(ol):
			ol.light_energy = float(l[1]) * lerpf(0.2, 1.0, night)
	for pm: Variant in paper:
		var m2 := pm as BaseMaterial3D
		if m2 != null:
			m2.emission_energy_multiplier = lerpf(0.35, 1.6, night)
	for g: Variant in glass:
		var m := g as BaseMaterial3D
		if m != null:
			m.emission_energy_multiplier = lerpf(0.3, 2.6, night)
