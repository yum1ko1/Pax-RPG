"""Подключает MCP-мост к картинкам OpenAI (pax_rpg\\dev\\openai\\openai_image_mcp.py) на этом ПК.

    python pax_rpg\\dev\\install_openai_mcp.py            → подписка ChatGPT (через Codex CLI), ключ не нужен
    python pax_rpg\\dev\\install_openai_mcp.py --api-key  → по ключу OpenAI API (оплата отдельно)

Подписка: ставит Codex CLI (если нет — через npm), запускает `codex login` (вход через ChatGPT в браузере) и пишет
сервер «pax-images» в %APPDATA%\\Claude\\claude_desktop_config.json (старый файл — рядом как .bak).
Ключ API: спрашивается здесь (ввод не виден), пишется в переменную пользователя OPENAI_API_KEY.
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


def codex() -> str:
    exe = shutil.which("codex")
    if exe:
        return exe
    npm = shutil.which("npm")
    if not npm:
        sys.exit("Нет ни codex, ни npm. Поставьте Node.js (https://nodejs.org), затем снова этот скрипт.")
    print("Ставлю Codex CLI: npm i -g @openai/codex …")
    subprocess.run([npm, "i", "-g", "@openai/codex"], check=True)
    exe = shutil.which("codex")
    if not exe:
        sys.exit("Codex поставлен, но не виден в PATH — откройте новый терминал и запустите скрипт снова.")
    return exe


def login_status(exe: str) -> str:
    r = subprocess.run([exe, "login", "status"], capture_output=True, text=True, stdin=subprocess.DEVNULL)
    return (r.stdout + r.stderr).strip()


def subscription():
    exe = codex()
    print("Codex:", subprocess.run([exe, "--version"], capture_output=True, text=True).stdout.strip())
    st = login_status(exe)
    if "ChatGPT" not in st:
        print("Вход в Codex через ChatGPT — откроется браузер, войдите своим аккаунтом с подпиской.")
        subprocess.run([exe, "login"])
        st = login_status(exe)
    print("Вход:", st)
    if "ChatGPT" not in st:
        sys.exit("Codex не вошёл через ChatGPT — повторите `codex login`.")
    feats = subprocess.run([exe, "features", "list"], capture_output=True, text=True).stdout
    line = next((ln for ln in feats.splitlines() if ln.startswith("image_generation")), "image_generation: не найдено")
    print("Генерация картинок в Codex:", " ".join(line.split()))


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


def api_key():
    key = getpass.getpass("Ключ OpenAI (sk-…, ввод не виден): ").strip()
    if not key.startswith("sk-"):
        sys.exit("Ключ OpenAI начинается с sk- — ничего не записано.")
    print("Проверка ключа:", check_key(key))
    subprocess.run(["setx", "OPENAI_API_KEY", key], capture_output=True)
    print("Переменная OPENAI_API_KEY: записана (видна новым программам)")


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
    # ключа в конфиге нет: мост берёт его из переменной пользователя, а без ключа идёт через Codex
    cfg.setdefault("mcpServers", {})["pax-images"] = {"command": sys.executable, "args": [SERVER]}
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return path


def main():
    api_key() if "--api-key" in sys.argv else subscription()
    print("Claude Desktop:", desktop())
    print("\nГотово. Claude Desktop — закрыть полностью (и в трее) и открыть снова; Claude Code — перезапустить в "
          "папке Pax-RPG и разрешить сервер pax-images (/mcp — проверить).")


if __name__ == "__main__":
    main()
