#pragma once

#include "CoreMinimal.h"

// Своя категория логов на каждую подсистему: ошибки ищутся по имени категории (Scripts\ue_log.ps1 -Pattern LogLLM).
COMMANDGAME_API DECLARE_LOG_CATEGORY_EXTERN(LogOrder, Log, All);
COMMANDGAME_API DECLARE_LOG_CATEGORY_EXTERN(LogOfficerAI, Log, All);
COMMANDGAME_API DECLARE_LOG_CATEGORY_EXTERN(LogLLM, Log, All);
COMMANDGAME_API DECLARE_LOG_CATEGORY_EXTERN(LogDestructionPool, Log, All);
COMMANDGAME_API DECLARE_LOG_CATEGORY_EXTERN(LogRagdollPool, Log, All);
COMMANDGAME_API DECLARE_LOG_CATEGORY_EXTERN(LogMission, Log, All);
