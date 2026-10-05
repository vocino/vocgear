local name, ns = ...
-- VocGear: equip what Pawn says is an upgrade. Nothing else (plus advice).

VocGearDB = VocGearDB or {}
ns.db = VocGearDB

-- Defaults. minUpgradePct is a percent in 5s; 0 accepts every Pawn
-- verdict (Pawn's own ~0.5% bar still applies upstream).
-- scale "" means any visible Pawn scale.
local defaults = {
  enabled = true,
  announce = true,
  audit = false,
  minUpgradePct = 0,
  autoTwoSlot = false,
  includeIlvl = true,
  keepHeirlooms = true,
  scale = "",
  sheetButton = true,
}
ns.defaults = defaults

-- Corrupt SavedVariables (a non-table global, or a known key holding the
-- wrong type) reset to defaults instead of erroring or misbehaving.
-- Unknown keys are left alone for forward compatibility.
function ns.opts()
  if type(ns.db) ~= "table" then ns.db = {} VocGearDB = ns.db end
  for k, v in pairs(defaults) do
    if type(ns.db[k]) ~= type(v) then ns.db[k] = v end
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
  if type(upgrades) == "table" then
    local bar = (o.minUpgradePct or 0) / 100
    for _, entry in ipairs(upgrades) do
      -- A non-table entry (Pawn drifted its return shape) is skipped:
      -- malformed data must never abort the whole scan.
      if type(entry) == "table" then
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
  end
  if not result.upgrade and o.includeIlvl then
    local okIlvl, diff = pcall(_G.PawnIsItemAnItemLevelUpgrade, item)
    if okIlvl and diff and ns.armorBest(item) then
      result.upgrade = true
      result.ilvl = true
      result.ilvlDiff = diff
    end
  end
  return result
end

-- Armor-type gate. Pawn applies PawnIsArmorBestTypeForPlayer to score
-- upgrades itself (Pawn.lua:3621); the item-level path has no such check,
-- so mirror it here. A missing API (older Pawn) fails open.
function ns.armorBest(item)
  if type(_G.PawnIsArmorBestTypeForPlayer) ~= "function" then return true end
  local ok, best = pcall(_G.PawnIsArmorBestTypeForPlayer, item)
  return ok and best
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

-- Primary slot per equip loc, same source. Used to see what an equip
-- would displace (for two-slot items the resolved slot is used instead).
ns.primarySlot = {
  INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
  INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
  INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
  INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
  INVTYPE_SHIELD = 17, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
  INVTYPE_RANGED = 16, INVTYPE_RANGEDRIGHT = 16, INVTYPE_WEAPONOFFHAND = 17,
  INVTYPE_HOLDABLE = 17, INVTYPE_TABARD = 19,
}

ns.HEIRLOOM_RARITY = 7
function ns.isHeirloom(link)
  if not link then return false end
  local _, _, rarity = C_Item.GetItemInfo(link)
  return rarity == ns.HEIRLOOM_RARITY
end

function ns.announceHeirloom(link, held)
  local o = ns.opts()
  if o.announce and not ns.flagged[link] then
    ns.flagged[link] = true
    print("VocGear: keeping heirloom " .. held .. " (" .. link .. " is an upgrade)")
  end
end

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
  local paused = ns.isPaused()
  if o.audit or paused then
    if o.announce and not ns.flagged[link] then
      ns.flagged[link] = true
      local reason = paused and " (paused: loop guard)" or " (audit mode)"
      print("VocGear: would equip " .. link .. ns.why(ev) .. reason)
    end
    return false
  end
  ns.ourEquipPending = true
  if slotID then EquipItemByName(link, slotID) else EquipItemByName(link) end
  if o.announce then print("VocGear: equipped " .. link .. ns.why(ev)) end
  return true
end

ns.flagged = {} -- links announced as not-auto-equipped, per session
ns.scanning = false

-- Loop guard: gear just swapped out is left alone for a while, so A->B->A
-- ping-pong (multi-scale verdicts, weapon-slot ambiguity, stale Pawn data
-- right after an equip) can't run forever.
ns.SWAP_COOLDOWN = 30 -- seconds a displaced link is skipped
ns.BREAKER_WINDOW = 60 -- sliding window for same-slot re-equips
ns.BREAKER_TRIPS = 3 -- our equips to one slot in-window that pause auto-equip
ns.BREAKER_PAUSE = 60 -- pause length in seconds
ns.equippedSnap = nil -- slotID -> link at the last scan's start
ns.recentSwap = {} -- link -> timestamp when it was displaced
ns.slotTouches = {} -- slotID -> timestamps of OUR equips
ns.pausedUntil = nil
ns.ourEquipPending = false

function ns.snapshotEquipped()
  local snap = {}
  for slotID = 1, 19 do
    snap[slotID] = GetInventoryItemLink("player", slotID)
  end
  return snap
end

function ns.noteDisplacement(prevLink, newLink, slotID, now)
  -- Any observed displacement (ours or the player's) seeds swap memory:
  -- don't yank back what just came off, including the player's own swaps.
  if prevLink then ns.recentSwap[prevLink] = now end
  if newLink and ns.ourEquipPending then
    local fresh = {}
    for _, t in ipairs(ns.slotTouches[slotID] or {}) do
      if now - t < ns.BREAKER_WINDOW then fresh[#fresh + 1] = t end
    end
    fresh[#fresh + 1] = now
    ns.slotTouches[slotID] = fresh
    if #fresh >= ns.BREAKER_TRIPS then
      ns.pausedUntil = now + ns.BREAKER_PAUSE
      if ns.opts().announce then
        print("VocGear: equip loop detected, auto-equip paused 60s (/vg twice to resume now)")
      end
    end
  end
end

function ns.trackSwaps()
  local now = GetTime()
  local snap = ns.snapshotEquipped()
  if ns.equippedSnap then
    for slotID = 1, 19 do
      local prev, cur = ns.equippedSnap[slotID], snap[slotID]
      if cur ~= prev then ns.noteDisplacement(prev, cur, slotID, now) end
    end
  end
  ns.equippedSnap = snap
  ns.ourEquipPending = false
  for link, t in pairs(ns.recentSwap) do
    if now - t >= ns.SWAP_COOLDOWN then ns.recentSwap[link] = nil end
  end
end

function ns.isPaused()
  return ns.pausedUntil ~= nil and GetTime() < ns.pausedUntil
end

function ns.clearGuard()
  ns.pausedUntil = nil
  ns.slotTouches = {}
  ns.recentSwap = {}
end

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

-- Manual trigger: forget one-shot announces so the report is complete,
-- then run the normal scan (audit/pause/threshold rules all apply).
function ns.checkNow()
  ns.flagged = {}
  ns.scan()
end

function ns.scan()
  if ns.scanning then return end
  local o = ns.opts()
  if not o.enabled then return end
  if not ns.pawnReady() then ns.retrySoon() return end
  if InCombatLockdown() then return end
  ns.trackSwaps()
  ns.scanning = true
  local unsure = false
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        -- Never let one bad item (or Pawn hiccup) abort the scan or wedge
        -- ns.scanning on: failures read as "unsure" and retry later.
        local okEv, ev = pcall(ns.evaluate, link)
        if not okEv or ev == nil then
          unsure = true
        -- Freshly displaced gear is left alone (loop guard), silently.
        elseif ev.upgrade and not ns.recentSwap[link] then
          local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
          local pair = equipLoc and ns.slotPairs[equipLoc]
          if equipLoc == nil or (pair and not o.autoTwoSlot) then
            ns.announce(link, ev)
          elseif pair then
            local slotID = ns.resolveTwoSlotSlot(equipLoc, ev, link)
            local held = slotID and GetInventoryItemLink("player", slotID)
            if slotID and o.keepHeirlooms and ns.isHeirloom(held) then
              ns.announceHeirloom(link, held)
            elseif slotID then
              if ns.equip(link, ev, slotID) then ns.scanning = false return end
            else
              ns.announce(link, ev)
            end
          else
            local slot = equipLoc and ns.primarySlot[equipLoc]
            local held = slot and GetInventoryItemLink("player", slot)
            if o.keepHeirlooms and ns.isHeirloom(held) then
              ns.announceHeirloom(link, held)
            elseif ns.equip(link, ev, nil) then ns.scanning = false return end
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

-- Blizzard Settings panel (Settings > AddOns > VocGear). Built once, after
-- SavedVariables land, and only if the Settings API is present.
-- Re-evaluate when behavior settings change in the panel. Guarded: without
-- setting callbacks the panel still works, just without auto-rescan.
function ns.onSettingChanged(setting, fn)
  if setting and type(setting.SetValueChangedCallback) == "function" then
    setting:SetValueChangedCallback(fn)
  end
end

ns.settingsBuilt = false
function ns.ensureSettings()
  if ns.settingsBuilt then return end
  if type(Settings) ~= "table" then return end
  if type(Settings.RegisterVerticalLayoutCategory) ~= "function" then return end
  local category = Settings.RegisterVerticalLayoutCategory("VocGear")
  Settings.RegisterAddOnCategory(category)
  local db = ns.opts() -- bound, defaulted table
  local function check(key, label, tooltip, onChange)
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_" .. key, key, db, type(defaults[key]), label, defaults[key])
    Settings.CreateCheckbox(category, s, tooltip)
    ns.onSettingChanged(s, onChange or ns.scan)
  end
  check("enabled", "Enable auto-equip", "Equip Pawn-flagged upgrades out of combat.")
  check("announce", "Chat announcements", "Print a line when VocGear equips, picks, or advises.")
  check("audit", "Audit mode", "Announce only: never equip or pick, just say what would happen.")
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_minUpgradePct", "minUpgradePct",
      db, type(defaults.minUpgradePct), "Minimum upgrade %", defaults.minUpgradePct)
    local sliderOpts = Settings.CreateSliderOptions(0, 25, 5)
    -- Right-side value label, like the native sliders. Guarded: without
    -- it the slider still works, just without the number.
    local rightLabel = MinimalSliderWithSteppersMixin
      and MinimalSliderWithSteppersMixin.Label
      and MinimalSliderWithSteppersMixin.Label.Right
    if rightLabel and type(sliderOpts.SetLabelFormatter) == "function" then
      sliderOpts:SetLabelFormatter(rightLabel)
    end
    Settings.CreateSlider(category, s, sliderOpts,
      "Only act on upgrades at or above this Pawn margin (0 = everything Pawn flags).")
    ns.onSettingChanged(s, ns.scan)
  end
  check("autoTwoSlot", "Auto-equip rings and trinkets",
    "Equip into the weaker of the pair instead of announcing.")
  check("includeIlvl", "Include item-level upgrades",
    "Treat Pawn's item-level-only upgrades as upgrades too.")
  check("keepHeirlooms", "Don't replace heirlooms",
    "Keep equipped heirlooms even when something else scores higher.")
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_scale", "scale",
      db, type(defaults.scale), "Pawn scale", defaults.scale)
    Settings.CreateDropdown(category, s, ns.scaleOptions,
      "Which Pawn scale counts. Any visible scale preserves stock behavior.")
    ns.onSettingChanged(s, ns.scan)
  end
  check("sheetButton", "Character sheet button",
    "Show a Check Bags button on the character sheet.",
    function() ns.ensurePaperDollButton() end)
  ns.settingsBuilt = true
  ns.settingsCategory = category
end

function ns.scaleOptions()
  local container = Settings.CreateControlTextContainer()
  container:Add("", "Any visible scale", "Count an upgrade for any of Pawn's visible scales.")
  if ns.pawnReady() then
    local ok, scales = pcall(_G.PawnGetAllScalesEx)
    if ok and type(scales) == "table" then
      for _, sc in ipairs(scales) do
        if type(sc) == "table" and sc.IsVisible and sc.Name then
          container:Add(sc.Name, sc.LocalizedName or sc.Name, "")
        end
      end
    end
  end
  return container:GetData()
end

-- Sit next to Pawn's sheet button (same template family, matched height),
-- following whichever side Pawn is on. Falls back to the sheet bottom.
function ns.placeSheetButton()
  local btn = ns.sheetButton
  if not btn then return end
  btn:ClearAllPoints()
  local pawnBtn = _G.PawnUI_InventoryPawnButton
  local point = pawnBtn and pawnBtn:GetPoint()
  if point == "TOPLEFT" then
    btn:SetPoint("TOPLEFT", pawnBtn, "TOPRIGHT", 2, 0)
  elseif pawnBtn then
    btn:SetPoint("TOPRIGHT", pawnBtn, "TOPLEFT", -2, 0)
  else
    btn:SetPoint("BOTTOM", PaperDollFrame, "BOTTOM", 0, 6)
  end
end

function ns.hookPawnButton()
  if ns.pawnMoveHooked then return end
  if type(_G.PawnUI_InventoryPawnButton_Move) ~= "function" then return end
  ns.pawnMoveHooked = true
  hooksecurefunc("PawnUI_InventoryPawnButton_Move", function() ns.placeSheetButton() end)
end

ns.sheetButton = nil
function ns.ensurePaperDollButton()
  local o = ns.opts()
  if ns.sheetButton then
    ns.sheetButton:SetShown(o.sheetButton ~= false)
    ns.placeSheetButton()
    ns.hookPawnButton()
    return
  end
  if PaperDollFrame == nil then return end
  local btn = CreateFrame("Button", nil, PaperDollFrame, "UIPanelButtonTemplate")
  btn:SetText("Check Bags")
  btn:SetSize(110, 24)
  btn:SetScript("OnClick", function() ns.checkNow() end)
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Find best gear in bags (honors VocGear settings)")
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btn:SetShown(o.sheetButton ~= false)
  ns.sheetButton = btn
  ns.placeSheetButton()
  ns.hookPawnButton()
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
ns.frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    -- The client replaces the SavedVariables global with the loaded table
    -- after our file ran, so rebind or settings never persist.
    if arg1 == name then
      -- A corrupt SavedVariables global (wrong type) resets to defaults
      -- instead of breaking every settings read for the session.
      if type(VocGearDB) ~= "table" then VocGearDB = {} end
      ns.db = VocGearDB ns.ensureSettings()
    end
    -- Cheap and idempotent, so run on every load: covers Pawn's button
    -- appearing late and the lazy Blizzard character UI creating
    -- PaperDollFrame after our own load events fired.
    ns.ensurePaperDollButton()
    if arg1 ~= "Pawn" and arg1 ~= name then return end
  elseif event == "PLAYER_ENTERING_WORLD" then
    ns.ensureSettings() -- in case Settings wasn't up at ADDON_LOADED
    ns.ensurePaperDollButton()
  end
  ns.scan()
end)

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so this
-- cannot be namespaced; the explicit _G marks it as deliberate.
_G.SLASH_VOCGEAR1 = "/vg"
SlashCmdList.VOCGEAR = function(msg)
  local o = ns.opts()
  msg = strtrim(msg or ""):lower()
  if msg == "announce" then
    o.announce = not o.announce
    print("VocGear: announcements " .. (o.announce and "on" or "off"))
  elseif msg == "config" then
    ns.openConfig()
  elseif msg == "scan" then
    ns.checkNow()
  else
    o.enabled = not o.enabled
    print("VocGear: " .. (o.enabled and "on" or "off"))
    if o.enabled then ns.clearGuard() ns.scan() end
  end
end
