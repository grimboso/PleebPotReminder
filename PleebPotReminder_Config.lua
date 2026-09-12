local _, ns = ...

local CreateFrame = _G.CreateFrame
local STANDARD_TEXT_FONT = _G.STANDARD_TEXT_FONT
local UISpecialFrames = _G.UISpecialFrames
local floor = math.floor

local COLORS = {
  background = { 0.12, 0.12, 0.16, 0.92 },
  panel = { 0.12, 0.12, 0.16, 0.92 },
  border = { 0.20, 0.20, 0.24, 1 },
  control = { 0.070, 0.070, 0.090, 0.96 },
  accent = { 0.20, 0.65, 1.00, 1 },
  text = { 0.96, 0.96, 0.96, 1 },
  muted = { 0.96, 0.96, 0.96, 0.72 },
}

local PANEL_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 3,
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

local function CreateLabel(parent, text, size)
  local label = parent:CreateFontString(nil, "OVERLAY")
  label:SetFont(STANDARD_TEXT_FONT, size or 12, "")
  label:SetText(text or "")
  label:SetTextColor(COLORS.text[1], COLORS.text[2], COLORS.text[3], COLORS.text[4])
  label:SetJustifyH("LEFT")
  return label
end

local function CreateButton(parent, text, width, height)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  button:SetSize(width or 120, height or 24)
  SetBackdrop(button, COLORS.panel, COLORS.border)
  button.label = CreateLabel(button, text, 12)
  button.label:SetPoint("CENTER")
  function button:SetText(value)
    self.label:SetText(value or "")
  end
  button:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
  end)
  button:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
  end)
  return button
end

local function CreateCheckButton(parent, label, y, onClick)
  local button = CreateFrame("CheckButton", nil, parent)
  button:SetSize(360, 22)
  button:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)

  button.box = CreateFrame("Frame", nil, button, "BackdropTemplate")
  button.box:SetSize(16, 16)
  button.box:SetPoint("LEFT", button, "LEFT", 0, 0)
  button.box:EnableMouse(false)
  SetBackdrop(button.box, COLORS.control, COLORS.border)

  button.fill = button.box:CreateTexture(nil, "ARTWORK")
  button.fill:SetPoint("TOPLEFT", button.box, "TOPLEFT", 3, -3)
  button.fill:SetPoint("BOTTOMRIGHT", button.box, "BOTTOMRIGHT", -3, 3)
  button.fill:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
  button.fill:Hide()

  button.label = CreateLabel(button, label, 11)
  button.label:SetPoint("LEFT", button.box, "RIGHT", 6, 0)
  button.label:SetPoint("RIGHT", button, "RIGHT", 0, 0)
  button:SetScript("OnClick", function(self)
    self.fill:SetShown(self:GetChecked() == true)
    if not refreshingOptions then
      onClick(self:GetChecked() == true)
    end
  end)
  button:SetScript("OnEnter", function(self)
    self.box:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
  end)
  button:SetScript("OnLeave", function(self)
    self.box:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
  end)
  hooksecurefunc(button, "SetChecked", function(self)
    self.fill:SetShown(self:GetChecked() == true)
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
  local slider = CreateFrame("Slider", name, parent, "BackdropTemplate")
  slider:SetSize(360, 16)
  slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 36, y)
  slider:SetMinMaxValues(minimum, maximum)
  slider:SetValueStep(1)
  slider:SetObeyStepOnDrag(true)
  slider:SetOrientation("HORIZONTAL")
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  SetBackdrop(slider, COLORS.control, COLORS.border)
  slider.label = label
  slider.suffix = suffix or ""
  slider.valueText = CreateLabel(slider, "", 11)
  slider.valueText:SetPoint("BOTTOMLEFT", slider, "TOPLEFT", 0, 5)
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
  local labelText = CreateLabel(parent, label, 11)
  labelText:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)

  local editBox = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  editBox:SetSize(360, 24)
  editBox:SetPoint("TOPLEFT", labelText, "BOTTOMLEFT", 4, -5)
  editBox:SetAutoFocus(false)
  editBox:SetMaxLetters(80)
  editBox:SetFont(STANDARD_TEXT_FONT, 12, "")
  editBox:SetTextInsets(6, 6, 3, 3)
  SetBackdrop(editBox, COLORS.control, COLORS.border)
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
  header:SetHeight(70)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  SetBackdrop(header, COLORS.panel, COLORS.border)
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

  local title = CreateLabel(header, "PleebPot", 20)
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -2)
  title:SetFont(STANDARD_TEXT_FONT, 20, "OUTLINE")
  title:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)

  local description = CreateLabel(
    header,
    "Reminders for Healthstones and combat potions.",
    11
  )
  description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)
  description:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3], COLORS.muted[4])

  local close = CreateButton(header, "×", 30, 30)
  close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -10, -10)
  close:SetScript("OnClick", function()
    frame:Hide()
  end)
  frame.puiHeader = header
  frame.puiCloseButton = close

  local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
  footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  footer:SetHeight(28)
  SetBackdrop(footer, COLORS.panel, COLORS.border)

  local footerText = CreateLabel(footer, "PleebUI  ·  /pleebpot", 11)
  footerText:SetPoint("LEFT", footer, "LEFT", 12, 0)
  footerText:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3], COLORS.muted[4])

  local footerState = CreateLabel(footer, "Changes apply immediately", 11)
  footerState:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
  footerState:SetTextColor(COLORS.muted[1], COLORS.muted[2], COLORS.muted[3], COLORS.muted[4])

  local scroll = CreateFrame(
    "ScrollFrame",
    nil,
    frame,
    "UIPanelScrollFrameTemplate"
  )
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 12, -10)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -30, -12)

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

  local resetPosition = CreateButton(content, "Reset position", 160, 24)
  resetPosition:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -730)
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

function ns.MountPleebUIOptions(host)
  if not optionsWindow then
    ns.CreateOptionsWindow()
  end

  optionsWindow:SetParent(host)
  optionsWindow:SetFrameStrata(host:GetFrameStrata())
  optionsWindow:SetFrameLevel(host:GetFrameLevel() + 1)
  optionsWindow:SetToplevel(false)
  optionsWindow:SetClampedToScreen(false)
  optionsWindow:SetMovable(false)
  optionsWindow:ClearAllPoints()
  optionsWindow:SetAllPoints(host)
  optionsWindow.puiHeader:EnableMouse(false)
  optionsWindow.puiCloseButton:Hide()
  optionsWindow:Show()

  return optionsWindow
end

_G.SLASH_PLEEBPOTREMINDER1 = "/pleebpot"
_G.SLASH_PLEEBPOTREMINDER2 = "/php"
_G.SlashCmdList.PLEEBPOTREMINDER = ToggleOptionsWindow
