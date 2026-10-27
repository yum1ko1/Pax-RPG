// Дымовой тест Спринта 0: проверяет, что модуль собран и тесты находятся по фильтру «CommandGame».
// Флаги автотестов сверять с Engine/Source/Runtime/Core/Public/Misc/AutomationTest.h текущей версии движка.
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCommandGameSmokeTest, "CommandGame.Smoke.ModuleLoaded",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCommandGameSmokeTest::RunTest(const FString& Parameters)
{
	TestTrue(TEXT("1 + 1 == 2"), 1 + 1 == 2);
	return true;
}

#endif
