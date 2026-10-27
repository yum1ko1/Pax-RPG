# CommandGame — «Приказ» (UE 5.8, C++)

Тактический симулятор командира, MVP. Документы проекта (читать при первом входе):
`C:\Users\mbkli\Desktop\The Order (Claude)\` → `ИНСТРУКЦИЯ ОРКЕСТРАТОРА.md`, `План для Claude.md` (ТЗ), `ДИЗДОК.md`.
Общение с автором — по-русски.

## Железные правила
- **LLM = голос, не мозг.** Действия юнитов — только детерминированный Behavior Tree / C++. LLM (Qwen3 через Llama-Unreal) выдаёт только текст реплик.
- **Стоп-лист MVP:** без покупных ассетов и ручного моделинга, серый UI, без голоса/TTS, без физического стола/голограммы,
  10×10 юнитов, без экономики, портреты — квадраты. Фича не служит петле «приказал → рушится дом → выкрутился» — откладывается.
- Данные (ключи, офицеры, приказы, миссии) — JSON в `Content/Data/`, не хардкод. Схемы — скилл `order-data`.
- **Логика — в C++.** Blueprint — тонкие обёртки и настройка. `.uasset` бинарный: его нельзя прочитать и сравнить в git.
  BT-задачи и сервисы — C++-классы (`UBTTask_*`, `UBTService_*`).
- Ассеты и уровни создавать **Python-скриптами редактора** (`Content/Python/*.py`) или через Unreal MCP — так шаги воспроизводимы.
- API движка не вспоминать, а **сверять с исходниками**: `$UERoot\Engine\Source` и `$UERoot\Engine\Plugins` (grep по имени класса/функции).
  Между версиями UE сигнатуры меняются.

## Команды (из корня проекта, PowerShell)
| Что | Команда |
|---|---|
| Проверить окружение | `powershell -ExecutionPolicy Bypass -File Scripts\setup_check.ps1` |
| Собрать (редактор закрыт) | `powershell -ExecutionPolicy Bypass -File Scripts\ue_build.ps1` |
| Автотесты | `powershell -ExecutionPolicy Bypass -File Scripts\ue_test.ps1 [-Filter CommandGame.Order]` |
| Редактор + Unreal MCP | `powershell -ExecutionPolicy Bypass -File Scripts\ue_editor.ps1` (закрыть: `-Stop`) |
| Запустить карту как игру | `powershell -ExecutionPolicy Bypass -File Scripts\ue_editor.ps1 -Map L_Blockout -Game` |
| Логи / крэш | `Scripts\ue_log.ps1`, `-Pattern LogLLM`, `-Tail 80`, `-Crash` |
| Плагины .uproject | `Scripts\ue_plugins.ps1` |
| clangd-база | `Scripts\ue_clangdb.ps1` |

- Сборка редакторской цели при открытом редакторе не идёт (Live Coding). Правки только в `.cpp` — Live Coding (Ctrl+Alt+F11);
  новые `UPROPERTY`/`UFUNCTION`/классы/заголовки — закрыть редактор и `ue_build.ps1`.
- Редактор открыт → в `.mcp.json` подключён Unreal MCP (`http://127.0.0.1:8000/mcp`): акторы, ассеты, материалы, автотесты.
  Вызовы MCP выполняются на игровом потоке по очереди — не слать параллельно.

## Цикл работы над задачей
1. Найти в исходниках движка нужный API (grep), записать сигнатуры в заметку задачи.
2. Код + тест (`Source/CommandGame/Tests/`, имя `CommandGame.<Подсистема>.<Случай>`).
3. `ue_build.ps1` → `ue_test.ps1` → при падении `ue_log.ps1`.
4. Визуальное (обрушение, ragdoll, UI) — запуск карты, скриншот, цифры FPS (`stat unit`, CSV-профайлер).
5. Коммит маленький и с понятным сообщением; `.uasset` — только осознанно (LFS, не мёржится).

## Структура
```
Source/CommandGame/
  Core/      GameMode, PlayerController, GameState, CommandLog (категории логов)
  Command/   OrderParser, OrderValidator, OrderDispatcher
  AI/        OfficerAIController, SoldierAIController, CivilianAIController, BT-задачи
  LLM/       ILLMProvider, StubLLMProvider, LocalLLMProvider, PromptBuilder
  Traits/    TraitSystem, TraitDatabase
  Physics/   RagdollPoolManager, DestructionPoolManager, SignificanceBridge
  Mission/   MissionManager, ObjectiveTracker, TaskGenerator
  UI/        ConsoleWidget, MonitorWidget, BriefingWidget, DroneController
  Tests/     автотесты
Content/Data/   traits.json, officers.json, orders.json, mission_01.json
Content/Python/ скрипты сборки уровней и ассетов
Saved/Models/   GGUF-модель (не в git)
```

## Скиллы проекта (`.claude/skills/`)
`ue-build-test`, `ue-cpp-pitfalls`, `ue-chaos-destruction`, `ue-ai-bt`, `llama-unreal`, `order-data` —
загружай нужный перед работой над подсистемой.
