local name, ns = ...
-- VocGear: equip what Pawn says is an upgrade. Nothing else (plus advice).

VocGearDB = VocGearDB or {}
ns.db = VocGearDB

-- Defaults. minUpgradePct is a percent; Pawn's own bar is 0.5.
-- scale "" means any visible Pawn scale.
local defaults = {
  enabled = true,
  announce = true,
  audit = false,
  minUpgradePct = 0.5,
  autoTwoSlot = false,
  includeIlvl = true,
  scale = "",
  questPicker = "highlight", -- "off" | "highlight" | "auto"
  lootAdvisor = true,
}
ns.defaults = defaults

function ns.opts()
  for k, v in pairs(defaults) do
    if ns.db[k] == nil then ns.db[k] = v end
  end
  return ns.db
end

-- Pawn API (verified against Pawn 2.13.16 source; see .reference/pawn-analysis.md):
-- PawnGetItemData(link) -> item table | nil
-- PawnIsItemAnUpgrade(item) -> upgrade entries | nil
--   (each entry: ScaleName, PercentUpgrade ratio, ExistingItemLink)
-- PawnIsItemAnItemLevelUpgrade(item) -> level difference | nil
-- PawnGetAllScalesEx() -> { {Name, LocalizedName, IsVisible}... }
-- PawnUnenchantItemLink(link) -> link without enchant/gem IDs
function ns.pawnReady()
  return type(_G.PawnGetItemData) == "function"
    and type(_G.PawnIsItemAnUpgrade) == "function"
    and type(_G.PawnIsItemAnItemLevelUpgrade) == "function"
end

-- Answer "is this link an upgrade?" through Pawn, honoring the scale
-- filter, percent threshold, and item-level toggle.
-- Returns nil when unsure (Pawn uncached or erroring), else:
--   { upgrade=bool, percent=ratio|nil, existing=link|nil,
--     ilvl=bool, ilvlDiff=n|nil, itemLevel=n|nil }
function ns.evaluate(link)
  local o = ns.opts()
  local ok, item = pcall(_G.PawnGetItemData, link)
  if not ok or not item or item.Link == nil then return nil end
  -- Min-level gate (what CheckLevel=true did on the old boolean API).
  local _, _, _, _, minLevel = C_Item.GetItemInfo(link)
  if minLevel and UnitLevel("player") < minLevel then
    return { upgrade = false }
  end
  local result = { upgrade = false, itemLevel = item.Level }
  local okUp, upgrades = pcall(_G.PawnIsItemAnUpgrade, item)
  if not okUp then return nil end
  if upgrades then
    local bar = (o.minUpgradePct or 0) / 100
    for _, entry in ipairs(upgrades) do
      local scaleOK = o.scale == nil or o.scale == "" or entry.ScaleName == o.scale
      if scaleOK and entry.PercentUpgrade and entry.PercentUpgrade >= bar then
        result.upgrade = true
        if not result.percent or entry.PercentUpgrade > result.percent then
          result.percent = entry.PercentUpgrade
          result.existing = entry.ExistingItemLink
          result.scaleName = entry.ScaleName
        end
      end
    end
  end
  if not result.upgrade and o.includeIlvl then
    local okIlvl, diff = pcall(_G.PawnIsItemAnItemLevelUpgrade, item)
    if okIlvl and diff then
      result.upgrade = true
      result.ilvl = true
      result.ilvlDiff = diff
    end
  end
  return result
end

function ns.unenchant(link)
  if type(_G.PawnUnenchantItemLink) == "function" then
    local ok, stripped = pcall(_G.PawnUnenchantItemLink, link)
    if ok and stripped then return stripped end
  end
  return link
end

-- Inventory slot pairs, mirroring Pawn's PawnItemEquipLocToSlot tables.
ns.slotPairs = { INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 } }

-- Which slot should a two-slot upgrade go into? Prefers the slot holding
-- the item Pawn says it replaces; falls back to the empty or weaker slot.
-- Returns a slot ID, or nil (can't resolve -> announce instead).
function ns.resolveTwoSlotSlot(equipLoc, ev, link)
  local pair = ns.slotPairs[equipLoc]
  if not pair then return nil end
  local held = {}
  for _, slotID in ipairs(pair) do
    held[slotID] = GetInventoryItemLink("player", slotID)
  end
  if ev.existing then
    local target = ns.unenchant(ev.existing)
    for _, slotID in ipairs(pair) do
      if held[slotID] and ns.unenchant(held[slotID]) == target then
        return slotID
      end
    end
  end
  for _, slotID in ipairs(pair) do
    if not held[slotID] then return slotID end
  end
  -- Both full, no Pawn-provided target (item-level path): take the weaker
  -- slot, but only if the candidate actually beats it.
  local candLevel = ev.itemLevel or C_Item.GetDetailedItemLevelInfo(link)
  if not candLevel then return nil end
  local weakSlot, weakLevel
  for _, slotID in ipairs(pair) do
    local lvl = C_Item.GetDetailedItemLevelInfo(held[slotID])
    if lvl and (not weakLevel or lvl < weakLevel) then
      weakSlot, weakLevel = slotID, lvl
    end
  end
  if weakSlot and candLevel > weakLevel then return weakSlot end
  return nil
end

function ns.why(ev)
  if ev.ilvl then return " (item level +" .. tostring(ev.ilvlDiff or "?") .. ")" end
  if ev.percent and ev.percent >= 100 then return " (big upgrade)" end
  if ev.percent then return string.format(" (+%.1f%%)", ev.percent * 100) end
  return ""
end

function ns.announce(link, ev)
  local o = ns.opts()
  if o.announce and not ns.flagged[link] then
    ns.flagged[link] = true
    print("VocGear: Pawn upgrade in bags (not auto-equipped): " .. link .. ns.why(ev))
  end
end

-- Returns true when an equip happened (scan should stop for this pass).
function ns.equip(link, ev, slotID)
  local o = ns.opts()
  if o.audit then
    if o.announce and not ns.flagged[link] then
      ns.flagged[link] = true
      print("VocGear: would equip " .. link .. ns.why(ev) .. " (audit mode)")
    end
    return false
  end
  if slotID then EquipItemByName(link, slotID) else EquipItemByName(link) end
  if o.announce then print("VocGear: equipped " .. link .. ns.why(ev)) end
  return true
end

ns.flagged = {} -- links announced as not-auto-equipped, per session
ns.scanning = false

-- Pawn may load after us or init late; one outstanding retry covers the race
-- without stacking a new timer on every bag event.
function ns.retrySoon()
  if ns.retryPending then return end
  ns.retryPending = true
  C_Timer.After(5, function()
    ns.retryPending = false
    ns.scan()
  end)
end

function ns.scan()
  if ns.scanning then return end
  local o = ns.opts()
  if not o.enabled then return end
  if not ns.pawnReady() then ns.retrySoon() return end
  if InCombatLockdown() then return end
  ns.scanning = true
  local unsure = false
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local ev = ns.evaluate(link)
        if ev == nil then
          unsure = true
        elseif ev.upgrade then
          local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
          local pair = equipLoc and ns.slotPairs[equipLoc]
          if equipLoc == nil or (pair and not o.autoTwoSlot) then
            ns.announce(link, ev)
          elseif pair then
            local slotID = ns.resolveTwoSlotSlot(equipLoc, ev, link)
            if slotID then
              if ns.equip(link, ev, slotID) then ns.scanning = false return end
            else
              ns.announce(link, ev)
            end
          else
            if ns.equip(link, ev, nil) then ns.scanning = false return end
          end
        end
      end
    end
  end
  ns.scanning = false
  -- One equip per scan; the bag update re-triggers for the rest. Items Pawn
  -- couldn't answer yet get a retry so they aren't skipped forever.
  if unsure then ns.retrySoon() end
end

-- Quest-reward picker. Runs when the quest-complete dialog shows; picks the
-- best Pawn upgrade among the choices, or just names it.
function ns.questChoices()
  if not ns.pawnReady() then return end
  local o = ns.opts()
  local mode = o.questPicker
  if not mode or mode == "off" then return end
  local n = GetNumQuestChoices()
  if not n or n < 2 then return end -- nothing to decide
  local best, bestEv, bestIndex
  for i = 1, n do
    local link = GetQuestItemLink("choice", i)
    if link then
      local ev = ns.evaluate(link)
      if ev and ev.upgrade and (not bestEv or (ev.percent or 0) > (bestEv.percent or 0)) then
        best, bestEv, bestIndex = link, ev, i
      end
    end
  end
  if mode == "auto" and not o.audit then
    if bestIndex then
      GetQuestReward(bestIndex)
      if o.announce then print("VocGear: quest reward taken: " .. best .. ns.why(bestEv)) end
    elseif o.announce then
      print("VocGear: no quest reward is a Pawn upgrade; left for you to pick")
    end
  elseif o.announce then
    if bestIndex then
      print("VocGear: quest reward pick: take " .. best .. ns.why(bestEv))
    else
      print("VocGear: no quest reward is a Pawn upgrade")
    end
  end
end

-- Loot roll advisor. Advisory only: never rolls, just informs.
function ns.lootRoll(rollID)
  if not ns.opts().lootAdvisor then return end
  if not ns.pawnReady() then return end
  local link = GetLootRollItemLink(rollID)
  if not link then return end
  local ev = ns.evaluate(link)
  if not ev then return end -- unsure; stay quiet rather than mislead
  if not ns.opts().announce then return end
  if ev.upgrade then
    print("VocGear: NEED " .. link .. ns.why(ev))
  else
    print("VocGear: GREED " .. link .. " (not a Pawn upgrade)")
  end
end

-- Blizzard Settings panel (Settings > AddOns > VocGear). Built once, after
-- SavedVariables land, and only if the Settings API is present.
ns.settingsBuilt = false
function ns.ensureSettings()
  if ns.settingsBuilt then return end
  if type(Settings) ~= "table" then return end
  if type(Settings.RegisterVerticalLayoutCategory) ~= "function" then return end
  local category = Settings.RegisterVerticalLayoutCategory("VocGear")
  Settings.RegisterAddOnCategory(category)
  local db = ns.opts() -- bound, defaulted table
  local function check(key, label, tooltip)
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_" .. key, key, db, type(defaults[key]), label, defaults[key])
    Settings.CreateCheckbox(category, s, tooltip)
  end
  check("enabled", "Enable auto-equip", "Equip Pawn-flagged upgrades out of combat.")
  check("announce", "Chat announcements", "Print a line when VocGear equips, picks, or advises.")
  check("audit", "Audit mode", "Announce only: never equip or pick, just say what would happen.")
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_minUpgradePct", "minUpgradePct",
      db, type(defaults.minUpgradePct), "Minimum upgrade %", defaults.minUpgradePct)
    local sliderOpts = Settings.CreateSliderOptions(0.5, 25, 0.5)
    Settings.CreateSlider(category, s, sliderOpts,
      "Only act on upgrades at or above this Pawn margin. Pawn's own bar is 0.5%.")
  end
  check("autoTwoSlot", "Auto-equip rings and trinkets",
    "Equip into the weaker of the pair instead of announcing.")
  check("includeIlvl", "Include item-level upgrades",
    "Treat Pawn's item-level-only upgrades as upgrades too.")
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_scale", "scale",
      db, type(defaults.scale), "Pawn scale", defaults.scale)
    Settings.CreateDropdown(category, s, ns.scaleOptions,
      "Which Pawn scale counts. Any visible scale preserves stock behavior.")
  end
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_questPicker", "questPicker",
      db, type(defaults.questPicker), "Quest rewards", defaults.questPicker)
    Settings.CreateDropdown(category, s, ns.questOptions,
      "Off: ignore. Highlight: print the pick. Auto: take the best choice.")
  end
  check("lootAdvisor", "Loot roll advisor", "Recommend NEED or GREED on group loot in chat.")
  ns.settingsBuilt = true
  ns.settingsCategory = category
end

function ns.scaleOptions()
  local container = Settings.CreateControlTextContainer()
  container:Add("", "Any visible scale", "Count an upgrade for any of Pawn's visible scales.")
  if ns.pawnReady() then
    local ok, scales = pcall(_G.PawnGetAllScalesEx)
    if ok and scales then
      for _, sc in ipairs(scales) do
        if sc.IsVisible then
          container:Add(sc.Name, sc.LocalizedName or sc.Name, "")
        end
      end
    end
  end
  return container:GetData()
end

function ns.questOptions()
  local container = Settings.CreateControlTextContainer()
  container:Add("off", "Off", "Never touch quest rewards.")
  container:Add("highlight", "Highlight best", "Print which choice to take.")
  container:Add("auto", "Auto-pick best", "Take the best choice for you.")
  return container:GetData()
end

function ns.openConfig()
  local ok = pcall(function() Settings.OpenToCategory(ns.settingsCategory:GetID()) end)
  if not ok then print("VocGear: open Settings > AddOns > VocGear") end
end

ns.frame = CreateFrame("Frame")
ns.frame:RegisterEvent("ADDON_LOADED")
ns.frame:RegisterEvent("BAG_UPDATE_DELAYED")
ns.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
ns.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
ns.frame:RegisterEvent("QUEST_COMPLETE")
ns.frame:RegisterEvent("START_LOOT_ROLL")
ns.frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    -- The client replaces the SavedVariables global with the loaded table
    -- after our file ran, so rebind or settings never persist.
    if arg1 == name then ns.db = VocGearDB ns.ensureSettings() end
    if arg1 ~= "Pawn" and arg1 ~= name then return end
  elseif event == "QUEST_COMPLETE" then
    ns.questChoices()
    return
  elseif event == "START_LOOT_ROLL" then
    ns.lootRoll(arg1)
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    ns.ensureSettings() -- in case Settings wasn't up at ADDON_LOADED
  end
  ns.scan()
end)

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so these two
-- cannot be namespaced; the explicit _G marks them as deliberate.
_G.SLASH_VOCGEAR1 = "/vg"
_G.SLASH_VOCGEAR2 = "/vocgear"
SlashCmdList.VOCGEAR = function(msg)
  local o = ns.opts()
  msg = strtrim(msg or ""):lower()
  if msg == "announce" then
    o.announce = not o.announce
    print("VocGear: announcements " .. (o.announce and "on" or "off"))
  elseif msg == "config" then
    ns.openConfig()
  else
    o.enabled = not o.enabled
    print("VocGear: " .. (o.enabled and "on" or "off"))
    if o.enabled then ns.scan() end
  end
end
