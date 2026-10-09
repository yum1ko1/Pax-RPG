"""Юрума — процедурная планета для Pax RPG: карты и референс-рендеры.

Запуск (из корня репозитория):
    python pax_rpg/dev/yuruma_planet.py [--width 2048] [--seed 7]

Пишет в pax_rpg/reference/yuruma/:
    yuruma_height.png      — высоты, 16 бит (0 — дно океана, 32767 — уровень моря)
    yuruma_color.png       — цветная карта поверхности (равнопромежуточная)
    yuruma_clouds.png      — мановые облака (альфа)
    yuruma_empires.png     — политическая карта: 5 империй, провинции
    yuruma_regions.png     — провинции цветами-регионами (для импорта карты в игру)
    yuruma_provinces.json  — цвет провинции → империя (для сценария)
    yuruma_globe_*.png     — вид из космоса
    yuruma_sheet.png       — сводный лист-референс

Всё считается шумом на сфере, поэтому карта бесшовная по долготе и без искажений у полюсов.
"""
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[1] / "reference" / "yuruma"
# Текстура планеты для мода Pax RPG (поверхность + мановые облака, без подписей).
MOD_TEXTURES = Path(__file__).resolve().parents[2] / "mods" / "pax_rpg" / "textures"

SEA_LEVEL = 0.0
LAND_SHARE_TARGET = 0.36


# ---------------------------------------------------------------- палитра

def rgb(hex_: str) -> np.ndarray:
    return np.array([int(hex_[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32) / 255.0


PAL = {
    "abyss": rgb("#070f3a"),
    "deep": rgb("#0d2373"),
    "sea": rgb("#1747a6"),
    "shallow": rgb("#2a9fd0"),
    "lagoon": rgb("#53d6e0"),
    "shore": rgb("#b9dcec"),
    "meadow": rgb("#6fb3d9"),
    "forest": rgb("#1c5d8f"),
    "forest_dark": rgb("#113f6b"),
    "jungle": rgb("#167f9c"),
    "canopy": rgb("#2a8fc4"),
    "canopy_light": rgb("#5cc3e0"),
    "rock": rgb("#46507e"),
    "rock_high": rgb("#7c74b4"),
    "crystal": rgb("#e6f3ff"),
    "ice": rgb("#dfeeff"),
    "cloud": rgb("#ffd2ef"),
    "cloud_shade": rgb("#a45cc0"),
    "atmo_haze": rgb("#ff8fd6"),
    "atmo_inner": rgb("#ff9ee0"),
    "atmo_outer": rgb("#ff5fc4"),
    "ley": rgb("#ff6ad5"),
    "ley_cyan": rgb("#62f0ff"),
}


# ---------------------------------------------------------------- шум на сфере

def _hash(ix: np.ndarray, iy: np.ndarray, iz: np.ndarray, seed: int) -> np.ndarray:
    h = (ix.astype(np.uint32) * np.uint32(0x8DA6B343)
         ^ iy.astype(np.uint32) * np.uint32(0xD8163841)
         ^ iz.astype(np.uint32) * np.uint32(0xCB1AB31F)
         ^ np.uint32(seed * 0x9E3779B1 & 0xFFFFFFFF))
    h ^= h >> np.uint32(13)
    h *= np.uint32(0x5BD1E995)
    h ^= h >> np.uint32(15)
    return (h & np.uint32(0xFFFFFF)).astype(np.float32) / float(0xFFFFFF)


def value_noise(p: np.ndarray, seed: int) -> np.ndarray:
    """3D value noise, p — (..., 3), результат в [0, 1]."""
    f = np.floor(p)
    t = p - f
    t = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    i = f.astype(np.int64)
    x0, y0, z0 = i[..., 0], i[..., 1], i[..., 2]
    tx, ty, tz = t[..., 0], t[..., 1], t[..., 2]

    def c(dx: int, dy: int, dz: int) -> np.ndarray:
        return _hash(x0 + dx, y0 + dy, z0 + dz, seed)

    x00 = c(0, 0, 0) + (c(1, 0, 0) - c(0, 0, 0)) * tx
    x10 = c(0, 1, 0) + (c(1, 1, 0) - c(0, 1, 0)) * tx
    x01 = c(0, 0, 1) + (c(1, 0, 1) - c(0, 0, 1)) * tx
    x11 = c(0, 1, 1) + (c(1, 1, 1) - c(0, 1, 1)) * tx
    y0_ = x00 + (x10 - x00) * ty
    y1_ = x01 + (x11 - x01) * ty
    return y0_ + (y1_ - y0_) * tz


def _rotation(seed: int) -> np.ndarray:
    """Случайный поворот на октаву: без него у value noise видна решётка (прямые берега)."""
    q, _ = np.linalg.qr(np.random.default_rng(seed).normal(size=(3, 3)))
    return q.astype(np.float32)


def fbm(p: np.ndarray, seed: int, octaves: int, freq: float, gain: float = 0.5) -> np.ndarray:
    total = np.zeros(p.shape[:-1], dtype=np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += amp * (value_noise((p @ _rotation(seed + o)) * freq, seed + o * 101) * 2.0 - 1.0)
        norm += amp
        amp *= gain
        freq *= 2.03
    return total / norm


def ridged(p: np.ndarray, seed: int, octaves: int, freq: float) -> np.ndarray:
    total = np.zeros(p.shape[:-1], dtype=np.float32)
    amp, norm, weight = 1.0, 0.0, np.ones(p.shape[:-1], dtype=np.float32)
    for o in range(octaves):
        n = 1.0 - np.abs(value_noise((p @ _rotation(seed + o)) * freq, seed + o * 57) * 2.0 - 1.0)
        n = n * n * weight
        weight = np.clip(n * 1.6, 0.0, 1.0)
        total += amp * n
        norm += amp
        amp *= 0.5
        freq *= 2.1
    return total / norm


def warp(p: np.ndarray, seed: int, strength: float, freq: float, octaves: int = 4) -> np.ndarray:
    q = np.stack([fbm(p, seed + k * 997, octaves, freq) for k in range(3)], axis=-1)
    return p + strength * q


# ---------------------------------------------------------------- геометрия

def sphere_grid(width: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    height = width // 2
    lon = (np.arange(width, dtype=np.float32) + 0.5) / width * 2.0 * np.pi - np.pi
    lat = np.pi / 2.0 - (np.arange(height, dtype=np.float32) + 0.5) / height * np.pi
    lon_g, lat_g = np.meshgrid(lon, lat)
    p = np.stack([np.cos(lat_g) * np.cos(lon_g), np.cos(lat_g) * np.sin(lon_g), np.sin(lat_g)], axis=-1)
    return p.astype(np.float32), lat_g, lon_g


def unit(lat_deg: float, lon_deg: float) -> np.ndarray:
    la, lo = np.radians(lat_deg), np.radians(lon_deg)
    return np.array([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)], dtype=np.float32)


@dataclass(frozen=True)
class Continent:
    name: str
    lat: float
    lon: float
    radius: float          # угловой радиус ядра, градусы
    stretch: float         # вытянутость по долготе
    spine: float           # сила горного хребта


CONTINENTS = (
    Continent("Велламир", 30.0, -60.0, 44.0, 1.3, 1.0),
    Continent("Шерракс", -14.0, 72.0, 38.0, 1.1, 0.9),
    Continent("Лунниэль", -38.0, -150.0, 32.0, 1.5, 0.7),
)


def continent_fields(p: np.ndarray, seed: int) -> np.ndarray:
    """Влияние каждого континента, (N, H, W)."""
    pw = warp(p, seed + 11, 0.5, 1.4, 5)
    pw /= np.linalg.norm(pw, axis=-1, keepdims=True)
    fields = []
    for c in CONTINENTS:
        centre = unit(c.lat, c.lon)
        # растягиваем по восток-запад: ось вращения — z, касательная восточная
        east = np.cross(np.array([0, 0, 1], dtype=np.float32), centre)
        east /= np.linalg.norm(east)
        north = np.cross(centre, east)
        x = pw @ east
        y = pw @ north
        z = pw @ centre
        ang = np.degrees(np.arctan2(np.sqrt((x / c.stretch) ** 2 + y ** 2), z))
        fields.append(1.0 - ang / c.radius)
    return np.stack(fields)


# ---------------------------------------------------------------- рельеф

def build_height(p: np.ndarray, lat: np.ndarray, seed: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    fields = continent_fields(p, seed)
    base = fields.max(axis=0)
    owner = fields.argmax(axis=0)
    # пролив там, где сходятся два континента: три отдельных материка
    second = np.sort(fields, axis=0)[-2]
    base = base - smooth(-0.35, 0.05, second) * 0.9
    detail = fbm(warp(p, seed + 5, 0.2, 2.5), seed + 3, 8, 1.7)
    coast = fbm(p, seed + 7, 5, 8.0)
    shape = base * 0.8 + 0.6 * detail + 0.12 * coast

    # хребты вдоль континентов: гребни шума, сильнее во внутренней части суши
    spine_mask = np.zeros_like(base)
    for k, c in enumerate(CONTINENTS):
        spine_mask = np.maximum(spine_mask, np.clip(fields[k] + 0.15, 0.0, 1.0) * c.spine)
    belts = ridged(warp(p, seed + 29, 0.3, 1.8), seed + 31, 7, 2.2)
    belt_select = np.clip((fbm(p, seed + 41, 3, 1.4) + 0.45) * 2.5, 0.0, 1.0)
    crest = smooth(0.45, 0.82, belts)
    mountains = (crest ** 1.5 * 0.8 + belts * 0.12) * belt_select * spine_mask

    h = shape * 0.55 + mountains * 0.75
    # подтянуть долю суши к цели
    level = np.quantile(h, 1.0 - LAND_SHARE_TARGET)
    h = h - level
    # «шпили до атмосферы»: самые высокие гребни вытягиваем вверх
    land = h > SEA_LEVEL
    top = np.quantile(h[land], 0.985)
    spikes = np.clip(h - top, 0.0, None)
    h = h + spikes * 5.0
    return h.astype(np.float32), owner, mountains * (h > SEA_LEVEL)


def shade(h: np.ndarray, strength: float = 7.0) -> np.ndarray:
    gx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    gy = np.zeros_like(h)
    gy[1:-1] = h[2:] - h[:-2]
    light = np.array([-0.6, -0.7, 0.4])
    n = np.stack([-gx * strength * h.shape[1] / 2048, -gy * strength * h.shape[1] / 2048, np.ones_like(h)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return np.clip(n @ (light / np.linalg.norm(light)), 0.0, 1.0)


def lerp(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    return a + (b - a) * t[..., None]


def smooth(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def build_color(p: np.ndarray, lat: np.ndarray, h: np.ndarray, mnt: np.ndarray, seed: int) -> np.ndarray:
    hmax = h.max()
    hmin = h.min()
    alat = np.abs(np.degrees(lat))
    moist = fbm(p, seed + 71, 5, 2.4)
    bloom = fbm(warp(p, seed + 81, 0.3, 3.0), seed + 83, 5, 5.0)

    # океан
    depth = np.clip(h / hmin, 0.0, 1.0)
    col = lerp(PAL["lagoon"], PAL["shallow"], smooth(0.0, 0.06, depth))
    col = lerp(col, PAL["sea"], smooth(0.05, 0.25, depth))
    col = lerp(col, PAL["deep"], smooth(0.25, 0.6, depth))
    col = lerp(col, PAL["abyss"], smooth(0.6, 1.0, depth))

    # суша
    e = np.clip(h / np.quantile(h[h > SEA_LEVEL], 0.995), 0.0, 1.4)
    tropic = smooth(34.0, 18.0, alat)
    veg = lerp(PAL["forest"], PAL["forest_dark"], smooth(-0.1, 0.4, moist))
    veg = lerp(veg, PAL["jungle"], tropic)
    veg = lerp(veg, PAL["meadow"], smooth(0.05, -0.35, moist) * 0.8)
    # рисунок крон — только голубые оттенки: розовый у Юрумы в атмосфере, не на земле
    veg = lerp(veg, PAL["canopy"], smooth(0.12, 0.38, bloom) * 0.6)
    veg = lerp(veg, PAL["canopy_light"], smooth(0.32, 0.5, bloom) * tropic * 0.5)
    land = lerp(PAL["shore"], veg, smooth(0.0, 0.012, e))
    m = mnt / max(float(np.quantile(mnt[mnt > 0], 0.995)), 1e-6) if (mnt > 0).any() else mnt
    land = lerp(land, PAL["rock"], smooth(0.12, 0.35, m))
    land = lerp(land, PAL["rock_high"], smooth(0.4, 0.7, m))
    land = lerp(land, PAL["crystal"], np.maximum(smooth(0.75, 1.0, m), smooth(0.9, 1.15, e)))
    land = lerp(land, PAL["ice"], smooth(66.0, 76.0, alat) * 0.9)

    is_land = h > SEA_LEVEL
    col = np.where(is_land[..., None], land, col)
    col = lerp(col, PAL["ice"], smooth(78.0, 84.0, alat) * 0.95)

    # рельеф тенью только на суше, в океане — мягко
    s = shade(np.where(is_land, h + mnt * 0.6, h * 0.15), strength=11.0)
    col = col * (0.62 + 0.55 * s[..., None])
    return np.clip(col, 0.0, 1.0)


def build_clouds(p: np.ndarray, lat: np.ndarray, seed: int) -> np.ndarray:
    """«Скомканные» мановые облака: клочья с завихрениями."""
    q = warp(p, seed + 201, 0.55, 1.8, 5)
    q = warp(q, seed + 211, 0.25, 4.0, 3)
    clumps = 1.0 - np.abs(fbm(q, seed + 221, 6, 3.4))   # «скомканность» — резкие гребни
    large = fbm(p, seed + 231, 3, 1.4)
    fine = fbm(q, seed + 241, 4, 14.0)
    c = smooth(0.7, 0.9, clumps + 0.12 * fine) * smooth(0.0, 0.35, large)
    bands = 0.5 + 0.5 * np.cos(np.radians(np.degrees(lat) * 3.2))
    return np.clip(c * (0.45 + 0.55 * bands), 0.0, 1.0).astype(np.float32)


def build_ley(p: np.ndarray, seed: int) -> np.ndarray:
    """Лей-линии маны: светятся на ночной стороне."""
    r = ridged(warp(p, seed + 301, 0.3, 1.5), seed + 303, 3, 2.2)
    return smooth(0.55, 0.9, r).astype(np.float32)


# ---------------------------------------------------------------- империи

EMPIRES = (
    # континент, имя, цвет, долгота/широта столицы (примерно)
    (0, "Лазурный Престол", "#3d8bff", 22.0, -70.0),
    (0, "Пиковый Доминион Хаддур", "#9a8cff", 38.0, -22.0),
    (1, "Орда Гхарн", "#ff5a6a", 0.0, 52.0),
    (1, "Империум Саэрит", "#ffb347", -24.0, 90.0),
    (2, "Двор Вечного Цветения", "#ff7fd0", -38.0, -150.0),
)


def build_provinces(p: np.ndarray, h: np.ndarray, owner: np.ndarray, seed: int, count: int = 420):
    rng = np.random.default_rng(seed)
    land_idx = np.flatnonzero(h.ravel() > SEA_LEVEL)
    pick = rng.choice(land_idx, size=count, replace=False)
    pts = p.reshape(-1, 3)[pick]
    # Ллойд в одну итерацию по случайной выборке для ровных провинций
    sample = p.reshape(-1, 3)[rng.choice(land_idx, size=min(200_000, land_idx.size), replace=False)]
    for _ in range(3):
        lab = np.argmax(sample @ pts.T, axis=1)
        for k in range(count):
            m = lab == k
            if m.any():
                v = sample[m].mean(axis=0)
                pts[k] = v / np.linalg.norm(v)
    flat = p.reshape(-1, 3)
    prov = np.full(flat.shape[0], -1, dtype=np.int32)
    land_flat = h.ravel() > SEA_LEVEL
    warped = warp(p, seed + 401, 0.04, 9.0, 3).reshape(-1, 3)
    for start in range(0, flat.shape[0], 262_144):
        sl = slice(start, start + 262_144)
        prov[sl] = np.argmax(warped[sl] @ pts.T, axis=1)
    prov[~land_flat] = -1
    prov = prov.reshape(h.shape)

    # провинция → империя: ближайшая столица своего континента
    owner_flat = owner.ravel()
    prov_cont = np.array([np.bincount(owner_flat[prov.ravel() == k], minlength=3).argmax()
                          if (prov.ravel() == k).any() else 0 for k in range(count)])
    caps = np.stack([unit(e[3], e[4]) for e in EMPIRES])
    cap_cont = np.array([e[0] for e in EMPIRES])
    emp = np.empty(count, dtype=np.int32)
    for k in range(count):
        cand = np.flatnonzero(cap_cont == prov_cont[k])
        emp[k] = cand[np.argmax(caps[cand] @ pts[k])]
    return prov, emp, pts


def borders(lbl: np.ndarray) -> np.ndarray:
    b = np.zeros(lbl.shape, dtype=bool)
    b[:, :-1] |= lbl[:, :-1] != lbl[:, 1:]
    b[:-1] |= lbl[:-1] != lbl[1:]
    return b


def political_map(color: np.ndarray, h: np.ndarray, prov: np.ndarray, emp: np.ndarray) -> np.ndarray:
    land = prov >= 0
    emp_map = np.where(land, emp[np.clip(prov, 0, None)], -1)
    tint = np.zeros_like(color)
    for k, e in enumerate(EMPIRES):
        tint[emp_map == k] = rgb(e[2])
    grey = color.mean(axis=-1, keepdims=True)
    out = np.where(land[..., None], grey * 0.55 + tint * 0.6, color * 0.75)
    out[borders(prov) & land] *= 0.72
    eb = borders(emp_map)
    out[eb] = np.array([1.0, 0.95, 1.0])
    return np.clip(out, 0, 1)


def region_colors(count: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed + 9)
    return rng.integers(16, 240, size=(count, 3)).astype(np.uint8)


def region_map(prov: np.ndarray, seed: int) -> np.ndarray:
    cols = region_colors(prov.max() + 1, seed)
    out = np.zeros(prov.shape + (3,), dtype=np.uint8)
    land = prov >= 0
    out[land] = cols[prov[land]]
    return out


# ---------------------------------------------------------------- глобус

def sample(img: np.ndarray, lat: np.ndarray, lon: np.ndarray) -> np.ndarray:
    hgt, wid = img.shape[:2]
    x = ((lon + np.pi) / (2 * np.pi) * wid - 0.5) % wid
    y = np.clip((np.pi / 2 - lat) / np.pi * hgt - 0.5, 0, hgt - 1)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None] if img.ndim == 3 else x - x0
    fy = (y - y0)[..., None] if img.ndim == 3 else y - y0
    x1 = (x0 + 1) % wid
    y1 = np.clip(y0 + 1, 0, hgt - 1)
    a = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    b = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return a * (1 - fy) + b * fy


def rot(yaw_deg: float, tilt_deg: float) -> np.ndarray:
    y, t = np.radians(yaw_deg), np.radians(tilt_deg)
    rz = np.array([[np.cos(y), -np.sin(y), 0], [np.sin(y), np.cos(y), 0], [0, 0, 1]])
    rx = np.array([[1, 0, 0], [0, np.cos(t), -np.sin(t)], [0, np.sin(t), np.cos(t)]])
    return rx @ rz


def stars(size: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    img = np.zeros((size, size, 3), dtype=np.float32)
    yy, xx = np.mgrid[0:size, 0:size]
    neb = fbm(np.stack([xx / size * 3, yy / size * 3, np.full_like(xx, 0.37, dtype=float)], -1).astype(np.float32),
              seed + 5, 5, 1.0)
    img += (smooth(0.0, 0.7, neb)[..., None] * (rgb("#3a1660") * 0.35 + rgb("#0f2a6b") * 0.25))
    n = size * size // 900
    sx, sy = rng.integers(0, size, n), rng.integers(0, size, n)
    b = rng.random(n) ** 3
    tint = np.where(rng.random(n)[:, None] < 0.3, rgb("#ffd0f0"), rgb("#d8e8ff"))
    img[sy, sx] += tint * b[:, None]
    return img


def render_globe(color, clouds, ley, h, size, yaw, tilt, sun, seed, cloud_spin=8.0):
    r_px = size * 0.40
    cy = cx = size / 2
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    u = (xx - cx) / r_px
    v = -(yy - cy) / r_px
    d2 = u * u + v * v
    inside = d2 <= 1.0
    w = np.sqrt(np.clip(1.0 - d2, 0.0, 1.0))
    # вид: камера смотрит вдоль -y_view; нормаль в координатах вида (x вправо, z вверх, y к зрителю)
    n_view = np.stack([u, w, v], -1)
    sun = np.asarray(sun, dtype=np.float32)
    sun /= np.linalg.norm(sun)

    m = rot(yaw, tilt)
    n_planet = n_view @ m            # обратный поворот (m ортогональна)
    lat = np.arcsin(np.clip(n_planet[..., 2], -1, 1))
    lon = np.arctan2(n_planet[..., 1], n_planet[..., 0])

    surf = sample(color, lat, lon)
    hgt = sample(h, lat, lon)
    lam = n_view @ sun
    day = smooth(-0.08, 0.25, lam)
    diffuse = np.clip(lam, 0, 1) ** 0.8

    # блик океана
    view = np.array([0, 1, 0], dtype=np.float32)
    half = (sun + view) / np.linalg.norm(sun + view)
    spec = np.clip(n_view @ half, 0, 1) ** 60 * (hgt <= SEA_LEVEL)
    lit = surf * (0.06 + 1.05 * diffuse[..., None]) + spec[..., None] * rgb("#ffd6f4") * 0.9

    # облака: поворот на cloud_spin градусов и тень со сдвигом к солнцу
    c_lon = lon + np.radians(cloud_spin)
    cl = sample(clouds, lat, c_lon)
    sh_lat = lat - sun[2] * 0.012
    sh = sample(clouds, sh_lat, c_lon - 0.012)
    lit *= (1.0 - 0.45 * sh[..., None] * day[..., None])
    cloud_col = lerp(PAL["cloud_shade"], PAL["cloud"], np.clip(diffuse * 1.3, 0, 1))
    lit = lerp(lit, cloud_col * (0.08 + 1.0 * diffuse[..., None]), cl * 0.8)

    # ночь: лей-линии и огни столиц маной
    night = 1.0 - day
    ly = sample(ley, lat, lon) * (hgt > SEA_LEVEL)
    glow = lerp(PAL["ley_cyan"], PAL["ley"], np.clip(sample(color, lat, lon)[..., 0] * 2.0, 0, 1))
    lit += glow * (ly * night * 0.55)[..., None]

    # атмосфера: лимб к краю и рассеяние на освещённой стороне
    rim = (1.0 - w) ** 3
    # мановая дымка: розовый слой над всей дневной стороной, гуще к краю
    lit_side = smooth(-0.3, 0.6, lam)
    haze = (0.1 + 0.55 * (1.0 - w) ** 1.5) * (0.35 + 0.65 * lit_side)
    lit = lerp(lit, PAL["atmo_haze"] * (0.25 + 0.85 * lit_side[..., None]), haze)
    atmo_col = lerp(PAL["atmo_inner"], PAL["atmo_outer"], rim)
    lit = lit + atmo_col * (rim * (0.3 + 0.9 * lit_side))[..., None]

    img = stars(size, seed + 999)
    img[inside] = lit[inside]

    # свечение за краем диска
    dist = np.sqrt(d2)
    halo_t = np.clip((dist - 1.0) / 0.12, 0.0, 1.0)
    outside = (dist > 1.0) & (dist < 1.12)
    edge_dir = np.stack([u, np.zeros_like(u), v], -1) / np.maximum(dist, 1e-6)[..., None]
    edge_lam = smooth(-0.5, 0.7, edge_dir @ sun)
    halo = (1.0 - halo_t) ** 1.8 * (0.25 + 0.95 * edge_lam)
    halo_col = lerp(PAL["atmo_inner"], PAL["atmo_outer"], halo_t)
    img[outside] += (halo_col * halo[..., None])[outside]

    # мягкий край диска (сглаживание)
    edge = np.clip((1.0 - dist) * r_px, 0.0, 1.0)
    bg = stars(size, seed + 999)
    img = np.where(inside[..., None], img * edge[..., None] + bg * (1 - edge[..., None]), img)
    img = img / (1.0 + img * 0.18)   # мягкий тонмаппинг
    return np.clip(img, 0, 1)


# ---------------------------------------------------------------- вывод

def to_img(a: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8))


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def label_map(img: Image.Image, h: np.ndarray, owner: np.ndarray, empires: bool) -> Image.Image:
    d = ImageDraw.Draw(img)
    wid, hgt = img.size
    f = font(max(12, wid // 70))

    def put(lat: float, lon: float, text: str, fill: str) -> None:
        x = (lon + 180) / 360 * wid
        y = (90 - lat) / 180 * hgt
        d.text((x, y), text, font=f, fill=fill, anchor="mm", stroke_width=3, stroke_fill="#0a0820")

    if empires:
        for e in EMPIRES:
            put(e[3], e[4], e[1], e[2])
    else:
        for c in CONTINENTS:
            put(c.lat, c.lon, c.name, "#fff4fd")
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=2048)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--globe", type=int, default=1200)
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    p, lat, lon = sphere_grid(args.width)
    print("рельеф…")
    h, owner, mnt = build_height(p, lat, args.seed)
    print("цвета…")
    color = build_color(p, lat, h, mnt, args.seed)
    print("облака…")
    clouds = build_clouds(p, lat, args.seed)
    ley = build_ley(p, args.seed)
    print("провинции…")
    prov, emp, _ = build_provinces(p, h, owner, args.seed)

    hmin, hmax = float(h.min()), float(h.max())
    h16 = np.where(h > 0, 32767 + h / hmax * 32768, 32767 * (1 - h / hmin)).clip(0, 65535).astype(np.uint16)
    Image.fromarray(h16).save(OUT / "yuruma_height.png")
    to_img(color).save(OUT / "yuruma_color.png")
    Image.fromarray((clouds * 255).astype(np.uint8)).save(OUT / "yuruma_clouds.png")
    Image.fromarray(region_map(prov, args.seed)).save(OUT / "yuruma_regions.png")
    # таблица провинций для сценария (pax_rpg/dev/yuruma_scenario.py): цвет на yuruma_regions.png → империя
    cols = region_colors(prov.max() + 1, args.seed)
    table = [{"color": "#%02x%02x%02x" % tuple(int(c) for c in cols[k]), "empire": EMPIRES[emp[k]][1]}
             for k in range(prov.max() + 1)]
    (OUT / "yuruma_provinces.json").write_text(json.dumps(table, ensure_ascii=False, indent=0), encoding="utf-8")

    pol = label_map(to_img(political_map(color, h, prov, emp)), h, owner, True)
    pol.save(OUT / "yuruma_empires.png")
    labelled = color.copy()
    labelled = lerp(labelled, PAL["cloud"], clouds * 0.7)
    MOD_TEXTURES.mkdir(parents=True, exist_ok=True)
    to_img(labelled).save(MOD_TEXTURES / "yuruma_surface.png")
    map_view = label_map(to_img(labelled), h, owner, False)
    map_view.save(OUT / "yuruma_map.png")

    print("глобусы…")
    sun = (0.75, 0.55, 0.38)
    views = {
        "vellamir": (-48.0, -22.0),
        "sherraks": (70.0, 10.0),
        "lunniel": (-150.0, 30.0),
    }
    globes = {}
    for name, (lon_c, tilt) in views.items():
        # yaw ставит нужную долготу к зрителю (ось y вида)
        g = render_globe(color, clouds, ley, h, args.globe, yaw=90.0 - lon_c, tilt=tilt, sun=sun, seed=args.seed)
        globes[name] = to_img(g)
        globes[name].save(OUT / f"yuruma_globe_{name}.png")

    land = h > 0
    stats = {
        "land_share": round(float(land.mean()), 3),
        "provinces": int(prov.max() + 1),
        "empires": {e[1]: int(np.sum(emp == k)) for k, e in enumerate(EMPIRES)},
        "continents_land_share": {c.name: round(float((land & (owner == k)).sum() / land.sum()), 3)
                                  for k, c in enumerate(CONTINENTS)},
        "seed": args.seed,
    }
    (OUT / "yuruma_stats.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")

    # сводный лист
    gw = args.globe // 2
    sheet_w = gw * 3
    map_h = sheet_w // 2
    sheet = Image.new("RGB", (sheet_w, gw + map_h * 2 + 80), "#06051a")
    for i, name in enumerate(views):
        sheet.paste(globes[name].resize((gw, gw), Image.LANCZOS), (i * gw, 60))
    sheet.paste(map_view.resize((sheet_w, map_h), Image.LANCZOS), (0, gw + 70))
    sheet.paste(pol.resize((sheet_w, map_h), Image.LANCZOS), (0, gw + 70 + map_h + 10))
    d = ImageDraw.Draw(sheet)
    d.text((20, 14), "ЮРУМА — референс планеты (черновик, Pax RPG)", font=font(30), fill="#ffd9f3")
    sheet.save(OUT / "yuruma_sheet.png")
    print(json.dumps(stats, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
