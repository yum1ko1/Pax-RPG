---
name: ue-ai-bt
description: ИИ юнитов CommandGame на Behavior Tree — офицеры, солдаты, гражданские, президент; передача приказа в Blackboard, задачи BT на C++, слух (AIPerception) для «звука боя», движение по NavMesh. Используй в Спринтах 3 и 5 и при отладке поведения.
---

# Behavior Tree и AI

## Поток приказа (детерминированный, без LLM)
`WBP_Console` → `OrderParser` → `OrderValidator` → `OrderDispatcher` → `AOfficerAIController::ReceiveOrder(FOrder)`:
1. Записать в Blackboard ключи `OrderType` (enum/name), `TargetLocation` (vector), `TargetActor` (object), `OrderId` (int).
2. Раздать отряду (у солдат свои контроллеры читают задачу офицера).
3. Параллельно — запрос реплики в `ILLMProvider` (асинхронно; результат только в консоль/UI).

## Правило: логика в C++
- Задачи: наследники `UBTTaskNode` (`ExecuteTask`, латентные — `EBTNodeResult::InProgress` + `FinishLatentTask`), сервисы — `UBTService`,
  декораторы — `UBTDecorator`. Граф BT — тонкий: Selector/Sequence + наши задачи. Сверять сигнатуры с `Engine/Source/Runtime/AIModule`.
- Сам граф `.uasset` (BT_Soldier, BT_Officer, BT_Civilian, BB_Common): создать через Unreal MCP/Python, если есть инструменты для BT;
  иначе — дать автору пошаговую инструкцию по кнопкам (граф из 3–5 узлов, 5–10 минут) со скриншотом-образцом.
- Альтернатива для простых юнитов (гражданские, президент): C++-машина состояний в контроллере. ТЗ называет BT — согласовать с автором.

## Движение
- `AAIController::MoveToLocation` / `MoveToActor`, результат — `OnMoveCompleted`. NavMesh: `NavMeshBoundsVolume` на карте;
  в `Config/DefaultEngine.ini` уже `RuntimeGeneration=Dynamic` (перестройка после обрушений).

## Гражданские: «звук боя»
- `UAIPerceptionComponent` + `UAISenseConfig_Hearing` на контроллере гражданского; выстрел/взрыв вызывает `UAISense_Hearing::ReportNoiseEvent(...)`.
- Реакция по ключу: паникёр — сразу бежит в ближайшее укрытие (точки укрытий — акторы-маркеры), спокойный — с задержкой.
- Счётчик живых гражданских → GameState → монитор («Гражданские: X%»).

## Президент
- Враги его игнорируют (команда/тег в perception). При штурме (дружественный юнит в радиусе / событие миссии) — бег по маршруту escape.
- Захват: overlap с дружественным юнитом → `MissionManager`.

## Отладка
- Gameplay Debugger (апостроф `'` в игре) — BT, Blackboard, perception выбранного юнита.
- Visual Logger (`vislog` / Tools → Visual Logger) — запись решений по времени, сохраняется в файл.
- Ключевые переходы — `UE_LOG(LogOfficerAI, Log, ...)` с id юнита и приказа.
