"""Подключает MCP-мост к OpenAI Images (pax_rpg\\dev\\openai\\openai_image_mcp.py) на этом ПК.

    python pax_rpg\\dev\\install_openai_mcp.py

Ключ OpenAI спрашивается здесь, в терминале (ввод не виден), и пишется только в локальные настройки:
  - переменная пользователя OPENAI_API_KEY — её читает мост (и Claude Code в репозитории через .mcp.json);
  - %APPDATA%\\Claude\\claude_desktop_config.json — сервер «pax-images» (старый файл сохраняется рядом как .bak).
Claude Code отдельно настраивать не нужно: в корне репозитория лежит .mcp.json, при первом запуске в папке
Pax-RPG он спросит, включить ли сервер pax-images.
"""
import getpass
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

SERVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "openai", "openai_image_mcp.py")


def check_key(key: str) -> str:
    req = urllib.request.Request("https://api.openai.com/v1/models", headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            ids = [m["id"] for m in json.loads(r.read().decode("utf-8")).get("data", [])]
            img = sorted(i for i in ids if i.startswith("gpt-image"))
            return "ключ принят; модели картинок: " + (", ".join(img) or "не видны (проверьте доступ проекта)")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return "ОШИБКА 401: OpenAI не принял ключ (неверный или отозван)"
        return f"ответ OpenAI: HTTP {e.code} (ключ записан, проверьте в клиенте)"
    except Exception as e:  # сеть
        return f"проверить не удалось ({e}); ключ записан"


def desktop() -> str:
    path = os.path.join(os.environ["APPDATA"], "Claude", "claude_desktop_config.json")
    cfg = {}
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak")
        with open(path, encoding="utf-8") as f:
            text = f.read().strip()
        cfg = json.loads(text) if text else {}
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    # ключ мост берёт из переменной пользователя (реестр), в конфиг он не пишется
    cfg.setdefault("mcpServers", {})["pax-images"] = {"command": sys.executable, "args": [SERVER]}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return path


def main():
    key = getpass.getpass("Ключ OpenAI (sk-…, ввод не виден): ").strip()
    if not key.startswith("sk-"):
        sys.exit("Ключ OpenAI начинается с sk- — ничего не записано.")
    print("Проверка ключа:", check_key(key))
    subprocess.run(["setx", "OPENAI_API_KEY", key], capture_output=True)
    print("Переменная OPENAI_API_KEY: записана (видна новым программам)")
    print("Claude Desktop:", desktop())
    print("\nГотово. Claude Desktop — закрыть полностью (и в трее) и открыть снова; Claude Code — перезапустить в "
          "папке Pax-RPG и разрешить сервер pax-images (/mcp — проверить).")


if __name__ == "__main__":
    main()
