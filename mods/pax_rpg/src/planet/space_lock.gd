extends RefCounted
## Под Хоэном одна Юрума: модули игры, которые ведут к другим звёздам и галактикам, выключены (data/systems.json:
## «space» — спутники, перелёты, экспедиции и мегаструктуры; «secrets» — тайны галактики; «guests» — гости со
## звёзд). Игра применяет это со следующего старта партии. Сами планеты, луны, пояса и звёзды галактики убраны
## данными мода (data/bodies.patch.json, galaxy.patch.json, galaxy_secrets.patch.json).

const SYSTEMS_OFF: Array[String] = ["space", "secrets", "guests"]


static func apply(m: PaxMod) -> void:
	for id: String in SYSTEMS_OFF:
		var why := Pax.disable_system(id)
		if why != "":
			m.log_warning("Pax RPG: game system %s stays on: %s" % [id, why])
