-- Lint config shared across the Voc family (see FAMILY.md). The WoW
-- client runs Lua 5.1; tests may use 5.4 features behind guards.
--
-- read_globals is the allowlist of WoW API verified against the build
-- in `## Interface:` (Blizzard_APIDocumentationGenerated for that
-- build, see FAMILY.md "Sources of truth"). Lint fails on any other
-- global on purpose: add a name here only after confirming it exists,
-- under that namespace, in the current build. Never from a wiki.
std = "lua51"
max_line_length = false
self = false
unused_args = false
exclude_files = { ".reference/**" }

-- Globals this addon owns: SavedVariables and slash registration.
globals = {
  "VocGearDB",
  "SLASH_VOCGEAR1", "SLASH_VOCGEAR2",
  "SlashCmdList",
}

-- WoW API and UI globals read by the addon.
read_globals = {
  "_G",
  "C_Container", "C_Item", "C_SpecializationInfo", "C_Timer",
  "CreateFrame", "EquipItemByName", "GameTooltip", "GetInventoryItemLink",
  "GetTime", "InCombatLockdown", "NUM_BAG_SLOTS", "PaperDollFrame",
  "PlaySound", "Settings", "MinimalSliderWithSteppersMixin", "UnitClass", "UnitLevel",
  "IsAddOnLoaded", "GetAddOnInfo",
  "CreateSettingsListSectionHeaderInitializer", "SettingsPanel",
  "hooksecurefunc", "strtrim",
  -- VocDebug guest hook (our own addon, not a Blizzard API)
  "VOCDBG",
  -- Pawn (required dependency)
  "PawnGetAllScalesEx", "PawnGetItemData", "PawnIsArmorBestTypeForPlayer",
  "PawnIsItemAnItemLevelUpgrade", "PawnIsItemAnUpgrade",
  "PawnUI_InventoryPawnButton", "PawnUI_InventoryPawnButton_Move",
  "PawnUnenchantItemLink",
}

files["tests/**"] = {
  std = "+lua54",
  globals = { "print" },
  read_globals = { "setfenv", "loadstring", "unpack" },
}
