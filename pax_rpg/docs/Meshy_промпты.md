# Meshy AI — промпты персонажа игрока

Базовые тела игрока, мужское и женское. На них потом надевается экипировка, поэтому одежда — только
облегающая нижняя: без брони, плащей, оружия и украшений, иначе это всё срастётся с телом в один меш.

> **Стиль Юрумы — азиатский.** В каждый промпт добавлять: `East Asian fantasy style` и деталь одежды
> (`hanfu-inspired`, `hakama trousers`, `sash belt`). Первый герой (Meshy, 9 окт.) уже в этом стиле: белые
> волосы, рога, широкие штаны с поясом-лентой — но сгенерирован с мечом в руке и на подставке; для базового
> тела снова писать `no weapons, no base, no pedestal`.

## Настройки генерации

- Text to 3D, промпт на английском (так Meshy понимает лучше).
- **Pose: A-pose** (если есть выбор позы), **Symmetry: on**.
- **Topology: quad**, полигонов около **30 000** — игроку хватит, потом LOD в Blender.
- Текстуры **PBR**, 2K (4K только для крупных планов).
- Сначала сделать мужскую модель. Если стиль понравится, женскую генерировать тем же стилем и с тем же
  seed — так оба тела будут из одной «серии».

## Мужчина

```
Full-body fantasy RPG player character base mesh, young adult human male, athletic average build,
standing in a strict A-pose, arms 45 degrees away from the body, legs slightly apart, facing forward,
perfectly symmetrical. Neutral calm face, short dark hair. Wearing only a simple fitted sleeveless
linen undershirt, fitted cloth trousers and soft low leather boots. No armor, no cape, no belt pouches,
no weapons, no jewelry. Open relaxed hands with separated fingers. Clean silhouette, game-ready
character, stylized realism, muted blue and teal fabric.
```

## Женщина

```
Full-body fantasy RPG player character base mesh, young adult human female, athletic slim build,
standing in a strict A-pose, arms 45 degrees away from the body, legs slightly apart, facing forward,
perfectly symmetrical. Neutral calm face, long hair tied in a low ponytail behind the back. Wearing only
a simple fitted sleeveless linen top, fitted cloth trousers and soft low leather boots. No armor,
no cape, no belt pouches, no weapons, no jewelry. Open relaxed hands with separated fingers. Clean
silhouette, game-ready character, stylized realism, muted blue and teal fabric.
```

## Если что-то пошло не так

| Проблема | Что дописать / поменять |
|---|---|
| Руки прилипли к телу, пальцы слиплись | усилить: `arms clearly separated from the torso, fingers spread apart` |
| Волосы срослись с плечами | короче стрижка или `hair tucked, not touching shoulders` |
| Модель «мультяшная» | `stylized realism` → `realistic proportions, realistic style` |
| Слишком детально, лишние ремешки | убрать `linen`, дописать `plain, minimal clothing details` |
| Негативный промпт (если есть поле) | `armor, weapon, cape, cloak, bag, jewelry, T-pose, sitting, multiple characters, base, pedestal` |

Сначала сравнить мужскую и женскую модели в одной сцене Blender, потом делать риг. Рост около
1,8 м и 1,7 м, ступни на нуле.

## Воин Юрумы (азиатское фэнтези) — тело без оружия

```
Full-body East Asian fantasy warrior, young adult male, athletic lean build, game character base mesh,
standing in a strict A-pose, arms 45 degrees away from the body, open relaxed hands with fingers apart,
legs slightly apart, facing forward, perfectly symmetrical. Human, no horns. Long white hair tied in a high
topknot bun close to the head, calm face. Bare toned chest, wide flowing white hakama trousers with blue ornamental patterns, long blue
sash belt, dark wrist bracers, simple cloth shoes. Hands are empty. No weapons, no sword, no scabbard,
no shield, no cape, no pedestal, no base, no horns, standing directly on the ground. Stylized realism, game-ready.
```

## Его катана — отдельная генерация

```
Single East Asian fantasy katana, straight horizontal view, isolated object, no hands, no stand.
Long slightly curved blade with glowing cyan mana runes, round dark iron tsuba guard, long grip wrapped
in dark navy cord, round ring pommel with a cyan gem. Stylized realism, game-ready, clean silhouette.
```
