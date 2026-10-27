using UnrealBuildTool;

public class CommandGameEditorTarget : TargetRules
{
	public CommandGameEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("CommandGame");
	}
}
