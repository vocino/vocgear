-- VocGear regression tests. Stub-harness: no WoW client needed.
-- Run from anywhere:  lua tests/scan_test.lua   (repo root also fine)
--
-- Convention: each test resets stubs, drives ns.scan() or the frame's
-- OnEvent handler, and asserts. Any failed assert aborts with the test name.

local testDir = debug.getinfo(1, "S").source:gsub("\\", "/"):match("@?(.*/)") or ""
local mainPath = testDir .. "../main.lua"

local passed = 0
local function check(name, cond)
  if not cond then error("FAIL: " .. name, 2) end
  passed = passed + 1
end

-- Fresh stub world per test. Returns the ns table main.lua was loaded with.
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
  }
  g.InCombatLockdown = function() return world.inCombat end
  g.EquipItemByName = function(item)
    world.equipped[#world.equipped + 1] = item
  end
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
  g.PawnGetItemData = world.pawn and function() return {} end or nil
  g.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted = world.pawn and
    function(link) return world.upgrades[link] end or nil
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
  return { bags = {}, slots = {}, upgrades = {}, equipped = {},
           printed = {}, timers = {}, inCombat = false, pawn = true,
           savedVars = nil }
end

-- Simulate the client deserializing SavedVariables (a FRESH table replaces
-- the file-top default) and then firing ADDON_LOADED.
local function clientLoaded(w)
  w.env.VocGearDB = w.savedVars or {}
  w.frame.onEvent(nil, "ADDON_LOADED", "VocGear")
end

-- 1. SavedVariables: the loaded table replaces the file-top default, so the
-- addon must rebind to it on ADDON_LOADED or toggles never persist.
do
  local w = newWorld()
  w.savedVars = { enabled = false, announce = false }
  local ns = loadAddon(w)
  clientLoaded(w)
  check("db rebind keeps saved enabled=false", ns.opts().enabled == false)
  check("db rebind keeps saved announce=false", ns.opts().announce == false)
end

-- 2. Fresh profile gets defaults without clobbering.
do
  local w = newWorld()
  w.savedVars = {}
  local ns = loadAddon(w)
  clientLoaded(w)
  check("defaults enabled=true", ns.opts().enabled == true)
  check("defaults announce=true", ns.opts().announce == true)
end

-- 3. Single-slot upgrade is equipped by full link (exact bonus variant).
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:12345:0:0:0:0:0:0:0:80:0:0:0|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgrades[link] = true
  local ns = loadAddon(w)
  ns.scan()
  check("equips exactly one item", #w.equipped == 1)
  check("equips by full link", w.equipped[1] == link)
end

-- 4. Same base ID, different bonuses: each link is judged and equipped on
-- its own; equipping by ID could grab the wrong variant.
do
  local w = newWorld()
  local low = "|cffa335ee|Hitem:555:0:0:0:0:0:0:0:80:0:0:0|h[Helm L]|h|r"
  local high = "|cffa335ee|Hitem:555:0:0:0:0:0:0:0:85:0:0:0|h[Helm H]|h|r"
  w.bags[0] = { low, high }
  w.slots[low], w.slots[high] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  w.upgrades[low], w.upgrades[high] = true, true
  local ns = loadAddon(w)
  ns.scan()
  check("first scan equips one", #w.equipped == 1)
  check("first scan equips the first link exactly", w.equipped[1] == low)
end

-- 5. Rings/trinkets: announced per link, never equipped.
do
  local w = newWorld()
  local r1 = "|cffa335ee|Hitem:777:0:0:0:0:0:0:0:80|h[Ring A]|h|r"
  local r2 = "|cffa335ee|Hitem:777:0:0:0:0:0:0:0:85|h[Ring B]|h|r"
  w.bags[0] = { r1, r2 }
  w.slots[r1], w.slots[r2] = "INVTYPE_FINGER", "INVTYPE_FINGER"
  w.upgrades[r1], w.upgrades[r2] = true, true
  local ns = loadAddon(w)
  ns.scan()
  check("two-slot items never equipped", #w.equipped == 0)
  check("both bonus variants announced", #w.printed == 2)
  ns.scan() -- repeat scan must not re-announce
  check("announces are once per session per link", #w.printed == 2)
end

-- 6. Unknown slot type: announce, don't blind-equip.
do
  local w = newWorld()
  local link = "|cffa335ee|Hitem:999|h[Oddity]|h|r"
  w.bags[0] = { link }
  w.slots[link] = nil
  w.upgrades[link] = true
  local ns = loadAddon(w)
  ns.scan()
  check("unknown slot never equipped", #w.equipped == 0)
  check("unknown slot announced", #w.printed == 1)
end

-- 7. Pawn unsure (nil) or negative: skip quietly.
do
  local w = newWorld()
  local maybe = "|cffa335ee|Hitem:111|h[Maybe]|h|r"
  local no = "|cffa335ee|Hitem:222|h[No]|h|r"
  w.bags[0] = { maybe, no }
  w.slots[maybe], w.slots[no] = "INVTYPE_HEAD", "INVTYPE_HEAD"
  w.upgrades[maybe], w.upgrades[no] = nil, false
  local ns = loadAddon(w)
  ns.scan()
  check("nil/false answers equip nothing", #w.equipped == 0)
  check("nil/false answers print nothing", #w.printed == 0)
end

-- 8. Combat lockdown: no equip attempts.
do
  local w = newWorld()
  w.inCombat = true
  local link = "|cffa335ee|Hitem:333|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgrades[link] = true
  local ns = loadAddon(w)
  ns.scan()
  check("no equip in combat", #w.equipped == 0)
end

-- 9. Pawn missing: idle quietly, schedule one retry (init-order races).
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

-- 10. Disabled addon: full no-op, even with upgrades present.
do
  local w = newWorld()
  w.savedVars = { enabled = false }
  local link = "|cffa335ee|Hitem:666|h[Helm]|h|r"
  w.bags[0] = { link }
  w.slots[link] = "INVTYPE_HEAD"
  w.upgrades[link] = true
  local ns = loadAddon(w)
  clientLoaded(w)
  ns.scan()
  check("disabled addon equips nothing", #w.equipped == 0)
end

-- 11. Slash commands toggle without errors.
do
  local w = newWorld()
  local ns = loadAddon(w)
  clientLoaded(w)
  w.env.SlashCmdList.VOCGEAR("")
  check("/vg toggles off", ns.opts().enabled == false)
  w.env.SlashCmdList.VOCGEAR("announce")
  check("/vg announce toggles", ns.opts().announce == false)
end

print("scan_test.lua: " .. passed .. " checks passed")
