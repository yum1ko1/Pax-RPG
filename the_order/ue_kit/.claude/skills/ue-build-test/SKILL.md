---
name: ue-build-test
description: Сборка, автотесты, логи и крэши проекта CommandGame (UE 5.8) без IDE — какие скрипты запускать, как читать ошибки UBT/компилятора, как писать автотесты и находить причину падения. Используй перед любой сборкой, после правки C++, при красном тесте, крэше или «ничего не происходит» в игре.
---

# Сборка, тесты, логи

Все команды — из корня проекта, PowerShell: `powershell -ExecutionPolicy Bypass -File Scripts\<скрипт>.ps1`.

## Сборка
- `ue_build.ps1` — цель `CommandGameEditor Development`; в консоль только ошибки и итог, полный лог `Saved\Logs\build_last.log`.
- Код выхода 2 — открыт редактор. Варианты: `ue_editor.ps1 -Stop` и собрать, или Live Coding (только тела функций в `.cpp`).
- Изменились `UCLASS/USTRUCT/UPROPERTY/UFUNCTION`, заголовки, `Build.cs`, `.uproject` → только полная сборка с закрытым редактором.
- Читать ошибки сверху вниз: первая ошибка — настоящая, остальные часто её следствие. UHT-ошибки (`UnrealHeaderTool failed`) — синтаксис макросов в `.h`.
- `error LNK2019` на чужой класс → не хватает модуля в `PublicDependencyModuleNames` (`CommandGame.Build.cs`) или нет `*_API` у класса.
  Имя модуля брать из `.Build.cs` рядом с заголовком в исходниках движка, не угадывать.

## Тесты
- `ue_test.ps1 [-Filter CommandGame.Order]` — без окна (`-nullrhi`), лог `Saved\Logs\test_last.log`, JSON-отчёт `Saved\Automation\Reports\index.json`.
  `-Render` — с рендером (то, что требует GPU).
- Имена: `CommandGame.<Подсистема>.<Случай>` — фильтр по префиксу запускает группу.
- Простой тест — `IMPLEMENT_SIMPLE_AUTOMATION_TEST` (пример: `Source/CommandGame/Tests/SmokeTest.cpp`), набор сценариев — Automation Spec
  (`BEGIN_DEFINE_SPEC`/`END_DEFINE_SPEC`, `Describe`/`It`). Перед использованием сверить макросы и флаги с
  `Engine/Source/Runtime/Core/Public/Misc/AutomationTest.h` текущей версии.
- Что покрывать тестами без мира: OrderParser/Validator, PromptBuilder, ObjectiveTracker, TraitDatabase (загрузка JSON), скоринг пулов.
- То, что требует мира (обрушение, ragdoll, BT) — функциональные тесты на тестовой карте или ручной прогон со скриншотом и цифрами.

## Логи и крэши
- `ue_log.ps1` — ошибки из последнего `Saved\Logs\CommandGame*.log`; `-Pattern LogLLM`; `-Tail 80`; `-Crash` — сообщение и стек последнего крэша.
- В коде — категории из `Core/CommandLog.h` (`LogOrder`, `LogOfficerAI`, `LogLLM`, `LogDestructionPool`, `LogRagdollPool`, `LogMission`).
  Ключевые переходы состояний логировать на `Log`, детали — `Verbose`; включить в рантайме: консоль `Log LogLLM Verbose`.
- `ensure(...)`/`ensureMsgf` вместо молчаливого `if (!x) return;` в местах, где null — это баг: в логе будет стек.

## Производительность (критерий FPS ≥ 50)
- Мерить в окне игры (`ue_editor.ps1 -Map ... -Game`), не в `-nullrhi`. Консоль: `stat unit`, `stat fps`; запись — `csvprofile start` / `csvprofile stop`
  (CSV в `Saved\Profiling`), разбирать CSV скриптом и приводить цифры (мин/среднее/1% low) в отчёте.
