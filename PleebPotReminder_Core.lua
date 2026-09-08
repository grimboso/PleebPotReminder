local ADDON_NAME, ns = ...

local CreateFrame = _G.CreateFrame
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT
local UIParent = _G.UIParent
local UnitClass = _G.UnitClass
local UnitHealthPercent = _G.UnitHealthPercent
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitPowerPercent = _G.UnitPowerPercent
local max = math.max
local min = math.min
local tonumber = tonumber
local type = type

local HEALTHSTONE_ITEM_ID = 5512
local DEMONIC_HEALTHSTONE_ITEM_ID = 224464
local HEALTHSTONE_FALLBACK_ICON = 134400
local POTION_FALLBACK_ICON = 134829
local MANA_POWER_TYPE = Enum.PowerType.Mana
local UPDATE_DELAY = 0.05

local POTION_ITEM_IDS = {
  271884,
  271883,
  245918,
  241304,
  245919,
  241305,
  211879,
}

local MANA_POTION_ITEM_IDS = {
  245916,
  241300,
  245917,
  241301,
}

ns.DEFAULTS = {
  enabled = true,
  healthstoneThreshold = 40,
  potionThreshold = 20,
  enableManaPotion = false,
  manaPotionThreshold = 20,
  healthstoneText = "Use Healthstone",
  potionText = "Use Health Potion",
  manaPotionText = "Use Mana Potion",
  fontSize = 20,
  iconOnly = false,
  posX = 0,
  posY = 180,
}

local BASE_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_DEAD",
  "PLAYER_ALIVE",
  "PLAYER_UNGHOST",
  "BAG_UPDATE_DELAYED",
}

local PANEL_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

local healthstoneCurve = C_CurveUtil.CreateCurve()
local potionCurve = C_CurveUtil.CreateCurve()
local manaPotionCurve = C_CurveUtil.CreateCurve()
local holder
local healthstoneText
local potionText
local manaPotionText
local eventFrame
local runtimeEnabled = false
local previewActive = false
local playerIsWarlock = false
local playerUnavailable = false
local cachedPotionItemID = POTION_ITEM_IDS[1]
local cachedManaPotionItemID = MANA_POTION_ITEM_IDS[1]
local cachedHealthstoneItemID = HEALTHSTONE_ITEM_ID
local cachedHealthstoneReady = false
local cachedPotionReady = false
local cachedManaPotionReady = false
local cachedHealthstoneCount = 0
local cachedPotionCount = 0
local cachedManaPotionCount = 0
local reminderTextDirty = true
local reminderUpdateTimer
local cooldownRefreshTimer

healthstoneCurve:SetType(Enum.LuaCurveType.Step)
potionCurve:SetType(Enum.LuaCurveType.Step)
manaPotionCurve:SetType(Enum.LuaCurveType.Step)

local function ClampNumber(value, minimum, maximum, fallback)
  return min(maximum, max(minimum, tonumber(value) or fallback))
end

function ns.ClampThreshold(value)
  return ClampNumber(value, 1, 100, 35)
end

local function NormalizeText(value, fallback)
  if type(value) ~= "string" or value == "" then
    return fallback
  end

  return value
end

local function NormalizeSettings(source)
  local defaults = ns.DEFAULTS
  return {
    enabled = source.enabled ~= false,
    healthstoneThreshold = ClampNumber(
      source.healthstoneThreshold,
      1,
      100,
      defaults.healthstoneThreshold
    ),
    potionThreshold = ClampNumber(
      source.potionThreshold,
      1,
      100,
      defaults.potionThreshold
    ),
    enableManaPotion = source.enableManaPotion == true,
    manaPotionThreshold = ClampNumber(
      source.manaPotionThreshold,
      1,
      100,
      defaults.manaPotionThreshold
    ),
    healthstoneText = NormalizeText(
      source.healthstoneText,
      defaults.healthstoneText
    ),
    potionText = NormalizeText(source.potionText, defaults.potionText),
    manaPotionText = NormalizeText(
      source.manaPotionText,
      defaults.manaPotionText
    ),
    fontSize = ClampNumber(source.fontSize, 10, 128, defaults.fontSize),
    iconOnly = source.iconOnly == true,
    posX = ClampNumber(source.posX, -1000, 1000, defaults.posX),
    posY = ClampNumber(source.posY, -1000, 1000, defaults.posY),
  }
end

local function InitializeDB()
  local globalSaved = _G.PleebPotReminderDB
  local globalSource = type(globalSaved) == "table" and globalSaved or {}

  ns.globalDB = NormalizeSettings(globalSource)
  _G.PleebPotReminderDB = ns.globalDB

  local characterSaved = _G.PleebPotReminderCharacterDB
  if type(characterSaved) ~= "table" then
    characterSaved = {}
  end

  ns.characterDB = {
    usePerCharacterSettings =
      characterSaved.usePerCharacterSettings == true,
  }

  if type(characterSaved.settings) == "table" then
    ns.characterDB.settings = NormalizeSettings(characterSaved.settings)
  elseif ns.characterDB.usePerCharacterSettings then
    ns.characterDB.settings = NormalizeSettings(ns.globalDB)
  end

  _G.PleebPotReminderCharacterDB = ns.characterDB
  ns.db = ns.characterDB.usePerCharacterSettings
    and ns.characterDB.settings
    or ns.globalDB
end

local function IsItemReady(itemID, itemCount)
  if itemCount <= 0 then
    return false
  end

  local startTime, duration, enabled = C_Item.GetItemCooldown(itemID)
  return enabled == true and startTime == 0 and duration == 0
end

local function FindFirstOwnedItem(itemIDs)
  for index = 1, #itemIDs do
    local itemID = itemIDs[index]
    local count = C_Item.GetItemCount(itemID)
    if count > 0 then
      return itemID, count
    end
  end

  return itemIDs[1], 0
end

local function RefreshHealthstoneCache()
  local primaryItemID = HEALTHSTONE_ITEM_ID
  local secondaryItemID

  if playerIsWarlock then
    primaryItemID = DEMONIC_HEALTHSTONE_ITEM_ID
    secondaryItemID = HEALTHSTONE_ITEM_ID
  end

  local primaryCount = C_Item.GetItemCount(primaryItemID)
  if primaryCount > 0 then
    cachedHealthstoneItemID = primaryItemID
    cachedHealthstoneCount = primaryCount
    cachedHealthstoneReady = IsItemReady(primaryItemID, primaryCount)
    return
  end

  if secondaryItemID then
    local secondaryCount = C_Item.GetItemCount(secondaryItemID)
    if secondaryCount > 0 then
      cachedHealthstoneItemID = secondaryItemID
      cachedHealthstoneCount = secondaryCount
      cachedHealthstoneReady = IsItemReady(secondaryItemID, secondaryCount)
      return
    end
  end

  cachedHealthstoneItemID = primaryItemID
  cachedHealthstoneCount = 0
  cachedHealthstoneReady = false
end

local function RefreshOwnedItemCache()
  local oldHealthstoneItemID = cachedHealthstoneItemID
  local oldPotionItemID = cachedPotionItemID
  local oldManaPotionItemID = cachedManaPotionItemID

  cachedPotionItemID, cachedPotionCount = FindFirstOwnedItem(POTION_ITEM_IDS)
  cachedManaPotionItemID, cachedManaPotionCount =
    FindFirstOwnedItem(MANA_POTION_ITEM_IDS)
  RefreshHealthstoneCache()

  cachedPotionReady = IsItemReady(cachedPotionItemID, cachedPotionCount)
  cachedManaPotionReady = IsItemReady(
    cachedManaPotionItemID,
    cachedManaPotionCount
  )

  if oldHealthstoneItemID ~= cachedHealthstoneItemID
    or oldPotionItemID ~= cachedPotionItemID
    or oldManaPotionItemID ~= cachedManaPotionItemID
  then
    reminderTextDirty = true
  end
end

local function RefreshCooldownReadiness()
  local oldHealthstoneReady = cachedHealthstoneReady
  local oldPotionReady = cachedPotionReady
  local oldManaPotionReady = cachedManaPotionReady

  cachedHealthstoneReady = IsItemReady(
    cachedHealthstoneItemID,
    cachedHealthstoneCount
  )
  cachedPotionReady = IsItemReady(cachedPotionItemID, cachedPotionCount)
  cachedManaPotionReady = IsItemReady(
    cachedManaPotionItemID,
    cachedManaPotionCount
  )

  return oldHealthstoneReady ~= cachedHealthstoneReady
    or oldPotionReady ~= cachedPotionReady
    or oldManaPotionReady ~= cachedManaPotionReady
end

local function GetReminderString(label, itemID, fallbackIcon)
  local db = ns.db
  local icon = C_Item.GetItemIconByID(itemID) or fallbackIcon

  if db.iconOnly then
    return string.format(
      "|T%d:%d:%d:0:0:64:64:5:59:5:59|t",
      icon,
      db.fontSize,
      db.fontSize
    )
  end

  return string.format(
    "%s |T%d:%d:%d:0:0:64:64:5:59:5:59|t",
    label,
    icon,
    db.fontSize,
    db.fontSize
  )
end

local function BuildAlphaStepCurve(curve, thresholdPercent)
  local threshold = thresholdPercent / 100
  local epsilon = 0.0001

  curve:ClearPoints()
  curve:AddPoint(0, 1)
  curve:AddPoint(threshold, 1)
  curve:AddPoint(min(1, threshold + epsilon), 0)
  curve:AddPoint(1, 0)
end

function ns.BuildHealthCurves()
  local db = ns.db
  BuildAlphaStepCurve(healthstoneCurve, db.healthstoneThreshold)
  BuildAlphaStepCurve(potionCurve, db.potionThreshold)
  BuildAlphaStepCurve(manaPotionCurve, db.manaPotionThreshold)
end

local function UpdateHolderSize()
  local db = ns.db
  local width = max(
    healthstoneText:GetStringWidth(),
    potionText:GetStringWidth(),
    manaPotionText:GetStringWidth()
  ) + 32
  local minimumWidth = db.iconOnly and (db.fontSize + 32) or 160
  holder:SetSize(
    max(minimumWidth, width),
    (db.fontSize * 3) + (db.iconOnly and 58 or 48)
  )
end

function ns.ApplyPosition()
  local db = ns.db
  holder:ClearAllPoints()
  holder:SetPoint("CENTER", UIParent, "CENTER", db.posX, db.posY)
end

function ns.ApplyAppearance()
  local db = ns.db

  healthstoneText:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
  potionText:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
  manaPotionText:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")

  healthstoneText:SetText(GetReminderString(
    db.healthstoneText,
    cachedHealthstoneItemID,
    HEALTHSTONE_FALLBACK_ICON
  ))
  potionText:SetText(GetReminderString(
    db.potionText,
    cachedPotionItemID,
    POTION_FALLBACK_ICON
  ))
  manaPotionText:SetText(GetReminderString(
    db.manaPotionText,
    cachedManaPotionItemID,
    POTION_FALLBACK_ICON
  ))
  reminderTextDirty = false

  healthstoneText:ClearAllPoints()
  healthstoneText:SetPoint("TOP", holder, "TOP", 0, -14)
  potionText:ClearAllPoints()
  potionText:SetPoint(
    "TOP",
    healthstoneText,
    "BOTTOM",
    0,
    db.iconOnly and -8 or -4
  )
  manaPotionText:ClearAllPoints()
  manaPotionText:SetPoint(
    "TOP",
    potionText,
    "BOTTOM",
    0,
    db.iconOnly and -8 or -4
  )
  UpdateHolderSize()
end

local function UpdateReminder()
  local db = ns.db
  if reminderTextDirty then
    healthstoneText:SetText(GetReminderString(
      db.healthstoneText,
      cachedHealthstoneItemID,
      HEALTHSTONE_FALLBACK_ICON
    ))
    potionText:SetText(GetReminderString(
      db.potionText,
      cachedPotionItemID,
      POTION_FALLBACK_ICON
    ))
    manaPotionText:SetText(GetReminderString(
      db.manaPotionText,
      cachedManaPotionItemID,
      POTION_FALLBACK_ICON
    ))
    reminderTextDirty = false
    UpdateHolderSize()
  end

  if previewActive then
    healthstoneText:SetAlpha(1)
    potionText:SetAlpha(1)
    manaPotionText:SetAlpha(db.enableManaPotion and 1 or 0)
    return
  end

  if not runtimeEnabled then
    healthstoneText:SetAlpha(0)
    potionText:SetAlpha(0)
    manaPotionText:SetAlpha(0)
    return
  end

  if playerUnavailable then
    healthstoneText:SetAlpha(0)
    potionText:SetAlpha(0)
    manaPotionText:SetAlpha(0)
    return
  end

  if not cachedHealthstoneReady
    and not cachedPotionReady
    and (not db.enableManaPotion or not cachedManaPotionReady)
  then
    healthstoneText:SetAlpha(0)
    potionText:SetAlpha(0)
    manaPotionText:SetAlpha(0)
    return
  end

  local healthstoneAlpha = 0
  local potionAlpha = 0
  local manaPotionAlpha = 0

  if cachedHealthstoneReady then
    healthstoneAlpha = UnitHealthPercent(
      "player",
      true,
      healthstoneCurve
    )
  end
  if cachedPotionReady then
    potionAlpha = UnitHealthPercent("player", true, potionCurve)
  end
  if db.enableManaPotion and cachedManaPotionReady then
    manaPotionAlpha = UnitPowerPercent(
      "player",
      MANA_POWER_TYPE,
      true,
      manaPotionCurve
    )
  end

  healthstoneText:SetAlpha(healthstoneAlpha)
  potionText:SetAlpha(potionAlpha)
  manaPotionText:SetAlpha(manaPotionAlpha)
end

function ns.RunReminderUpdate()
  if reminderUpdateTimer then
    reminderUpdateTimer:Cancel()
    reminderUpdateTimer = nil
  end
  UpdateReminder()
end

local function QueueReminderUpdate()
  if reminderUpdateTimer then
    return
  end

  reminderUpdateTimer = C_Timer.NewTimer(UPDATE_DELAY, function()
    reminderUpdateTimer = nil
    UpdateReminder()
  end)
end

local function QueueCooldownRefresh()
  if cooldownRefreshTimer then
    return
  end

  cooldownRefreshTimer = C_Timer.NewTimer(UPDATE_DELAY, function()
    cooldownRefreshTimer = nil
    if RefreshCooldownReadiness() then
      ns.RunReminderUpdate()
    end
  end)
end

function ns.RefreshRuntimeEventWiring()
  local db = ns.db
  if not runtimeEnabled then
    eventFrame:UnregisterEvent("UNIT_HEALTH")
    eventFrame:UnregisterEvent("UNIT_POWER_UPDATE")
    eventFrame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
    return
  end

  local hasHealthItem = cachedHealthstoneCount > 0 or cachedPotionCount > 0
  local hasManaPotion = db.enableManaPotion and cachedManaPotionCount > 0
  if hasHealthItem then
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
  else
    eventFrame:UnregisterEvent("UNIT_HEALTH")
  end
  if hasManaPotion then
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
  else
    eventFrame:UnregisterEvent("UNIT_POWER_UPDATE")
  end

  if hasHealthItem or hasManaPotion then
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
  else
    eventFrame:UnregisterEvent("BAG_UPDATE_COOLDOWN")
  end
end

local function HandleEvent(_, event, unitTarget, powerType)
  if event == "UNIT_HEALTH" then
    QueueReminderUpdate()
    return
  end
  if event == "UNIT_POWER_UPDATE" then
    if unitTarget == "player" and powerType == "MANA" then
      QueueReminderUpdate()
    end
    return
  end
  if event == "BAG_UPDATE_COOLDOWN" then
    QueueCooldownRefresh()
    return
  end
  if event == "PLAYER_DEAD" then
    playerUnavailable = true
    ns.RunReminderUpdate()
    return
  end
  if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
    playerUnavailable = UnitIsDeadOrGhost("player") == true
    RefreshCooldownReadiness()
    ns.RunReminderUpdate()
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then
    playerUnavailable = UnitIsDeadOrGhost("player") == true
  end

  RefreshOwnedItemCache()
  ns.RefreshRuntimeEventWiring()
  ns.RunReminderUpdate()
end

local function SavePosition()
  local holderX, holderY = holder:GetCenter()
  local parentX, parentY = UIParent:GetCenter()
  local defaults = ns.DEFAULTS
  ns.db.posX = ClampNumber(
    holderX - parentX,
    -1000,
    1000,
    defaults.posX
  )
  ns.db.posY = ClampNumber(
    holderY - parentY,
    -1000,
    1000,
    defaults.posY
  )
  ns.ApplyPosition()
  ns.RefreshOptionsControls()
end

function ns.SetPreviewActive(enabled)
  previewActive = enabled
  holder:EnableMouse(enabled)
  holder.moverLabel:SetShown(enabled)

  if enabled then
    holder:SetBackdropColor(0.05, 0.08, 0.11, 0.72)
    holder:SetBackdropBorderColor(0.20, 0.72, 0.92, 1)
  else
    holder:SetBackdropColor(0, 0, 0, 0)
    holder:SetBackdropBorderColor(0, 0, 0, 0)
  end
  ns.RunReminderUpdate()
end

local function CreateRuntimeFrames()
  holder = CreateFrame(
    "Frame",
    ADDON_NAME .. "Anchor",
    UIParent,
    "BackdropTemplate"
  )
  holder:SetBackdrop(PANEL_BACKDROP)
  holder:SetBackdropColor(0, 0, 0, 0)
  holder:SetBackdropBorderColor(0, 0, 0, 0)
  holder:SetFrameStrata("HIGH")
  holder:SetClampedToScreen(true)
  holder:SetMovable(true)
  holder:RegisterForDrag("LeftButton")
  holder:EnableMouse(false)
  holder:SetScript("OnDragStart", function(self)
    if previewActive then
      self:StartMoving()
    end
  end)
  holder:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)

  healthstoneText = holder:CreateFontString(nil, "OVERLAY")
  healthstoneText:SetJustifyH("CENTER")
  healthstoneText:SetTextColor(1, 0.95, 0.8, 1)
  potionText = holder:CreateFontString(nil, "OVERLAY")
  potionText:SetJustifyH("CENTER")
  potionText:SetTextColor(1, 0.95, 0.8, 1)
  manaPotionText = holder:CreateFontString(nil, "OVERLAY")
  manaPotionText:SetJustifyH("CENTER")
  manaPotionText:SetTextColor(1, 0.95, 0.8, 1)

  holder.moverLabel = holder:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
  )
  holder.moverLabel:SetPoint("BOTTOM", holder, "BOTTOM", 0, 7)
  holder.moverLabel:SetText("Drag to move")
  holder.moverLabel:SetTextColor(0.20, 0.72, 0.92, 1)
  holder.moverLabel:Hide()

  eventFrame = CreateFrame("Frame")
  eventFrame:SetScript("OnEvent", HandleEvent)
  ns.ApplyAppearance()
  ns.ApplyPosition()
  UpdateReminder()
end

local function EnableRuntime()
  if runtimeEnabled then
    return
  end

  runtimeEnabled = true
  local _, classTag = UnitClass("player")
  playerIsWarlock = classTag == "WARLOCK"

  for index = 1, #BASE_EVENTS do
    eventFrame:RegisterEvent(BASE_EVENTS[index])
  end

  playerUnavailable = UnitIsDeadOrGhost("player") == true
  RefreshOwnedItemCache()
  ns.RefreshRuntimeEventWiring()
  ns.RunReminderUpdate()
end

local function DisableRuntime()
  if not runtimeEnabled then
    return
  end

  runtimeEnabled = false
  eventFrame:UnregisterAllEvents()

  if reminderUpdateTimer then
    reminderUpdateTimer:Cancel()
    reminderUpdateTimer = nil
  end
  if cooldownRefreshTimer then
    cooldownRefreshTimer:Cancel()
    cooldownRefreshTimer = nil
  end

  ns.RunReminderUpdate()
end

function ns.SetRuntimeEnabled(enabled)
  ns.db.enabled = enabled
  if enabled then
    EnableRuntime()
  else
    DisableRuntime()
  end
end

function ns.SetUsePerCharacterSettings(enabled)
  local characterDB = ns.characterDB
  if characterDB.usePerCharacterSettings == enabled then
    return
  end

  if enabled and not characterDB.settings then
    characterDB.settings = NormalizeSettings(ns.globalDB)
  end

  characterDB.usePerCharacterSettings = enabled
  ns.db = enabled and characterDB.settings or ns.globalDB

  ns.BuildHealthCurves()
  if ns.db.enabled then
    EnableRuntime()
  else
    DisableRuntime()
  end
  ns.RefreshRuntimeEventWiring()
  ns.ApplyAppearance()
  ns.ApplyPosition()
  ns.RefreshOptionsControls()
  ns.RunReminderUpdate()
end

local function ApplySavedRuntimeState()
  if ns.db.enabled then
    EnableRuntime()
  else
    ns.RunReminderUpdate()
  end
end

local bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:SetScript("OnEvent", function(self, event, loadedAddon)
  if event == "ADDON_LOADED" then
    if loadedAddon ~= ADDON_NAME then
      return
    end

    self:UnregisterEvent("ADDON_LOADED")
    InitializeDB()
    ns.BuildHealthCurves()
    CreateRuntimeFrames()

    if IsLoggedIn() then
      ApplySavedRuntimeState()
    else
      self:RegisterEvent("PLAYER_LOGIN")
    end
    return
  end

  self:UnregisterEvent("PLAYER_LOGIN")
  ApplySavedRuntimeState()
end)
