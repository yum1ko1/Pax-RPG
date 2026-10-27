using UnrealBuildTool;

public class CommandGame : ModuleRules
{
	public CommandGame(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		// Подпапки модуля (Core, Command, AI, LLM, Traits, Physics, Mission, UI) видны как корни include.
		PublicIncludePaths.Add(ModuleDirectory);

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput",
			"AIModule", "GameplayTasks", "NavigationSystem",
			"UMG", "Slate", "SlateCore",
			"Json", "JsonUtilities"
		});

		// Добавлять по спринтам, сверив имена модулей с исходниками движка/плагинов (.Build.cs рядом с модулем):
		// Спринт 1–2: Chaos / Geometry Collection / PhysicsCore; Significance Manager.
		// Спринт 6:   модуль Llama-Unreal (имя — в Plugins/Llama*/**/*.Build.cs).
	}
}
