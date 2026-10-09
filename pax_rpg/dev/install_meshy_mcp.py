"""Подключает Meshy MCP (https://github.com/meshy-dev/meshy-mcp-server) к Claude Desktop и Claude Code на этом ПК.

    python pax_corporations_dev\\install_meshy_mcp.py

Ключ Meshy спрашивается здесь, в терминале (ввод не виден), и пишется только в локальные настройки:
  - %APPDATA%\\Claude\\claude_desktop_config.json — сервер «meshy» (старый файл сохраняется рядом как .bak);
  - Claude Code — `claude mcp add-json meshy … --scope user`;
  - переменная пользователя MESHY_API_KEY — чтобы скрипты на этом ПК тоже могли звать Meshy.
"""
import getpass
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

SERVER = {"command": "cmd", "args": ["/c", "npx", "-y", "@meshy-ai/meshy-mcp-server"]}


def check_key(key: str) -> str:
    req = urllib.request.Request("https://api.meshy.ai/openapi/v1/balance", headers={"Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return "ключ принят, баланс: " + r.read().decode("utf-8", "replace")[:120]
    except urllib.error.HTTPError as e:
        if e.code == 401:
            return "ОШИБКА 401: Meshy не принял ключ (неверный или отозван)"
        return f"ответ Meshy: HTTP {e.code} (ключ записан, проверьте в клиенте)"
    except Exception as e:  # сеть
        return f"проверить не удалось ({e}); ключ записан"


def desktop(key: str) -> str:
    path = os.path.join(os.environ["APPDATA"], "Claude", "claude_desktop_config.json")
    cfg = {}
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak")
        with open(path, encoding="utf-8") as f:
            text = f.read().strip()
        cfg = json.loads(text) if text else {}
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    cfg.setdefault("mcpServers", {})["meshy"] = dict(SERVER, env={"MESHY_API_KEY": key})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return path


def claude_code(key: str) -> str:
    exe = shutil.which("claude.cmd") or shutil.which("claude")
    if not exe:
        return "Claude Code (claude) не найден — пропущено"
    subprocess.run([exe, "mcp", "remove", "meshy", "--scope", "user"], capture_output=True, text=True)
    spec = json.dumps(dict(SERVER, env={"MESHY_API_KEY": key}))
    r = subprocess.run([exe, "mcp", "add-json", "meshy", spec, "--scope", "user"], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip().replace(key, "msy_***")
    return ("добавлен" if r.returncode == 0 else f"ошибка (код {r.returncode})") + (": " + out if out else "")


def main():
    key = getpass.getpass("Ключ Meshy (msy_…, ввод не виден): ").strip()
    if not key.startswith("msy_"):
        sys.exit("Ключ Meshy начинается с msy_ — ничего не записано.")
    print("Проверка ключа:", check_key(key))
    print("Claude Desktop:", desktop(key))
    print("Claude Code:", claude_code(key))
    subprocess.run(["setx", "MESHY_API_KEY", key], capture_output=True)
    print("Переменная MESHY_API_KEY: записана (видна новым программам)")
    print("\nГотово. Claude Desktop — закрыть полностью (и в трее) и открыть снова; Claude Code — команда /mcp.")


if __name__ == "__main__":
    main()
