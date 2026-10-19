extends RefCounted
## Простой профайлер для rpg_perf: сколько микросекунд за кадр тратит каждая часть мода (сумма с прошлого сброса).

static var sums := {}
static var since := 0
static var on := false               # копит, только пока кто-то просит отчёт (оверлей rpg_perf): иначе — ноль работы


static func add(key: String, t0: int) -> void:
	if not on:
		return
	sums[key] = int(sums.get(key, 0)) + Time.get_ticks_usec() - t0


## Средние мс на кадр по частям с прошлого вызова и сброс.
static func report(frames: int) -> String:
	on = true
	var keys := sums.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(sums[a]) > int(sums[b]))
	var out := []
	for k: Variant in keys:
		out.append("%s %.2f мс" % [k, int(sums[k]) / 1000.0 / maxf(frames, 1)])
	sums.clear()
	return " · ".join(out)
