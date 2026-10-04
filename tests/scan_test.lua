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
      return nil, nil, world.rarities[link], nil, world.minLevels[link]
    end,
    GetDetailedItemLevelInfo = function(link) return world.levels[link] end,
  }
  g.UnitLevel = function() return world.playerLevel end
  g.GetTime = function() return world.time end
  g.InCombatLockdown = function() return world.inCombat end
  -- Game-chosen equip slot per equip loc, mirroring Pawn's slot table.
  local equipLocSlot = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3,
    INVTYPE_CHEST = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8,
    INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16,
    INVTYPE_SHIELD = 17, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_WEAPONOFFHAND = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 16 }
  g.EquipItemByName = function(item, slot)
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
      return {}
    end
    S.CreateCheckbox = function() world.settingsChecks = world.settingsChecks + 1 end
    S.CreateSliderOptions = function(min, max, step)
      world.sliderOpts = { min = min, max = max, step = step,
        SetLabelFormatter = function(_, f) world.sliderFormatter = f end }
      return world.sliderOpts
    end
    g.MinimalSliderWithSteppersMixin = { Label = { Right = "RIGHT" } }
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
  return { bags = {}, slots = {}, minLevels = {}, levels = {}, time = 1000,
           equippedSlots = {}, equipped = {}, printed = {}, timers = {},
           inCombat = false, pawn = true, pawnNil = {}, upgradeLists = {},
           armorBest = {}, rarities = {},
           ilvlDiffs = {}, scales = {}, savedVars = nil, playerLevel = 80,
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
  check("default threshold 0", o.minUpgradePct == 0)
  check("default two-slot manual", o.autoTwoSlot == false)
  check("default ilvl on", o.includeIlvl == true)
  check("default scale any", o.scale == "")
  check("default keepHeirlooms", o.keepHeirlooms == true)
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


-- 19. Settings panel-- 24. Settings panel registers all eight options.
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
      "autoTwoSlot", "includeIlvl", "keepHeirlooms", "scale" }) do
    check("setting registered: " .. k, keys[k] ~= nil)
  end
  check("six checkboxes", w.settingsChecks == 6)
  check("one slider", w.settingsSliders == 1)
  check("slider range", w.sliderOpts.min == 0 and w.sliderOpts.max == 25
    and w.sliderOpts.step == 5)
  check("slider value label", w.sliderFormatter == "RIGHT")
  check("one dropdown", #w.settingsDropdowns == 1)
  local scaleData = w.settingsDropdowns[1]()
  check("scale dropdown has Any + visible",
    #scaleData == 2 and scaleData[1].value == "" and scaleData[2].value == "A")
  check("built once", (function()
    local n = #w.settingsReg
    w.frame.onEvent(nil, "PLAYER_ENTERING_WORLD")
    return #w.settingsReg == n
  end)())
end

-- 20. Slash commands: toggle, announce, config hint.
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
  ns.scan() -- equips C
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

-- 25. Re-enabling clears the guard (/vg twice resumes now).
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

print("scan_test.lua: " .. passed .. " checks passed")
