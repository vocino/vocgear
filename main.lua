local name, ns = ...
-- VocGear: equip bag upgrades out of combat. Pawn's verdict when Pawn is
-- driving, item level when it is not. Nothing else (plus advice).

-- VocDebug guest hook: silent no-op unless the debug addon is loaded.
local dbg = VOCDBG or function() end

VocGearDB = VocGearDB or {}
ns.db = VocGearDB

-- Chat voice shared by every Voc addon (see FAMILY.md): one line, the
-- addon name as a colored prefix, then the message.
ns.PREFIX_COLOR = "ff66ccff"
function ns.say(msg)
  print("|c" .. ns.PREFIX_COLOR .. name .. "|r: " .. tostring(msg))
end

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
  protectSets = true,
  scale = "",
  sheetButton = true,
  equipSound = "878", -- "0" = off; others are SOUNDKIT IDs, see ns.EQUIP_SOUNDS
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

-- Equip celebration sound. IDs verified in Blizzard_SharedXML/Mainline
-- SoundKitConstants.lua (live branch): these are the client's own UI
-- chimes, played with PlaySound so they honor the player's volume.
-- "0" disables the sound. The quest-complete chime is the default: a
-- chill ding, audibly distinct from the level-up fanfare.
ns.EQUIP_SOUNDS = {
  { id = "878", label = "Quest chime" }, -- IG_QUEST_LIST_COMPLETE
  { id = "23404", label = "Auto quest complete" }, -- UI_AUTO_QUEST_COMPLETE
  { id = "73277", label = "World quest complete" }, -- UI_WORLDQUEST_COMPLETE
}

-- Play the configured equip sound. Silent when off, when PlaySound is
-- unavailable, or when the ID is unknown: a sound must never error.
function ns.playEquipSound()
  local id = tonumber(ns.opts().equipSound) or 0
  if id == 0 then return end
  if type(PlaySound) ~= "function" then return end
  pcall(PlaySound, id)
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

-- Pawn is the upgrade source when its API is present. Pawn itself filters
-- by visible scales; a loaded Pawn with no scales simply finds nothing,
-- and the item-level toggle still applies. When Pawn is absent entirely,
-- the built-in fallback drives.
function ns.pawnActive()
  return ns.pawnReady()
end

-- Pawn installed and loadable but not loaded yet: its ADDON_LOADED will
-- trigger a rescan, so wait instead of falling back for a single pass and
-- switching systems mid-session. A missing or disabled Pawn falls back
-- immediately (this is also the Forever path: Pawn has no Forever build).
function ns.pawnPending()
  if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("Pawn") then
    return false
  end
  if type(GetAddOnInfo) ~= "function" then return false end
  local ok, installedName, _, _, loadable = pcall(GetAddOnInfo, "Pawn")
  return ok and installedName ~= nil and loadable
end

-- Which system is deciding upgrades right now. Shown in settings and in
-- announcements so the player always knows what is driving.
function ns.sourceLabel()
  if ns.pawnActive() then return "Pawn" end
  return "item level"
end

-- Answer "is this link an upgrade?", through Pawn when it is driving and
-- through the built-in item-level fallback otherwise.
-- Returns nil when unsure (data uncached or erroring), else:
--   { upgrade=bool, percent=ratio|nil, existing=link|nil,
--     ilvl=bool, ilvlDiff=n|nil, itemLevel=n|nil }
function ns.evaluate(link)
  -- Min-level gate, both paths (what CheckLevel=true did on Pawn's old API).
  local _, _, _, _, minLevel = C_Item.GetItemInfo(link)
  if minLevel and UnitLevel("player") < minLevel then
    return { upgrade = false }
  end
  if ns.pawnActive() then
    return ns.evaluatePawn(link)
  end
  return ns.evaluateBuiltin(link)
end

function ns.evaluatePawn(link)
  local o = ns.opts()
  local ok, item = pcall(_G.PawnGetItemData, link)
  if not ok or not item or item.Link == nil then return nil end
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

-- Class best armor, Enum.ItemArmorSubclass (ItemConstantsDocumentation,
-- live 12.1.0): Cloth 1, Leather 2, Mail 3, Plate 4.
ns.ARMOR_BEST = {
  WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4,
  HUNTER = 3, SHAMAN = 3, EVOKER = 3,
  ROGUE = 2, MONK = 2, DRUID = 2, DEMONHUNTER = 2,
  MAGE = 1, PRIEST = 1, WARLOCK = 1,
}

-- Armor-type gate for the built-in path (Pawn's own gate is unavailable).
-- A candidate passes when it matches the class best type, or when it
-- matches what is already worn (leveling in a lower armor type).
-- Cloaks have no proficiency gate. Unknown data reads as unsure (nil),
-- never as a yes: a firm answer waits for the item cache.
function ns.armorBestBuiltin(link)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  if equipLoc == "INVTYPE_CLOAK" then return true end
  if classID == nil or subclassID == nil then return nil end
  if classID ~= 4 or subclassID == 0 or subclassID == 5 then return true end
  local _, classKey = UnitClass("player")
  local best = classKey and ns.ARMOR_BEST[classKey]
  if best and subclassID == best then return true end
  local slotID = equipLoc and ns.primarySlot[equipLoc]
  local held = slotID and GetInventoryItemLink("player", slotID)
  if held then
    local _, _, _, _, _, hClass, hSub = C_Item.GetItemInfoInstant(held)
    if hClass == 4 and hSub == subclassID then return true end
  end
  return false
end

-- Built-in upgrade check: pure item level, no stat weights. Fires only
-- when Pawn is not driving. Same result shape as the Pawn path, so the
-- scan, safeguards, and announcements downstream need no changes.
function ns.evaluateBuiltin(link)
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
  if not equipLoc or equipLoc == "" then return { upgrade = false } end
  local armorOK = ns.armorBestBuiltin(link)
  if armorOK == nil then return nil end
  if not armorOK then return { upgrade = false } end
  local candLevel = C_Item.GetDetailedItemLevelInfo(link)
  if not candLevel then return nil end
  local pair = ns.slotPairs[equipLoc]
  if pair then
    -- Two-slot: upgrade when it beats the weaker of the pair.
    local weakLevel
    for _, slotID in ipairs(pair) do
      local held = GetInventoryItemLink("player", slotID)
      if not held then
        return { upgrade = true, ilvl = true, ilvlDiff = candLevel, itemLevel = candLevel }
      end
      local lvl = C_Item.GetDetailedItemLevelInfo(held)
      if lvl and (not weakLevel or lvl < weakLevel) then weakLevel = lvl end
    end
    if not weakLevel then return nil end
    local diff = candLevel - weakLevel
    return { upgrade = diff > 0, ilvl = true, ilvlDiff = diff, itemLevel = candLevel }
  end
  local slotID = ns.primarySlot[equipLoc]
  if not slotID then return { upgrade = false } end
  local held = GetInventoryItemLink("player", slotID)
  if not held then
    return { upgrade = true, ilvl = true, ilvlDiff = candLevel, itemLevel = candLevel }
  end
  local heldLevel = C_Item.GetDetailedItemLevelInfo(held)
  if not heldLevel then return nil end
  local diff = candLevel - heldLevel
  return { upgrade = diff > 0, ilvl = true, ilvlDiff = diff, itemLevel = candLevel }
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
    ns.say("keeping heirloom " .. held .. " (" .. link .. " is an upgrade)")
  end
end

-- Weapon-kind gate. Bows, guns, and crossbows share main-hand slot 16
-- with melee, and Pawn scores them together: it normalizes ranged to
-- 2H (wands to MH 1H, Pawn 2.13.16 Pawn.lua:1423); the item-level path
-- has no weapon check at all. A swap across the melee/ranged line can
-- disable a whole action bar (BM hunter + sword), so VocGear
-- announces those swaps and leaves them to the player, both ways.
-- Unknown kinds fail open: an undetectable weapon still equips.
-- Enum.ItemWeaponSubclass (ItemConstantsDocumentation, live 12.1.0).
ns.RANGED_SUBCLASS = { [2] = true, [3] = true, [18] = true } -- Bows, Guns, Crossbow
ns.WAND_SUBCLASS = 19 -- Enum.ItemWeaponSubclass.Wand, same source
function ns.weaponKind(link)
  if not link then return nil end
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
  if equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
    if subclassID == ns.WAND_SUBCLASS then return "melee" end -- wand: MH 1H, like Pawn
    return "ranged"
  end
  if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND"
      or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_2HWEAPON"
      or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
    if classID == 2 and ns.RANGED_SUBCLASS[subclassID] then return "ranged" end -- belt
    return "melee"
  end
  return nil -- not a weapon
end

function ns.weaponKindCrosses(link, held)
  if not held then return false end
  local cand, cur = ns.weaponKind(link), ns.weaponKind(held)
  if not cand or not cur then return false end
  return cand ~= cur
end

function ns.announceWeaponKind(link, ev)
  local o = ns.opts()
  if o.announce and not ns.flagged[link] then
    ns.flagged[link] = true
    ns.say(ns.sourceLabel() .. " upgrade in bags (melee/ranged swap, not auto-equipped): " .. link .. ns.why(ev))
  end
end

-- Set bonus handling. Pawn scores pure stats and never values 2pc/4pc
-- bonuses (verified: no set handling in Pawn 2.13.16), so an unguided
-- equip can silently break an active bonus while a bonus-completing tier
-- piece never surfaces. Sets are handled as a gate, not a weight: bonus
-- value is spec- and bonus-specific, so no static number is right. With
-- "Prioritize set bonuses" on, a bag piece that completes a bonus equips
-- automatically, and anything that would break an active bonus is
-- announced instead. Breaking a set yourself declines it for the
-- session: VocGear leaves that set alone until you reload.
--
-- Detection (verified in Blizzard_APIDocumentationGenerated, branch live):
-- C_Item.GetItemInfo's 16th return is the setID, C_Item.GetItemInfoInstant's
-- 1st return is the base itemID, C_Item.GetSetBonusesForSpecializationByItemID
-- lists the set's bonus spells for a spec (non-empty = worth protecting),
-- and C_SpecializationInfo.GetSpecialization + GetSpecializationInfo
-- resolve the current specID. Piece-count thresholds have no API, so the
-- modern 2/4 layout is assumed: legacy sets with wider layouts are
-- under-protected, never over-protected.
ns.SET_THRESHOLDS = { 2, 4 }
ns.setDeclined = {} -- setID -> true, per session

-- Set membership of a link, or nil (not a set piece, or data uncached).
-- Unknown reads as "no set action" (fail open, like the weapon gate).
function ns.setID(link)
  if not link then return nil end
  local ok, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID = pcall(C_Item.GetItemInfo, link)
  if not ok then return nil end
  return setID
end

-- Current spec's ID, or nil when undetectable (fail open: no set logic).
function ns.playerSpecID()
  if type(C_SpecializationInfo) ~= "table" then return nil end
  if type(C_SpecializationInfo.GetSpecialization) ~= "function" then return nil end
  if type(C_SpecializationInfo.GetSpecializationInfo) ~= "function" then return nil end
  local okIdx, idx = pcall(C_SpecializationInfo.GetSpecialization)
  if not okIdx or type(idx) ~= "number" then return nil end
  local okID, specID = pcall(C_SpecializationInfo.GetSpecializationInfo, idx)
  if not okID or type(specID) ~= "number" or specID == 0 then return nil end
  return specID
end

-- True when the link's set grants bonuses to the given spec. Anything
-- unknown (no set, no itemID, API hiccup) reads as false: only confirmed
-- bonus sets are protected or completed.
function ns.setHasBonuses(link, specID)
  if not link or type(specID) ~= "number" then return false end
  if ns.setID(link) == nil then return false end
  local itemID = C_Item.GetItemInfoInstant(link)
  if type(itemID) ~= "number" then return false end
  local ok, spells = pcall(C_Item.GetSetBonusesForSpecializationByItemID, specID, itemID)
  return ok and type(spells) == "table" and #spells > 0
end

function ns.setName(setID)
  local ok, label = pcall(C_Item.GetItemSetInfo, setID)
  if ok and type(label) == "string" and label ~= "" then return label end
  return nil
end

-- "Testplate 4pc", or just "4pc" when the set name is unavailable.
function ns.bonusLabel(setID, threshold)
  local label = setID and ns.setName(setID) or nil
  if label then return label .. " " .. threshold .. "pc" end
  return threshold .. "pc"
end

-- Equipped pieces per setID, from live slots or a snapshot.
function ns.setCounts()
  local counts = {}
  for slotID = 1, 19 do
    local id = ns.setID(GetInventoryItemLink("player", slotID))
    if id then counts[id] = (counts[id] or 0) + 1 end
  end
  return counts
end

function ns.setCountsForSnap(snap)
  local counts = {}
  if snap then
    for slotID = 1, 19 do
      local id = ns.setID(snap[slotID])
      if id then counts[id] = (counts[id] or 0) + 1 end
    end
  end
  return counts
end

-- Per-scan set state, or nil when set logic is off or the spec is
-- unknown (fail open: pure Pawn behavior).
function ns.setContext()
  if not ns.opts().protectSets then return nil end
  local specID = ns.playerSpecID()
  if not specID then return nil end
  return { specID = specID, counts = ns.setCounts() }
end

-- Threshold (2/4) equipping link over held would break, plus the set;
-- nil when nothing breaks. Same-set swaps change no count, and declined
-- sets are left alone, so neither ever vetoes.
function ns.setBreaks(ctx, link, held)
  if not ctx or not held then return nil end
  local heldSet = ns.setID(held)
  if not heldSet or ns.setDeclined[heldSet] then return nil end
  if ns.setID(link) == heldSet then return nil end
  if not ns.setHasBonuses(held, ctx.specID) then return nil end
  local n = ctx.counts[heldSet] or 0
  for _, t in ipairs(ns.SET_THRESHOLDS) do
    if n == t then return t, heldSet end
  end
  return nil
end

-- Candidate-level completion precheck (no held item needed): threshold
-- and set when the link belongs to a protected set sitting exactly one
-- piece below a bonus. The equip path confirms the swap actually adds a
-- piece (same-set swaps don't).
function ns.setCompletionReady(ctx, link)
  if not ctx then return nil end
  local candSet = ns.setID(link)
  if not candSet or ns.setDeclined[candSet] then return nil end
  if not ns.setHasBonuses(link, ctx.specID) then return nil end
  local n = ctx.counts[candSet] or 0
  for _, t in ipairs(ns.SET_THRESHOLDS) do
    if n + 1 == t then
      -- Level gate, same as evaluate's: above-level pieces never complete.
      local okLvl, _, _, _, _, minLevel = pcall(C_Item.GetItemInfo, link)
      if okLvl and minLevel and UnitLevel("player") < minLevel then return nil end
      return t, candSet
    end
  end
  return nil
end

-- A ready completion only fires when the swap adds a set piece.
function ns.setSwapCompletes(held, readyThreshold, readySet)
  if readyThreshold and ns.setID(held) ~= readySet then return readyThreshold end
  return nil
end

-- Manual set changes are decisions: a downward threshold crossing (a
-- bonus just broke) declines the set for the session, an upward one (a
-- bonus just completed) clears the decline. Our own equips never cross
-- downward (the veto forbids it), so any crossing seen here is the
-- player's doing.
function ns.trackSetCrossings(prevSnap, snap)
  local before, after = ns.setCountsForSnap(prevSnap), ns.setCountsForSnap(snap)
  local seen = {}
  for id in pairs(before) do seen[id] = true end
  for id in pairs(after) do seen[id] = true end
  for id in pairs(seen) do
    local b, a = before[id] or 0, after[id] or 0
    if b ~= a then
      for _, t in ipairs(ns.SET_THRESHOLDS) do
        if b >= t and a < t then ns.setDeclined[id] = true end
        if b < t and a >= t then ns.setDeclined[id] = nil end
      end
    end
  end
end

function ns.announceSetBreak(link, breakSet, threshold)
  local o = ns.opts()
  if o.announce and not ns.flagged[link] then
    ns.flagged[link] = true
    ns.say("not equipping " .. link .. " (would break " .. ns.bonusLabel(breakSet, threshold) .. ")")
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
  local base = ""
  if ev.ilvl then base = " (item level +" .. tostring(ev.ilvlDiff or "?") .. ")"
  elseif ev.percent and ev.percent >= 100 then base = " (big upgrade)"
  elseif ev.percent then base = string.format(" (+%.1f%%)", ev.percent * 100) end
  if ev.completes then base = base .. " (completes " .. ev.completes .. ")" end
  return base
end

function ns.announce(link, ev)
  local o = ns.opts()
  if o.announce and not ns.flagged[link] then
    ns.flagged[link] = true
    ns.say(ns.sourceLabel() .. " upgrade in bags (not auto-equipped): " .. link .. ns.why(ev))
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
      ns.say("would equip " .. link .. ns.why(ev) .. reason)
    end
    return false
  end
  ns.ourEquipPending = true
  if slotID then EquipItemByName(link, slotID) else EquipItemByName(link) end
  dbg("vocgear", "equipped", "item=" .. tostring(link) .. " slot=" .. tostring(slotID))
  ns.playEquipSound()
  if o.announce then ns.say("equipped " .. link .. ns.why(ev)) end
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
        ns.say("equip loop detected, auto-equip paused 60s (/vg on resumes now)")
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
    ns.trackSetCrossings(ns.equippedSnap, snap)
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
  -- Pawn installed but still loading: wait for it rather than falling back
  -- for a single pass. Otherwise the scan runs on whichever source is
  -- active (Pawn's verdict, or the built-in item-level fallback).
  if ns.pawnPending() then ns.retrySoon() return end
  if InCombatLockdown() then return end
  ns.trackSwaps()
  ns.scanning = true
  local setCtx = ns.setContext()
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
        elseif not ns.recentSwap[link] then
          -- Set completion can act on items Pawn doesn't flag; anything
          -- else needs a Pawn verdict to proceed.
          local readyThreshold, readySet = ns.setCompletionReady(setCtx, link)
          if ev.upgrade or readyThreshold then
            local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
            local pair = equipLoc and ns.slotPairs[equipLoc]
            if equipLoc == nil or (pair and not o.autoTwoSlot) then
              -- A completion that can't auto-equip stays silent: there is
              -- no Pawn verdict behind it to report.
              if ev.upgrade then ns.announce(link, ev) end
            elseif pair then
              local slotID = ns.resolveTwoSlotSlot(equipLoc, ev, link)
              if not slotID then
                if ev.upgrade then ns.announce(link, ev) end
              else
                local held = GetInventoryItemLink("player", slotID)
                local breakThreshold, breakSet = ns.setBreaks(setCtx, link, held)
                local completes = ns.setSwapCompletes(held, readyThreshold, readySet)
                if o.keepHeirlooms and ns.isHeirloom(held) then
                  ns.announceHeirloom(link, held)
                elseif breakThreshold then
                  ns.announceSetBreak(link, breakSet, breakThreshold)
                elseif ev.upgrade or completes then
                  if completes then ev.completes = ns.bonusLabel(readySet, completes) end
                  if ns.equip(link, ev, slotID) then ns.scanning = false return end
                end
              end
            else
              local slotID = equipLoc and ns.primarySlot[equipLoc]
              local held = slotID and GetInventoryItemLink("player", slotID)
              local breakThreshold, breakSet = ns.setBreaks(setCtx, link, held)
              local completes = ns.setSwapCompletes(held, readyThreshold, readySet)
              if o.keepHeirlooms and ns.isHeirloom(held) then
                ns.announceHeirloom(link, held)
              elseif ns.weaponKindCrosses(link, held) then
                ns.announceWeaponKind(link, ev)
              elseif breakThreshold then
                ns.announceSetBreak(link, breakSet, breakThreshold)
              elseif ev.upgrade or completes then
                if completes then ev.completes = ns.bonusLabel(readySet, completes) end
                if ns.equip(link, ev, nil) then ns.scanning = false return end
              end
            end
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
  check("enabled", "Enable auto-equip", "Equip upgrades out of combat. Pawn's verdict when Pawn is driving, item level otherwise.")
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
  check("protectSets", "Prioritize set bonuses",
    "Complete set bonuses automatically and never break an active one.")
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_scale", "scale",
      db, type(defaults.scale), "Pawn scale", defaults.scale)
    Settings.CreateDropdown(category, s, ns.scaleOptions,
      "Which Pawn scale counts. Any visible scale preserves stock behavior.")
    ns.onSettingChanged(s, ns.scan)
  end
  do
    local s = Settings.RegisterAddOnSetting(
      category, "VocGear_equipSound", "equipSound",
      db, type(defaults.equipSound), "Equip sound", defaults.equipSound)
    Settings.CreateDropdown(category, s, ns.equipSoundOptions,
      "Sound played when VocGear equips an upgrade. Changing it previews the sound.")
    ns.onSettingChanged(s, ns.playEquipSound)
  end
  check("sheetButton", "Character sheet button",
    "Show a Check Bags button on the character sheet.",
    function() ns.ensurePaperDollButton() end)
  ns.settingsBuilt = true
  ns.settingsCategory = category
end

function ns.sourceNoteText()
  if ns.pawnActive() then return "Upgrade source: Pawn (your stat weights)" end
  return "Upgrade source: built-in item level (install Pawn for stat weights)"
end

-- Upgrade-source indicator at the top of the panel, so the player always
-- knows which system is deciding. Added once all addons are loaded (a
-- late Pawn is counted); plain-text header via the vertical layout's own
-- initializer, guarded so the panel is complete without it.
ns.sourceNoteAdded = false
function ns.ensureSourceNote()
  if ns.sourceNoteAdded or not ns.settingsBuilt then return end
  if type(CreateSettingsListSectionHeaderInitializer) ~= "function" then return end
  if not (SettingsPanel and type(SettingsPanel.GetLayout) == "function") then return end
  local ok = pcall(function()
    local layout = SettingsPanel:GetLayout(ns.settingsCategory)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(ns.sourceNoteText()))
  end)
  if ok then ns.sourceNoteAdded = true end
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

function ns.equipSoundOptions()
  local container = Settings.CreateControlTextContainer()
  container:Add("0", "Off", "No sound when equipping.")
  for _, snd in ipairs(ns.EQUIP_SOUNDS) do
    container:Add(snd.id, snd.label, "")
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
  if not ok then ns.say("open Settings > AddOns > VocGear") end
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
    ns.ensureSourceNote() -- all addons loaded: the source reading is final
    ns.ensurePaperDollButton()
  end
  ns.scan()
end)

-- Slash grammar shared by every Voc addon (FAMILY.md): the bare command
-- does the one main thing, `config` opens the panel, `help` lists the
-- rest, and anything unrecognized prints help instead of acting.
ns.HELP = {
  "/vg            toggle auto-equip on/off",
  "/vg on|off     set auto-equip explicitly",
  "/vg scan       check bags now",
  "/vg announce   toggle chat announcements",
  "/vg config     open Settings > AddOns > VocGear",
  "/vg help       this list (/vocgear works too)",
}

function ns.help()
  ns.say("commands")
  for _, line in ipairs(ns.HELP) do print("  " .. line) end
end

-- Toggle or set auto-equip; re-enabling clears the loop guard.
function ns.setEnabled(on)
  local o = ns.opts()
  o.enabled = on
  ns.say("auto-equip " .. (on and "on" or "off"))
  if on then ns.clearGuard() ns.scan() end
end

-- Blizzard's slash dispatcher reads SLASH_* globals by name, so these
-- cannot be namespaced (they are declared in .luacheckrc instead).
SLASH_VOCGEAR1 = "/vg"
SLASH_VOCGEAR2 = "/vocgear"
SlashCmdList.VOCGEAR = function(msg)
  local o = ns.opts()
  msg = strtrim(msg or ""):lower()
  if msg == "" then
    ns.setEnabled(not o.enabled)
  elseif msg == "on" or msg == "off" then
    ns.setEnabled(msg == "on")
  elseif msg == "announce" then
    o.announce = not o.announce
    ns.say("announcements " .. (o.announce and "on" or "off"))
  elseif msg == "config" then
    ns.openConfig()
  elseif msg == "scan" then
    ns.checkNow()
  else
    ns.help()
  end
end
