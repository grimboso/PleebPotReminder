local _, ns = ...

local CreateFrame = _G.CreateFrame
local UISpecialFrames = _G.UISpecialFrames
local floor = math.floor

local COLORS = {
  background = { 0.035, 0.043, 0.055, 0.98 },
  border = { 0.15, 0.18, 0.22, 1 },
  control = { 0.075, 0.088, 0.108, 1 },
}

local PANEL_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}

local optionsWindow
local controls
local refreshingOptions = false

local function SetBackdrop(frame, background, border)
  frame:SetBackdrop(PANEL_BACKDROP)
  frame:SetBackdropColor(
    background[1],
    background[2],
    background[3],
    background[4]
  )
  frame:SetBackdropBorderColor(
    border[1],
    border[2],
    border[3],
    border[4]
  )
end

local function CreateCheckButton(parent, label, y, onClick)
  local button = CreateFrame(
    "CheckButton",
    nil,
    parent,
    "UICheckButtonTemplate"
  )
  button:SetSize(24, 24)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  button.Text:SetText(label)
  button:SetScript("OnClick", function(self)
    if not refreshingOptions then
      onClick(self:GetChecked() == true)
    end
  end)
  return button
end

local function UpdateSliderLabel(slider, value)
  slider.valueText:SetText(
    slider.label .. ": " .. floor(value + 0.5) .. slider.suffix
  )
end

local function CreateSlider(
  parent,
  name,
  label,
  minimum,
  maximum,
  y,
  suffix,
  onValueChanged
)
  local slider = CreateFrame(
    "Slider",
    name,
    parent,
    "OptionsSliderTemplate"
  )
  slider:SetSize(360, 17)
  slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 36, y)
  slider:SetMinMaxValues(minimum, maximum)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  slider.label = label
  slider.suffix = suffix or ""
  slider.valueText = _G[name .. "Text"]
  _G[name .. "Low"]:SetText(minimum)
  _G[name .. "High"]:SetText(maximum)
  slider:SetScript("OnValueChanged", function(self, value)
    local rounded = floor(value + 0.5)
    UpdateSliderLabel(self, rounded)
    if not refreshingOptions then
      onValueChanged(rounded)
    end
  end)
  return slider
end

local function CreateEditBox(parent, label, y, fallback, onCommit)
  local labelText = parent:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
  labelText:SetText(label)

  local editBox = CreateFrame(
    "EditBox",
    nil,
    parent,
    "InputBoxTemplate"
  )
  editBox:SetSize(360, 24)
  editBox:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 4, -5)
  editBox:SetAutoFocus(false)
  editBox:SetMaxLetters(80)
  editBox.labelText = labelText

  local function Commit(self)
    local value = self:GetText():match("^%s*(.-)%s*$")
    if value == "" then
      value = fallback
    end
    self:SetText(value)
    onCommit(value)
  end

  editBox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  editBox:SetScript("OnEditFocusLost", Commit)
  editBox:SetScript("OnEscapePressed", function(self)
    ns.RefreshOptionsControls()
    self:ClearFocus()
  end)
  return editBox
end

function ns.RefreshOptionsControls()
  if not controls then
    return
  end

  local db = ns.db
  refreshingOptions = true
  controls.usePerCharacterSettings:SetChecked(
    ns.characterDB.usePerCharacterSettings
  )
  controls.enabled:SetChecked(db.enabled)
  controls.iconOnly:SetChecked(db.iconOnly)
  controls.enableManaPotion:SetChecked(db.enableManaPotion)
  controls.healthstoneThreshold:SetValue(db.healthstoneThreshold)
  controls.potionThreshold:SetValue(db.potionThreshold)
  controls.manaPotionThreshold:SetValue(db.manaPotionThreshold)
  controls.fontSize:SetValue(db.fontSize)
  controls.posX:SetValue(db.posX)
  controls.posY:SetValue(db.posY)
  controls.healthstoneEdit:SetText(db.healthstoneText)
  controls.potionEdit:SetText(db.potionText)
  controls.manaPotionEdit:SetText(db.manaPotionText)
  controls.manaPotionThreshold:SetEnabled(db.enableManaPotion)
  controls.manaPotionThreshold:SetAlpha(db.enableManaPotion and 1 or 0.5)
  local textEnabled = not db.iconOnly
  local manaTextEnabled = textEnabled and db.enableManaPotion
  controls.healthstoneEdit:SetEnabled(textEnabled)
  controls.healthstoneEdit:SetAlpha(textEnabled and 1 or 0.5)
  controls.healthstoneEdit.labelText:SetAlpha(textEnabled and 1 or 0.5)
  controls.potionEdit:SetEnabled(textEnabled)
  controls.potionEdit:SetAlpha(textEnabled and 1 or 0.5)
  controls.potionEdit.labelText:SetAlpha(textEnabled and 1 or 0.5)
  controls.manaPotionEdit:SetEnabled(manaTextEnabled)
  controls.manaPotionEdit:SetAlpha(manaTextEnabled and 1 or 0.5)
  controls.manaPotionEdit.labelText:SetAlpha(manaTextEnabled and 1 or 0.5)
  refreshingOptions = false
end

local function ToggleOptionsWindow()
  if not optionsWindow then
    ns.CreateOptionsWindow()
  end
  if optionsWindow:IsShown() then
    optionsWindow:Hide()
  else
    optionsWindow:Show()
    optionsWindow:Raise()
  end
end

function ns.CreateOptionsWindow()
  local defaults = ns.DEFAULTS
  local frame = CreateFrame(
    "Frame",
    "PleebPotReminderOptions",
    UIParent,
    "BackdropTemplate"
  )
  optionsWindow = frame
  controls = {}

  frame:SetSize(500, 650)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:Hide()
  SetBackdrop(frame, COLORS.background, COLORS.border)

  local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  header:SetHeight(64)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  SetBackdrop(header, COLORS.control, COLORS.border)
  header:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)

  local logo = header:CreateTexture(nil, "ARTWORK")
  logo:SetSize(46, 46)
  logo:SetPoint("LEFT", header, "LEFT", 12, 0)
  logo:SetTexture("Interface\\AddOns\\PleebPotReminder\\Media\\logo.tga")

  local title = header:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightLarge"
  )
  title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
  title:SetText("PleebPot")
  title:SetTextColor(0.20, 0.72, 0.92, 1)

  local close = CreateFrame(
    "Button",
    nil,
    header,
    "UIPanelCloseButton"
  )
  close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  local scroll = CreateFrame(
    "ScrollFrame",
    nil,
    frame,
    "UIPanelScrollFrameTemplate"
  )
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -10)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 12)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(438, 840)
  scroll:SetScrollChild(content)

  local previewHelp = content:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
  )
  previewHelp:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
  previewHelp:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  previewHelp:SetJustifyH("LEFT")
  previewHelp:SetWordWrap(true)
  previewHelp:SetText(
    "Preview is always shown while settings are open. Drag the highlighted reminder to move it."
  )
  previewHelp:SetTextColor(0.62, 0.68, 0.74, 1)

  controls.enabled = CreateCheckButton(
    content,
    "Enable reminders",
    -60,
    function(value)
      ns.SetRuntimeEnabled(value)
    end
  )

  controls.usePerCharacterSettings = CreateCheckButton(
    content,
    "Use separate settings for this character",
    -88,
    function(value)
      ns.SetUsePerCharacterSettings(value)
    end
  )

  controls.iconOnly = CreateCheckButton(
    content,
    "Icons only",
    -116,
    function(value)
      ns.db.iconOnly = value
      ns.ApplyAppearance()
      ns.RefreshOptionsControls()
      ns.RunReminderUpdate()
    end
  )

  controls.enableManaPotion = CreateCheckButton(
    content,
    "Enable mana potion reminder",
    -144,
    function(value)
      ns.db.enableManaPotion = value
      ns.RefreshRuntimeEventWiring()
      ns.RefreshOptionsControls()
      ns.RunReminderUpdate()
    end
  )

  controls.healthstoneThreshold = CreateSlider(
    content,
    "PleebPotReminderHealthstoneThresholdSlider",
    "Healthstone",
    1,
    100,
    -194,
    "% health",
    function(value)
      ns.db.healthstoneThreshold = ns.ClampThreshold(value)
      ns.BuildHealthCurves()
      ns.RunReminderUpdate()
    end
  )
  controls.potionThreshold = CreateSlider(
    content,
    "PleebPotReminderPotionThresholdSlider",
    "Health Potion",
    1,
    100,
    -254,
    "% health",
    function(value)
      ns.db.potionThreshold = ns.ClampThreshold(value)
      ns.BuildHealthCurves()
      ns.RunReminderUpdate()
    end
  )
  controls.manaPotionThreshold = CreateSlider(
    content,
    "PleebPotReminderManaThresholdSlider",
    "Mana Potion",
    1,
    100,
    -314,
    "% mana",
    function(value)
      ns.db.manaPotionThreshold = ns.ClampThreshold(value)
      ns.BuildHealthCurves()
      ns.RunReminderUpdate()
    end
  )
  controls.fontSize = CreateSlider(
    content,
    "PleebPotReminderFontSizeSlider",
    "Reminder size",
    10,
    128,
    -374,
    "",
    function(value)
      ns.db.fontSize = value
      ns.ApplyAppearance()
      ns.RunReminderUpdate()
    end
  )
  controls.posX = CreateSlider(
    content,
    "PleebPotReminderPositionXSlider",
    "Horizontal offset",
    -1000,
    1000,
    -434,
    "",
    function(value)
      ns.db.posX = value
      ns.ApplyPosition()
    end
  )
  controls.posY = CreateSlider(
    content,
    "PleebPotReminderPositionYSlider",
    "Vertical offset",
    -1000,
    1000,
    -494,
    "",
    function(value)
      ns.db.posY = value
      ns.ApplyPosition()
    end
  )

  controls.healthstoneEdit = CreateEditBox(
    content,
    "Healthstone label",
    -542,
    defaults.healthstoneText,
    function(value)
      ns.db.healthstoneText = value
      ns.ApplyAppearance()
      ns.RunReminderUpdate()
    end
  )
  controls.potionEdit = CreateEditBox(
    content,
    "Health Potion label",
    -602,
    defaults.potionText,
    function(value)
      ns.db.potionText = value
      ns.ApplyAppearance()
      ns.RunReminderUpdate()
    end
  )
  controls.manaPotionEdit = CreateEditBox(
    content,
    "Mana Potion label",
    -662,
    defaults.manaPotionText,
    function(value)
      ns.db.manaPotionText = value
      ns.ApplyAppearance()
      ns.RunReminderUpdate()
    end
  )

  local resetPosition = CreateFrame(
    "Button",
    nil,
    content,
    "UIPanelButtonTemplate"
  )
  resetPosition:SetSize(160, 24)
  resetPosition:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -730)
  resetPosition:SetText("Reset position")
  resetPosition:SetScript("OnClick", function()
    ns.db.posX = defaults.posX
    ns.db.posY = defaults.posY
    ns.ApplyPosition()
    ns.RefreshOptionsControls()
  end)

  local note = content:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
  )
  note:SetPoint("TOPLEFT", resetPosition, "BOTTOMLEFT", 0, -18)
  note:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  note:SetJustifyH("LEFT")
  note:SetWordWrap(true)
  note:SetText(
    "Reminders appear when the matching item is in your bags and ready. Healthstone and Health Potion use your health thresholds; Mana Potion uses your mana threshold. Item selection is automatic."
  )
  note:SetTextColor(0.62, 0.68, 0.74, 1)

  frame:SetScript("OnShow", function()
    ns.RefreshOptionsControls()
    ns.SetPreviewActive(true)
  end)
  frame:SetScript("OnHide", function()
    controls.healthstoneEdit:ClearFocus()
    controls.potionEdit:ClearFocus()
    controls.manaPotionEdit:ClearFocus()
    ns.SetPreviewActive(false)
  end)

  UISpecialFrames[#UISpecialFrames + 1] = frame:GetName()
end
_G.SLASH_PLEEBPOTREMINDER1 = "/pleebpot"
_G.SlashCmdList.PLEEBPOTREMINDER = ToggleOptionsWindow
