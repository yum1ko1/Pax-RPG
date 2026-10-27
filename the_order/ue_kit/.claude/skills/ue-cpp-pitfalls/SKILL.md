---
name: ue-cpp-pitfalls
description: Типичные ошибки ИИ при написании C++ для Unreal Engine 5 (сборщик мусора, потоки, макросы рефлексии, модули, устаревшие API) и как их избежать. Используй при написании и ревью любого C++ кода CommandGame.
---

# Подводные камни UE C++ (проверять при каждом ревью)

1. **Указатель на `UObject` в поле класса без `UPROPERTY()`** → сборщик мусора удалит объект, крэш «через раз».
   Поля: `UPROPERTY() TObjectPtr<UFoo> Foo;`. В не-UObject структурах — `TStrongObjectPtr`/`TWeakObjectPtr` или `FGCObject`.
2. **Работа с UObject/акторами/UI не на игровом потоке** (колбэки фоновых задач, LLM-плагина, HTTP) → гонки и крэши.
   Возвращаться так: `AsyncTask(ENamedThreads::GameThread, [WeakThis = TWeakObjectPtr<UThis>(this), Text]() { if (WeakThis.IsValid()) { ... } });`
   Захватывать `TWeakObjectPtr`, не сырой `this`.
3. **Макросы рефлексии:** `GENERATED_BODY()` в каждом `UCLASS/USTRUCT`; `#include "X.generated.h"` — последним include в заголовке;
   классы, которые используются из других модулей — с `COMMANDGAME_API`.
4. **Модули:** каждый внешний модуль — в `CommandGame.Build.cs`. Имя модуля — из `.Build.cs` в исходниках движка/плагина.
5. **Устаревшие API.** UE 5.8 ≠ память модели. Перед вызовом незнакомой функции — grep по `Engine/Source` и `Engine/Plugins`,
   посмотреть `UE_DEPRECATED` рядом. Предупреждение C4996 = устаревший вызов, исправлять сразу.
6. **`new`/`delete` для UObject нельзя:** `NewObject<T>(Outer)`, акторы — `GetWorld()->SpawnActor<T>(...)`, компоненты в конструкторе —
   `CreateDefaultSubobject<T>(TEXT("Name"))`.
7. **Таймеры и делегаты на уничтоженных объектах:** снимать в `EndPlay`; для динамических делегатов — `AddUniqueDynamic`/`RemoveDynamic`,
   функции-обработчики помечены `UFUNCTION()`.
8. **`Tick` без нужды** — отключать (`PrimaryActorTick.bCanEverTick = false`), пулы и трекеры обновлять таймером с интервалом.
9. **JSON:** `FJsonSerializer` + `FJsonObjectConverter::JsonObjectStringToUStruct` в `USTRUCT` с `UPROPERTY` — поля называть как в JSON
   (конвертер сопоставляет без учёта регистра); ошибки разбора логировать с путём файла.
10. **Строки:** `FString` для текста, `FName` для идентификаторов (id ключей, офицеров), `FText` для показа в UI. Русский текст в коде —
    `TEXT("...")`, файлы исходников в UTF-8 с BOM или без не-ASCII; тексты интерфейса и реплик — в JSON.
11. **Детерминизм ИИ:** решения BT не зависят от ответа LLM. Ответ LLM приходит асинхронно и может не прийти — отряд выполняет приказ в любом случае.
