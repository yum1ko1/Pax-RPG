using UnrealBuildTool;

public class CommandGameTarget : TargetRules
{
	public CommandGameTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("CommandGame");
	}
}
