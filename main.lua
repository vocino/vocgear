-- VocGear: equip what Pawn says is an upgrade. Nothing else.
local addonName = ...

VocGearDB = VocGearDB or {}
local db = VocGearDB

local function opts()
  if db.enabled == nil then db.enabled = true end
  if db.announce == nil then db.announce = true end
  return db
end

-- Pawn's current API (verified against BetterBags' integration):
-- PawnGetItemData exists when Pawn is loaded; PawnShouldItemLinkHaveUpgradeArrowUnbudgeted
-- answers the upgrade question per item link. The old PawnIsContainerItemAnUpgrade
-- global no longer exists, so don't use it.
local function pawnReady()
  return type(_G.PawnGetItemData) == "function"
    and type(_G.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted) == "function"
end

-- Rings and trinkets have two slots; blind auto-equip can replace the
-- better one. Announce those, don't equip them. (v1 scope)
local twoSlot = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

local flagged = {} -- itemIDs announced as two-slot upgrades, per session
local scanning = false

local function scan()
  if scanning then return end
  local o = opts()
  if not o.enabled then return end
  if not pawnReady() then return end
  if InCombatLockdown() then return end
  scanning = true
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link then
        local ok, isUpgrade = pcall(_G.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted, link, true)
        if ok and isUpgrade then
          local id = tonumber(link:match("item:(%d+)"))
          local _, _, _, _, _, _, _, _, equipSlot = GetItemInfo(link)
          if twoSlot[equipSlot] then
            if o.announce and id and not flagged[id] then
              flagged[id] = true
              print("VocGear: Pawn upgrade in bags (two slots, not auto-equipped): " .. link)
            end
          elseif id then
            EquipItemByName(id)
            if o.announce then print("VocGear: equipped " .. link .. " (Pawn upgrade)") end
            scanning = false
            return -- one equip per scan; the bag update re-triggers for the rest
          end
        end
      end
    end
  end
  scanning = false
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 ~= "Pawn" and arg1 ~= addonName then return end
  scan()
end)

SLASH_VOCGEAR1 = "/vg"
SLASH_VOCGEAR2 = "/vocgear"
SlashCmdList.VOCGEAR = function(msg)
  local o = opts()
  msg = strtrim(msg or ""):lower()
  if msg == "announce" then
    o.announce = not o.announce
    print("VocGear: announcements " .. (o.announce and "on" or "off"))
  else
    o.enabled = not o.enabled
    print("VocGear: " .. (o.enabled and "on" or "off"))
    if o.enabled then scan() end
  end
end
