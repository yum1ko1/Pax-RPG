---
name: ue-chaos-destruction
description: Разрушаемость зданий (Chaos Geometry Collection) и пул ragdoll для CommandGame — как устроено в UE 5.8, что проверить в исходниках, как фиксировать обломки и тела, как будить их взрывом и мерить FPS. Используй в Спринтах 1, 2 и 7.
---

# Chaos Destruction и ragdoll

## Важное расхождение с ТЗ (решить до кода)
Обломки **Geometry Collection — это частицы внутри одного компонента**, а не отдельные акторы/тела. Поэтому «`SetSimulatePhysics(false)` на
обломок с наименьшим score» из ТЗ напрямую не применим. Варианты (выбрать после чтения исходников, решение записать в отчёт спринта):
- встроенные механизмы GC: засыпание по порогам, удаление/фиксация после сна, перевод частиц в static/kinematic;
- `DestructionPoolManager` управляет **компонентами GC целиком** (активные дома/куски) + лимитом активных частиц через настройки GC.
Критерий ТЗ остаётся: «обломки фиксируются через 3–5 с, FPS ≥ 50».

## Что найти в исходниках UE 5.8 (grep, записать точные сигнатуры)
- `GeometryCollectionComponent.h` (ищи: `find "$UERoot\Engine" -name GeometryCollectionComponent.h`):
  функции и свойства со словами `Sleep`, `Removal`, `Remove`, `Static`, `Kinematic`, `ObjectState`, `Crumble`, `Strain`, `Break`, `DamageThreshold`.
- События разрушения: `OnChaosBreakEvent` / `NotifyBreaks` / `OnChaosRemovalEvent` (проверить наличие).
- Поля урона/кластеров: `DamageThreshold`, `ClusterConnectionType` (Cluster Connection из ТЗ).
- Взрыв: Field System (`AFieldSystemActor`, радиальное поле/strain) или функции применения импульса/strain к GC — проверить, что есть в 5.8.
- Подготовка ассета: Fracture Mode в редакторе (Modeling → Fracture). Плагин и его имя — `Scripts\ue_plugins.ps1 -Find Fracture,GeometryCollection`.
  Если операции фрактуры доступны из Python/MCP — делать скриптом; если нет — автору нужна короткая инструкция по кнопкам (5 мин).

## Ragdoll (Спринт 2) — API UPrimitiveComponent/USkeletalMeshComponent
Ожидаемые имена (сверить по `PrimitiveComponent.h`, `SkeletalMeshComponent.h`): `SetSimulatePhysics`, `SetAllBodiesSimulatePhysics`,
`PutAllRigidBodiesToSleep`, `WakeAllRigidBodies`, `AddRadialImpulse` / `AddRadialForce`, делегаты `OnComponentWake` / `OnComponentSleep`,
`SetCollisionProfileName("Ragdoll")`.
- Пул: активных ≤ 20–30; score = важность (президент > офицер > рядовой > гражданский) + близость к камере + свежесть − время в пуле.
  Вытесненное тело: физика выключена или усыплена, **коллайдер остаётся** (тело не удаляется — ТЗ §I.15).
- Significance: дальше 50 м — `SetVisibility(false)`, физика sleep, коллайдер есть. Плагин Significance Manager.
- Пробуждение взрывом: все тела в радиусе 5 м — разбудить и дать импульс; логировать в `LogRagdollPool`.

## Проверка
- Тест «20 смертей одновременно»: лог числа активных тел + CSV FPS; фризы = кадры > 33 мс.
- Тест «граната у спящего тела»: в логе `OnComponentWake` для этого тела.
