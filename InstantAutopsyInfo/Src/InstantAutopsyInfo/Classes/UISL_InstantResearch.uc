/**
 * UISL_InstantResearch
 *
 * UI screen listener responsible for augmenting the Research screen
 * with additional information about Instant Research requirements.
 *
 * Responsibilities:
 * - Detect opening of the Research screen
 * - Read InstantRequirements from X2TechTemplate
 * - Gather player inventory counts for required items
 * - Merge duplicate requirements originating from modded templates
 * - Format and inject requirement information into research descriptions
 * - Colorize requirement text depending on whether requirements are met
 *
 * The listener modifies only UI display data and does not alter templates
 * or game states, maximizing compatibility with other mods.
 *
 * @author Tigrik
 */
class UISL_InstantResearch extends UIScreenListener;

`include(InstantAutopsyInfo\Src\InstantAutopsyInfo\LoggerMacros.uci)

/**
 * Container describing a single Instant Research requirement entry.
 *
 * ItemName   - Localized/friendly item name
 * Required   - Required quantity for instant research
 * Have       - Current quantity in player inventory
 * Met        - Whether Have >= Required
 */
struct InstantRequirementItem
{
	var string ItemName;
	var int Required;
	var int Have;
	var bool Met;
};

/**
 * Triggered whenever a UI screen is initialized.
 *
 * Detects UIChooseResearch screens and patches their displayed
 * research descriptions with Instant Research requirement data.
 *
 * @param Screen    Newly initialized UI screen
 */
event OnInit(UIScreen Screen)
{
	local UIChooseResearch ResearchScreen;

	ResearchScreen = UIChooseResearch(Screen);

	if(ResearchScreen == none) return;

	`TRACE("ResearchScreen != none");
	PatchResearchScreen(ResearchScreen);
}

/**
 * Patches all research entries currently displayed on the
 * Research screen.
 *
 * Iterates through all visible tech references, gathers
 * inventory/requirement information, and updates UI descriptions.
 *
 * @param ResearchScreen    Active research selection screen
 */
function PatchResearchScreen(UIChooseResearch ResearchScreen)
{
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;

	local array<StateObjectReference> Refs;

	local int i;

	`TRACE_ENTRY("");

	History = `XCOMHISTORY;
	XComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));

	Refs = ResearchScreen.m_arrRefs;

	for(i = 0; i < Refs.Length; ++i)
	{
		PatchTech(ResearchScreen, History, XComHQ, Refs, i);
	}

	ResearchScreen.PopulateData();
}

/**
 * Patches a single research entry on the Research screen.
 *
 * Extracts Instant Research requirements from the associated
 * tech template, gathers inventory counts, merges duplicate
 * requirements, and prepends formatted information to the
 * displayed research description.
 *
 * @param ResearchScreen    Active research selection screen
 * @param History           Global game state history
 * @param XComHQ            XCOM headquarters state
 * @param Refs              Array of displayed tech references
 * @param i                 Index of the tech entry being patched
 */
function PatchTech(UIChooseResearch ResearchScreen, XComGameStateHistory History, XComGameState_HeadquartersXCom XComHQ, array<StateObjectReference> Refs, int i)
{
	local XComGameState_Tech TechState;
	local X2TechTemplate TechTemplate;
	local ArtifactCost Artifact;
	local array<InstantRequirementItem> Requirements;

	`TRACE_ENTRY("");

	TechState = XComGameState_Tech(History.GetGameStateForObjectID(Refs[i].ObjectID));

	if(TechState == none) return;

	TechTemplate = TechState.GetMyTemplate();
	if(TechTemplate == none) return;
	`TRACE("Tech:" @ TechTemplate.DisplayName);

	if(TechTemplate.InstantRequirements.RequiredItemQuantities.Length == 0) return;
	`TRACE("Tech has Instant Requirements:" @ TechTemplate.DisplayName);

	// Don't show requirements for instant research in the Archive
	if(XComHQ.TechIsResearched(Refs[i]) && !TechState.GetMyTemplate().bRepeatable) return;

	foreach TechTemplate.InstantRequirements.RequiredItemQuantities(Artifact)
	{
		Requirements.AddItem(GetRequirementData(XComHQ, Artifact));
	}

	MergeSameRequirements(Requirements);

	ResearchScreen.arrItems[i].Desc = FormatRequirementData(ResearchScreen, Requirements) $ "<br/>" $ ResearchScreen.arrItems[i].Desc;

	`TRACE_EXIT("");
}

/**
 * Builds requirement information for a single artifact cost entry.
 *
 * Retrieves item display name, inventory count, required amount,
 * and determines whether the requirement is currently satisfied.
 *
 * @param XComHQ    XCOM headquarters state
 * @param Artifact  Artifact cost entry from InstantRequirements
 *
 * @return InstantRequirementItem    Populated requirement data
 */
function InstantRequirementItem GetRequirementData(XComGameState_HeadquartersXCom XComHQ, ArtifactCost Artifact)
{
	local InstantRequirementItem RequirementData;
	local X2ItemTemplate ItemTemplate;

	`TRACE_ENTRY("");
	ItemTemplate = class'X2ItemTemplateManager'.static.GetItemTemplateManager().FindItemTemplate(Artifact.ItemTemplateName);
	RequirementData.ItemName = ItemTemplate != none ? ItemTemplate.GetItemFriendlyName() : string(Artifact.ItemTemplateName);
	RequirementData.Required = Artifact.Quantity;
	RequirementData.Have = XComHQ.GetNumItemInInventory(Artifact.ItemTemplateName);
	RequirementData.Met = RequirementData.Have >= RequirementData.Required;

	`TRACE_EXIT("");
	return RequirementData;
}

/**
 * Merges duplicate requirement entries referring to the same item.
 *
 * If multiple entries share the same ItemName, only the entry with
 * the highest Required value is preserved.
 *
 * The original array is modified in-place.
 *
 * @param Requirements    Requirement array to normalize
 */
function MergeSameRequirements(out array<InstantRequirementItem> Requirements)
{
	local int i;
	local int j;

	`TRACE_ENTRY("");

	for(i = 0; i < Requirements.Length; ++i)
	{
		j = i + 1;

		while(j < Requirements.Length)
		{
			if(Requirements[i].ItemName == Requirements[j].ItemName)
			{
				// Keep the one with the higher Required value
				if(Requirements[j].Required > Requirements[i].Required) Requirements[i] = Requirements[j];

				// Remove duplicate entry
				Requirements.Remove(j, 1);
			}
			else ++j;
		}
	}

	`TRACE_EXIT("");
}

/**
 * Formats Instant Research requirement information into a UI-ready
 * HTML string with font styling and colorized requirement states.
 *
 * Requirements that are met are displayed in a positive color,
 * while unmet requirements are displayed in a negative color.
 *
 * @param ResearchScreen    Active research selection screen
 * @param Requirements      Requirement data to format
 *
 * @return string           Formatted HTML UI string
 */
function string FormatRequirementData(UIChooseResearch ResearchScreen, array<InstantRequirementItem> Requirements)
{
	local string Label, sRequirements, sRequirement, Result;
	local int i;

	`TRACE_ENTRY("");

	Label = class'UIUtilities_Text'.static.GetColoredText(class'UIUtilities_Text'.static.AddFontInfo(ConstructInstantLabel(ResearchScreen), false, true,, 22), eUIState_Header);

	for(i = 0; i < Requirements.Length; ++i)
	{
		if(i > 0) sRequirements $= ", ";

		sRequirement = Requirements[i].Have $ "/" $ Requirements[i].Required @ Requirements[i].ItemName;
		sRequirement = class'UIUtilities_Text'.static.GetColoredText(sRequirement, Requirements[i].Met ? eUIState_Good : eUIState_Bad);
		sRequirements $= sRequirement;
	}

	sRequirements = class'UIUtilities_Text'.static.AddFontInfo(sRequirements, false, true,, 28);

	Result = Label $ "<br/>" $ sRequirements;
	`TRACE_EXIT("Return:" @ Result);
	return Result;
}

/**
 * Constructs a localized Instant Research label suitable for UI display.
 *
 * Removes surrounding square brackets from the localized
 * ResearchScreen.m_strInstant string if present and appends ':'.
 *
 * Example:
 * "[INSTANT]" -> "INSTANT:"
 *
 * @param ResearchScreen    Active research selection screen
 *
 * @return string           Formatted localized label
 */
function string ConstructInstantLabel(UIChooseResearch ResearchScreen)
{
	local string Label;

	Label = ResearchScreen.m_strInstant;

	// Unwrap [TEXT] -> TEXT
	if(Left(Label, 1) == "[" && Right(Label, 1) == "]") Label = Mid(Label, 1, Len(Label) - 2);

	return Label $ ":";
}