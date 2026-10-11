"""Генератор части дерева Obsidian «Pax RPG» (obsidian/Pax RPG/): заметки кода (по одной на .gd мода — как
code_map.py для модов Pax CorpInc) и империй (из сценария pax_rpg/scenario/yuruma.json). Ручные заметки
(город, пайплайн, механики) не трогает.

    python pax_rpg/dev/obsidian_vault.py            → обновить obsidian/Pax RPG/Код и Лор/Империи
На ПК дерево раскладывается в хранилище: pax_rpg/dev/obsidian_sync.ps1.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VAULT = os.path.join(ROOT, "obsidian", "Pax RPG")
MOD = os.path.join(ROOT, "mods", "pax_rpg")


def code_notes():
    out = os.path.join(VAULT, "Код")
    os.makedirs(out, exist_ok=True)
    files = []
    for d, _, fs in os.walk(MOD):
        for f in fs:
            if f.endswith(".gd"):
                files.append(os.path.join(d, f))
    names = {os.path.relpath(p, MOD).replace(os.sep, "/"): os.path.splitext(os.path.basename(p))[0] for p in files}
    used_by = {k: [] for k in names}
    info = {}
    for p in sorted(files):
        rel = os.path.relpath(p, MOD).replace(os.sep, "/")
        lines = open(p, encoding="utf-8").read().split("\n")
        ext = next((l.split()[1] for l in lines if l.startswith("extends ")), "?")
        doc = " ".join(l[2:].strip() for l in lines[:40] if l.startswith("##"))
        deps = re.findall(r'preload\("res://mods/pax_rpg/([^"]+\.gd)"\)', "\n".join(lines))
        funcs = []
        for i, l in enumerate(lines):
            m = re.match(r"(static )?func (\w+)\((.*)", l)
            if m:
                d = []
                j = i - 1
                while j >= 0 and lines[j].startswith("##"):
                    d.insert(0, lines[j][2:].strip())
                    j -= 1
                sig = l.rstrip(":").strip()
                funcs.append((sig, " ".join(d)))
        for dp in deps:
            if dp in used_by:
                used_by[dp].append(rel)
        info[rel] = (ext, doc, deps, funcs, len(lines))
    for rel, (ext, doc, deps, funcs, n) in info.items():
        name = names[rel]
        folder = rel.split("/")[1] if rel.startswith("src/") else "основа"
        t = [f"---\nmod: pax_rpg\nfile: {rel}\nlines: {n}\nweight: {len(used_by[rel])}\ntags: [мод/rpg, функция/{folder}]\n---\n",
             f"# {name}\n", f"`{rel}` · [[Код Pax RPG]] · `extends {ext}` · {n} строк · подключают: **{len(used_by[rel])}**\n"]
        if doc:
            t.append("> " + doc + "\n")
        if deps:
            t.append("## Подключает\n" + "\n".join(f"- [[{names.get(d, d)}]]" for d in deps) + "\n")
        if used_by[rel]:
            t.append("## Кто подключает\n" + "\n".join(f"- [[{names[u]}]]" for u in used_by[rel]) + "\n")
        t.append("## Функции\n" + "\n".join(f"- `{s}`" + (f" — {d}" if d else "") for s, d in funcs) + "\n")
        open(os.path.join(out, name + ".md"), "w", encoding="utf-8").write("\n".join(t))
    idx = ["---\ntags: [мод/rpg, карта-кода]\n---\n", "# Код Pax RPG\n",
           "Собрано `pax_rpg/dev/obsidian_vault.py` из `mods/pax_rpg`. Механики словами — [[Механики]].\n",
           "| Файл | Строк | Что |", "|---|---|---|"]
    for rel, (ext, doc, deps, funcs, n) in sorted(info.items(), key=lambda x: -x[1][4]):
        short = (doc[:110] + "…") if len(doc) > 110 else doc
        idx.append(f"| [[{names[rel]}]] | {n} | {short} |")
    open(os.path.join(out, "Код Pax RPG.md"), "w", encoding="utf-8").write("\n".join(idx) + "\n")
    return len(info)


def empire_notes():
    out = os.path.join(VAULT, "Лор", "Империи")
    os.makedirs(out, exist_ok=True)
    sc = json.load(open(os.path.join(ROOT, "pax_rpg", "scenario", "yuruma.json"), encoding="utf-8"))
    lang = json.load(open(os.path.join(MOD, "data", "lang", "ru.json"), encoding="utf-8"))
    n = 0
    for e in sc.get("страны", sc.get("фракции", [])):
        if "лор" not in e:
            continue
        name = e["имя"]
        t = [f"---\ntags: [лор, империя]\nлюдей: {e.get('людей', '')}\n---\n", f"# {name}\n",
             f"Столица: [[{lang.get('pax_rpg_city_' + e.get('столица_город', ''), e.get('столица_город', ''))}]] · [[Юрума]] · народы и облик — [[Юрума#Континенты и империи]]\n",
             "## Лор\n" + "\n".join((l if l else "") for l in e.get("лор", [])) + "\n",
             f"## Сейчас\n- Чем заняты: {e.get('чем_заняты', '')}\n- Цель: {e.get('цель', '')}\n"
             f"- Почему ты у власти: {e.get('почему', '')}\n"]
        um = e.get("ум", {})
        if um:
            t.append("## Нрав державы\n" + "\n".join(f"- {k.replace('_', ' ')}: {v}" for k, v in um.items()) + "\n")
        t.append("## Вожди\n")
        for l in e.get("лидеры", []):
            t.append(f"- **{l['имя']}** — {l.get('откуда', '')}. {l.get('характер', '')}. «{l.get('первое_слово', '')}»")
        if name == "Орда Гхарн":
            t.append("\nСтолица подробно: [[Гхарн]] (город, планировка, места, модели).")
        open(os.path.join(out, name + ".md"), "w", encoding="utf-8").write("\n".join(t) + "\n")
        n += 1
    return n


if __name__ == "__main__":
    print("код:", code_notes(), "заметок; империи:", empire_notes())
