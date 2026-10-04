local name, ns = ...
-- VocGear: equip what Pawn says is an upgrade. Nothing else.

VocGearDB = VocGearDB or {}
ns.db = VocGearDB

function ns.opts()
  if ns.db.enabled == nil then ns.db.enabled = true end
  if ns.db.announce == nil then ns.db.announce = true end
  return ns.db
end

-- Pawn's API (verified against Pawn 2.13.16 source; see .reference/pawn-analysis.md):
-- PawnGetItemData exists when Pawn is loaded; PawnShouldItemLinkHaveUpgradeArrowUnbudgeted
-- answers the upgrade question per item link. The old PawnIsContainerItemAnUpgrade
-- global no longer exists, so don't use it.
function ns.pawnReady()
  return type(_G.PawnGetItemData) == "function"
    and type(_G.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted) == "function"
end

-- Rings and trinkets have two slots; blind auto-equip can replace the
-- better one. Announce those, don't equip them. (v1 scope)
ns.twoSlot = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

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
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local ok, isUpgrade = pcall(_G.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted, link, true)
        if ok and isUpgrade then
          -- Instant (uncached-safe) equip-loc lookup, same call Pawn itself uses.
          local _, _, _, equipSlot = C_Item.GetItemInfoInstant(link)
          if equipSlot == nil or ns.twoSlot[equipSlot] then
            -- Unknown slot or two slots: announce, don't blind-equip.
            -- Keyed by full link so bonus variants each get one line.
            if o.announce and not ns.flagged[link] then
              ns.flagged[link] = true
              print("VocGear: Pawn upgrade in bags (not auto-equipped): " .. link)
            end
          else
            EquipItemByName(link) -- full link equips the exact bonus variant
            if o.announce then print("VocGear: equipped " .. link .. " (Pawn upgrade)") end
            ns.scanning = false
            return -- one equip per scan; the bag update re-triggers for the rest
          end
        end
      end
    end
  end
  ns.scanning = false
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
    if arg1 == name then ns.db = VocGearDB end
    if arg1 ~= "Pawn" and arg1 ~= name then return end
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
  else
    o.enabled = not o.enabled
    print("VocGear: " .. (o.enabled and "on" or "off"))
    if o.enabled then ns.scan() end
  end
end
