-- VocGear regression tests. Stub-harness: no WoW client needed.
-- Run from anywhere:  lua tests/scan_test.lua   (repo root also fine)
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
    GetItemInfoInstant = function(link) return nil, nil, nil, world.slots[link] end,
    GetItemInfo = function(link)
      return nil, nil, nil, nil, world.minLevels[link]
    end,
    GetDetailedItemLevelInfo = function(link) return world.levels[link] end,
  }
  g.UnitLevel = function() return world.playerLevel end
  g.InCombatLockdown = function() return world.inCombat end
  g.EquipItemByName = function(item, slot)
    world.equipped[#world.equipped + 1] = { item = item, slot = slot }
    -- Like the real client, the equipped item leaves the bags.
    for _, b in pairs(world.bags) do
      for i = #b, 1, -1 do
        if b[i] == item then table.remove(b, i) end
      end
    end
  end
  g.GetInventoryItemLink = function(_, slot) return world.equippedSlots[slot] end
  g.C_Timer = {
    After = function(_, fn) world.timers[#world.timers + 1] = fn end,
  }
  g.SlashCmdList = {}
  local frame = { events = {} }
  frame.RegisterEvent = function(_, e) frame.events[e] = true end
  frame.SetScript = function(_, _, fn) frame.onEvent = fn end
  g.CreateFrame = function() return frame end
  world.frame = frame
  -- Pawn stubs (nil them out to simulate Pawn missing/not ready).
  g.PawnGetItemData = world.pawn and
    function(link)
      if world.pawnNil[link] then return nil end
      return { Link = link, Level = world.levels[link] or 80 }
    end or nil
  g.PawnIsItemAnUpgrade = world.pawn and
    function(item) return world.upgradeLists[item.Link] end or nil
  g.PawnIsItemAnItemLevelUpgrade = world.pawn and
    function(item) return world.ilvlDiffs[item.Link] end or nil
  g.PawnGetAllScalesEx = world.pawn and
    function() return world.scales end or nil
  g.PawnUnenchantItemLink = world.pawn and
    function(link) return link end or nil
  -- Quest + loot stubs.
  g.GetNumQuestChoices = function() return #world.questChoices end
  g.GetQuestItemLink = function(_, i) return world.questChoices[i] end
  g.GetQuestReward = function(i) world.questTaken[#world.questTaken + 1] = i end
  g.GetLootRollItemLink = function(rollID) return world.rolls[rollID] end
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
      return {}
    end
    S.CreateCheckbox = function() world.settingsChecks = world.settingsChecks + 1 end
    S.CreateSliderOptions = function(min, max, step)
      world.sliderOpts = { min = min, max = max, step = step }
      return world.sliderOpts
    end
    S.CreateSlider = function() world.settingsSliders = world.settingsSliders + 1 end
    S.CreateDropdown = function(_, _, getOptions)
      world.settingsDropdowns[#world.settingsDropdowns + 1] = getOptions
    end
    S.CreateControlTextContainer = function()
      local t = { data = {} }
      t.Add = function(_, value, text) t.data[#t.data + 1] = { value = value, text = text } end
      t.GetData = function() return t.data end
      return t
    end
    g.Settings = S
  end
  g.VocGearDB = nil -- client hasn't restored SavedVariables at file-exec time

  local f = assert(io.open(mainPath, "r"))
  local src = f:read("*a")
  f:close()
  -- Fourth-arg env works on 5.2+; main.lua itself stays 5.1-clean for WoW.
  local chunk = assert(load(src, "@" .. mainPath, "t", g))
  local ns = {}
  chunk("VocGear", ns)
  world.ns = ns
  world.env = g
  return ns
end

local function newWorld()
  return { bags = {}, slots = {}, minLevels = {}, levels = {},
           equippedSlots = {}, equipped = {}, printed = {}, timers = {},
           inCombat = false, pawn = true, pawnNil = {}, upgradeLists = {},
           ilvlDiffs = {}, scales = {}, savedVars = nil, playerLevel = 80,
           questChoices = {}, questTaken = {}, rolls = {},
           withSettings = false, settingsReg = {}, settingsChecks = 0,
           settingsSliders = 0, settingsDropdowns = {} }
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
  check("default threshold 0.5", o.minUpgradePct == 0.5)
  check("default two-slot manual", o.autoTwoSlot == false)
  check("default ilvl on", o.includeIlvl == true)
  check("default scale any", o.scale == "")
  check("default quest highlight", o.questPicker == "highlight")
  check("default loot advisor on", o.lootAdvisor == true)
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
  local link = "|cffa335ee|Hitem:555|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgradeLists[link] = upgrade("A", 0.004) -- 0.4% < 0.5% default bar
  local ns = loadAddon(w)
  ns.scan()
  check("below-threshold skipped", #w.equipped == 0)
  check("below-threshold silent", #w.printed == 0)
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

-- 17. Pawn missing: idle quietly, schedule one retry.
do
  local w = newWorld()
  w.pawn = false
  local link = "|cffa335ee|Hitem:444|h[Helm]|h|r"
  w.bags[0] = { link }
  local ns = loadAddon(w)
  check("pawnReady false without Pawn", ns.pawnReady() == false)
  ns.scan()
  ns.scan()
  check("no equip without Pawn", #w.equipped == 0)
  check("exactly one retry scheduled", #w.timers == 1)
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

-- 19. Quest picker highlights the best choice by default.
do
  local w = newWorld()
  local bad = "|cff0070dd|Hitem:300|h[Bad]|h|r"
  local good = "|cffa335ee|Hitem:301|h[Good]|h|r"
  w.questChoices = { bad, good }
  w.upgradeLists[good] = upgrade("A", 0.08)
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "QUEST_COMPLETE")
  check("highlight prints the pick", #w.printed == 1)
  check("highlight names best", w.printed[1]:find("Good", 1) ~= nil)
  check("highlight takes nothing", #w.questTaken == 0)
end

-- 20. Quest picker auto-picks the best choice.
do
  local w = newWorld()
  w.savedVars = { questPicker = "auto" }
  local good = "|cffa335ee|Hitem:301|h[Good]|h|r"
  local bad = "|cff0070dd|Hitem:300|h[Bad]|h|r"
  w.questChoices = { good, bad }
  w.upgradeLists[good] = upgrade("A", 0.08)
  local ns = loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "QUEST_COMPLETE")
  check("auto takes best index", #w.questTaken == 1 and w.questTaken[1] == 1)
end

-- 21. Quest picker: off / single choice / no upgrade stay quiet-ish.
do
  local w = newWorld()
  w.savedVars = { questPicker = "off" }
  w.questChoices = { "|cff0070dd|Hitem:300|h[A]|h|r", "|cff0070dd|Hitem:301|h[B]|h|r" }
  local ns = loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "QUEST_COMPLETE")
  check("quest off is silent", #w.printed == 0 and #w.questTaken == 0)
end
do
  local w = newWorld()
  w.questChoices = { "|cff0070dd|Hitem:300|h[Only]|h|r" }
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "QUEST_COMPLETE")
  check("single choice is silent", #w.printed == 0 and #w.questTaken == 0)
end
do
  local w = newWorld()
  w.savedVars = { questPicker = "auto" }
  w.questChoices = { "|cff0070dd|Hitem:300|h[A]|h|r", "|cff0070dd|Hitem:301|h[B]|h|r" }
  local ns = loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "QUEST_COMPLETE")
  check("no upgrade takes nothing", #w.questTaken == 0)
  check("no upgrade says so", #w.printed == 1)
end

-- 22. Audit mode degrades quest auto-pick to highlight.
do
  local w = newWorld()
  w.savedVars = { questPicker = "auto", audit = true }
  local good = "|cffa335ee|Hitem:301|h[Good]|h|r"
  w.questChoices = { good, "|cff0070dd|Hitem:300|h[Bad]|h|r" }
  w.upgradeLists[good] = upgrade("A", 0.08)
  local ns = loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "QUEST_COMPLETE")
  check("audit takes nothing", #w.questTaken == 0)
  check("audit still highlights", #w.printed == 1)
end

-- 23. Loot advisor: NEED upgrades, GREED the rest, silence when unsure.
do
  local w = newWorld()
  local up = "|cffa335ee|Hitem:400|h[Up]|h|r"
  w.rolls[7] = up
  w.upgradeLists[up] = upgrade("A", 0.1)
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "START_LOOT_ROLL", 7)
  check("upgrade advises NEED", w.printed[1]:find("NEED", 1) ~= nil)
end
do
  local w = newWorld()
  local no = "|cff0070dd|Hitem:401|h[No]|h|r"
  w.rolls[8] = no
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "START_LOOT_ROLL", 8)
  check("non-upgrade advises GREED", w.printed[1]:find("GREED", 1) ~= nil)
end
do
  local w = newWorld()
  local maybe = "|cffa335ee|Hitem:402|h[Maybe]|h|r"
  w.rolls[9] = maybe
  w.pawnNil[maybe] = true
  local ns = loadAddon(w)
  w.frame.onEvent(nil, "START_LOOT_ROLL", 9)
  check("unsure stays silent", #w.printed == 0)
end
do
  local w = newWorld()
  w.savedVars = { lootAdvisor = false }
  local up = "|cffa335ee|Hitem:400|h[Up]|h|r"
  w.rolls[7] = up
  w.upgradeLists[up] = upgrade("A", 0.1)
  local ns = loadAddon(w)
  clientLoaded(w)
  w.frame.onEvent(nil, "START_LOOT_ROLL", 7)
  check("advisor off is silent", #w.printed == 0)
end

-- 24. Settings panel registers all nine options.
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
      "autoTwoSlot", "includeIlvl", "scale", "questPicker", "lootAdvisor" }) do
    check("setting registered: " .. k, keys[k] ~= nil)
  end
  check("six checkboxes", w.settingsChecks == 6)
  check("one slider", w.settingsSliders == 1)
  check("slider range", w.sliderOpts.min == 0.5 and w.sliderOpts.max == 25
    and w.sliderOpts.step == 0.5)
  check("two dropdowns", #w.settingsDropdowns == 2)
  local scaleData = w.settingsDropdowns[1]()
  check("scale dropdown has Any + visible",
    #scaleData == 2 and scaleData[1].value == "" and scaleData[2].value == "A")
  local questData = w.settingsDropdowns[2]()
  check("quest dropdown has three modes", #questData == 3)
  check("built once", (function()
    local n = #w.settingsReg
    w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
    return #w.settingsReg == n
  end)())
end

-- 25. Slash commands: toggle, announce, config hint.
do
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  w.env.SlashCmdList.VOCGEAR("")
  check("/vg toggles off", ns.opts().enabled == false)
  w.env.SlashCmdList.VOCGEAR("announce")
  check("/vg announce toggles", ns.opts().announce == false)
  w.env.SlashCmdList.VOCGEAR("config")
  check("/vg config prints hint without Settings",
    w.printed[#w.printed]:find("Settings > AddOns", 1) ~= nil)
end

print("scan_test.lua: " .. passed .. " checks passed")
