extends RefCounted
## Слава арены (фаза 3 плана): сколько этапов арены герой прошёл (arena.gd → настройка arena_stage) и побеждал ли
## последний (arena_champion) — ступень 0…5, от чужака до чемпиона Гхарна. Жители и стража узнают героя на улице
## (реплика над головой, location.gd → _fame_barks), торговцы и кузнец уступают в цене, нейросеть знает титул в
## разговоре (talk.gd → hero_title). Только чтение настроек — прогресс пишет арена.

const DISCOUNT := [0, 0, 5, 5, 10, 15]     # % скидки в лавке и кузне по ступени славы


static func level(mod: PaxMod) -> int:
	var won := clampi(int(mod.get_setting("arena_stage", 0)), 0, 4)
	if int(mod.get_setting("arena_champion", 0)) > 0:
		won = 5
	return won


static func title(mod: PaxMod) -> String:
	return mod.tr_key("pax_rpg_fame_%d" % level(mod))


static func discount(mod: PaxMod) -> int:
	return int(DISCOUNT[level(mod)])


static func discount_mult(mod: PaxMod) -> float:
	return 1.0 - discount(mod) / 100.0


## Реплика жителя, узнавшего героя: стража — своя; "" — не узнал (славы мало).
static func bark(mod: PaxMod, role: String, rng_v: int) -> String:
	var l := level(mod)
	if l < 1:
		return ""
	var tier := 1 if l <= 2 else (2 if l <= 4 else 3)
	var who := "guard" if role == "guard" else "folk"
	var opts := mod.tr_key("pax_rpg_fame_bark_%s_%d" % [who, tier]).split("|", false)
	return opts[absi(rng_v) % opts.size()] if not opts.is_empty() else ""
