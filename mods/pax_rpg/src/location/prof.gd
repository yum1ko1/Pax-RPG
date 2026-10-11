extends RefCounted
## Простой профайлер для rpg_perf: сколько микросекунд за кадр тратит каждая часть мода (сумма с прошлого сброса).

static var sums := {}
static var since := 0


static func add(key: String, t0: int) -> void:
	sums[key] = int(sums.get(key, 0)) + Time.get_ticks_usec() - t0


## Средние мс на кадр по частям с прошлого вызова и сброс.
static func report(frames: int) -> String:
	var keys := sums.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(sums[a]) > int(sums[b]))
	var out := []
	for k: Variant in keys:
		out.append("%s %.2f мс" % [k, int(sums[k]) / 1000.0 / maxf(frames, 1)])
	sums.clear()
	return " · ".join(out)
