"""Быстрые проверки мода без Godot: JSON, песочница CodeGuard, переводы, файлы из конфигов.

    python static_checks.py <корень репозитория>

Код выхода 1 — есть ошибки. Каждая строка ошибки — «файл:строка: что не так».
Правила CodeGuard — из docs/modding/en/04-code.md игры («What mod code may not do»).
"""
import json
import os
import re
import sys

CODEGUARD = [  # (шаблон, почему нельзя / чем заменить)
    (r"\bOS\.(execute|create_process|shell_open|shell_show_in_file_manager|kill)\b", "запуск программ — нельзя"),
    (r"\bshell_open\s*\(", "shell_open — нельзя, ссылки: open_link()"),
    (r"\bOS\.(get_environment|set_environment|has_environment|unset_environment|get_system_dir|get_user_data_dir|"
     r"get_cmdline_args|get_cmdline_user_args)\b", "окружение, системные папки и командная строка — нельзя"),
    (r"\b(FileAccess|DirAccess|ConfigFile)\b", "файлы — только read_text()/list_files()/save_data()"),
    (r"[\"']user://", "user:// — нельзя, только save_data()/load_data()"),
    (r"[\"'][A-Za-z]:[/\\]", "абсолютные пути — нельзя"),
    (r"[\"'][^\"']*\.\./", "«..» в путях — нельзя"),
    (r"(?<![\w.])load\s*\(\s*[^\"'\s)]", "load(переменная) — нельзя: load_resource() или preload(\"res://mods/…\")"),
    (r"\bResourceLoader\b", "ResourceLoader — нельзя: load_resource() / Pax.resource()"),
    (r"\b(Expression|ClassDB|GDScript|str_to_var)\b", "Expression/ClassDB/GDScript/str_to_var — нельзя"),
    (r"\bset_script\s*\(", "set_script — нельзя"),
    (r"\.callv?\s*\(\s*[\"'&]", "вызов метода по строке — нельзя"),
    (r"[\"']res://scripts/", "скрипты игры напрямую — нельзя, только API Pax"),
    (r"\bchange_scene", "смена сцены — нельзя"),
    (r"get_tree\(\)\s*\.\s*quit\b", "выход из игры — нельзя"),
]
PATH_RE = re.compile(r"^(models|sounds|textures|shaders|config|data|presets|fonts)/[^\s\"']+\.\w+$")


def strip_comment(line):
    out, q = [], None
    for i, ch in enumerate(line):
        if q:
            out.append(ch)
            if ch == q and line[i - 1] != "\\":
                q = None
        elif ch in "\"'":
            q = ch
            out.append(ch)
        elif ch == "#":
            break
        else:
            out.append(ch)
    return "".join(out)


def main(root):
    mod = os.path.join(root, "mods", "pax_rpg")
    errors = []
    gd_files, json_files = [], []
    for d, _, files in os.walk(mod):
        for f in files:
            p = os.path.join(d, f)
            if f.endswith(".gd"):
                gd_files.append(p)
            elif f.endswith(".json"):
                json_files.append(p)
    rel = lambda p: os.path.relpath(p, root)
    # 1. JSON
    parsed = {}
    for p in sorted(json_files):
        try:
            parsed[p] = json.load(open(p, encoding="utf-8-sig"))
        except Exception as e:
            errors.append(f"{rel(p)}:{getattr(e, 'lineno', 0)}: JSON не читается: {e}")
    # 2. CodeGuard
    for p in sorted(gd_files):
        for n, line in enumerate(open(p, encoding="utf-8"), 1):
            code = strip_comment(line)
            for pat, why in CODEGUARD:
                if re.search(pat, code):
                    errors.append(f"{rel(p)}:{n}: CodeGuard: {why}: {line.strip()}")
    # 3. переводы: одинаковые ключи во всех языках
    lang_dir = os.path.join(mod, "data", "lang")
    langs = {f[:-5]: parsed.get(os.path.join(lang_dir, f), {}) for f in os.listdir(lang_dir) if f.endswith(".json")}
    all_keys = set().union(*[set(v) for v in langs.values()]) if langs else set()
    for code, d in sorted(langs.items()):
        for k in sorted(all_keys - set(d)):
            errors.append(f"{rel(os.path.join(lang_dir, code + '.json'))}:0: нет ключа «{k}» (есть в другом языке)")
    if "en" not in langs:
        errors.append(f"{rel(lang_dir)}:0: нет en.json — игра берёт английский, когда нет языка игрока")
    # 4. ключи tr_key("…") из кода есть в переводах
    for p in sorted(gd_files):
        for n, line in enumerate(open(p, encoding="utf-8"), 1):
            for k in re.findall(r"tr_key\(\s*\"([^\"]+)\"\s*[,)]", strip_comment(line)):
                for code, d in sorted(langs.items()):
                    if k not in d:
                        errors.append(f"{rel(p)}:{n}: ключа «{k}» нет в data/lang/{code}.json")
    # 5. файлы, на которые ссылаются код и конфиги, существуют
    def check_path(s, where):
        if "%" not in s and PATH_RE.match(s) and not os.path.exists(os.path.join(mod, s)):
            errors.append(f"{where}: нет файла мода «{s}»")

    def walk(v, where):
        if isinstance(v, dict):
            for x in v.values():
                walk(x, where)
        elif isinstance(v, list):
            for x in v:
                walk(x, where)
        elif isinstance(v, str):
            check_path(v, where)
    for p, v in parsed.items():
        if os.sep + "config" + os.sep in p:
            walk(v, rel(p) + ":0")
    for p in sorted(gd_files):
        for n, line in enumerate(open(p, encoding="utf-8"), 1):
            for s in re.findall(r"\b(?:model|texture|sound|shader|read_text|read_bytes|load_resource)\(\s*\"([^\"]+)\"",
                                strip_comment(line)):
                check_path(s, f"{rel(p)}:{n}")
    for e in errors:
        print(e)
    print(f"static: {len(gd_files)} .gd, {len(json_files)} .json, ошибок: {len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
