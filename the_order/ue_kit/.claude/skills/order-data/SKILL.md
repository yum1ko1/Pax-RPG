---
name: order-data
description: Форматы данных CommandGame — traits.json, officers.json, orders.json, mission_01.json (схемы, правила валидации, загрузка в C++). Используй при правке данных, парсера приказов, TraitDatabase, MissionManager.
---

# Данные проекта (`Content/Data/`)

Источник схем — ДИЗДОК §III.5 и §I.7/§I.11. JSON читается в `USTRUCT` через `FJsonObjectConverter`; любая ошибка — `UE_LOG` с файлом и полем.
Загрузчик валидирует ссылки: ключ офицера существует в traits, у офицера 3 ключа из разных категорий, у рядового 2.

## traits.json
```json
{"traits":[{"id":"brave","name":"Храбрый","category":"morale","prompt_block":"…","icon":"icon_brave","color":"#c0392b"}]}
```
Категории и ключи (§I.11): `morale` — brave / coward / steadfast / panicky; `combat_style` — cautious / aggressive / tactician;
`authority` (только офицеры) — loyal / cynical / rebel. id — латиница, `name` — русский.

## officers.json
```json
{"officers":[{"id":"off_01","name":"Капитан Волков","portrait":"p_01","traits":["brave","aggressive","loyal"],"rank":"капитан","unit":"1-й батальон"}]}
```

## orders.json — словарь приказов (в ТЗ формат не задан, это предложение; согласовать с автором)
```json
{
  "verbs":[
    {"id":"occupy","forms":["занять","займи","занимай"],"category":"movement","target":"point"},
    {"id":"attack","forms":["атаковать","атакуй"],"category":"attack","target":"point_or_unit"}
  ],
  "points":[{"id":"house_14","names":["дом 14","дом14"],"location_actor":"BP_Point_House14"}]
}
```
Категории глаголов (§I.7): движение (занять, обойти, отступить, выдвинуться), атака (атаковать, подавить, уничтожить, зачистить),
оборона (оборонять, занять позицию, держать), взаимодействие (поддержать, прикрыть, отвлечь), спец (разрушить, заминировать, эвакуировать).
Парсер: `[кому] [что] [где]`, регистр и ё/е не важны, автодополнение по префиксу из officers.names, verbs.forms, points.names.

## mission_01.json
```json
{"id":"mission_01","objectives":[
  {"id":"obj_whitehouse","type":"destroy","target":"white_house","description":"Разрушить Белый дом"},
  {"id":"obj_president","type":"capture","target":"president","description":"Захватить президента"},
  {"id":"obj_civilians","type":"preserve","threshold":0.8,"description":"Сохранить > 80% гражданских"}],
 "budget":10000,"reinforcements":false}
```
Типы задач: `destroy` (цель — тег актора), `capture` (тег юнита), `preserve` (доля живых гражданских ≥ threshold).
Доп. задачи (TaskGenerator) — тот же формат + `"appear_after_sec"`.
