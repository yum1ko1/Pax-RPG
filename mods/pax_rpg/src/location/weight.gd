extends RefCounted
## Вес героя и ударов — по школьной механике (динамика и вращательное движение):
##  • инерция, II закон Ньютона a = F/m: шаг и бег набираются за время, тяжёлый (с бронёй и мечом) — медленнее;
##  • трение F = μ·m·g: остановка — торможение, а не мгновенный стоп;
##  • центростремительное ускорение a = v²/r ≤ μ·g: на бегу поворот по дуге, ω ≤ μ·g / v — чем быстрее, тем шире;
##  • удар: острие идёт по дуге, v = ω·r (длиннее клинок — быстрее острие); импульс p = m·v, где m — меч плюс
##    часть тела, вложенная в удар;
##  • сохранение импульса: враг получает Δv = p / m_врага (лёгкого гоблина уносит, орка едва сдвигает);
##  • III закон Ньютона: герой получает −p / m_героя — отдача от тяжёлого врага;
##  • F = Δp / Δt: чем больше импульс, тем дольше замирание удара (hitstop) и сильнее дрожь камеры;
##  • закон Гука F = −k·x: отдача гаснет как пружина с демпфером, без рывка.
## Всё настраивается в config/hero.json → weight.

const G := 9.8

var cfg: Dictionary = {}


func _init(c: Variant) -> void:
	cfg = c if c is Dictionary else {}


func f(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


## Масса героя со снаряжением, кг.
func hero_mass() -> float:
	return f("hero_mass", 80.0) + f("armor_mass", 18.0) + f("weapon_mass", 3.5)


## Горизонтальная скорость к желаемой: разгон силой ног (a = F/m), торможение — трением (μ·g) плюс ноги.
func approach(vel: Vector2, want: Vector2, delta: float) -> Vector2:
	var m := hero_mass()
	var drive := f("leg_force", 1150.0) / m                     # м/с², разгон
	var brake := f("friction", 0.9) * G + drive * 0.5          # м/с², остановка: подошвы о землю и упор ногами
	var a := drive if want.length() > vel.length() * 0.98 and want.dot(vel) >= 0.0 else brake
	return vel.move_toward(want, a * delta)


## Наибольшая скорость поворота на бегу, рад/с: ω = a / v, a — сцепление μ·g (дальше — занос).
func max_turn(speed: float) -> float:
	return f("friction", 0.9) * G * f("turn_grip", 1.6) / maxf(speed, 0.5)


## Импульс удара, кг·м/с. tip_speed — скорость острия (м/с); 0 — из ω·r клипа (weapon_omega × weapon_length).
func impulse(tip_speed: float, heavy: bool) -> float:
	var v := tip_speed if tip_speed > 0.0 else f("weapon_omega", 9.0) * f("weapon_length", 1.3)
	var body := f("body_share_heavy", 0.22) if heavy else f("body_share", 0.1)    # доля тела, вложенная в удар
	return (f("weapon_mass", 3.5) + body * f("hero_mass", 80.0)) * v


## Скорость отлёта врага массой m_enemy от импульса p (передаётся доля transfer — остальное уходит в рану и стойку).
func knock(p: float, m_enemy: float) -> float:
	return clampf(p * f("transfer", 0.55) / maxf(m_enemy, 1.0), 0.0, f("knock_max", 9.0))


## Отдача герою (III закон): та же доля импульса, делённая на массу героя; лёгкого врага почти не чувствует.
func recoil(p: float, m_enemy: float) -> float:
	var share := m_enemy / (m_enemy + hero_mass())                # тяжёлый враг «стоит стеной» — отдача больше
	return p * f("transfer", 0.55) * share / hero_mass() * f("recoil_gain", 2.2)


## Вес удара 0.5…2: импульс относительно обычного удара — на замирание, тряску, стойку врага.
func heft(p: float) -> float:
	return clampf(p / maxf(impulse(0.0, false), 0.01), 0.5, 2.0)


## Отдача гаснет как у пружины с демпфером (Гук, F = −k·x − c·v): скорость толчка убывает плавно, без рывка.
static func spring(v: Vector3, delta: float, k: float, c: float) -> Vector3:
	return v - v * minf(1.0, (c + k * delta) * delta)
