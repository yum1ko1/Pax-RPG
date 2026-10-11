extends RefCounted
## Шины громкости мода: PaxRpgMusic (фоновая музыка) и PaxRpgSfx (шаги, удары, город, заставки).
## Громкость — доля 0..1 из настроек мода (music_volume / sfx_volume), меняется в меню паузы → Настройки.

const MUSIC := "PaxRpgMusic"
const SFX := "PaxRpgSfx"


static func ensure(mod: PaxMod) -> void:
	for b: String in [MUSIC, SFX]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	set_volume(MUSIC, float(mod.get_setting("music_volume", 0.6)))
	set_volume(SFX, float(mod.get_setting("sfx_volume", 1.0)))


static func set_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)
