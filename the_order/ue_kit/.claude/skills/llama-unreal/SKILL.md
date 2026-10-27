---
name: llama-unreal
description: Локальная LLM в CommandGame через плагин Llama-Unreal (getnamo, v1.4.0 для UE 5.8) и модель Qwen3-4B-RPG-Roleplay-V2 Q4_K_M — установка, API компонента, стриминг токенов, отключение «размышлений», GBNF-грамматика для формата реплик, потоки, LocalLLMProvider/PromptBuilder. Используй в Спринте 6 и при любых правках LLM-слоя.
---

# Llama-Unreal + Qwen3-4B-RPG-Roleplay-V2

## Установка (делает `Scripts\get_deps.ps1 -Plugin -Model`)
- Плагин: релиз `Llama-Unreal-UE5.8-v1.4.0-Vulkan.7z` → содержимое папки `Plugins` архива в `Plugins` проекта. На Windows готов сразу (Vulkan).
- Модель: `Chun121/Qwen3-4B-RPG-Roleplay-V2` → `unsloth.Q4_K_M.gguf` (2 497 276 416 байт, лицензия MIT; дообучение `unsloth/Qwen3-4B-Base`)
  → `Saved/Models/Qwen3-4B-RPG-Roleplay-V2.Q4_K_M.gguf`. В `PathToModel` путь, начинающийся с `.`, считается от `Saved/Models`.
- Имя C++-модуля плагина для `CommandGame.Build.cs` — из `Plugins/Llama*/**/*.Build.cs`.

## API (по README плагина; сверить с заголовками в `Plugins/Llama*/Source`)
- Классы: `ULlamaComponent` (на акторе), `ULlamaSubsystem` (на всё приложение — **наш выбор**: модель грузится один раз, переживает смену уровня).
- Функции: `LoadModel(bForceReload)`, `InsertTemplatedPrompt` (сообщение, роль, генерировать ли ответ), `InsertRawPrompt`, `StopGeneration`,
  `ResetContextHistory`, `UpdateSamplingParams`, `UnloadModel`.
- События: `OnModelLoaded`, `OnNewTokenGenerated` (по токену — для стриминга в UI), `OnPartialGenerated` (по предложению),
  `OnResponseGenerated` (готово), `OnEndOfStream`, `OnError(Message, Code)` (10–19 — загрузка модели).
- Параметры `FLLMModelParams`: `PathToModel`, `SystemPrompt`, `MaxContextLength` (ставим 2048 по ТЗ), `GPULayers` (-1 = все на GPU),
  `StopSequences`, `Advanced.Sampling.*` (temperature 0.7, top_p 0.9, repeat_penalty 1.1), `Advanced.Sampling.Grammar` (GBNF).
- Отдельного `max_tokens` в README нет → лимит 40 токенов делаем сами: счётчик в `OnNewTokenGenerated` + `StopGeneration`, плюс `StopSequences`.
- «Размышления» Qwen3: локально подавляются через `AssistantPrefill` = пустой блок `<think></think>` и пустые строки; содержимое `<think>`
  плагин выносит в категорию Thinking. Модель — дообучение Base-версии: проверить, есть ли у неё вообще `<think>` и какой chat template
  зашит в GGUF (лог загрузки модели).
- **Поток колбэков в README не указан** → считать, что может быть не игровой: всё, что трогает UI/акторы, — через `AsyncTask(GameThread)` (скилл `ue-cpp-pitfalls`).

## GBNF: формат реплики
Грамматика жёстко задаёт 1–2 предложения без `*действий*` и без markdown. Стартовое правило — `root`. Черновик (проверить на модели):
```
root     ::= sentence (" " sentence)?
sentence ::= [^*\n.!?]+ [.!?]
```
Неверная грамматика → `OnError` с кодом 12, генерация идёт без ограничений — ловить и логировать.

## Архитектура в проекте
- `ILLMProvider::RequestReply(const FLLMRequest&, FOnLLMToken, FOnLLMDone)` — асинхронно. Реализации: `StubLLMProvider` (шаблоны по ключам,
  мгновенно, fallback) и `LocalLLMProvider` (Llama-Unreal).
- `PromptBuilder`: [Базовая роль] + сумма `prompt_block` ключей офицера + [Контекст: приказ, силы, потери, история] — шаблон в ТЗ §III.5.
  Ре-инъекция ключей в каждом вызове, 2–3 few-shot примера на пару ключей.
- Очередь: один запрос генерируется за раз; новый приказ тому же офицеру — `StopGeneration` старого.
- Модель грузится при старте миссии (брифинг), не на первом приказе. Не загрузилась → `StubLLMProvider`, в лог `LogLLM` ошибка.

## Проверка (тест-план)
- Время до первого токена и до конца ответа — в `LogLLM`; цель < 1 с до появления текста.
- Набор 20+ пар «приказ × набор ключей» (тест или консольная команда) → таблица ответов, доля попаданий в характер ≥ 80 %.
