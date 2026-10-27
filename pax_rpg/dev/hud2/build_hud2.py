"""HUD v2 (рамки в стиле инвентаря): вырезанные по хромакею рамки GPT (gpt-refs: gpt/hud2_*, key_hud.py) →
textures/hud2/*.png и config/hud2.json — окна рамок (прозрачные каналы под полосы, портреты, иконки) в долях.

    python build_hud2.py <папка с keyed/hud2_*.png> <mods/pax_rpg>
"""
import json, sys
from collections import deque
import numpy as np
from PIL import Image

# имя ассета → (файл, ширина в игре px; хранится с запасом ×1.5 под 1440p)
FRAMES = {
    'hero': ('hud2_hero_0.png', 590), 'skills': ('hud2_skillbar_0.png', 760), 'quest': ('hud2_quest_0.png', 430),
    'minimap': ('hud2_minimap_0.png', 250), 'enemy': ('hud2_enemy_0.png', 84), 'boss': ('hud2_boss_frame.png', 940),
    'boss_name': ('hud2_boss_name_0.png', 380), 'compass': ('hud2_compass_1.png', 900),
}
STORE = 1.5


def holes(a):
    """прозрачные окна, не касающиеся края: [x0, y0, x1, y1] px"""
    a = a < 128
    h, w = a.shape
    lab = np.zeros((h, w), np.int32)
    n, out = 0, []
    for sy in range(0, h, 3):
        for sx in range(0, w, 3):
            if a[sy, sx] and lab[sy, sx] == 0:
                n += 1
                q = deque([(sy, sx)])
                lab[sy, sx] = n
                edge, ys, xs = False, [], []
                while q:
                    y, x = q.popleft()
                    ys.append(y)
                    xs.append(x)
                    if y in (0, h - 1) or x in (0, w - 1):
                        edge = True
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy, xx = y + dy, x + dx
                        if 0 <= yy < h and 0 <= xx < w and a[yy, xx] and lab[yy, xx] == 0:
                            lab[yy, xx] = n
                            q.append((yy, xx))
                if not edge and len(ys) > 400:
                    out.append([min(xs), min(ys), max(xs) + 1, max(ys) + 1])
    return out


def main(src, mod):
    cfg = {'_note': 'Сгенерировано pax_rpg/dev/hud2/build_hud2.py. size — ширина рамки в макете 1920×1080, aspect — h/w; '
                    'holes — окна рамки [x0, y0, x1, y1] в долях её ширины и высоты (порядок — как в build_hud2.py).',
           'frames': {}}
    for key, (fn, w) in FRAMES.items():
        im = Image.open(f'{src}/{fn}').convert('RGBA')
        hs = holes(np.asarray(im)[:, :, 3])
        W, H = im.size
        cfg['frames'][key] = {'tex': f'textures/hud2/{key}.png', 'size': w, 'aspect': round(H / W, 5),
                              'holes': [[round(x0 / W, 5), round(y0 / H, 5), round(x1 / W, 5), round(y1 / H, 5)] for x0, y0, x1, y1 in hs]}
        sw = int(w * STORE)
        im.resize((sw, round(sw * H / W)), Image.LANCZOS).save(f'{mod}/textures/hud2/{key}.png', optimize=True)
        print(key, im.size, '→', sw, len(hs), 'окон')
    json.dump(cfg, open(f'{mod}/config/hud2.json', 'w', encoding='utf-8'), ensure_ascii=False, indent='\t')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
