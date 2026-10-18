"""Чертёж Гхарна для Obsidian: SVG со значками и легендой — рисуется из той же планировки, что и город
(gharn_layout.py вызывает draw_plan после сборки), поэтому чертёж всегда совпадает с игрой.
Север — вверх (−Z), 1 м = 4 px. Дороги — из ROADS/TRAILS, постройки — по габаритам моделей, значки — по типу."""
import math
from xml.sax.saxutils import escape

S = 4.0
X0, X1, Z0, Z1 = -130.0, 130.0, -132.0, 132.0
LEG_W = 430

# модель → (значок, цвет пятна, подпись в легенде)
ICONS = [
    ("khan_palace", "🏯", "#8e2a2a", "Ставка Хаана"), ("gate_fang", "🚪", "#5a4632", "Врата Клыка"),
    ("guild_hall", "📜", "#3d5a80", "Дом Вольных Клинков (гильдия)"), ("tavern_hall", "🍶", "#9a6a2a", "Таверна «Сытый Тумен»"),
    ("forge_smithy", "🔨", "#5b4a43", "Кузня"), ("stable_hay", "🐎", "#8a6d3b", "Конюшня / сарай"),
    ("shaman_tower", "🔮", "#7b3fa0", "Башня шаманки"), ("watch_tower", "🏹", "#4a3b2e", "Дозорная вышка"),
    ("house_two", "🏠", "#b5533c", "Двухэтажный дом"), ("house_shop", "🏪", "#c06a3a", "Лавка с домом"),
    ("house_timber", "🛖", "#7d5a3c", "Сруб"), ("yurt_noble", "⛺", "#c9a24a", "Юрта знати"),
    ("yurt_large", "⛺", "#d8c7a0", "Юрта"), ("yurt_small", "⛺", "#e2d6b6", "Юрта малая"),
    ("stilt_hut", "🪵", "#6b5a3a", "Хижина на сваях (гоблины)"), ("fountain_dragon", "⛲", "#4aa3c9", "Фонтан Пасти"),
    ("oath_tree", "🌳", "#3f7a3a", "Древо Клятв"), ("flame_tree", "🌸", "#e7799a", "Сакура"),
    ("guardian_statue", "🗿", "#777", "Статуя-страж"), ("stone_lantern", "🏮", "#d9a441", "Каменный фонарь"),
    ("bench_long", "🪑", "#8b6b47", "Скамья с урной"), ("market_stall", "🛒", "#b07a3a", "Лавка-навес"),
    ("stall_frame", "🛒", "#b07a3a", "Торговый ряд"), ("beast_cage", "🐺", "#555", "Клетка / псарня"),
    ("spit_roast", "🍖", "#a0522d", "Вертел, очаг"), ("firepit", "🔥", "#d2691e", "Костёр"),
    ("war_drum", "🥁", "#8b4513", "Боевой барабан"), ("totem_pole", "🗼", "#6d4c41", "Тотем"),
    ("ovoo_cairn", "🪨", "#8d8d8d", "Тур (обо), курган"), ("tusk_arch", "🦴", "#e0d8c8", "Арка клыков"),
    ("training_dummy", "🎯", "#9c7b4f", "Чучело / пугало"), ("trough", "💧", "#5d8aa8", "Колодец, поилка"),
    ("hay_bale", "🌾", "#d4b04a", "Сено, стог"), ("buffalo", "🐃", "#4b3a2e", "Буйволы"),
    ("tug_banner", "🚩", "#b22222", "Туг, знамя"), ("bone_banner", "🚩", "#e8e0d0", "Костяное знамя"),
    ("mana_totem", "✨", "#d070e0", "Мановый тотем"), ("wall_hob", "🧱", "#9e9e9e", "Казарма, стена хобгоблинов"),
]
ROUTE = [(0, 84), (0, 32), (0, 26), (17, 17), (24, 0), (34, -6), (44, -13)]   # первый путь: Врата → Аллея → Круг → гильдия
ZONES = [  # (x0, z0, x1, z1, подпись, цвет)
    (-15, 14, 15, 84, "Аллея Сакур", "#f6b3c6"), (-30, -30, 30, 30, "Площадь Круга · Арена", "#e9d9b8"),
    (-26, -72, 26, -36, "Ставка Хаана", "#d9a3a3"), (-26, -92, 26, -74, "Сад Хаана", "#c8e2b4"),
    (-78, -8.5, 78, 8.5, "Аллея Знамён", "#f0d0a0"), (-72, -4, -36, 32, "Базар Добычи", "#ead2a8"),
    (-88, 34, -20, 82, "Курени Кланов", "#e8e1cc"), (18, 44, 90, 82, "Улица Мастеров", "#e7c9b5"),
    (-70, -58, -48, -30, "Счётный двор", "#cfcfcf"), (-90, -92, -36, -60, "Курганы Предков", "#d3d0c4"),
    (36, -60, 62, -36, "Гоблинский закоулок", "#d9c6e8"), (54, -76, 78, -56, "Склон шаманов", "#c9a8e0"),
    (22, -88, 48, -60, "Волчьи Псарни", "#d8cbb8"), (40, 4, 66, 34, "Таверна", "#efd3a2"),
    (44, -30, 64, -12, "Гильдия", "#bfd0e6"), (66, 12, 86, 32, "Конюшня", "#e3d2b0"),
    (23, 27, 41, 40, "Буйволиный двор", "#dcc9a6"), (-44, -34, -22, -14, "Кузнечный двор", "#d6c2b4"),
]


def px(x, z):
    return (x - X0) * S, (z - Z0) * S


def icon_of(m):
    for k, ic, col, name in ICONS:
        if k in m:
            return k, ic, col, name
    return None


def draw_plan(path, items, roads, trails, foot, ground, outer):
    W = (X1 - X0) * S
    H = (Z1 - Z0) * S
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W + LEG_W:.0f}" height="{H:.0f}" '
         f'font-family="Segoe UI Emoji, Noto Color Emoji, Segoe UI, sans-serif">',
         f'<rect width="100%" height="100%" fill="#efe6d2"/>']
    gx0, gz0 = ground[2] - ground[0] / 2, ground[3] - ground[1] / 2
    a, b = px(gx0 - outer, gz0 - outer)
    o.append(f'<rect x="{a:.0f}" y="{b:.0f}" width="{(ground[0] + 2 * outer) * S:.0f}" height="{(ground[1] + 2 * outer) * S:.0f}" fill="#e3d5b5"/>')
    a, b = px(gx0, gz0)
    o.append(f'<rect x="{a:.0f}" y="{b:.0f}" width="{ground[0] * S:.0f}" height="{ground[1] * S:.0f}" fill="#d9c49c" stroke="#5a4632" stroke-width="6"/>')
    for x0, z0, x1, z1, name, col in ZONES:
        a, b = px(x0, z0)
        o.append(f'<rect x="{a:.0f}" y="{b:.0f}" width="{(x1 - x0) * S:.0f}" height="{(z1 - z0) * S:.0f}" fill="{col}" opacity="0.55" rx="10"/>')

    def shape(sh, fill, op):
        if sh[0] == "rect":
            a, b = px(sh[1], sh[3])
            return f'<rect x="{a:.0f}" y="{b:.0f}" width="{(sh[2] - sh[1]) * S:.0f}" height="{(sh[4] - sh[3]) * S:.0f}" fill="{fill}" opacity="{op}"/>'
        if sh[0] == "disc":
            a, b = px(sh[1], sh[2])
            return f'<circle cx="{a:.0f}" cy="{b:.0f}" r="{sh[3] * S:.0f}" fill="{fill}" opacity="{op}"/>'
        pts = " ".join("%.0f,%.0f" % px(x, z) for x, z in sh[1])
        return f'<polyline points="{pts}" fill="none" stroke="{fill}" stroke-width="{sh[2] * S:.0f}" stroke-linecap="round" stroke-linejoin="round" opacity="{op}"/>'
    for sh in trails:
        o.append(shape(sh, "#b48a5a", 0.55))
    for sh in roads:
        o.append(shape(sh, "#8a8278", 0.85))
    # поля
    for it in items:
        if "box" in it and str(it.get("mat", "")).startswith("field"):
            bx, _, bz = it["p"]
            sx, _, sz = it["box"]
            a, b = px(bx - sx / 2, bz - sz / 2)
            col = {"field_millet": "#e0b84a", "field_green": "#7aa33a", "field_rice": "#9cc35a"}[it["mat"]]
            o.append(f'<rect x="{a:.0f}" y="{b:.0f}" width="{sx * S:.0f}" height="{sz * S:.0f}" fill="{col}"/>')
    # гирлянды фонарей
    for it in items:
        if "lanterns" in it:
            x0, z0, x1, z1 = it["lanterns"][:4]
            a, b = px(x0, z0)
            c, d = px(x1, z1)
            o.append(f'<line x1="{a:.0f}" y1="{b:.0f}" x2="{c:.0f}" y2="{d:.0f}" stroke="#e8562a" stroke-width="3" stroke-dasharray="5,6"/>')
    a, b = px(0, 0)                                       # Арена: яма r 17.5 в центре площади
    o.append(f'<circle cx="{a:.0f}" cy="{b:.0f}" r="{17.5 * S:.0f}" fill="#c9a66b" stroke="#5a4632" stroke-width="4"/>')
    o.append(f'<circle cx="{a:.0f}" cy="{b:.0f}" r="{13.5 * S:.0f}" fill="#e6cf98"/>')
    o.append(f'<text x="{a:.0f}" y="{b + 14:.0f}" font-size="40" text-anchor="middle">⚔️</text>')
    pts = " ".join("%.0f,%.0f" % px(x, z) for x, z in ROUTE)
    o.append(f'<polyline points="{pts}" fill="none" stroke="#1f6fd1" stroke-width="5" stroke-dasharray="14,9" opacity="0.85"/>')
    used = {"arena": ("⚔️", "#c9a66b", "Арена (яма, трибуны)"), "route": ("➜", "#1f6fd1", "Первый путь игрока (синий пунктир)")}
    marks = []
    for it in items:
        m = it.get("m", "")
        ic = icon_of(m)
        if ic is None or not (X0 < it["p"][0] < X1 and Z0 < it["p"][2] < Z1):
            continue
        k, glyph, col, name = ic
        used[k] = (glyph, col, name)
        x, _, z = it["p"]
        hx, hz = foot(m)
        s = float(it.get("s", 1.0))
        r = math.radians(it.get("r", 0.0))
        ex = abs(math.cos(r)) * hx * s + abs(math.sin(r)) * hz * s
        ez = abs(math.sin(r)) * hx * s + abs(math.cos(r)) * hz * s
        big = max(ex, ez) > 2.4
        if big:
            a, b = px(x - ex, z - ez)
            o.append(f'<rect x="{a:.0f}" y="{b:.0f}" width="{2 * ex * S:.0f}" height="{2 * ez * S:.0f}" fill="{col}" stroke="#2b2118" stroke-width="1.5" rx="3"/>')
        fs = 22 if big else 12
        a, b = px(x, z)
        marks.append(f'<text x="{a:.0f}" y="{b + fs * 0.35:.0f}" font-size="{fs}" text-anchor="middle">{glyph}</text>')
    o += marks
    for x0, z0, x1, z1, name, col in ZONES:
        a, b = px((x0 + x1) / 2, z0)
        o.append(f'<text x="{a:.0f}" y="{b + 16:.0f}" font-size="15" font-weight="700" text-anchor="middle" fill="#2b2118" '
                 f'stroke="#fff8ea" stroke-width="4" paint-order="stroke">{escape(name)}</text>')
    a, b = px(0, Z0 + 6)
    o.append(f'<text x="{a:.0f}" y="{b:.0f}" font-size="20" text-anchor="middle" font-weight="700">▲ С (−Z)</text>')
    # легенда
    lx = W + 18
    o.append(f'<rect x="{W:.0f}" y="0" width="{LEG_W}" height="{H:.0f}" fill="#fbf6ea"/>')
    o.append(f'<text x="{lx}" y="36" font-size="22" font-weight="700">Гхарн — план столицы</text>')
    o.append(f'<text x="{lx}" y="60" font-size="13" fill="#555">1 клетка сетки = 10 м · север вверху · из gharn_layout.py</text>')
    y = 92
    for col, name in (("#8a8278", "Мощёная дорога"), ("#b48a5a", "Тропа, двор, переулок"), ("#e8562a", "Гирлянда фонарей (пунктир)"),
                      ("#e0b84a", "Поле проса"), ("#7aa33a", "Огород, зелень"), ("#9cc35a", "Рисовое поле")):
        o.append(f'<rect x="{lx}" y="{y - 13}" width="28" height="14" fill="{col}"/><text x="{lx + 38}" y="{y}" font-size="14">{escape(name)}</text>')
        y += 24
    y += 8
    for k, (glyph, col, name) in sorted(used.items(), key=lambda kv: kv[1][2]):
        o.append(f'<text x="{lx + 12}" y="{y}" font-size="18" text-anchor="middle">{glyph}</text><text x="{lx + 38}" y="{y - 2}" font-size="14">{escape(name)}</text>')
        y += 25
    o.append("</svg>")
    grid = []
    for gx in range(int(X0), int(X1) + 1, 10):
        a, _ = px(gx, 0)
        grid.append(f'<line x1="{a:.0f}" y1="0" x2="{a:.0f}" y2="{H:.0f}" stroke="#000" stroke-opacity="0.05"/>')
    for gz in range(int(Z0), int(Z1) + 1, 10):
        _, b = px(0, gz)
        grid.append(f'<line x1="0" y1="{b:.0f}" x2="{W:.0f}" y2="{b:.0f}" stroke="#000" stroke-opacity="0.05"/>')
    o[2:2] = grid
    open(path, "w", encoding="utf-8").write("\n".join(o))
