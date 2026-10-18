-- VocGear regression tests. Stub-harness: no WoW client needed.
-- Run from anywhere:  lua tests/run.lua   (repo root also fine)
-- Works on Lua 5.1 (the client's dialect) and 5.2+.
--
-- Convention: each test resets stubs, drives ns.* or the frame's OnEvent
-- handler, and asserts. Any failed assert aborts with the test name.

local testDir = debug.getinfo(1, "S").source:gsub("\\", "/"):match("@?(.*/)") or ""
local mainPath = testDir .. "../main.lua"

local passed = 0
local function check(name, cond)
  if not cond then error("FAIL: " .. name, 2) end
  passed = passed + 1
end

-- Fresh stub world per test.
local function loadAddon(world)
  local g = {}
  for k, v in pairs(_G) do g[k] = v end -- inherit stdlib (string, table...)
  g._G = g
  g.print = function(...) world.printed[#world.printed + 1] = table.concat({...}, " ") end
  g.strtrim = function(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end
  g.NUM_BAG_SLOTS = 4
  g.C_Container = {
    GetContainerNumSlots = function(bag) return #(world.bags[bag] or {}) end,
    GetContainerItemLink = function(bag, slot)
      local b = world.bags[bag]
      return b and b[slot] or nil
    end,
  }
  g.C_Item = {
    GetItemInfoInstant = function(link) return world.itemIDs[link], nil, nil, world.slots[link], nil, world.classIDs[link], world.subclassIDs[link] end,
    GetItemInfo = function(link)
      return link, link, world.rarities[link], 80, world.minLevels[link],
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, world.setIDs[link]
    end,
    GetDetailedItemLevelInfo = function(link) return world.levels[link] end,
    GetItemUniquenessByID = function(link) return world.uniqueness[link] end,
    IsEquippableItem = function(link) return not world.notEquippable[link] end,
    GetItemSetInfo = function(setID) return world.setNames[setID] end,
    GetSetBonusesForSpecializationByItemID = function(specID, itemID)
      world.lastBonusSpec = specID
      return world.setBonusSpells[itemID]
    end,
  }
  g.C_SpecializationInfo = {
    GetSpecialization = function() return world.specIndex end,
    GetSpecializationInfo = function() return world.specID end,
  }
  g.C_PetBattles = { IsInBattle = function() return world.petBattle end }
  g.UnitLevel = function() return world.playerLevel end
  g.UnitClass = function() return "Warrior", world.playerClass or "WARRIOR" end
  g.UnitIsDeadOrGhost = function() return world.dead end
  g.PlaySound = function(id) world.playedSounds[#world.playedSounds + 1] = id end
  g.C_AddOns = {
    IsAddOnLoaded = function(n) return world.loadedAddons and world.loadedAddons[n] or false end,
    GetAddOnInfo = function(n)
      local a = world.installedAddons and world.installedAddons[n]
      if not a then return nil end
      return n, n, "", a.loadable
    end,
  }
  g.CreateSettingsListSectionHeaderInitializer = function(text)
    world.headerNotes[#world.headerNotes + 1] = text
    return {}
  end
  g.SettingsPanel = {
    GetLayout = function(_)
      return { AddInitializer = function(_, _) end }
    end,
  }
  g.GetTime = function() return world.time end
  g.InCombatLockdown = function() return world.inCombat end
  -- Game-chosen equip slot per equip loc, mirroring Pawn's slot table.
  local equipLocSlot = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
    INVTYPE_SHIELD = 17, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = world.rangedSlot or 16,
    INVTYPE_RANGEDRIGHT = world.rangedSlot or 16 }
  local equipStub = function(item, slot)
    world.equipped[#world.equipped + 1] = { item = item, slot = slot }
    -- Like the real client, the equipped item leaves the bags.
    for _, b in pairs(world.bags) do
      for i = #b, 1, -1 do
        if b[i] == item then table.remove(b, i) end
      end
    end
    -- ...and the displaced item lands back in the bags.
    local s = slot or equipLocSlot[world.slots[item]]
    if s then
      local prev = world.equippedSlots[s]
      world.equippedSlots[s] = item
      if prev then
        world.bags[0] = world.bags[0] or {}
        world.bags[0][#world.bags[0] + 1] = prev
      end
    end
  end
  g.C_Item.EquipItemByName = equipStub -- C_Item.EquipItemByName, ItemDocumentation
  g.GetInventoryItemLink = function(_, slot) return world.equippedSlots[slot] end
  g.C_Timer = {
    After = function(_, fn) world.timers[#world.timers + 1] = fn end,
  }
  g.C_PaperDollInfo = {
    GetInventorySlotInfo = function(_) return world.rangedSlot end,
  }
  g.Enum = { CachedRewardType = { Item = 1, Currency = 2 } }
  g.C_WeeklyRewards = {
    GetActivities = function() return world.vaultActivities end,
    GetItemHyperlink = function(itemDBID) return world.vaultLinks[itemDBID] end,
    CanClaimRewards = function() return world.vaultClaimable end,
  }
  g.SlashCmdList = {}
  g.CreateFrame = function(ftype, _, _, template)
    local f = { events = {}, scripts = {}, ctype = ftype, template = template }
    f.RegisterEvent = function(_, e) f.events[e] = true end
    f.SetScript = function(_, name, fn) f.scripts[name] = fn end
    f.SetText = function(_, t) f.text = t end
    f.SetSize = function(_, w, h) f.size = { w, h } end
    f.SetPoint = function(_, ...) f.point = { ... } end
    f.ClearAllPoints = function() f.point = nil end
    f.SetShown = function(_, s) f.shown = s end
    world.frames[#world.frames + 1] = f
    return f
  end
  g.GameTooltip = {
    SetOwner = function(_, owner, anchor) world.gametip.owner, world.gametip.anchor = owner, anchor end,
    SetText = function(_, t, r, gg, b) world.gametip.text = t world.gametip.titleColor = { r, gg, b } end,
    AddLine = function(_, t) world.gametip.lines[#world.gametip.lines + 1] = t end,
    Show = function() world.gametip.shown = true end,
    Hide = function() world.gametip.shown = false end,
  }
  if world.withPaperDoll then g.PaperDollFrame = {} end
  g.hooksecurefunc = function(fname, fn) world.hooks[fname] = fn end
  if world.pawnBtn then
    g.PawnUI_InventoryPawnButton = {
      GetPoint = function() return world.pawnBtn.point end,
    }
    g.PawnUI_InventoryPawnButton_Move = function() end
  end
  -- Pawn stubs (nil them out to simulate Pawn missing/not ready).
  g.PawnGetItemData = world.pawn and
    function(link)
      if world.pawnNil[link] then return nil end
      return { Link = link, Level = world.levels[link] or 80, CanEquip = world.canEquip[link] }
    end or nil
  g.PawnIsItemAnUpgrade = world.pawn and
    function(item) return world.upgradeLists[item.Link] end or nil
  g.PawnIsItemAnItemLevelUpgrade = world.pawn and
    function(item) return world.ilvlDiffs[item.Link] end or nil
  g.PawnGetAllScalesEx = world.pawn and
    function() return world.scales end or nil
  g.PawnUnenchantItemLink = world.pawn and
    function(link, evenIf)
      if type(link) ~= "string" then return nil end
      local target = link:match("|H(.-)|h") or link
      local _, _, id, e, g1, g2, g3, g4, rest = target:find("^item:(%-?%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(.*)")
      if not id then return nil end
      if evenIf or (e ~= "0" and e ~= "" and e ~= nil) or (g1 ~= "0" and g1 ~= "" and g1 ~= nil)
          or (g2 ~= "0" and g2 ~= "" and g2 ~= nil) or (g3 ~= "0" and g3 ~= "" and g3 ~= nil)
          or (g4 ~= "0" and g4 ~= "" and g4 ~= nil) then
        return "item:" .. id .. "::::::" .. (rest or "")
      end
      return nil
    end or nil
  g.PawnGetBestItemLink = world.pawn and
    function(scale, invType, index, doNotRescan)
      world.bestLinkCalls[#world.bestLinkCalls + 1] =
        { scale = scale, invType = invType, index = index, doNotRescan = doNotRescan }
      return (world.bestLinks[scale] or {})[invType]
    end or nil
  g.PawnIsArmorBestTypeForPlayer = world.pawn and
    function(item)
      local b = world.armorBest[item.Link]
      if b == nil then return true end -- best type unless a test says otherwise
      return b
    end or nil
  if world.withSettings then
    local S = {}
    S.RegisterVerticalLayoutCategory = function(n)
      world.settingsCat = n
      return { GetID = function() return 99 end }
    end
    S.RegisterAddOnCategory = function() world.settingsCatRegistered = true end
    S.RegisterAddOnSetting = function(_, var, key, tbl, typ, label, default)
      world.settingsReg[#world.settingsReg + 1] =
        { var = var, key = key, type = typ, label = label, default = default }
      if tbl[key] == nil then tbl[key] = default end
      local s = {}
      s.SetValueChangedCallback = function(_, fn) world.settingCallbacks[var] = fn end
      return s
    end
    S.CreateCheckbox = function() world.settingsChecks = world.settingsChecks + 1 end
    S.CreateSliderOptions = function(min, max, step)
      world.sliderOpts = { min = min, max = max, step = step }
      if not world.noSliderFormatter then world.sliderOpts.SetLabelFormatter = function(_, f) world.sliderFormatter = f end end
      return world.sliderOpts
    end
    g.MinimalSliderWithSteppersMixin = { Label = { Right = "RIGHT" } }
    S.CreateSlider = function() world.settingsSliders = world.settingsSliders + 1 end
    S.CreateDropdown = function(_, _, getOptions)
      world.settingsDropdowns[#world.settingsDropdowns + 1] = getOptions
    end
    S.CreateControlTextContainer = function()
      local t = { data = {} }
      t.Add = function(_, value, text, tip) t.data[#t.data + 1] = { value = value, text = text, tip = tip } end
      t.GetData = function() return t.data end
      return t
    end
    g.Settings = S
  end
  g.VocGearDB = nil -- client hasn't restored SavedVariables at file-exec time

  local f = assert(io.open(mainPath, "r"))
  local src = f:read("*a")
  f:close()
  -- 5.1 sandboxes with setfenv; 5.2+ takes the env as load's 4th arg.
  local chunk
  if setfenv then
    chunk = assert(loadstring(src, "@" .. mainPath))
    setfenv(chunk, g)
  else
    chunk = assert(load(src, "@" .. mainPath, "t", g))
  end
  local ns = {}
  chunk("VocGear", ns)
  world.frame = world.frames[1] -- the event frame, created at load
  world.frame.onEvent = function(...)
    return world.frames[1].scripts.OnEvent(...)
  end
  world.ns = ns
  world.env = g
  return ns
end

local function newWorld()
  return { bags = {}, slots = {}, minLevels = {}, levels = {}, classIDs = {}, subclassIDs = {}, time = 1000,
           equippedSlots = {}, equipped = {}, printed = {}, timers = {},
           inCombat = false, dead = false, petBattle = false, pawn = true, pawnNil = {}, upgradeLists = {},
           armorBest = {}, rarities = {}, uniqueness = {}, notEquippable = {},
           bestLinks = {}, bestLinkCalls = {}, canEquip = {},
           setIDs = {}, itemIDs = {}, setBonusSpells = {}, setNames = {},
           specIndex = nil, specID = nil, lastBonusSpec = nil,
           ilvlDiffs = {}, scales = {}, savedVars = nil, playerLevel = 80,
           withSettings = false, settingsReg = {}, settingsChecks = 0,
           settingsSliders = 0, settingsDropdowns = {}, settingCallbacks = {},
           frames = {}, gametip = { lines = {} }, withPaperDoll = false,
           hooks = {}, pawnBtn = nil, playerClass = nil,
           loadedAddons = nil, installedAddons = nil, headerNotes = {},
           playedSounds = {}, vaultActivities = {}, vaultClaimable = false,
           vaultLinks = {} }
end

-- Simulate the client deserializing SavedVariables (a FRESH table replaces
-- the file-top default) and then firing ADDON_LOADED.
local function clientLoaded(w)
  w.env.VocGearDB = w.savedVars or {}
  w.frame.onEvent(nil, "ADDON_LOADED", "VocGear")
end

local function upgrade(scale, pct, existing)
  return { { ScaleName = scale, PercentUpgrade = pct, ExistingItemLink = existing } }
end

-- Tier piece factory for set tests: unique link + itemID, set membership,
-- and (unless bonuses == false) two bonus spells for the current spec.
local tierSeq = 90000
local function tierPiece(w, setID, bonuses)
  tierSeq = tierSeq + 1
  local link = "|cffa335ee|Hitem:" .. tierSeq .. "|h[Tier " .. tierSeq .. "]|h|r"
  w.setIDs[link] = setID
  w.itemIDs[link] = tierSeq
  if bonuses ~= false then w.setBonusSpells[tierSeq] = { 1101, 1102 } end
  return link
end

-- Every set test plays a character with a spec selected.
local function specReady(w, specID)
  w.specIndex = 1
  w.specID = specID or 70
end

-- 1. SavedVariables rebind.
do
  local w = newWorld()
  w.savedVars = { enabled = false, announce = false }
  local ns = loadAddon(w)
  clientLoaded(w)
  check("db rebind keeps saved enabled=false", ns.opts().enabled == false)
  check("db rebind keeps saved announce=false", ns.opts().announce == false)
end

-- 2. Fresh profile gets all defaults.
do
  local w = newWorld()
  w.savedVars = {}
  local ns = loadAddon(w)
  clientLoaded(w)
  local o = ns.opts()
  check("default enabled", o.enabled == true)
  check("default announce", o.announce == true)
  check("default audit off", o.audit == false)
  check("default threshold 0", o.minUpgradePct == 0)
  check("default two-slot manual", o.autoTwoSlot == false)
  check("default ilvl on", o.includeIlvl == true)
  check("default scale any", o.scale == "")
  check("default keepHeirlooms", o.keepHeirlooms == true)
  check("default sheetButton", o.sheetButton == true)
  check("default protectSets", o.protectSets == true)
  check("default swapWeapons", o.swapWeapons == true)
  check("default equipSound quest chime", o.equipSound == "878")
end

-- 3. Single-slot upgrade equipped by full link, margin in the message.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:12345:0:0:0:0:0:0:0:80|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("equips exactly one item", #w.equipped == 1)
  check("equips by full link", w.equipped[1].item == link)
  check("no forced slot", w.equipped[1].slot == nil)
  check("margin printed", w.printed[1]:find("%+5%.0%%%)", 1) ~= nil)
end

-- 4. Percent threshold gates equips.
do
  local w = newWorld()
  w.savedVars = { minUpgradePct = 5 }
  local link = "|cffa335ee|Hitem:555|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.04) -- 4% < 5% bar
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("below-threshold skipped", #w.equipped == 0)
  check("below-threshold silent", #w.printed == 0)
  w.upgradeLists[link] = upgrade("A", 0.05) -- exactly 5%
  ns.scan()
  check("at-threshold equipped", #w.equipped == 1)
end

-- 5. Scale filter.
do
  local w = newWorld()
  w.savedVars = { scale = "Mine" }
  local link = "|cffa335ee|Hitem:556|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("Other", 0.5)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("other-scale entry ignored", #w.equipped == 0)
  w.upgradeLists[link] = upgrade("Mine", 0.5)
  ns.scan()
  check("chosen-scale entry equipped", #w.equipped == 1)
end

-- 6. Item-level upgrades follow their toggle.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:557|h[Trinket]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD" -- score path empty, ilvl path decides
  w.upgradeLists[link] = nil
  w.ilvlDiffs[link] = 5
  local ns = loadAddon(w)
  ns.scan()
  check("ilvl upgrade equipped by default", #w.equipped == 1)
  check("ilvl margin printed", w.printed[1]:find("item level %+5", 1) ~= nil)
end

-- 7. Item-level upgrades can be excluded.
do
  local w = newWorld()
  w.savedVars = { includeIlvl = false }
  local link = "|cffa335ee|Hitem:558|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = nil
  w.ilvlDiffs[link] = 5
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("ilvl upgrade skipped when excluded", #w.equipped == 0)
end

-- 8. Above-level items are never upgrades.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:559|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.minLevels[link] = 85
  w.upgradeLists[link] = upgrade("A", 0.5)
  local ns = loadAddon(w)
  ns.scan()
  check("above-level skipped", #w.equipped == 0)
end

-- 9. Pawn unsure: skip + retry, never equip.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:560|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.pawnNil[link] = true
  local ns = loadAddon(w)
  ns.scan()
  check("unsure equips nothing", #w.equipped == 0)
  check("unsure schedules retry", #w.timers == 1)
end

-- 10. Rings/trinkets: announced per link, never equipped, by default.
do
  local w = newWorld()
  local r1 = "|cffa335ee|Hitem:777:0:0:0:0:0:0:0:80|h[Ring A]|h|r"
  local r2 = "|cffa335ee|Hitem:777:0:0:0:0:0:0:0:85|h[Ring B]|h|r"
  w.bags[0] = { r1, r2 }
  w.slots[r1], w.slots[r2] = "INVTYPE_FINGER", "INVTYPE_FINGER"
  w.upgradeLists[r1], w.upgradeLists[r2] = upgrade("A", 0.05), upgrade("A", 0.06)
  local ns = loadAddon(w)
  ns.scan()
  check("two-slot items never equipped", #w.equipped == 0)
  check("both bonus variants announced", #w.printed == 2)
  ns.scan()
  check("announces are once per session per link", #w.printed == 2)
end

-- 11. Two-slot auto: equip into the slot Pawn says it replaces.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, ringB)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("two-slot auto equips", #w.equipped == 1)
  check("equips into replaced slot", w.equipped[1].slot == 12)
  check("equips exact link", w.equipped[1].item == cand)
end

-- 12. Two-slot auto: empty slot wins when Pawn names nothing.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  w.equippedSlots[11] = ringA
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = { { ScaleName = "A", PercentUpgrade = 100 } } -- big: empty slot
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("empty slot equipped", #w.equipped == 1)
  check("empty slot targeted", w.equipped[1].slot == 12)
end

-- 13. Two-slot auto: unresolvable falls back to announce.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local t1 = "|cff0070dd|Hitem:200|h[Trinket A]|h|r"
  local t2 = "|cff0070dd|Hitem:201|h[Trinket B]|h|r"
  local cand = "|cffa335ee|Hitem:202|h[Trinket C]|h|r"
  w.equippedSlots[13], w.equippedSlots[14] = t1, t2
  w.levels[t1], w.levels[t2], w.levels[cand] = 100, 100, 90 -- weaker than both
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_TRINKET"
  w.upgradeLists[cand] = nil
  w.ilvlDiffs[cand] = 3 -- Pawn's tracker says upgrade, but not vs equipped
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("weaker candidate not equipped", #w.equipped == 0)
  check("weaker candidate announced", #w.printed == 1)
end

-- 14. Unknown slot: announce, don't blind-equip.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:999|h[Oddity]|h|r"
  w.bags[0] = { link }
  w.slots[link] = nil
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("unknown slot never equipped", #w.equipped == 0)
  check("unknown slot announced", #w.printed == 1)
end

-- 15. Audit mode: report, never act.
do
  local w = newWorld()
  w.savedVars = { audit = true }
  local link = "|cffa335ee|Hitem:333|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  ns.scan()
  check("audit equips nothing", #w.equipped == 0)
  check("audit reports once", #w.printed == 1)
  check("audit wording", w.printed[1]:find("would equip", 1) ~= nil)
end

-- 16. Combat lockdown: no equip attempts.
do
  local w = newWorld()
  w.inCombat = true
  local link = "|cffa335ee|Hitem:334|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("no equip in combat", #w.equipped == 0)
end
-- 16b. Combat starting mid-scan: the entry check already passed, so the
-- equip-time guard must still refuse (otherwise the client fires
-- ADDON_ACTION_FORBIDDEN through BugGrabber).
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:335|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  local realEvaluate = ns.evaluate
  ns.evaluate = function(l)
    w.inCombat = true -- combat starts after the scan's entry check
    return realEvaluate(l)
  end
  ns.scan()
  check("no equip when combat starts mid-scan", #w.equipped == 0)
end

-- 17. Pawn missing: the built-in fallback drives, not idle.
do
  local w = newWorld()
  w.pawn = false
  local link = "|cffa335ee|Hitem:444|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.levels[link] = 100 -- empty slot: equips
  w.classIDs[link], w.subclassIDs[link] = 4, 4
  local ns = loadAddon(w)
  check("pawnReady false without Pawn", ns.pawnReady() == false)
  check("fallback drives", ns.pawnReady() == false and ns.sourceLabel() == "item level")
  ns.scan()
  check("empty slot equips in fallback", #w.equipped == 1)
end

-- 18. Disabled addon: full no-op.
do
  local w = newWorld()
  w.savedVars = { enabled = false }
  local link = "|cffa335ee|Hitem:666|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("disabled addon equips nothing", #w.equipped == 0)
end


-- 19. Settings panel registers all ten options.
do
  local w = newWorld()
  w.withSettings = true
  w.scales = {
    { Name = "B", LocalizedName = "Bee", IsVisible = false },
    { Name = "A", LocalizedName = "Aye", IsVisible = true },
  }
  local ns = loadAddon(w)
  clientLoaded(w)
  check("settings built", ns.settingsBuilt == true)
  check("category registered", w.settingsCat == "VocGear" and w.settingsCatRegistered)
  local keys = {}
  for _, r in ipairs(w.settingsReg) do keys[r.key] = r end
  for _, k in ipairs({ "enabled", "announce", "audit", "minUpgradePct",
      "autoTwoSlot", "includeIlvl", "keepHeirlooms", "protectSets", "swapWeapons", "scale", "sheetButton" }) do
    check("setting registered: " .. k, keys[k] ~= nil)
  end
  check("nine checkboxes", w.settingsChecks == 9)
  check("one slider", w.settingsSliders == 1)
  check("slider range", w.sliderOpts.min == 0 and w.sliderOpts.max == 25
    and w.sliderOpts.step == 5)
  check("slider value label", w.sliderFormatter == "RIGHT")
  check("two dropdowns", #w.settingsDropdowns == 2)
  local scaleData = w.settingsDropdowns[1]()
  check("scale dropdown has Any + visible",
    #scaleData == 2 and scaleData[1].value == "" and scaleData[2].value == "A")
  local soundData = w.settingsDropdowns[2]()
  check("sound dropdown has Off + chimes",
    #soundData == 4 and soundData[1].value == "0" and soundData[2].value == "878")
  check("callbacks attached", (function()
    for _, r in ipairs(w.settingsReg) do
      if not w.settingCallbacks[r.var] then return false end
    end
    return #w.settingsReg == 12
  end)())
  local clink = "|cffa335ee|Hitem:710|h[Helm]|h|r"
  w.bags[0] = { clink }
  w.slots[clink] = "INVTYPE_HEAD"
  w.upgradeLists[clink] = upgrade("A", 0.05)
  w.settingCallbacks["VocGear_minUpgradePct"]()
  check("setting callback rescans", #w.equipped == 1)
  w.settingCallbacks["VocGear_sheetButton"]()
  check("sheet callback safe without frame", ns.sheetButton == nil)
  check("built once", (function()
    local n = #w.settingsReg
    w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
    return #w.settingsReg == n
  end)())
end

-- 20. Slash commands: toggle, on/off, announce, config hint, help.
do
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  w.env.SlashCmdList.VOCGEAR("")
  check("/vg toggles off", ns.opts().enabled == false)
  check("/vg says so", w.printed[#w.printed]:find("auto%-equip off", 1) ~= nil)
  w.env.SlashCmdList.VOCGEAR(" ON ")
  check("/vg on sets explicitly", ns.opts().enabled == true)
  w.env.SlashCmdList.VOCGEAR("off")
  check("/vg off sets explicitly", ns.opts().enabled == false)
  w.env.SlashCmdList.VOCGEAR("announce")
  check("/vg announce toggles", ns.opts().announce == false)
  check("toggles confirm with the checkbox pair (numeric fallback, no SOUNDKIT)",
    table.concat(w.playedSounds, ",") == "857,856,857,857")
  w.env.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1856 }
  w.env.SlashCmdList.VOCGEAR("announce")
  check("SOUNDKIT name wins over the fallback", w.playedSounds[#w.playedSounds] == 1856)
  w.env.SlashCmdList.VOCGEAR("config")
  check("/vg config prints hint without Settings",
    w.printed[#w.printed]:find("Settings > AddOns", 1) ~= nil)
  local before = #w.printed
  w.env.SlashCmdList.VOCGEAR("confg") -- typo: help, never a toggle
  check("unknown subcommand prints help", #w.printed == before + 1 + #ns.HELP)
  check("unknown subcommand never toggles", ns.opts().enabled == false)
  before = #w.printed
  w.env.SlashCmdList.VOCGEAR("help")
  check("/vg help lists every command", #w.printed == before + 1 + #ns.HELP)
  check("short and long slash registered",
    w.env.SLASH_VOCGEAR1 == "/vg" and w.env.SLASH_VOCGEAR2 == "/vocgear"
    and w.env.SLASH_VOCGEAR3 == nil)
end

-- 20b. Chat voice: colored addon prefix, then the message.
do
  local w = newWorld()
  local ns = loadAddon(w)
  ns.say("hello")
  check("say prefixes the addon name",
    w.printed[1] == "|c" .. ns.PREFIX_COLOR .. "VocGear|r: hello")
  check("family prefix color", ns.PREFIX_COLOR == "ff66ccff")
end

-- 21. Swap memory breaks A<->B ping-pong, then expires.
do
  local w = newWorld()
  local helmA = "|cff0070dd|Hitem:500|h[Helm A]|h|r"
  local helmB = "|cffa335ee|Hitem:501|h[Helm B]|h|r"
  w.equippedSlots[1] = helmA
  w.bags[0] = { helmB }
  w.slots[helmA], w.slots[helmB] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  w.upgradeLists[helmA], w.upgradeLists[helmB] = upgrade("Y", 0.05), upgrade("X", 0.05)
  local ns = loadAddon(w)
  ns.scan() -- equips B, displaces A back to bags
  check("first equip happens", #w.equipped == 1)
  ns.scan() -- A flagged by Pawn but freshly displaced: left alone
  check("ping-pong broken", #w.equipped == 1)
  w.time = w.time + 31
  ns.scan() -- memory expired: A equips again
  check("memory expires", #w.equipped == 2)
end

-- 22. Player's own manual swaps are respected, not attributed.
do
  local w = newWorld()
  local helmA = "|cff0070dd|Hitem:500|h[Helm A]|h|r"
  local helmB = "|cffa335ee|Hitem:501|h[Helm B]|h|r"
  w.equippedSlots[1] = helmA
  w.bags[0] = {}
  w.slots[helmA] = "INVTYPE_HEAD"
  w.upgradeLists[helmA] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan() -- baseline snapshot
  w.equippedSlots[1] = helmB -- player swaps manually; A lands in bags
  w.bags[0] = { helmA }
  ns.scan()
  check("manual swap not yanked back", #w.equipped == 0)
  check("manual swap unattributed", ns.slotTouches[1] == nil)
end

-- 23. Breaker trips on 3 same-slot equips, pauses, then resumes.
-- Consecutive scans can no longer churn one slot (the settle defers them),
-- so each follow-up equip lands on a later scan past the settle but still
-- inside the breaker window: the breaker stays the slow-burn backstop.
do
  local w = newWorld()
  local mk = function(id) return "|cffa335ee|Hitem:" .. id .. "|h[Helm " .. id .. "]|h|r" end
  local a, b, c, d = mk(510), mk(511), mk(512), mk(513)
  w.equippedSlots[1] = a
  w.bags[0] = { b, c, d }
  for _, l in ipairs({ a, b, c, d }) do
    w.slots[l] = "INVTYPE_HEAD"
    w.upgradeLists[l] = upgrade("A", 0.05)
  end
  local ns = loadAddon(w)
  ns.scan() -- equips B
  w.time = w.time + 1
  ns.scan() -- sees B's touch; C waits out the settle
  check("settle defers churn", #w.equipped == 1)
  w.time = w.time + 10
  ns.scan() -- equips C
  w.time = w.time + 1
  ns.scan() -- sees C's touch; D waits
  w.time = w.time + 10
  ns.scan() -- equips D
  ns.scan() -- sees 3rd touch: trips
  check("breaker trips", ns.isPaused())
  check("trip announced", w.printed[#w.printed]:find("loop detected", 1) ~= nil)
  check("trip stops equips", #w.equipped == 3)
  w.time = w.time + 61
  ns.scan() -- pause + memory expired: equips again
  check("auto-resumes after pause", #w.equipped == 4)
end

-- 24. Manual swaps never trip the breaker.
do
  local w = newWorld()
  w.equippedSlots[1] = "|cff0070dd|Hitem:520|h[A]|h|r"
  local ns = loadAddon(w)
  ns.scan()
  for i = 1, 3 do
    w.equippedSlots[1] = "|cff0070dd|Hitem:" .. (520 + i) .. "|h[M" .. i .. "]|h|r"
    ns.scan()
  end
  check("manual swaps don't pause", not ns.isPaused())
end

-- 25. Re-enabling clears the guard (/vg twice, or /vg on, resumes now).
do
  local w = newWorld()
  local ns = loadAddon(w)
  ns.pausedUntil = w.time + 60
  ns.recentSwap["|cff0070dd|Hitem:1|h[X]|h|r"] = w.time
  check("paused", ns.isPaused())
  w.env.SlashCmdList.VOCGEAR("")
  w.env.SlashCmdList.VOCGEAR("")
  check("re-enable clears pause", not ns.isPaused())
  check("re-enable clears memory", next(ns.recentSwap) == nil)
  ns.pausedUntil = w.time + 60
  w.env.SlashCmdList.VOCGEAR("on") -- already on: still a resume
  check("/vg on clears pause while enabled", not ns.isPaused())
end

-- 26. Wrong armor type: item-level upgrades skipped, score path trusts Pawn.
do
  local w = newWorld()
  local cloth = "|cffa335ee|Hitem:600|h[Cloth Helm]|h|r"
  w.bags[0] = { cloth }
  w.slots[cloth] = "INVTYPE_HEAD"
  w.upgradeLists[cloth] = nil
  w.ilvlDiffs[cloth] = 8
  w.armorBest[cloth] = false -- e.g. plate wearer, cloth helm
  local ns = loadAddon(w)
  ns.scan()
  check("wrong-armor ilvl skipped", #w.equipped == 0)
  check("wrong-armor ilvl silent", #w.printed == 0)
end
do
  local w = newWorld()
  local helm = "|cffa335ee|Hitem:601|h[Helm]|h|r"
  w.bags[0] = { helm }
  w.slots[helm] = "INVTYPE_HEAD"
  w.upgradeLists[helm] = upgrade("A", 0.05)
  w.armorBest[helm] = false -- Pawn pre-gates score entries itself; pass through
  local ns = loadAddon(w)
  ns.scan()
  check("score path trusts Pawn's own gate", #w.equipped == 1)
end
do
  local w = newWorld()
  local helm = "|cffa335ee|Hitem:602|h[Helm]|h|r"
  w.bags[0] = { helm }
  w.slots[helm] = "INVTYPE_HEAD"
  w.upgradeLists[helm] = nil
  w.ilvlDiffs[helm] = 8
  local ns = loadAddon(w)
  w.env.PawnIsArmorBestTypeForPlayer = nil -- older Pawn without the API
  ns.scan()
  check("missing armor API fails open", #w.equipped == 1)
end

-- 27. Equipped heirlooms are kept by default.
do
  local w = newWorld()
  local heir = "|cffa335ee|Hitem:700|h[Heirloom Helm]|h|r"
  local cand = "|cffa335ee|Hitem:701|h[Helm]|h|r"
  w.equippedSlots[1] = heir
  w.rarities[heir] = 7
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.upgradeLists[cand] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  ns.scan()
  check("heirloom not replaced", #w.equipped == 0)
  check("heirloom keep announced once", #w.printed == 1)
  check("heirloom wording", w.printed[1]:find("keeping heirloom", 1) ~= nil)
end
do
  local w = newWorld()
  w.savedVars = { keepHeirlooms = false }
  local heir = "|cffa335ee|Hitem:700|h[Heirloom Helm]|h|r"
  local cand = "|cffa335ee|Hitem:701|h[Helm]|h|r"
  w.equippedSlots[1] = heir
  w.rarities[heir] = 7
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.upgradeLists[cand] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("heirloom replaced when unprotected", #w.equipped == 1)
end
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local heirRing = "|cffa335ee|Hitem:702|h[Heirloom Ring]|h|r"
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local cand = "|cffa335ee|Hitem:703|h[Ring C]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, heirRing
  w.rarities[heirRing] = 7
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, heirRing)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("two-slot heirloom not replaced", #w.equipped == 0)
  check("two-slot heirloom announced", #w.printed == 1)
end

-- 28. Manual trigger re-reports and /vg scan equips.
do
  local w = newWorld()
  local r1 = "|cffa335ee|Hitem:777|h[Ring]|h|r"
  w.bags[0] = { r1 }
  w.slots[r1] = "INVTYPE_FINGER"
  w.upgradeLists[r1] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  ns.scan()
  check("announce consumed", #w.printed == 1)
  ns.checkNow()
  check("checkNow re-announces", #w.printed == 2)
end
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:701|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  loadAddon(w)
  w.env.SlashCmdList.VOCGEAR("scan")
  check("/vg scan equips", #w.equipped == 1)
end

-- 29. Character-sheet button.
do
  local w = newWorld()
  w.withPaperDoll = true
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("button created", ns.sheetButton ~= nil)
  check("button labeled", ns.sheetButton.text == "Check Bags")
  check("button shown by default", ns.sheetButton.shown == true)
  local link = "|cffa335ee|Hitem:701|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  ns.sheetButton.scripts.OnClick()
  check("button click scans", #w.equipped == 1)
  ns.sheetButton.scripts.OnEnter(ns.sheetButton)
  check("tooltip shows", w.gametip.shown == true)
  check("tooltip title", w.gametip.text == "Check Bags"
    and w.gametip.titleColor[1] == 1 and w.gametip.titleColor[2] == 0.82 and w.gametip.titleColor[3] == 0)
  check("tooltip line", (w.gametip.lines[1] or ""):find("best gear in your bags", 1) ~= nil)
  check("click confirms audibly, then the equip chime",
    w.playedSounds[1] == 856 and w.playedSounds[2] == 878)
  ns.sheetButton.scripts.OnLeave()
  check("tooltip hides", w.gametip.shown == false)
end
do
  local w = newWorld()
  w.withPaperDoll = true
  w.savedVars = { sheetButton = false }
  local ns = loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("button hidden when disabled", ns.sheetButton.shown == false)
end
do
  local w = newWorld()
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("no frame, no button, no error", ns.sheetButton == nil)
end


-- 30. Sheet button sits next to Pawn's button.
do
  local w = newWorld()
  w.withPaperDoll = true
  w.pawnBtn = { point = "TOPRIGHT" } -- Pawn on the right, below trinket
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  local pt = ns.sheetButton.point
  check("right-side Pawn: ours goes left",
    pt[1] == "TOPRIGHT" and pt[3] == "TOPLEFT" and pt[4] == -2)
  check("hook installed", w.hooks["PawnUI_InventoryPawnButton_Move"] ~= nil)
  check("matched height", ns.sheetButton.size[2] == 24)
  w.pawnBtn.point = "TOPLEFT" -- user moves Pawn left; hook re-places us
  w.hooks["PawnUI_InventoryPawnButton_Move"]()
  pt = ns.sheetButton.point
  check("left-side Pawn: ours goes right",
    pt[1] == "TOPLEFT" and pt[3] == "TOPRIGHT" and pt[4] == 2)
end
do
  local w = newWorld()
  w.withPaperDoll = true
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("no Pawn: sheet-bottom fallback", ns.sheetButton.point[1] == "BOTTOM")
  w.env.PawnUI_InventoryPawnButton = { GetPoint = function() return "TOPRIGHT" end }
  w.env.PawnUI_InventoryPawnButton_Move = function() end
  w.frame.onEvent(nil, "ADDON_LOADED", "Pawn")
  local pt = ns.sheetButton.point
  check("late Pawn re-anchors", pt[1] == "TOPRIGHT" and pt[3] == "TOPLEFT")
  check("late hook installs", w.hooks["PawnUI_InventoryPawnButton_Move"] ~= nil)
end

-- 31. Corrupt SavedVariables recover to defaults.
do
  local w = newWorld()
  local ns = loadAddon(w)
  w.env.VocGearDB = "corrupt" -- client restored garbage
  w.frame.onEvent(nil, "ADDON_LOADED", "VocGear")
  local o = ns.opts()
  check("corrupt global replaced", type(w.env.VocGearDB) == "table")
  check("corrupt global defaults", o.enabled == true and o.minUpgradePct == 0 and o.scale == "")
  ns.db = 42 -- belt: a non-table db heals the same way
  o = ns.opts()
  check("non-table db healed", type(ns.db) == "table" and o.enabled == true)
end
do
  local w = newWorld()
  w.savedVars = { enabled = "yes", minUpgradePct = "high", scale = 42, audit = 1 }
  local ns = loadAddon(w)
  clientLoaded(w)
  local o = ns.opts()
  check("wrong-type enabled reset", o.enabled == true)
  check("wrong-type threshold reset", o.minUpgradePct == 0)
  check("wrong-type scale reset", o.scale == "")
  check("wrong-type audit reset", o.audit == false)
  ns.db.minUpgradePct = 500
  check("threshold above slider range reset", ns.opts().minUpgradePct == 0)
  ns.db.minUpgradePct = -5
  check("threshold below slider range reset", ns.opts().minUpgradePct == 0)
  ns.db.minUpgradePct = 15
  check("threshold inside slider range kept", ns.opts().minUpgradePct == 15)
end

-- 32. Malformed Pawn answers never wedge the scan.
do
  local w = newWorld()
  local bad = "|cffa335ee|Hitem:800|h[Bad]|h|r"
  local good = "|cffa335ee|Hitem:801|h[Good]|h|r"
  w.bags[0] = { bad, good }
  w.slots[bad], w.slots[good] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  w.upgradeLists[bad] = "not-a-table" -- Pawn drifted its return shape
  w.upgradeLists[good] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("malformed entry skipped", #w.equipped == 1 and w.equipped[1].item == good)
  check("scan not wedged", ns.scanning == false)
  ns.scan()
  check("second scan still runs", ns.scanning == false)
end
do
  local w = newWorld()
  local bad = "|cffa335ee|Hitem:802|h[Bad]|h|r"
  w.bags[0] = { bad }
  w.slots[bad] = "INVTYPE_HEAD"
  w.upgradeLists[bad] = { "not-an-entry-table", 42 }
  local ns = loadAddon(w)
  ns.scan()
  check("malformed entries skipped silently", #w.equipped == 0 and #w.printed == 0)
  check("scan flag clear", ns.scanning == false)
end
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:803|h[Boom]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  local ns = loadAddon(w)
  w.env.C_Item.GetItemInfo = function() error("api exploded") end
  ns.scan()
  check("evaluate error reads as unsure", #w.equipped == 0 and #w.timers == 1)
  check("error does not wedge scan", ns.scanning == false)
end

-- 33. Scale dropdown tolerates malformed Pawn scale lists.
do
  local w = newWorld()
  w.withSettings = true
  w.scales = "garbage"
  loadAddon(w)
  clientLoaded(w)
  local data = w.settingsDropdowns[1]()
  check("non-table scales tolerated", #data == 1 and data[1].value == "")
end
do
  local w = newWorld()
  w.withSettings = true
  w.scales = { "nope", { Name = "A", IsVisible = true }, { IsVisible = true } }
  loadAddon(w)
  clientLoaded(w)
  local data = w.settingsDropdowns[1]()
  check("malformed scale entries skipped", #data == 2 and data[2].value == "A")
end

-- 34. Sheet button appears when the character UI loads late.
do
  local w = newWorld()
  local ns = loadAddon(w) -- no PaperDollFrame yet
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("no frame yet, no button", ns.sheetButton == nil)
  w.env.PaperDollFrame = {} -- lazy Blizzard character UI arrives
  w.frame.onEvent(nil, "ADDON_LOADED", "Blizzard_CharacterUI")
  check("late character UI creates button", ns.sheetButton ~= nil)
  check("late load does not scan", #w.equipped == 0 and #w.timers == 0)
end

-- 35. Settings build without slider label-formatter support.
do
  local w = newWorld()
  w.withSettings = true
  w.noSliderFormatter = true
  local ns = loadAddon(w)
  clientLoaded(w) -- would error on the unguarded method call
  check("settings built without formatter", ns.settingsBuilt == true)
  check("no formatter recorded", w.sliderFormatter == nil)
end

-- 36. Addon load and scans leak no globals.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:900|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  w.env.SlashCmdList.VOCGEAR("help")
  for _, leaked in ipairs({ "bag", "slot", "slotID", "checkSlot", "link", "ev", "o", "s", "db",
      "snap", "pair", "held", "btn", "now", "bar", "item", "line", "msg",
      "cand", "cur", "equipLoc", "classID", "subclassID",
      "setCtx", "readyThreshold", "readySet", "breakThreshold", "breakSet",
      "completes", "candSet", "heldSet", "counts", "before", "after", "seen",
      "spells", "specID", "itemID", "setID", "ctx", "threshold",
      "okIdx", "okID", "idx", "label", "otherHeld",
      "candID", "otherID", "isUnique", "okItem", "okUp", "bestFor",
      "weaker", "best", "bestSlot", "equippable", "handSwap", "ok", "err" }) do
    check("no leaked global: " .. leaked, w.env[leaked] == nil)
  end
  check("slash global registered", w.env.SLASH_VOCGEAR1 == "/vg")
end

-- 37. Melee/ranged swaps announce, never equip (hunter sword-over-bow).
do
  local w = newWorld()
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  local helm = "|cffa335ee|Hitem:902|h[Helm]|h|r"
  w.slots[bow], w.slots[sword], w.slots[helm] =
    "INVTYPE_RANGED", "INVTYPE_WEAPON", "INVTYPE_HEAD"
  local ns = loadAddon(w)
  check("bow reads ranged", ns.weaponKind(bow) == "ranged")
  check("sword reads melee", ns.weaponKind(sword) == "melee")
  check("armor reads nil", ns.weaponKind(helm) == nil)
  check("nil reads nil", ns.weaponKind(nil) == nil)
end
do
  local w = newWorld()
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[sword] = "INVTYPE_RANGED", "INVTYPE_WEAPON"
  w.bags[0] = { sword }
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  ns.scan()
  check("sword over bow not equipped", #w.equipped == 0)
  check("sword over bow announced once", #w.printed == 1)
  check("swap wording", w.printed[1]:find("melee/ranged swap", 1) ~= nil)
end
do -- symmetric: bow over sword announces too, never auto-swaps
  local w = newWorld()
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  w.equippedSlots[16] = sword
  w.slots[bow], w.slots[sword] = "INVTYPE_RANGED", "INVTYPE_WEAPON"
  w.bags[0] = { bow }
  w.upgradeLists[bow] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("bow over sword not equipped", #w.equipped == 0)
  check("bow over sword announced", #w.printed == 1)
end

-- 38. Same-kind weapon upgrades still equip.
do -- bow over bow
  local w = newWorld()
  local bowA = "|cff0070dd|Hitem:903|h[Bow A]|h|r"
  local bowB = "|cffa335ee|Hitem:904|h[Bow B]|h|r"
  w.equippedSlots[16] = bowA
  w.slots[bowA], w.slots[bowB] = "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT"
  w.bags[0] = { bowB }
  w.upgradeLists[bowB] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("bow over bow equips", #w.equipped == 1)
end
do -- sword over sword
  local w = newWorld()
  local swA = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local swB = "|cffa335ee|Hitem:906|h[Sword B]|h|r"
  w.equippedSlots[16] = swA
  w.slots[swA], w.slots[swB] = "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON"
  w.bags[0] = { swB }
  w.upgradeLists[swB] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("sword over sword equips", #w.equipped == 1)
end
do -- 2H sword over bow: same Pawn handedness, still a swap
  local w = newWorld()
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  local clay = "|cffa335ee|Hitem:907|h[Claymore]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[clay] = "INVTYPE_RANGED", "INVTYPE_2HWEAPON"
  w.bags[0] = { clay }
  w.upgradeLists[clay] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("2H sword over bow not equipped", #w.equipped == 0)
  check("2H sword over bow announced", #w.printed == 1)
end

-- 39. Item-level path honors the guard too.
do
  local w = newWorld()
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[sword] = "INVTYPE_RANGED", "INVTYPE_WEAPON"
  w.bags[0] = { sword }
  w.upgradeLists[sword] = nil
  w.ilvlDiffs[sword] = 5
  local ns = loadAddon(w)
  ns.scan()
  check("ilvl sword over bow not equipped", #w.equipped == 0)
  check("ilvl sword over bow announced", #w.printed == 1)
end

-- 40. Empty hand equips any weapon; armor ignores the guard.
do
  local w = newWorld()
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("empty hand equips weapon", #w.equipped == 1)
end
do
  local w = newWorld()
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  local helm = "|cffa335ee|Hitem:902|h[Helm]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[helm] = "INVTYPE_RANGED", "INVTYPE_HEAD"
  w.bags[0] = { helm }
  w.upgradeLists[helm] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("armor equips under a bow", #w.equipped == 1)
end

-- 41. Wand counts as main-hand 1H (Pawn normalizes it so), not ranged.
do
  local w = newWorld()
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local wand = "|cffa335ee|Hitem:908|h[Wand]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[wand] = "INVTYPE_WEAPON", "INVTYPE_RANGED"
  w.classIDs[wand], w.subclassIDs[wand] = 2, 19
  w.bags[0] = { wand }
  w.upgradeLists[wand] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  check("wand reads melee", ns.weaponKind(wand) == "melee")
  ns.scan()
  check("wand over sword equips", #w.equipped == 1)
end

-- 42. Breaking an active set bonus announces, never equips.
do
  local w = newWorld()
  specReady(w)
  w.setNames[11] = "Testplate"
  local t1, t2, t3, t4 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] = t1, t2, t3, t4
  local off = "|cffa335ee|Hitem:910|h[Off Helm]|h|r"
  w.bags[0] = { off }
  w.slots[off] = "INVTYPE_HEAD"
  w.upgradeLists[off] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  ns.scan()
  check("4pc break not equipped", #w.equipped == 0)
  check("4pc break announced once", #w.printed == 1)
  check("veto wording", w.printed[1]:find("would break Testplate 4pc", 1) ~= nil)
  check("bonus check uses current spec", w.lastBonusSpec == 70)
end

-- 43. Set swaps that keep every bonus intact still equip.
do -- fifth piece is stats-only: 5 -> 4 keeps 4pc
  local w = newWorld()
  specReady(w)
  local t = {}
  for i = 1, 5 do t[i] = tierPiece(w, 11) end
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7], w.equippedSlots[10] =
    t[1], t[2], t[3], t[4], t[5]
  local off = "|cffa335ee|Hitem:911|h[Off Helm]|h|r"
  w.bags[0] = { off }
  w.slots[off] = "INVTYPE_HEAD"
  w.upgradeLists[off] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("5th piece swap equips", #w.equipped == 1)
end
do -- same-set sidegrade Pawn flags: count unchanged, equips
  local w = newWorld()
  specReady(w)
  local t1, t2, t3, t4 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] = t1, t2, t3, t4
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.upgradeLists[cand] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("same-set swap equips", #w.equipped == 1)
end

-- 44. Bonus-completing tier pieces equip even when Pawn is silent.
do -- 3 -> 4
  local w = newWorld()
  specReady(w)
  w.setNames[11] = "Testplate"
  local t1, t2, t3 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5] = t1, t2, t3
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_LEGS"
  local ns = loadAddon(w)
  ns.scan()
  check("3->4 completes", #w.equipped == 1 and w.equipped[1].item == cand)
  check("completion names the bonus", w.printed[1]:find("completes Testplate 4pc", 1) ~= nil)
end
do -- 1 -> 2
  local w = newWorld()
  specReady(w)
  w.equippedSlots[1] = tierPiece(w, 11)
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_SHOULDER"
  local ns = loadAddon(w)
  ns.scan()
  check("1->2 completes", #w.equipped == 1)
  check("2pc message", w.printed[1]:find("completes 2pc", 1) ~= nil)
end
do -- Pawn-flagged and completing: one equip, both reasons told
  local w = newWorld()
  specReady(w)
  local t1, t2, t3 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5] = t1, t2, t3
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_LEGS"
  w.upgradeLists[cand] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("flagged completion equips once", #w.equipped == 1)
  check("combined reasons", w.printed[1]:find("%+5%.0%%", 1) ~= nil
    and w.printed[1]:find("completes 4pc", 1) ~= nil)
end
do -- audit mode reports the completion without equipping
  local w = newWorld()
  w.savedVars = { audit = true }
  specReady(w)
  local t1, t2, t3 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5] = t1, t2, t3
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_LEGS"
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("audit completion equips nothing", #w.equipped == 0)
  check("audit completion reported", #w.printed == 1
    and w.printed[1]:find("would equip", 1) ~= nil
    and w.printed[1]:find("completes 4pc", 1) ~= nil)
end

-- 45. A first tier piece Pawn rejects stays in bags, silently.
do
  local w = newWorld()
  specReady(w)
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  local ns = loadAddon(w)
  ns.scan()
  check("0->1 equips nothing", #w.equipped == 0)
  check("0->1 silent", #w.printed == 0)
end

-- 46. Breaking a set yourself declines it for the session.
do -- no re-completion, past the swap-memory window, silently
  local w = newWorld()
  specReady(w)
  local t1, t2 = tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3] = t1, t2
  local off = "|cffa335ee|Hitem:912|h[Off Helm]|h|r"
  w.slots[off], w.slots[t1] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  local ns = loadAddon(w)
  ns.scan() -- baseline snapshot; bags empty so nothing equips
  w.equippedSlots[1] = off -- player breaks 2pc by hand; t1 lands in bags
  w.bags[0] = { t1 }
  ns.scan()
  check("break declined", ns.setDeclined[11] == true)
  check("declined set not re-completed", #w.equipped == 0)
  check("decline silent", #w.printed == 0)
  w.time = w.time + 31
  ns.scan()
  check("decline outlasts swap memory", #w.equipped == 0 and #w.printed == 0)
end
do -- vetoes for a declined set stay off too
  local w = newWorld()
  specReady(w)
  local t1, t2, t3, t4 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] = t1, t2, t3, t4
  local offA = "|cffa335ee|Hitem:913|h[Off Helm]|h|r"
  local offB = "|cffa335ee|Hitem:914|h[Off Shoulders]|h|r"
  local offC = "|cffa335ee|Hitem:915|h[Off Chest]|h|r"
  w.slots[offA], w.slots[offB], w.slots[offC] = "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST"
  w.slots[t1], w.slots[t2] = "INVTYPE_HEAD", "INVTYPE_SHOULDER"
  local ns = loadAddon(w)
  ns.scan()
  w.equippedSlots[1] = offA -- 4 -> 3 by hand: declined
  w.bags[0] = { t1 }
  ns.scan()
  w.equippedSlots[3] = offB -- 3 -> 2 by hand: still declined
  w.bags[0] = { t1, t2 }
  ns.scan()
  check("still declined", ns.setDeclined[11] == true)
  w.bags[0] = { t1, t2, offC }
  w.upgradeLists[offC] = upgrade("A", 0.05) -- 2 -> 1 crossing, veto suppressed
  ns.scan()
  check("declined veto suppressed", #w.equipped == 1 and w.equipped[1].item == offC)
end

-- 47. Re-completing a declined set by hand re-arms protection.
do
  local w = newWorld()
  specReady(w)
  local t1, t2 = tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3] = t1, t2
  local off = "|cffa335ee|Hitem:916|h[Off Helm]|h|r"
  w.slots[off], w.slots[t1] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  local ns = loadAddon(w)
  ns.scan()
  w.equippedSlots[1] = off -- break 2 -> 1: declined
  w.bags[0] = { t1 }
  ns.scan()
  check("declined after break", ns.setDeclined[11] == true)
  w.equippedSlots[1] = t1 -- change of heart: complete 1 -> 2 by hand
  w.bags[0] = { off }
  ns.scan()
  check("decline cleared", ns.setDeclined[11] == nil)
  w.time = w.time + 31 -- let the manual-swap memory expire
  w.upgradeLists[off] = upgrade("A", 0.05)
  ns.scan() -- off-piece over tier would break 2 -> 1: vetoed again
  check("veto re-armed", #w.equipped == 0 and #w.printed == 1)
end

-- 48. A set with no bonuses for the current spec gets no protection.
do -- missing bonus record
  local w = newWorld()
  specReady(w)
  local t1, t2, t3, t4 = tierPiece(w, 11, false), tierPiece(w, 11, false),
    tierPiece(w, 11, false), tierPiece(w, 11, false)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] = t1, t2, t3, t4
  local off = "|cffa335ee|Hitem:917|h[Off Helm]|h|r"
  w.bags[0] = { off }
  w.slots[off] = "INVTYPE_HEAD"
  w.upgradeLists[off] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("bonus-less set not protected", #w.equipped == 1)
end
do -- empty bonus record
  local w = newWorld()
  specReady(w)
  local pieces = { tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11) }
  for _, t in ipairs(pieces) do w.setBonusSpells[w.itemIDs[t]] = {} end
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] =
    pieces[1], pieces[2], pieces[3], pieces[4]
  local off = "|cffa335ee|Hitem:918|h[Off Helm]|h|r"
  w.bags[0] = { off }
  w.slots[off] = "INVTYPE_HEAD"
  w.upgradeLists[off] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("empty bonus record not protected", #w.equipped == 1)
end

-- 49. "Prioritize set bonuses" off: pure Pawn behavior.
do -- veto off
  local w = newWorld()
  w.savedVars = { protectSets = false }
  specReady(w)
  local t1, t2, t3, t4 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] = t1, t2, t3, t4
  local off = "|cffa335ee|Hitem:919|h[Off Helm]|h|r"
  w.bags[0] = { off }
  w.slots[off] = "INVTYPE_HEAD"
  w.upgradeLists[off] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("veto disabled", #w.equipped == 1)
end
do -- completion off
  local w = newWorld()
  w.savedVars = { protectSets = false }
  specReady(w)
  local t1, t2, t3 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5] = t1, t2, t3
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_LEGS"
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("completion disabled", #w.equipped == 0 and #w.printed == 0)
end

-- 50. Breaking an old bonus to complete a new one: the veto wins.
do
  local w = newWorld()
  specReady(w)
  w.setNames[11], w.setNames[22] = "Oldplate", "Newplate"
  local a1, a2, a3, a4 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  local b1 = tierPiece(w, 22)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[10] = a1, a2, a3, a4
  w.equippedSlots[7] = b1
  local cand = tierPiece(w, 22) -- completes new 2pc, breaks old 4pc
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  local ns = loadAddon(w)
  ns.scan()
  check("break-to-complete not equipped", #w.equipped == 0)
  check("veto names the old set", w.printed[1]:find("would break Oldplate 4pc", 1) ~= nil)
end

-- 51. Completion respects the heirloom and level gates.
do -- completing over an heirloom keeps the heirloom
  local w = newWorld()
  specReady(w)
  local heir = "|cffa335ee|Hitem:920|h[Heirloom Helm]|h|r"
  w.rarities[heir] = 7
  w.equippedSlots[1] = heir
  local t2, t3, t4 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[3], w.equippedSlots[5], w.equippedSlots[7] = t2, t3, t4
  local cand = tierPiece(w, 11)
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  local ns = loadAddon(w)
  ns.scan()
  check("completion keeps heirloom", #w.equipped == 0)
  check("heirloom announced", #w.printed == 1 and w.printed[1]:find("keeping heirloom", 1) ~= nil)
end
do -- above-level tier never completes
  local w = newWorld()
  specReady(w)
  local t1, t2, t3 = tierPiece(w, 11), tierPiece(w, 11), tierPiece(w, 11)
  w.equippedSlots[1], w.equippedSlots[3], w.equippedSlots[5] = t1, t2, t3
  local cand = tierPiece(w, 11)
  w.minLevels[cand] = 85
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_LEGS"
  local ns = loadAddon(w)
  ns.scan()
  check("above-level completion skipped", #w.equipped == 0 and #w.printed == 0)
end

-- 52. Built-in fallback drives when Pawn is absent.
do
  local w = newWorld()
  w.pawn = false -- no Pawn stubs at all
  local held = "|cffa335ee|Hitem:700|h[Plate Helm 90]|h|r"
  local cand = "|cffa335ee|Hitem:701|h[Plate Helm 100]|h|r"
  w.equippedSlots[1] = held
  w.levels[held], w.levels[cand] = 90, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 4
  w.classIDs[held], w.subclassIDs[held] = 4, 4
  local ns = loadAddon(w)
  check("fallback source label", ns.sourceLabel() == "item level")
  check("not pawn-active without Pawn", ns.pawnReady() == false)
  ns.scan()
  check("fallback equips higher ilvl", #w.equipped == 1 and w.equipped[1].item == cand)
  check("fallback why names item level", w.printed[1]:find("item level %+10", 1) ~= nil)
end

-- 53. Fallback announce names the source on two-slot items.
do
  local w = newWorld()
  w.pawn = false
  local r1 = "|cffa335ee|Hitem:710|h[Ring 90]|h|r"
  local r2 = "|cffa335ee|Hitem:711|h[Ring 95]|h|r"
  local cand = "|cffa335ee|Hitem:712|h[Ring 100]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = r1, r2
  w.levels[r1], w.levels[r2], w.levels[cand] = 90, 95, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 0 -- rings read as generic armor
  local ns = loadAddon(w)
  ns.scan()
  check("two-slot fallback announced", #w.equipped == 0 and #w.printed == 1)
  check("announce names item level", w.printed[1]:find("item level upgrade in bags %(not auto%-equipped%)", 1) ~= nil)
end

-- 54. Lower ilvl is not an upgrade in fallback.
do
  local w = newWorld()
  w.pawn = false
  local held = "|cffa335ee|Hitem:720|h[Plate Helm 100]|h|r"
  local cand = "|cffa335ee|Hitem:721|h[Plate Helm 90]|h|r"
  w.equippedSlots[1] = held
  w.levels[held], w.levels[cand] = 100, 90
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 4
  local ns = loadAddon(w)
  ns.scan()
  check("lower ilvl ignored", #w.equipped == 0 and #w.printed == 0)
end

-- 55. Armor-type gate: cloth on a plate wearer is not an upgrade.
do
  local w = newWorld()
  w.pawn = false
  local held = "|cffa335ee|Hitem:730|h[Plate Helm 90]|h|r"
  local cand = "|cffa335ee|Hitem:731|h[Cloth Helm 100]|h|r"
  w.equippedSlots[1] = held
  w.levels[held], w.levels[cand] = 90, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 1 -- cloth
  w.classIDs[held], w.subclassIDs[held] = 4, 4
  local ns = loadAddon(w)
  ns.scan()
  check("cloth-on-warrior rejected", #w.equipped == 0)
end

-- 56. Leveling in a lower armor type: matching the worn type passes.
do
  local w = newWorld()
  w.pawn = false
  w.playerClass = "PALADIN"
  local held = "|cffa335ee|Hitem:740|h[Mail Helm 90]|h|r"
  local cand = "|cffa335ee|Hitem:741|h[Mail Helm 100]|h|r"
  w.equippedSlots[1] = held
  w.levels[held], w.levels[cand] = 90, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 3 -- mail
  w.classIDs[held], w.subclassIDs[held] = 4, 3
  local ns = loadAddon(w)
  ns.scan()
  check("mail-on-mail paladin equips", #w.equipped == 1)
end

-- 57. Cloaks are exempt from the armor gate.
do
  local w = newWorld()
  w.pawn = false -- warrior, empty cloak slot
  local cand = "|cffa335ee|Hitem:750|h[Cloak 100]|h|r"
  w.levels[cand] = 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_CLOAK"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 1 -- cloaks read as cloth
  local ns = loadAddon(w)
  ns.scan()
  check("cloak equips into empty slot", #w.equipped == 1)
end

-- 58. Pawn installed but not loaded yet: the scan waits for it.
do
  local w = newWorld()
  w.pawn = false -- API not present yet
  w.installedAddons = { Pawn = { loadable = true } }
  w.loadedAddons = {} -- Pawn not loaded
  local held = "|cffa335ee|Hitem:760|h[Plate Helm 90]|h|r"
  local cand = "|cffa335ee|Hitem:761|h[Plate Helm 100]|h|r"
  w.equippedSlots[1] = held
  w.levels[held], w.levels[cand] = 90, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 4
  local ns = loadAddon(w)
  check("pawn pending detected", ns.pawnPending() == true)
  ns.scan()
  check("scan waits for Pawn", #w.equipped == 0 and #w.timers == 1)
  -- Pawn arrives: API present now, ADDON_LOADED rescans with Pawn driving.
  w.env.PawnGetItemData = function(link) return { Link = link, Level = w.levels[link] or 80 } end
  w.env.PawnIsItemAnUpgrade = function(item) return w.upgradeLists[item.Link] end
  w.env.PawnIsItemAnItemLevelUpgrade = function(item) return w.ilvlDiffs[item.Link] end
  w.loadedAddons = { Pawn = true }
  w.upgradeLists[cand] = { { ScaleName = "A", PercentUpgrade = 0.05 } }
  w.frame.onEvent(nil, "ADDON_LOADED", "Pawn")
  check("Pawn takes over after load", ns.pawnReady() == true)
  check("Pawn verdict equips", #w.equipped == 1)
  check("Pawn percent printed", w.printed[1]:find("%+5%.0%%%)", 1) ~= nil)
end

-- 59. Settings shows which source is driving.
do
  local w = newWorld()
  w.pawn = false
  w.withSettings = true
  loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("source note added", #w.headerNotes == 1)
  check("note names item level", w.headerNotes[1]:find("built%-in item level", 1) ~= nil)
end
do
  local w = newWorld()
  w.pawn = true
  w.withSettings = true
  loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
  check("note names Pawn", w.headerNotes[1]:find("Upgrade source: Pawn", 1) ~= nil)
end

-- 60. Equip plays the configured sound.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:800|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("equipped", #w.equipped == 1)
  check("quest chime played", #w.playedSounds == 1 and w.playedSounds[1] == 878)
end

-- 61. Sound off: no PlaySound call.
do
  local w = newWorld()
  w.savedVars = { equipSound = "0" }
  local link = "|cffa335ee|Hitem:801|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("equipped without sound", #w.equipped == 1 and #w.playedSounds == 0)
end

-- 62. Audit mode never equips, so no sound either.
do
  local w = newWorld()
  w.savedVars = { audit = true }
  local link = "|cffa335ee|Hitem:802|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("audit silent", #w.equipped == 0 and #w.playedSounds == 0)
end

-- 63. Sound dropdown lists Off plus the verified chimes; changing it previews.
do
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  clientLoaded(w)
  local getOptions
  for _, fn in ipairs(w.settingsDropdowns) do
    local data = fn()
    if data[1] and data[1].value == "0" then getOptions = data end
  end
  check("sound dropdown found", getOptions ~= nil)
  check("off plus three chimes", #getOptions == 4)
  check("first option is Off", getOptions[1].text == "Off")
  -- Preview: switching the setting plays the new choice immediately.
  ns.opts().equipSound = "73277"
  w.settingCallbacks["VocGear_equipSound"]()
  check("preview plays selection", #w.playedSounds == 1 and w.playedSounds[1] == 73277)
end

-- 64. Unique-Equipped twin in the pair's other slot: announce, never equip.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local twin = "|cff0070dd|Hitem:101|h[Twin]|h|r" -- worn copy, other slot
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- Pawn's named target
  local cand = "|cffa335ee|Hitem:102|h[Twin+]|h|r" -- same base item, new bonuses
  w.equippedSlots[11], w.equippedSlots[12] = twin, ringA
  w.itemIDs[twin], w.itemIDs[cand] = 5001, 5001
  w.itemIDs[ringA] = 5002
  w.uniqueness[cand] = true
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, ringA)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  ns.scan()
  check("unique twin not equipped", #w.equipped == 0)
  check("unique twin announced once", #w.printed == 1)
  check("unique wording", w.printed[1]:find("unique%-equipped", 1) ~= nil)
end

-- 65. Same-item upgrade into its own slot still equips.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local twin = "|cff0070dd|Hitem:101|h[Twin]|h|r"
  local ringB = "|cff0070dd|Hitem:103|h[Ring B]|h|r"
  local cand = "|cffa335ee|Hitem:102|h[Twin+]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = twin, ringB
  w.itemIDs[twin], w.itemIDs[cand] = 5001, 5001
  w.itemIDs[ringB] = 5003
  w.uniqueness[cand] = true
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, twin) -- replaces its own twin
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("same-slot twin upgrade equips", #w.equipped == 1)
  check("twin slot targeted", w.equipped[1].slot == 11)
end

-- 66. Same base item, not unique: no veto.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local worn = "|cff0070dd|Hitem:101|h[Worn]|h|r"
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local cand = "|cffa335ee|Hitem:102|h[Worn+]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = worn, ringA
  w.itemIDs[worn], w.itemIDs[cand] = 5001, 5001
  w.itemIDs[ringA] = 5002
  -- uniqueness[cand] unset: an ordinary item
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, ringA)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("non-unique duplicate equips", #w.equipped == 1)
end

-- 67. Missing uniqueness API fails open (status quo ante).
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local twin = "|cff0070dd|Hitem:101|h[Twin]|h|r"
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local cand = "|cffa335ee|Hitem:102|h[Twin+]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = twin, ringA
  w.itemIDs[twin], w.itemIDs[cand] = 5001, 5001
  w.itemIDs[ringA] = 5002
  w.uniqueness[cand] = true
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, ringA)
  local ns = loadAddon(w)
  clientLoaded(w)
  w.env.C_Item.GetItemUniquenessByID = nil -- older client
  ns.scan()
  check("missing uniqueness API fails open", #w.equipped == 1)
end

-- 68. Rings: Pawn's named replacement no longer worn -> displace the ring
-- that isn't Pawn's best.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- Pawn's best for A
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r"
  local gone = "item:109::::::" -- historical 2nd-best, unworn (Pawn sends it bare)
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  w.bestLinks.A = { INVTYPE_FINGER = "item:100::::::" }
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("best-aware ring equips", #w.equipped == 1)
  check("non-best slot targeted", w.equipped[1].slot == 12)
  check("best lookup skips rescan", w.bestLinkCalls[1].doNotRescan == true
    and w.bestLinkCalls[1].index == 1 and w.bestLinkCalls[1].scale == "A"
    and w.bestLinkCalls[1].invType == "INVTYPE_FINGER")
end

-- 69. Mirror: best in the second slot -> the first slot takes the upgrade.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r" -- Pawn's best for A
  local gone = "item:109::::::"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  w.bestLinks.A = { INVTYPE_FINGER = "item:101::::::" }
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("mirrored ring equips", #w.equipped == 1)
  check("first slot targeted", w.equipped[1].slot == 11)
end

-- 70. Best tracked for another scale only: falls back to item level.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- ilvl 100
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r" -- ilvl 90, best for Other
  local gone = "item:109::::::"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r" -- ilvl 95
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.levels[ringA], w.levels[ringB], w.levels[cand] = 100, 90, 95
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  w.bestLinks.Other = { INVTYPE_FINGER = "item:101::::::" }
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("other-scale best ignored", #w.equipped == 1)
  check("ilvl weaker slot targeted", w.equipped[1].slot == 12)
end

-- 71. No best data (tracking off / unscanned): falls back to item level.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- ilvl 100
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r" -- ilvl 90
  local gone = "item:109::::::"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r" -- ilvl 95
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.levels[ringA], w.levels[ringB], w.levels[cand] = 100, 90, 95
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("missing best falls back", #w.equipped == 1)
  check("fallback targets ilvl weaker", w.equipped[1].slot == 12)
end
do -- older Pawn without the best-link API: same fallback
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- ilvl 100
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r" -- ilvl 90
  local gone = "item:109::::::"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r" -- ilvl 95
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.levels[ringA], w.levels[ringB], w.levels[cand] = 100, 90, 95
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  local ns = loadAddon(w)
  clientLoaded(w)
  w.env.PawnGetBestItemLink = nil -- older Pawn
  ns.scan()
  check("missing best-link API fails open", #w.equipped == 1 and w.equipped[1].slot == 12)
end

-- 72. Malformed best answers fail open; best held twice is no call.
do -- non-string best link: not a link at all
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- ilvl 90
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r" -- ilvl 100
  local gone = "item:109::::::"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r" -- ilvl 95
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.levels[ringA], w.levels[ringB], w.levels[cand] = 90, 100, 95
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  w.bestLinks.A = { INVTYPE_FINGER = 42 }
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("malformed best falls back", #w.equipped == 1 and w.equipped[1].slot == 11)
  check("scan not wedged", ns.scanning == false)
end
do -- duplicate pair: best matches both slots, so no call
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- ilvl 90, worn twice
  local gone = "item:109::::::"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r" -- ilvl 95
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringA
  w.levels[ringA], w.levels[cand] = 90, 95
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  w.bestLinks.A = { INVTYPE_FINGER = "item:100::::::" }
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("duplicate best falls back", #w.equipped == 1 and w.equipped[1].slot == 11)
end

-- 73. Trinkets skip the best tier: no score tracking upstream. (Real Pawn
-- never scores trinkets; the stub forces a scored verdict to prove the gate.)
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local trinkA = "|cff0070dd|Hitem:200|h[Trinket A]|h|r" -- ilvl 90
  local trinkB = "|cff0070dd|Hitem:201|h[Trinket B]|h|r" -- ilvl 100, "best"
  local gone = "item:209::::::"
  local cand = "|cffa335ee|Hitem:202|h[Trinket C]|h|r" -- ilvl 95
  w.equippedSlots[13], w.equippedSlots[14] = trinkA, trinkB
  w.levels[trinkA], w.levels[trinkB], w.levels[cand] = 90, 100, 95
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_TRINKET"
  w.upgradeLists[cand] = upgrade("A", 0.05, gone)
  w.bestLinks.A = { INVTYPE_TRINKET = "item:201::::::" }
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("trinket ignores best claims", #w.equipped == 1)
  check("trinket uses ilvl weaker", w.equipped[1].slot == 13)
  check("trinket never consults best", #w.bestLinkCalls == 0)
end

-- 74. Pawn's bare-form replacement matches an unenchanted held ring.
-- (Live, ExistingItemLink is bare "item:..." while held links are full;
-- without EvenIfNotEnchanted the two forms never compare equal.)
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r"
  local cand = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  w.upgradeLists[cand] = upgrade("A", 0.05, "item:101::::::")
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("bare existing matches held", #w.equipped == 1)
  check("named slot targeted", w.equipped[1].slot == 12)
end

-- 75. Score verdicts for unwieldable items never equip, silently.
do
  local w = newWorld()
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.upgradeLists[sword] = upgrade("A", 0.05)
  w.canEquip[sword] = false
  local ns = loadAddon(w)
  ns.scan()
  check("unwieldable not equipped", #w.equipped == 0)
  check("unwieldable silent", #w.printed == 0)
end
do -- control: wieldable verdicts still equip
  local w = newWorld()
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.upgradeLists[sword] = upgrade("A", 0.05)
  w.canEquip[sword] = true
  local ns = loadAddon(w)
  ns.scan()
  check("wieldable equips", #w.equipped == 1)
end

-- 76. Same-slot settle: a second ring for one slot waits for Pawn to
-- catch up instead of displacing the ring just equipped. (Pawn refreshes
-- best-item data on a 250ms throttle, so the immediate post-equip rescan
-- prices every leftover candidate against the pre-equip second-best.)
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r" -- Pawn's best for A
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r" -- stale second-best
  local cand1 = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  local cand2 = "|cffa335ee|Hitem:103|h[Ring D]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.bags[0] = { cand1, cand2 }
  w.slots[cand1], w.slots[cand2] = "INVTYPE_FINGER", "INVTYPE_FINGER"
  w.upgradeLists[cand1] = upgrade("A", 0.022)
  w.upgradeLists[cand2] = upgrade("A", 0.028)
  w.bestLinks.A = { INVTYPE_FINGER = "item:100::::::" }
  local ns = loadAddon(w)
  clientLoaded(w) -- its ADDON_LOADED scan puts cand1 in the non-best slot
  check("first ring equips", #w.equipped == 1 and w.equipped[1].slot == 12)
  w.time = w.time + 1 -- bag update lands a second later, Pawn still stale
  ns.scan()
  check("second ring waits out the settle", #w.equipped == 1)
  check("settle announced", w.printed[#w.printed]:find("slot settling", 1) ~= nil)
  check("settle schedules retry", #w.timers == 1)
  w.time = w.time + 10 -- settle expires; the stub stays stale, so it equips
  ns.scan()
  check("settled ring equips", #w.equipped == 2 and w.equipped[2].slot == 12)
  check("breaker never trips", not ns.isPaused())
end

-- 77. Settle covers single-slot items too (slot derived, equip unforced).
do
  local w = newWorld()
  local helmA = "|cff0070dd|Hitem:500|h[Helm A]|h|r"
  local cand1 = "|cffa335ee|Hitem:501|h[Helm B]|h|r"
  local cand2 = "|cffa335ee|Hitem:502|h[Helm C]|h|r"
  w.equippedSlots[1] = helmA
  w.bags[0] = { cand1, cand2 }
  w.slots[cand1], w.slots[cand2] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  w.upgradeLists[cand1] = upgrade("A", 0.05)
  w.upgradeLists[cand2] = upgrade("A", 0.06)
  local ns = loadAddon(w)
  ns.scan()
  check("first helm equips unforced", #w.equipped == 1 and w.equipped[1].slot == nil)
  w.time = w.time + 1
  ns.scan()
  check("second helm waits", #w.equipped == 1)
  w.time = w.time + 10
  ns.scan()
  check("settled helm equips", #w.equipped == 2)
end

-- 78. Settle only guards displacement: an emptied touched slot still equips.
do
  local w = newWorld()
  w.savedVars = { autoTwoSlot = true }
  local ringA = "|cff0070dd|Hitem:100|h[Ring A]|h|r"
  local ringB = "|cff0070dd|Hitem:101|h[Ring B]|h|r"
  local cand1 = "|cffa335ee|Hitem:102|h[Ring C]|h|r"
  local cand2 = "|cffa335ee|Hitem:103|h[Ring D]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = ringA, ringB
  w.bags[0] = { cand1 }
  w.slots[cand1], w.slots[cand2] = "INVTYPE_FINGER", "INVTYPE_FINGER"
  w.upgradeLists[cand1] = upgrade("A", 0.05, ringB) -- names slot 12
  w.upgradeLists[cand2] = upgrade("A", 0.03)
  local ns = loadAddon(w)
  clientLoaded(w) -- its ADDON_LOADED scan puts cand1 in the named slot
  check("ring equips into named slot", #w.equipped == 1 and w.equipped[1].slot == 12)
  ns.scan() -- observes the touch; displaced ringB sits out
  check("observation scan equips nothing", #w.equipped == 1)
  w.equippedSlots[12] = nil -- player removes the new ring by hand
  w.bags[0][#w.bags[0] + 1] = cand1
  w.bags[0][#w.bags[0] + 1] = cand2
  w.time = w.time + 1
  ns.scan()
  check("empty touched slot equips", #w.equipped == 2 and w.equipped[2].slot == 12)
  check("emptied slot takes the new ring", w.equipped[2].item == cand2)
end

-- 65. Addon compartment: click opens settings; hover follows the tooltip
-- contract (gold title, what it does, the slash hint).
do
  local w = newWorld()
  w.withSettings = true
  local ns = loadAddon(w)
  clientLoaded(w)
  local opened
  w.env.Settings.OpenToCategory = function(id) opened = id end
  check("compartment globals", type(w.env.VocGear_CompartmentClick) == "function"
    and type(w.env.VocGear_CompartmentEnter) == "function"
    and type(w.env.VocGear_CompartmentLeave) == "function")
  w.env.VocGear_CompartmentClick("VocGear", "LeftButton")
  check("compartment click opens config", opened == 99)
  local btn = {}
  w.env.VocGear_CompartmentEnter("VocGear", btn)
  check("compartment tooltip anchors to the button", w.gametip.owner == btn and w.gametip.shown == true)
  check("compartment tooltip title is gold", w.gametip.text == "VocGear"
    and w.gametip.titleColor[1] == 1 and w.gametip.titleColor[2] == 0.82)
  check("compartment tooltip names the source and the slash", #w.gametip.lines == 2
    and w.gametip.lines[1]:find("Pawn", 1, true) ~= nil
    and w.gametip.lines[2]:find("/vg", 1, true) ~= nil)
  w.env.VocGear_CompartmentLeave("VocGear", btn)
  check("compartment leave hides the tooltip", w.gametip.shown == false)
  w.env.Settings = nil
  w.env.VocGear_CompartmentClick("VocGear", "LeftButton")
  check("compartment without Settings says where",
    w.printed[#w.printed]:find("Settings > AddOns > VocGear", 1, true) ~= nil)
  check("no C_AddOns reads as Pawn not pending", (function()
    w.env.C_AddOns = nil
    return ns.pawnPending() == false
  end)())
end

-- 66. The equip call lives in C_Item; a client without it announces
-- once and never errors or loops.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:900|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  w.env.C_Item.EquipItemByName = nil
  ns.scan()
  ns.scan()
  check("no namespace: nothing equipped, no error", #w.equipped == 0)
  check("no namespace: announced once", #w.printed == 1
    and w.printed[1]:find("C_Item.EquipItemByName is missing", 1, true) ~= nil)
end

-- 79. Scale dropdown tooltips say what counts: Any spans every visible
-- scale, a named scale counts only itself.
do
  local w = newWorld()
  w.withSettings = true
  w.scales = {
    { Name = "PaladinHoly", LocalizedName = "Paladin: Holy", IsVisible = true },
  }
  loadAddon(w)
  clientLoaded(w)
  local data = w.settingsDropdowns[1]()
  check("Any tooltip points at named scales",
    data[1].value == "" and data[1].tip:find("that scale only", 1, true) ~= nil)
  check("named tooltip counts only itself",
    data[2].value == "PaladinHoly" and data[2].tip:find("Only count", 1, true) ~= nil
    and data[2].tip:find("Paladin: Holy", 1, true) ~= nil)
end

-- 80. Swap weapon types off: same-hand type swaps announce, never equip.
do -- dagger over sword (both melee 1H)
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local dagger = "|cffa335ee|Hitem:909|h[Dagger]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[dagger] = "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.classIDs[dagger], w.subclassIDs[dagger] = 2, 15
  w.bags[0] = { dagger }
  w.upgradeLists[dagger] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  ns.scan()
  check("off: dagger over sword not equipped", #w.equipped == 0)
  check("off: dagger over sword announced once", #w.printed == 1)
  check("off: type wording", w.printed[1]:find("different weapon type", 1) ~= nil)
end
do -- gun over bow (both ranged)
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local bow = "|cff0070dd|Hitem:903|h[Bow A]|h|r"
  local gun = "|cffa335ee|Hitem:904|h[Gun B]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[gun] = "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT"
  w.classIDs[bow], w.subclassIDs[bow] = 2, 2
  w.classIDs[gun], w.subclassIDs[gun] = 2, 3
  w.bags[0] = { gun }
  w.upgradeLists[gun] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("off: gun over bow not equipped", #w.equipped == 0)
  check("off: gun over bow announced", #w.printed == 1)
end

-- 81. Swap off: the same weapon type still equips.
do -- sword over sword, across 1H equip locs
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local swA = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local swB = "|cffa335ee|Hitem:906|h[Sword B]|h|r"
  w.equippedSlots[16] = swA
  w.slots[swA], w.slots[swB] = "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON"
  w.classIDs[swA], w.subclassIDs[swA] = 2, 7
  w.classIDs[swB], w.subclassIDs[swB] = 2, 7
  w.bags[0] = { swB }
  w.upgradeLists[swB] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("off: sword over sword equips", #w.equipped == 1)
end
do -- staff over staff
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local stA = "|cff0070dd|Hitem:907|h[Staff A]|h|r"
  local stB = "|cffa335ee|Hitem:908|h[Staff B]|h|r"
  w.equippedSlots[16] = stA
  w.slots[stA], w.slots[stB] = "INVTYPE_2HWEAPON", "INVTYPE_2HWEAPON"
  w.classIDs[stA], w.subclassIDs[stA] = 2, 10
  w.classIDs[stB], w.subclassIDs[stB] = 2, 10
  w.bags[0] = { stB }
  w.upgradeLists[stB] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("off: staff over staff equips", #w.equipped == 1)
end

-- 82. Swap on (the default): cross-type same-hand equips.
do -- dagger over sword
  local w = newWorld()
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local dagger = "|cffa335ee|Hitem:909|h[Dagger]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[dagger] = "INVTYPE_WEAPON", "INVTYPE_WEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.classIDs[dagger], w.subclassIDs[dagger] = 2, 15
  w.bags[0] = { dagger }
  w.upgradeLists[dagger] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("on: dagger over sword equips", #w.equipped == 1)
end
do -- gun over bow
  local w = newWorld()
  local bow = "|cff0070dd|Hitem:903|h[Bow A]|h|r"
  local gun = "|cffa335ee|Hitem:904|h[Gun B]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[gun] = "INVTYPE_RANGED", "INVTYPE_RANGED"
  w.classIDs[bow], w.subclassIDs[bow] = 2, 2
  w.classIDs[gun], w.subclassIDs[gun] = 2, 3
  w.bags[0] = { gun }
  w.upgradeLists[gun] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("on: gun over bow equips", #w.equipped == 1)
end
do -- 2H sword over staff (same hand, different type)
  local w = newWorld()
  local staff = "|cff0070dd|Hitem:907|h[Staff A]|h|r"
  local clay = "|cffa335ee|Hitem:910|h[Claymore]|h|r"
  w.equippedSlots[16] = staff
  w.slots[staff], w.slots[clay] = "INVTYPE_2HWEAPON", "INVTYPE_2HWEAPON"
  w.classIDs[staff], w.subclassIDs[staff] = 2, 10
  w.classIDs[clay], w.subclassIDs[clay] = 2, 8
  w.bags[0] = { clay }
  w.upgradeLists[clay] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("on: 2H sword over staff equips", #w.equipped == 1)
end

-- 83. Handedness: 1H/2H swaps equip when on, via the item-level paths
-- (Pawn's score path never flags across the line).
do -- staff over sword, through Pawn's own ilvl verdict
  local w = newWorld()
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local staff = "|cffa335ee|Hitem:907|h[Staff B]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[staff] = "INVTYPE_WEAPON", "INVTYPE_2HWEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.classIDs[staff], w.subclassIDs[staff] = 2, 10
  w.bags[0] = { staff }
  w.upgradeLists[staff] = nil
  w.ilvlDiffs[staff] = 10
  local ns = loadAddon(w)
  ns.scan()
  check("on: staff over sword equips", #w.equipped == 1)
  check("on: swap note printed", w.printed[1]:find("1H/2H swap", 1) ~= nil)
  check("on: ilvl margin kept", w.printed[1]:find("item level %+10", 1) ~= nil)
end
do -- 1H over 2H in the built-in fallback
  local w = newWorld()
  w.pawn = false
  local staff = "|cff0070dd|Hitem:907|h[Staff 90]|h|r"
  local sword = "|cffa335ee|Hitem:905|h[Sword 100]|h|r"
  w.equippedSlots[16] = staff
  w.levels[staff], w.levels[sword] = 90, 100
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: higher-ilvl sword over staff equips", #w.equipped == 1)
end

-- 84. Handedness off: 1H/2H announces, never equips.
do
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local staff = "|cffa335ee|Hitem:907|h[Staff B]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[staff] = "INVTYPE_WEAPON", "INVTYPE_2HWEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.classIDs[staff], w.subclassIDs[staff] = 2, 10
  w.bags[0] = { staff }
  w.upgradeLists[staff] = nil
  w.ilvlDiffs[staff] = 10
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  ns.scan()
  check("off: staff over sword not equipped", #w.equipped == 0)
  check("off: staff over sword announced once", #w.printed == 1)
  check("off: handedness wording wins over type wording",
    w.printed[1]:find("1H/2H swap", 1) ~= nil
    and w.printed[1]:find("different weapon type", 1) == nil)
end

-- 85. Unusable weapons never equip, silently, on either source.
do -- Pawn path: the client says no, the verdict is dropped
  local w = newWorld()
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.upgradeLists[sword] = upgrade("A", 0.05)
  w.notEquippable[sword] = true
  local ns = loadAddon(w)
  ns.scan()
  check("unusable Pawn verdict skipped", #w.equipped == 0)
  check("unusable Pawn verdict silent", #w.printed == 0)
end
do -- fallback path: same gate, no Pawn involved
  local w = newWorld()
  w.pawn = false
  local sword = "|cffa335ee|Hitem:901|h[Sword 100]|h|r"
  w.levels[sword] = 100
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.notEquippable[sword] = true
  local ns = loadAddon(w)
  ns.scan()
  check("unusable fallback skipped", #w.equipped == 0)
  check("unusable fallback silent", #w.printed == 0)
end

-- 86. Missing usability API fails open (status quo ante).
do
  local w = newWorld()
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  w.env.C_Item.IsEquippableItem = nil -- older client
  ns.scan()
  check("missing usability API fails open", #w.equipped == 1)
end

-- 87. Unknown weapon subclass fails open: off still equips.
do
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local dagger = "|cffa335ee|Hitem:909|h[Dagger]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[dagger] = "INVTYPE_WEAPON", "INVTYPE_WEAPON"
  -- classIDs/subclassIDs unset: the item cache hasn't answered yet
  w.bags[0] = { dagger }
  w.upgradeLists[dagger] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("off: unknown subclass fails open", #w.equipped == 1)
end

-- 88. Gate order: the melee/ranged wording wins over the type wording.
do
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local bow = "|cffa335ee|Hitem:900|h[Bow]|h|r"
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[sword] = "INVTYPE_RANGED", "INVTYPE_WEAPON"
  w.classIDs[bow], w.subclassIDs[bow] = 2, 2
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.bags[0] = { sword }
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("melee/ranged wording wins", w.printed[1]:find("melee/ranged swap", 1) ~= nil
    and w.printed[1]:find("different weapon type", 1) == nil)
end

-- 89. Armor ignores the weapon option; empty weapon slots fill anyway.
do -- helm over helm with the option off
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local held = "|cff0070dd|Hitem:500|h[Helm A]|h|r"
  local cand = "|cffa335ee|Hitem:501|h[Helm B]|h|r"
  w.equippedSlots[1] = held
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_HEAD"
  w.upgradeLists[cand] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("off: armor equips", #w.equipped == 1)
end
do -- a first weapon fills an empty hand with the option off
  local w = newWorld()
  w.savedVars = { swapWeapons = false }
  local sword = "|cffa335ee|Hitem:901|h[Sword]|h|r"
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("off: empty hand equips", #w.equipped == 1)
end

-- 90. Fallback equips shields: empty off-hand, over shields, over holdables.
do -- a first shield fills an empty off-hand
  local w = newWorld()
  w.pawn = false
  local shield = "|cffa335ee|Hitem:760|h[Shield 100]|h|r"
  w.levels[shield] = 100
  w.bags[0] = { shield }
  w.slots[shield] = "INVTYPE_SHIELD"
  w.classIDs[shield], w.subclassIDs[shield] = 4, 6
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: first shield equips", #w.equipped == 1)
end
do -- shield over shield still upgrades by level
  local w = newWorld()
  w.pawn = false
  local worn = "|cff0070dd|Hitem:761|h[Shield 90]|h|r"
  local cand = "|cffa335ee|Hitem:762|h[Shield 100]|h|r"
  w.equippedSlots[17] = worn
  w.levels[worn], w.levels[cand] = 90, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_SHIELD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 6
  w.classIDs[worn], w.subclassIDs[worn] = 4, 6
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: shield over shield equips", #w.equipped == 1)
end
do -- shield over a holdable (different armor subclass, same slot)
  local w = newWorld()
  w.pawn = false
  local frill = "|cff0070dd|Hitem:763|h[Frill 90]|h|r"
  local cand = "|cffa335ee|Hitem:764|h[Shield 100]|h|r"
  w.equippedSlots[17] = frill
  w.levels[frill], w.levels[cand] = 90, 100
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_SHIELD"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 6
  w.classIDs[frill], w.subclassIDs[frill] = 4, 0
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: shield over holdable equips", #w.equipped == 1)
end
do -- an unusable shield stays silent (usability still gates shields)
  local w = newWorld()
  w.pawn = false
  local shield = "|cffa335ee|Hitem:765|h[Shield 100]|h|r"
  w.levels[shield] = 100
  w.bags[0] = { shield }
  w.slots[shield] = "INVTYPE_SHIELD"
  w.classIDs[shield], w.subclassIDs[shield] = 4, 6
  w.notEquippable[shield] = true
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: unusable shield skipped", #w.equipped == 0 and #w.printed == 0)
end

-- 91. Cosmetics never count, on either source, and never schedule retries.
do -- fallback: a high-ilvl shirt is ignored, silently
  local w = newWorld()
  w.pawn = false
  local shirt = "|cffa335ee|Hitem:770|h[Shirt 100]|h|r"
  w.levels[shirt] = 100
  w.bags[0] = { shirt }
  w.slots[shirt] = "INVTYPE_BODY"
  w.classIDs[shirt], w.subclassIDs[shirt] = 4, 0
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: shirt ignored", #w.equipped == 0 and #w.printed == 0)
  check("fallback: shirt schedules no retry", #w.timers == 0)
end
do -- fallback: a tabard is ignored too
  local w = newWorld()
  w.pawn = false
  local tabard = "|cffa335ee|Hitem:771|h[Tabard 100]|h|r"
  w.levels[tabard] = 100
  w.bags[0] = { tabard }
  w.slots[tabard] = "INVTYPE_TABARD"
  w.classIDs[tabard], w.subclassIDs[tabard] = 4, 0
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: tabard ignored", #w.equipped == 0 and #w.printed == 0)
end
do -- fallback: a fishing pole never wins a weapon slot
  local w = newWorld()
  w.pawn = false
  local staff = "|cff0070dd|Hitem:907|h[Staff 90]|h|r"
  local pole = "|cffa335ee|Hitem:772|h[Pole 100]|h|r"
  w.equippedSlots[16] = staff
  w.levels[staff], w.levels[pole] = 90, 100
  w.bags[0] = { pole }
  w.slots[pole] = "INVTYPE_2HWEAPON"
  w.classIDs[pole], w.subclassIDs[pole] = 2, 20
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: pole over staff refused", #w.equipped == 0 and #w.printed == 0)
end
do -- Pawn path: a statless pole skips the unsure loop entirely
  local w = newWorld()
  local pole = "|cffa335ee|Hitem:772|h[Pole]|h|r"
  w.bags[0] = { pole }
  w.slots[pole] = "INVTYPE_2HWEAPON"
  w.classIDs[pole], w.subclassIDs[pole] = 2, 20
  w.pawnNil[pole] = true -- Pawn caches nothing for statless items
  local ns = loadAddon(w)
  ns.scan()
  check("Pawn: pole ignored", #w.equipped == 0 and #w.printed == 0)
  check("Pawn: pole schedules no retry", #w.timers == 0)
end
do -- a real weapon still displaces a wielded pole
  local w = newWorld()
  local pole = "|cff0070dd|Hitem:772|h[Pole]|h|r"
  local sword = "|cffa335ee|Hitem:905|h[Sword]|h|r"
  w.equippedSlots[16] = pole
  w.slots[pole], w.slots[sword] = "INVTYPE_2HWEAPON", "INVTYPE_WEAPON"
  w.classIDs[pole], w.subclassIDs[pole] = 2, 20
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.bags[0] = { sword }
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("sword over pole equips", #w.equipped == 1)
end

-- 92. The missing-equip-API notice honors the announce toggle.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:900|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.opts().announce = false -- set directly: clientLoaded would scan first
  w.env.C_Item.EquipItemByName = nil
  ns.scan()
  ns.scan()
  check("announce off: missing API stays silent", #w.equipped == 0 and #w.printed == 0)
end

-- 93. A mid-scan error clears the flag and still surfaces: no wedge,
-- no silence. The next trigger scans clean.
do
  local w = newWorld()
  local bad = "|cffa335ee|Hitem:880|h[Bad]|h|r"
  w.bags[0] = { bad }
  w.slots[bad] = "INVTYPE_HEAD"
  w.upgradeLists[bad] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  local realEquip = w.env.C_Item.EquipItemByName
  w.env.C_Item.EquipItemByName = function(item, slot)
    if item == bad then error("equip exploded") end
    return realEquip(item, slot)
  end
  local ok, err = pcall(ns.scan)
  check("mid-scan error surfaces with its cause", ok == false
    and tostring(err):find("equip exploded", 1) ~= nil)
  check("mid-scan error does not wedge", ns.scanning == false)
  w.env.C_Item.EquipItemByName = realEquip
  ns.scan()
  check("scan recovers after error", #w.equipped == 1 and ns.scanning == false)
end

-- 94. Unresolved items get five retries (~25s for slow caches), then go
-- quiet until the next bag event; a clean scan re-arms.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:560|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.pawnNil[link] = true
  local ns = loadAddon(w)
  local function fire()
    local fn = table.remove(w.timers, 1)
    if fn then fn() end
  end
  ns.scan() -- streak 1: retry scheduled
  check("first unsure schedules", #w.timers == 1)
  fire() -- streak 2
  check("second unsure schedules", #w.timers == 1)
  fire() -- streak 3
  fire() -- streak 4
  fire() -- streak 5: last retry scheduled
  check("fifth unsure schedules", #w.timers == 1)
  fire() -- streak 6: give up, no timer
  check("sixth unsure goes quiet", #w.timers == 0)
  w.bags[0] = {} -- the item leaves; a clean scan re-arms
  ns.scan()
  w.bags[0] = { link }
  ns.scan()
  check("clean scan re-arms retries", #w.timers == 1)
end

-- 98. Vault links enumerate item rewards, skip currency.
do
  local w = newWorld()
  local helm = "|cffa335ee|Hitem:90001|h[Vault Helm]|h|r"
  w.vaultActivities = {
    { rewards = {
      { type = 1, itemDBID = 101 },
      { type = 2, itemDBID = 102 },
      { type = 1, itemDBID = nil },
    } },
  }
  w.vaultLinks[101] = helm
  local ns = loadAddon(w)
  local links = ns.vaultLinks()
  check("one item link enumerated", links and #links == 1 and links[1] == helm)
end

-- 99. Vault recommend ranks tier completion above a higher Pawn score,
-- and 4pc completion above 2pc.
do
  local w = newWorld()
  specReady(w)
  local setID = 7001
  local worn = tierPiece(w, setID)
  w.equippedSlots[1] = worn
  w.slots[worn] = "INVTYPE_HEAD"
  local tierReward = tierPiece(w, setID)
  w.slots[tierReward] = "INVTYPE_SHOULDER"
  local pawnReward = "|cffa335ee|Hitem:90002|h[Vault Chest]|h|r"
  w.slots[pawnReward] = "INVTYPE_CHEST"
  w.vaultActivities = {
    { rewards = { { type = 1, itemDBID = 201 }, { type = 1, itemDBID = 202 } } },
  }
  w.vaultLinks[201] = tierReward
  w.vaultLinks[202] = pawnReward
  w.upgradeLists[tierReward] = upgrade("A", 0.02)
  w.upgradeLists[pawnReward] = upgrade("A", 0.20)
  local ns = loadAddon(w)
  local recs = ns.vaultRecommend()
  check("two picks ranked", recs and #recs == 2)
  check("2pc completion outranks score", recs[1].link == tierReward and recs[1].tierProgress == 3)
  check("runner-up keeps its score", recs[2].link == pawnReward)
end

-- 99b. Toward-4pc outranks starting a set; starting outranks raw score.
do
  local w = newWorld()
  specReady(w)
  local setA, setB = 7010, 7020
  local wornA1, wornA2 = tierPiece(w, setA), tierPiece(w, setA)
  w.equippedSlots[1], w.equippedSlots[3] = wornA1, wornA2
  w.slots[wornA1], w.slots[wornA2] = "INVTYPE_HEAD", "INVTYPE_SHOULDER"
  local toward4 = tierPiece(w, setA) -- 2 -> 3
  local starter = tierPiece(w, setB) -- 0 -> 1
  local plain = "|cffa335ee|Hitem:90007|h[Vault Plain]|h|r"
  w.slots[toward4], w.slots[starter], w.slots[plain] = "INVTYPE_CHEST", "INVTYPE_LEGS", "INVTYPE_FEET"
  w.vaultActivities = { { rewards = {
    { type = 1, itemDBID = 601 }, { type = 1, itemDBID = 602 }, { type = 1, itemDBID = 603 } } } }
  w.vaultLinks[601], w.vaultLinks[602], w.vaultLinks[603] = toward4, starter, plain
  w.upgradeLists[toward4] = upgrade("A", 0.01)
  w.upgradeLists[starter] = upgrade("A", 0.01)
  w.upgradeLists[plain] = upgrade("A", 0.30)
  local ns = loadAddon(w)
  local recs = ns.vaultRecommend()
  check("toward-4pc first", recs[1].link == toward4 and recs[1].tierProgress == 2)
  check("starter second", recs[2].link == starter and recs[2].tierProgress == 1)
  check("raw score last", recs[3].link == plain and recs[3].tierProgress == 0)
  check("verdict names the progress", ns.vaultVerdict(recs[1]):find("toward", 1, true) ~= nil)
end

-- 99c. A fifth piece of a completed set gets no tier priority.
do
  local w = newWorld()
  specReady(w)
  local setID = 7030
  for i, slot in ipairs({ 1, 3, 5, 7 }) do
    local p = tierPiece(w, setID)
    w.equippedSlots[slot] = p
    w.slots[p] = "INVTYPE_HEAD"
  end
  local fifth = tierPiece(w, setID)
  local plain = "|cffa335ee|Hitem:90008|h[Vault Plain2]|h|r"
  w.slots[fifth], w.slots[plain] = "INVTYPE_WRIST", "INVTYPE_WRIST"
  w.vaultActivities = { { rewards = { { type = 1, itemDBID = 701 }, { type = 1, itemDBID = 702 } } } }
  w.vaultLinks[701], w.vaultLinks[702] = fifth, plain
  w.upgradeLists[fifth] = upgrade("A", 0.02)
  w.upgradeLists[plain] = upgrade("A", 0.09)
  local ns = loadAddon(w)
  local recs = ns.vaultRecommend()
  check("completed set scores normally", recs[1].link == plain)
  check("fifth piece no priority", recs[2].tierProgress == 0)
end

-- 100. Vault recommend falls back to Pawn percent with no tier in play.
do
  local w = newWorld()
  specReady(w)
  local a = "|cffa335ee|Hitem:90003|h[Vault A]|h|r"
  local b = "|cffa335ee|Hitem:90004|h[Vault B]|h|r"
  w.slots[a], w.slots[b] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  w.vaultActivities = { { rewards = { { type = 1, itemDBID = 301 }, { type = 1, itemDBID = 302 } } } }
  w.vaultLinks[301], w.vaultLinks[302] = a, b
  w.upgradeLists[a] = upgrade("A", 0.03)
  w.upgradeLists[b] = upgrade("A", 0.11)
  local ns = loadAddon(w)
  local recs = ns.vaultRecommend()
  check("higher percent wins", recs and recs[1].link == b)
end

-- 101. /vg vault prints the top pick with its reason.
do
  local w = newWorld()
  specReady(w)
  local a = "|cffa335ee|Hitem:90005|h[Vault Pick]|h|r"
  w.slots[a] = "INVTYPE_HEAD"
  w.vaultActivities = { { rewards = { { type = 1, itemDBID = 401 } } } }
  w.vaultLinks[401] = a
  w.upgradeLists[a] = upgrade("A", 0.07)
  local ns = loadAddon(w)
  ns.vaultSay()
  check("vault pick announced", #w.printed == 1 and w.printed[1]:find("vault pick:", 1, true) ~= nil)
  check("percent in reason", w.printed[1]:find("+7.0%", 1, true) ~= nil)
end

-- 102. Auto-recommend fires once per claimable set.
do
  local w = newWorld()
  local a = "|cffa335ee|Hitem:90006|h[Vault Auto]|h|r"
  w.slots[a] = "INVTYPE_HEAD"
  w.vaultActivities = { { rewards = { { type = 1, itemDBID = 501 } } } }
  w.vaultLinks[501] = a
  w.upgradeLists[a] = upgrade("A", 0.05)
  w.vaultClaimable = true
  local ns = loadAddon(w)
  ns.maybeVaultRecommend()
  ns.maybeVaultRecommend()
  check("one announcement per set", #w.printed == 1)
  w.vaultClaimable = false
  ns.maybeVaultRecommend()
  w.vaultClaimable = true
  ns.maybeVaultRecommend()
  check("re-arms after claim", #w.printed == 2)
end

-- 103. No C_WeeklyRewards: vault commands degrade quietly.
do
  local w = newWorld()
  local ns = loadAddon(w)
  w.env.C_WeeklyRewards = nil
  check("vaultLinks nil without API", ns.vaultLinks() == nil)
  ns.vaultSay()
  check("vaultSay explains", #w.printed == 1 and w.printed[1]:find("no vault rewards", 1, true) ~= nil)
end

-- 104. Off-hand over a two-hand main hand: announced, never equipped.
do -- the warlock case: staff worn, frill in bags, no main hand to pair
  local w = newWorld()
  local staff = "|cff0070dd|Hitem:907|h[Staff A]|h|r"
  local frill = "|cffa335ee|Hitem:920|h[Frill]|h|r"
  w.equippedSlots[16] = staff
  w.slots[staff], w.slots[frill] = "INVTYPE_2HWEAPON", "INVTYPE_HOLDABLE"
  w.bags[0] = { frill }
  w.upgradeLists[frill] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  check("staff main hand strands", ns.offhandStrands(frill) == true)
  ns.scan()
  ns.scan()
  check("frill over staff not equipped", #w.equipped == 0)
  check("frill over staff announced once", #w.printed == 1)
  check("off-hand wording", w.printed[1]:find("one%-hand main hand", 1) ~= nil)
end
do -- bow main hand strands too (ranged two-handers block the off-hand)
  local w = newWorld()
  local bow = "|cff0070dd|Hitem:903|h[Bow A]|h|r"
  local frill = "|cffa335ee|Hitem:921|h[Frill]|h|r"
  w.equippedSlots[16] = bow
  w.slots[bow], w.slots[frill] = "INVTYPE_RANGED", "INVTYPE_HOLDABLE"
  w.bags[0] = { frill }
  w.upgradeLists[frill] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("frill over bow not equipped", #w.equipped == 0 and #w.printed == 1)
end
do -- one-hand main hand: the normal off-hand upgrade still equips
  local w = newWorld()
  local sword = "|cff0070dd|Hitem:905|h[Sword A]|h|r"
  local frill = "|cffa335ee|Hitem:922|h[Frill]|h|r"
  w.equippedSlots[16] = sword
  w.slots[sword], w.slots[frill] = "INVTYPE_WEAPON", "INVTYPE_HOLDABLE"
  w.bags[0] = { frill }
  w.upgradeLists[frill] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  check("one-hand main hand pairs", ns.offhandStrands(frill) == false)
  ns.scan()
  check("frill over sword equips", #w.equipped == 1)
end
do -- wand main hand pairs like a one-hander
  local w = newWorld()
  local wand = "|cff0070dd|Hitem:908|h[Wand]|h|r"
  local frill = "|cffa335ee|Hitem:923|h[Frill]|h|r"
  w.equippedSlots[16] = wand
  w.slots[wand], w.slots[frill] = "INVTYPE_RANGED", "INVTYPE_HOLDABLE"
  w.classIDs[wand], w.subclassIDs[wand] = 2, 19
  w.bags[0] = { frill }
  w.upgradeLists[frill] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("frill over wand equips", #w.equipped == 1)
end
do -- empty main hand still fills (nothing to unequip)
  local w = newWorld()
  local frill = "|cffa335ee|Hitem:924|h[Frill]|h|r"
  w.slots[frill] = "INVTYPE_HOLDABLE"
  w.bags[0] = { frill }
  w.upgradeLists[frill] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("frill into empty hands equips", #w.equipped == 1)
end
do -- non-off-hand candidates never trip the gate
  local w = newWorld()
  local staff = "|cff0070dd|Hitem:907|h[Staff A]|h|r"
  local sword = "|cffa335ee|Hitem:905|h[Sword]|h|r"
  w.equippedSlots[16] = staff
  w.slots[staff], w.slots[sword] = "INVTYPE_2HWEAPON", "INVTYPE_WEAPON"
  w.classIDs[staff], w.subclassIDs[staff] = 2, 10
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  local ns = loadAddon(w)
  check("main-hand candidate exempt", ns.offhandStrands(sword) == false)
end

-- 105. A paired main hand in bags equips first; the off-hand follows.
do
  local w = newWorld()
  local staff = "|cff0070dd|Hitem:907|h[Staff A]|h|r"
  local sword = "|cffa335ee|Hitem:905|h[Sword]|h|r"
  local frill = "|cffa335ee|Hitem:925|h[Frill]|h|r"
  w.equippedSlots[16] = staff
  w.slots[staff], w.slots[sword], w.slots[frill] =
    "INVTYPE_2HWEAPON", "INVTYPE_WEAPON", "INVTYPE_HOLDABLE"
  w.classIDs[staff], w.subclassIDs[staff] = 2, 10
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  w.bags[0] = { frill, sword } -- off-hand scanned first, still waits
  w.upgradeLists[frill] = upgrade("A", 0.05)
  w.upgradeLists[sword] = upgrade("A", 0.06)
  local ns = loadAddon(w)
  ns.scan()
  check("main hand equips first", #w.equipped == 1 and w.equipped[1].item == sword)
  ns.scan()
  check("off-hand follows", #w.equipped == 2 and w.equipped[2].item == frill)
  check("main hand never emptied", w.equippedSlots[16] == sword and w.equippedSlots[17] == frill)
end
do -- built-in fallback: empty off-hand slot is no license to drop a staff
  local w = newWorld()
  w.pawn = false
  local staff = "|cff0070dd|Hitem:907|h[Staff 90]|h|r"
  local frill = "|cffa335ee|Hitem:926|h[Frill 100]|h|r"
  w.equippedSlots[16] = staff
  w.levels[staff], w.levels[frill] = 90, 100
  w.bags[0] = { frill }
  w.slots[staff], w.slots[frill] = "INVTYPE_2HWEAPON", "INVTYPE_HOLDABLE"
  w.classIDs[frill], w.subclassIDs[frill] = 4, 0
  local ns = loadAddon(w)
  ns.scan()
  ns.scan()
  check("fallback: frill over staff not equipped", #w.equipped == 0)
  check("fallback: frill over staff announced once", #w.printed == 1)
end

-- 106. Restricted states wait out the scan instead of a forbidden equip.
do -- dead: dying drops combat, so regen can fire straight into this
  local w = newWorld()
  w.dead = true
  local link = "|cffa335ee|Hitem:930|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  check("dead reads restricted", ns.restricted() == true)
  ns.scan()
  check("dead equips nothing", #w.equipped == 0)
  check("dead waits silently", #w.printed == 0)
  check("dead schedules recheck", #w.timers == 1)
  w.dead = false -- rez: the recheck equips
  local fn = table.remove(w.timers, 1)
  if fn then fn() end
  check("recheck after rez equips", #w.equipped == 1)
end
do -- pet battle: its own lockdown, invisible to InCombatLockdown
  local w = newWorld()
  w.petBattle = true
  local link = "|cffa335ee|Hitem:931|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  check("pet battle reads restricted", ns.restricted() == true)
  ns.scan()
  check("pet battle equips nothing", #w.equipped == 0 and #w.printed == 0 and #w.timers == 1)
  w.petBattle = false
  local fn2 = table.remove(w.timers, 1)
  if fn2 then fn2() end
  check("recheck after battle equips", #w.equipped == 1)
  check("alive reads unrestricted", ns.restricted() == false)
end
do -- missing state APIs fail open (older client)
  local w = newWorld()
  local link = "|cffa335ee|Hitem:932|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  w.env.UnitIsDeadOrGhost = nil
  w.env.C_PetBattles = nil
  ns.scan()
  check("missing state APIs fail open", #w.equipped == 1)
end

-- 107. Poor (grey) gear never displaces worn gear, and class-unusable
-- shields never equip, on either source -- but an empty slot takes
-- anything, trash included. The Forever case: Pawn has no build there,
-- so the built-in fallback judges alone: no score path to ignore greys,
-- no CanEquip backstop to catch unwieldable verdicts.
do -- the reported bug: grey shield on a warlock, empty off-hand
  local w = newWorld()
  w.pawn = false
  w.playerClass = "WARLOCK"
  local shield = "|cff9d9d9d|Hitem:2362|h[Bent Large Shield]|h|r"
  w.levels[shield] = 10
  w.rarities[shield] = 0
  w.bags[0] = { shield }
  w.slots[shield] = "INVTYPE_SHIELD"
  w.classIDs[shield], w.subclassIDs[shield] = 4, 6
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: grey shield on warlock ignored", #w.equipped == 0 and #w.printed == 0)
  check("fallback: firm no schedules no retry", #w.timers == 0)
end
do -- the rarity gate stands alone: grey sword never displaces a worn blade
  local w = newWorld()
  w.pawn = false
  w.playerClass = "WARRIOR"
  local worn = "|cffffffff|Hitem:2134|h[Worn Sword]|h|r"
  local sword = "|cff9d9d9d|Hitem:2363|h[Bent Shortsword]|h|r"
  w.equippedSlots[16] = worn
  w.levels[worn], w.levels[sword] = 15, 10
  w.rarities[sword] = 0
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.classIDs[sword], w.subclassIDs[sword] = 2, 7
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: grey weapon never displaces", #w.equipped == 0 and #w.printed == 0)
end
do -- the shield gate stands alone: green shield on a warlock
  local w = newWorld()
  w.pawn = false
  w.playerClass = "WARLOCK"
  local shield = "|cff1eff00|Hitem:2364|h[Green Shield]|h|r"
  w.levels[shield] = 100
  w.rarities[shield] = 2
  w.bags[0] = { shield }
  w.slots[shield] = "INVTYPE_SHIELD"
  w.classIDs[shield], w.subclassIDs[shield] = 4, 6
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: green shield on warlock blocked", #w.equipped == 0 and #w.printed == 0)
end
do -- every shield class equips a green shield; nobody else does
  local members = { "WARRIOR", "PALADIN", "SHAMAN" }
  local others = { "HUNTER", "ROGUE", "MONK", "DRUID", "DEMONHUNTER",
    "DEATHKNIGHT", "MAGE", "PRIEST", "WARLOCK", "EVOKER" }
  for _, class in ipairs(members) do
    local w = newWorld()
    w.pawn = false
    w.playerClass = class
    local shield = "|cff1eff00|Hitem:2365|h[Green Shield]|h|r"
    w.levels[shield] = 100
    w.rarities[shield] = 2
    w.bags[0] = { shield }
    w.slots[shield] = "INVTYPE_SHIELD"
    w.classIDs[shield], w.subclassIDs[shield] = 4, 6
    local ns = loadAddon(w)
    ns.scan()
    check("fallback: shield equips for " .. class, #w.equipped == 1)
  end
  for _, class in ipairs(others) do
    local w = newWorld()
    w.pawn = false
    w.playerClass = class
    local shield = "|cff1eff00|Hitem:2365|h[Green Shield]|h|r"
    w.levels[shield] = 100
    w.rarities[shield] = 2
    w.bags[0] = { shield }
    w.slots[shield] = "INVTYPE_SHIELD"
    w.classIDs[shield], w.subclassIDs[shield] = 4, 6
    local ns = loadAddon(w)
    ns.scan()
    check("fallback: shield blocked for " .. class, #w.equipped == 0 and #w.printed == 0)
  end
end
do -- Pawn path: a flagged grey never displaces worn gear either
  local w = newWorld()
  w.playerClass = "WARRIOR"
  local worn = "|cffffffff|Hitem:2134|h[Worn Sword]|h|r"
  local sword = "|cff9d9d9d|Hitem:2363|h[Bent Shortsword]|h|r"
  w.equippedSlots[16] = worn
  w.rarities[sword] = 0
  w.bags[0] = { sword }
  w.slots[sword] = "INVTYPE_WEAPON"
  w.upgradeLists[sword] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("Pawn: flagged grey never displaces", #w.equipped == 0 and #w.printed == 0)
end
do -- Pawn path: a flagged shield for a warlock is dropped
  local w = newWorld()
  w.playerClass = "WARLOCK"
  local shield = "|cff1eff00|Hitem:2364|h[Green Shield]|h|r"
  w.rarities[shield] = 2
  w.bags[0] = { shield }
  w.slots[shield] = "INVTYPE_SHIELD"
  w.classIDs[shield], w.subclassIDs[shield] = 4, 6
  w.upgradeLists[shield] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("Pawn: flagged shield for warlock dropped", #w.equipped == 0 and #w.printed == 0)
end

do -- fallback: a skinning knife never displaces a worn dagger
  local w = newWorld()
  w.pawn = false
  local dagger = "|cffffffff|Hitem:2135|h[Worn Dagger]|h|r"
  local knife = "|cffffffff|Hitem:7005|h[Skinning Knife]|h|r"
  w.equippedSlots[16] = dagger
  w.levels[dagger], w.levels[knife] = 2, 4
  w.bags[0] = { knife }
  w.slots[knife] = "INVTYPE_WEAPON"
  w.classIDs[knife], w.subclassIDs[knife] = 2, 14 -- Weapon/Generic, like the classic tool
  w.classIDs[dagger], w.subclassIDs[dagger] = 2, 15
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: skinning knife over dagger refused", #w.equipped == 0 and #w.printed == 0)
  check("fallback: skinning knife schedules no retry", #w.timers == 0)
end
do -- fallback: a real dagger upgrade still equips (gate precision)
  local w = newWorld()
  w.pawn = false
  local worn = "|cffffffff|Hitem:2135|h[Worn Dagger]|h|r"
  local sharp = "|cff1eff00|Hitem:2136|h[Sharp Dagger]|h|r"
  w.equippedSlots[16] = worn
  w.levels[worn], w.levels[sharp] = 2, 5
  w.bags[0] = { sharp }
  w.slots[sharp] = "INVTYPE_WEAPON"
  w.classIDs[sharp], w.subclassIDs[sharp] = 2, 15
  w.classIDs[worn], w.subclassIDs[worn] = 2, 15
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: sharper dagger equips", #w.equipped == 1)
end
do -- Pawn path: a Pawn-flagged skinning knife is dropped too
  local w = newWorld()
  local knife = "|cffffffff|Hitem:7005|h[Skinning Knife]|h|r"
  w.bags[0] = { knife }
  w.slots[knife] = "INVTYPE_WEAPON"
  w.classIDs[knife], w.subclassIDs[knife] = 2, 14
  w.upgradeLists[knife] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("Pawn: flagged skinning knife dropped", #w.equipped == 0 and #w.printed == 0)
  check("Pawn: skinning knife schedules no retry", #w.timers == 0)
end
do -- Pawn path: profession-class equipment is never a combat upgrade
  local w = newWorld()
  local tool = "|cff1eff00|Hitem:7010|h[Tool]|h|r"
  w.bags[0] = { tool }
  w.slots[tool] = "INVTYPE_PROFESSION_TOOL"
  w.classIDs[tool], w.subclassIDs[tool] = 19, 0 -- Enum.ItemClass.Profession
  w.upgradeLists[tool] = upgrade("A", 0.05)
  local ns = loadAddon(w)
  ns.scan()
  check("Pawn: profession tool dropped", #w.equipped == 0 and #w.printed == 0)
end
do -- fallback: a grey cloak fills an empty back slot
  local w = newWorld()
  w.pawn = false
  local cloak = "|cff9d9d9d|Hitem:2375|h[Dingy Cloak]|h|r"
  w.levels[cloak] = 5
  w.rarities[cloak] = 0
  w.bags[0] = { cloak }
  w.slots[cloak] = "INVTYPE_CLOAK"
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: grey cloak fills empty back", #w.equipped == 1 and w.equipped[1].item == cloak)
end
do -- fallback: a grey cloak never displaces a worn cloak
  local w = newWorld()
  w.pawn = false
  local worn = "|cff1eff00|Hitem:2376|h[Green Cloak]|h|r"
  local cloak = "|cff9d9d9d|Hitem:2375|h[Dingy Cloak]|h|r"
  w.equippedSlots[15] = worn
  w.levels[worn], w.levels[cloak] = 10, 5
  w.rarities[cloak] = 0
  w.bags[0] = { cloak }
  w.slots[cloak] = "INVTYPE_CLOAK"
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: grey cloak never displaces", #w.equipped == 0 and #w.printed == 0)
end
do -- Pawn path: a grey cloak fills an empty back slot too
  local w = newWorld()
  local cloak = "|cff9d9d9d|Hitem:2375|h[Dingy Cloak]|h|r"
  w.levels[cloak] = 5
  w.rarities[cloak] = 0
  w.bags[0] = { cloak }
  w.slots[cloak] = "INVTYPE_CLOAK"
  local ns = loadAddon(w)
  ns.scan()
  check("Pawn: grey cloak fills empty back", #w.equipped == 1 and w.equipped[1].item == cloak)
end
do -- an above-level grey waits, even for an empty slot
  local w = newWorld()
  w.pawn = false
  local cloak = "|cff9d9d9d|Hitem:2375|h[Dingy Cloak]|h|r"
  w.levels[cloak] = 5
  w.rarities[cloak] = 0
  w.minLevels[cloak] = 85
  w.bags[0] = { cloak }
  w.slots[cloak] = "INVTYPE_CLOAK"
  local ns = loadAddon(w)
  ns.scan()
  check("above-level grey waits for empty back", #w.equipped == 0 and #w.printed == 0)
end
do -- why: above-level names the level
  local w = newWorld()
  local link = "|cffa335ee|Hitem:559|h[Helm]|h|r"
  w.slots[link] = "INVTYPE_HEAD"
  w.minLevels[link] = 85
  local ns = loadAddon(w)
  check("why: needs level", ns.whyNot(link, {}) :find("needs level 85", 1, true) ~= nil)
end
do -- why: grey into an occupied slot says so
  local w = newWorld()
  local held = "|cff1eff00|Hitem:2376|h[Green Cloak]|h|r"
  local cloak = "|cff9d9d9d|Hitem:2375|h[Dingy Cloak]|h|r"
  w.equippedSlots[15] = held
  w.rarities[cloak] = 0
  w.bags[0] = { cloak }
  w.slots[cloak] = "INVTYPE_CLOAK"
  local ns = loadAddon(w)
  check("why: grey occupied", ns.whyNot(cloak, { upgrade = false }):find("grey, slot occupied", 1, true) ~= nil)
end
do -- why: a Pawn silence names Pawn
  local w = newWorld()
  local link = "|cffa335ee|Hitem:560|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  local ns = loadAddon(w)
  local ev = ns.evaluate(link)
  check("why: no Pawn verdict", ns.whyNot(link, ev):find("no Pawn upgrade verdict", 1, true) ~= nil)
end
do -- why: a beaten item level shows both numbers
  local w = newWorld()
  w.pawn = false
  local worn = "|cff1eff00|Hitem:2376|h[Green Belt]|h|r"
  local cand = "|cff1eff00|Hitem:2377|h[Worn Belt]|h|r"
  w.equippedSlots[6] = worn
  w.levels[worn], w.levels[cand] = 10, 5
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_WAIST"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 4
  w.classIDs[worn], w.subclassIDs[worn] = 4, 4
  local ns = loadAddon(w)
  local ev = ns.evaluate(cand)
  check("why: ilvl vs worn", ns.whyNot(cand, ev):find("item level 5 vs worn 10", 1, true) ~= nil)
end
do -- why: wrong armor type for the class says so
  local w = newWorld()
  w.pawn = false
  w.playerClass = "MAGE"
  local belt = "|cff1eff00|Hitem:2378|h[Leather Belt]|h|r"
  w.bags[0] = { belt }
  w.slots[belt] = "INVTYPE_WAIST"
  w.classIDs[belt], w.subclassIDs[belt] = 4, 2
  local ns = loadAddon(w)
  local ev = ns.evaluate(belt)
  check("why: wrong armor type", ns.whyNot(belt, ev):find("wrong armor type", 1, true) ~= nil)
end
do -- /vg why reports each bag item with its reason
  local w = newWorld()
  local held = "|cff1eff00|Hitem:2376|h[Green Cloak]|h|r"
  local cloak = "|cff9d9d9d|Hitem:2375|h[Dingy Cloak]|h|r"
  w.equippedSlots[15] = held
  w.rarities[cloak] = 0
  w.bags[0] = { cloak }
  w.slots[cloak] = "INVTYPE_CLOAK"
  loadAddon(w)
  w.env.SlashCmdList.VOCGEAR("why")
  check("why: slash reports link", w.printed[1]:find("Dingy Cloak", 1, true) ~= nil)
  check("why: slash reports reason", w.printed[1]:find("grey, slot occupied", 1, true) ~= nil)
end
do -- /vg why on empty bags says so
  local w = newWorld()
  loadAddon(w)
  w.env.SlashCmdList.VOCGEAR("why")
  check("why: empty bags", w.printed[1]:find("bags hold no equipment", 1, true) ~= nil)
end
do -- fallback: a low-level hunter wears leather (pre-40 leveling type)
  local w = newWorld()
  w.pawn = false
  w.playerLevel = 5
  w.playerClass = "HUNTER"
  local belt = "|cff1eff00|Hitem:2186|h[Outfitter Belt]|h|r"
  w.levels[belt] = 5
  w.bags[0] = { belt }
  w.slots[belt] = "INVTYPE_WAIST"
  w.classIDs[belt], w.subclassIDs[belt] = 4, 2
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: young hunter belts leather", #w.equipped == 1 and w.equipped[1].item == belt)
end
do -- fallback: past 40 the hunter holds out for mail
  local w = newWorld()
  w.pawn = false
  w.playerClass = "HUNTER"
  local belt = "|cff1eff00|Hitem:2186|h[Outfitter Belt]|h|r"
  w.levels[belt] = 5
  w.bags[0] = { belt }
  w.slots[belt] = "INVTYPE_WAIST"
  w.classIDs[belt], w.subclassIDs[belt] = 4, 2
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: grown hunter refuses leather", #w.equipped == 0 and #w.printed == 0)
end
do -- fallback: a low-level warrior wears mail (pre-40 leveling type)
  local w = newWorld()
  w.pawn = false
  w.playerLevel = 5
  w.playerClass = "WARRIOR"
  local belt = "|cff1eff00|Hitem:2187|h[Mail Belt]|h|r"
  w.levels[belt] = 5
  w.bags[0] = { belt }
  w.slots[belt] = "INVTYPE_WAIST"
  w.classIDs[belt], w.subclassIDs[belt] = 4, 3
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: young warrior belts mail", #w.equipped == 1 and w.equipped[1].item == belt)
end
do -- fallback: white displaces grey on an item-level tie
  local w = newWorld()
  w.pawn = false
  local grey = "|cff9d9d9d|Hitem:2375|h[Dingy Belt]|h|r"
  local white = "|cff1eff00|Hitem:2377|h[Plain Belt]|h|r"
  w.equippedSlots[6] = grey
  w.levels[grey], w.levels[white] = 10, 10
  w.rarities[grey], w.rarities[white] = 0, 1
  w.bags[0] = { white }
  w.slots[white] = "INVTYPE_WAIST"
  w.classIDs[white], w.subclassIDs[white] = 4, 4
  w.classIDs[grey], w.subclassIDs[grey] = 4, 4
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: white displaces grey on tie", #w.equipped == 1 and w.equipped[1].item == white)
  check("fallback: tiebreak names rarity", w.printed[1]:find("higher rarity", 1, true) ~= nil)
end
do -- fallback: grey never displaces white, even tied
  local w = newWorld()
  w.pawn = false
  local white = "|cff1eff00|Hitem:2377|h[Plain Belt]|h|r"
  local grey = "|cff9d9d9d|Hitem:2375|h[Dingy Belt]|h|r"
  w.equippedSlots[6] = white
  w.levels[white], w.levels[grey] = 10, 10
  w.rarities[white], w.rarities[grey] = 1, 0
  w.bags[0] = { grey }
  w.slots[grey] = "INVTYPE_WAIST"
  w.classIDs[grey], w.subclassIDs[grey] = 4, 4
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: grey never displaces on tie", #w.equipped == 0 and #w.printed == 0)
end
do -- fallback: above grey, ties stand (stat question, not a rarity one)
  local w = newWorld()
  w.pawn = false
  local worn = "|cff1eff00|Hitem:2377|h[Plain Belt]|h|r"
  local cand = "|cff1eff00|Hitem:2379|h[Green Belt]|h|r"
  w.equippedSlots[6] = worn
  w.levels[worn], w.levels[cand] = 10, 10
  w.rarities[worn], w.rarities[cand] = 1, 2
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_WAIST"
  w.classIDs[cand], w.subclassIDs[cand] = 4, 4
  local ns = loadAddon(w)
  ns.scan()
  check("fallback: green-white tie stands", #w.equipped == 0 and #w.printed == 0)
end
do -- fallback two-slot: a tied white takes the grey ring slot when asked
  local w = newWorld()
  w.pawn = false
  w.savedVars = { autoTwoSlot = true }
  local greyRing = "|cff9d9d9d|Hitem:2380|h[Dingy Ring]|h|r"
  local otherRing = "|cff1eff00|Hitem:2381|h[Plain Ring]|h|r"
  local cand = "|cff1eff00|Hitem:2382|h[Bright Ring]|h|r"
  w.equippedSlots[11], w.equippedSlots[12] = greyRing, otherRing
  w.levels[greyRing], w.levels[otherRing], w.levels[cand] = 10, 12, 10
  w.rarities[greyRing], w.rarities[cand] = 0, 1
  w.classIDs[cand], w.subclassIDs[cand] = 4, 0 -- rings read as generic armor
  w.bags[0] = { cand }
  w.slots[cand] = "INVTYPE_FINGER"
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("fallback: tied white takes grey ring slot", #w.equipped == 1 and w.equipped[1].slot == 11)
end
do -- Forever layout: a bow upgrade compares against the ranged slot (18)
  local w = newWorld()
  w.pawn = false
  w.playerClass = "HUNTER"
  w.rangedSlot = 18
  local sword = "|cff1eff00|Hitem:2136|h[Sword]|h|r"
  local oldbow = "|cff1eff00|Hitem:2401|h[Old Bow]|h|r"
  local candbow = "|cff1eff00|Hitem:2402|h[New Bow]|h|r"
  w.equippedSlots[16], w.equippedSlots[18] = sword, oldbow
  w.levels[sword], w.levels[oldbow], w.levels[candbow] = 20, 5, 10
  w.bags[0] = { candbow }
  w.slots[candbow] = "INVTYPE_RANGED"
  w.classIDs[candbow], w.subclassIDs[candbow] = 2, 2
  local ns = loadAddon(w)
  ns.scan()
  check("forever: bow displaces bow at 18", #w.equipped == 1 and w.equipped[1].item == candbow)
  check("forever: ranged slot holds the bow", w.equippedSlots[18] == candbow)
end
do -- retail layout: no ranged slot, bows live in the main hand (16)
  local w = newWorld()
  w.pawn = false
  w.playerClass = "HUNTER"
  local oldbow = "|cff1eff00|Hitem:2401|h[Old Bow]|h|r"
  local candbow = "|cff1eff00|Hitem:2402|h[New Bow]|h|r"
  w.equippedSlots[16] = oldbow
  w.levels[oldbow], w.levels[candbow] = 5, 10
  w.bags[0] = { candbow }
  w.slots[candbow] = "INVTYPE_RANGED"
  w.classIDs[candbow], w.subclassIDs[candbow] = 2, 2
  local ns = loadAddon(w)
  ns.scan()
  check("retail: bow displaces bow at 16", #w.equipped == 1 and w.equippedSlots[16] == candbow)
end
do -- missing paperdoll API falls back to the main hand (16)
  local w = newWorld()
  w.pawn = false
  w.playerClass = "HUNTER"
  local oldbow = "|cff1eff00|Hitem:2401|h[Old Bow]|h|r"
  local candbow = "|cff1eff00|Hitem:2402|h[New Bow]|h|r"
  w.equippedSlots[16] = oldbow
  w.levels[oldbow], w.levels[candbow] = 5, 10
  w.bags[0] = { candbow }
  w.slots[candbow] = "INVTYPE_RANGED"
  w.classIDs[candbow], w.subclassIDs[candbow] = 2, 2
  local ns = loadAddon(w)
  w.env.C_PaperDollInfo = nil
  ns.scan()
  check("no paperdoll API: bow still equips at 16", #w.equipped == 1 and w.equippedSlots[16] == candbow)
end
print("tests/run.lua: " .. passed .. " checks passed")
