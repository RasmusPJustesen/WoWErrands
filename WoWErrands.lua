-- WoWErrands: small, native-styled zone todo lists for WoW: Forever (Interface 16001).
local addon = CreateFrame("Frame")
local popup, tracker, mapPanel, mapTab
local activeZone, lastAlertZone
local rows = {}
local selectedZone
local MAX_ROWS = 8

local function zoneName()
    local name = GetZoneText()
    if name and name ~= "" then return name end
    return GetRealZoneText() or "Unknown Zone"
end

local function db()
    if not WoWErrandsDB then WoWErrandsDB = { zones = {}, settings = {} } end
    WoWErrandsDB.zones = WoWErrandsDB.zones or {}
    WoWErrandsDB.settings = WoWErrandsDB.settings or {}
    return WoWErrandsDB
end

local function getTasks(zone, create)
    local zones = db().zones
    if create and not zones[zone] then zones[zone] = {} end
    return zones[zone]
end

local function pending(zone)
    local tasks = getTasks(zone)
    local count = 0
    if tasks then for _, task in ipairs(tasks) do if not task.done then count = count + 1 end end end
    return count
end

local function nativeFrame(name, width, height)
    -- The copper/rusted flat panel is the same template Spoken Zone Lore uses.
    local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "DefaultPanelFlatTemplate")
    local samePanelTemplate = ok and f and f.SetTitle
    if not samePanelTemplate then
        f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    end
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)
    if samePanelTemplate then
        f:SetTitle("Zone Errands")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButtonDefaultAnchors")
        close:SetScript("OnClick", function() f:Hide() end)
        local holder = CreateFrame("Frame", nil, f)
        holder:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -25)
        holder:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 6)
        local background = holder:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        local art = _G.SpokenZones and _G.SpokenZones.Art
        local copy = art and art.COPIES and art.COPIES["QuestDetailsBackgrounds"]
        if copy then
            background:SetTexture(copy.file)
            background:SetTexCoord(copy.leftTexCoord, copy.rightTexCoord,
                copy.topTexCoord, copy.bottomTexCoord)
        else
            background:SetTexture("Interface\\AddOns\\WoWErrands\\parchment")
        end
        if background.SetSnapToPixelGrid then background:SetSnapToPixelGrid(false) end
        if background.SetTexelSnappingBias then background:SetTexelSnappingBias(0) end
        local rim = CreateFrame("Frame", nil, holder)
        rim:SetPoint("TOPLEFT", holder, "TOPLEFT", -2, 3)
        rim:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 2, -3)
        rim:SetFrameLevel(holder:GetFrameLevel() + 12)
        rim:EnableMouse(false)
        if art and art.NineSlice then
            rim.border = art.NineSlice(rim, "questlog-frame", "OVERLAY")
            local filigree = rim:CreateTexture(nil, "OVERLAY", nil, 1)
            art.Atlas(filigree, "questlog-frame-filigree", true)
            filigree:SetPoint("TOP", rim, "TOP", 0, 1)
        end
    end
    f:Hide()
    return f
end

local function button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height)
    b:SetText(label)
    return b
end

local function check(parent, width)
    local b = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    b:SetSize(25, 25)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("LEFT", b, "RIGHT", 3, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWidth(width - 35)
    b.label:SetWordWrap(false)
    return b
end

local updateAll

local function buildPopup()
    popup = nativeFrame("WoWErrandsPopup", 365, 330)
    if popup.TitleText then popup.TitleText:SetText("Zone Errands") end
    popup.zone = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.zone:SetPoint("TOPLEFT", 23, -35)
    popup.zone:SetTextColor(0.25, 0.16, 0.08)
    popup.zone:SetShadowColor(0, 0, 0, 0)
    popup.help = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.help:SetPoint("TOPLEFT", popup.zone, "BOTTOMLEFT", 0, -6)
    popup.help:SetText("Things to do before leaving")
    popup.help:SetTextColor(0.38, 0.25, 0.12)
    popup.help:SetShadowColor(0, 0, 0, 0)
    for i = 1, MAX_ROWS do
        local row = check(popup, 315)
        row:SetPoint("TOPLEFT", 20, -75 - (i - 1) * 26)
        row.label:SetTextColor(0.25, 0.16, 0.08)
        row.label:SetShadowColor(0, 0, 0, 0)
        row:SetScript("OnClick", function(self)
            local tasks = getTasks(activeZone)
            if tasks and tasks[self.index] then
                tasks[self.index].done = self:GetChecked() and true or false
                updateAll()
            end
        end)
        rows[i] = row
    end
    popup.more = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    popup.more:SetPoint("TOPLEFT", 24, -284)
    popup.more:SetTextColor(0.38, 0.25, 0.12)
    local edit = button(popup, "Manage errands", 135, 23)
    edit:SetPoint("BOTTOMRIGHT", -14, 12)
    edit:SetScript("OnClick", function() popup:Hide(); if WorldMapFrame and WorldMapFrame:IsShown() then
        if mapPanel then mapPanel:Show() end
    elseif ToggleWorldMap then ToggleWorldMap() elseif WorldMapFrame then WorldMapFrame:Show() end end)
    popup.empty = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    popup.empty:SetPoint("TOPLEFT", 25, -82)
    popup.empty:SetText("All errands completed!")
    popup.empty:SetTextColor(0.25, 0.16, 0.08)
    popup.empty:SetShadowColor(0, 0, 0, 0)
end

-- Native objective tracker category. Unlike the previous floating companion, this
-- uses Blizzard's real ObjectiveTrackerModuleTemplate and participates in the
-- same module layout as Quests and Professions. No Blizzard frames are scanned,
-- patched, resized, or compared against protected/secret strings.
local trackerRegistered = false
local trackerRegistrationAttempts = 0
local MAX_TRACKED_ERRANDS = 40

local function buildTracker()
    if tracker then return true end
    if not (ObjectiveTrackerModuleMixin and ObjectiveTrackerManager and ObjectiveTrackerFrame) then
        return false
    end

    -- The built-in module template provides the exact accordion heading, collapse
    -- button, animations and ContentsFrame used by Blizzard's other categories.
    local ok, module = pcall(CreateFrame, "Frame", nil, UIParent, "ObjectiveTrackerModuleTemplate")
    if not ok or not module or not module.Header or not module.ContentsFrame
        or not module.SetHeader or not module.MarkDirty then
        return false
    end

    tracker = module
    _G.WoWErrandsObjectiveModule = module -- debugging: /dump WoWErrandsObjectiveModule
    tracker:SetHeader("Errands")
    tracker.uiOrder = ((ProfessionsRecipeTracker and ProfessionsRecipeTracker.uiOrder) or 9) + 0.5
    tracker.leftMargin = 0
    tracker.headerHeight = 25
    tracker.errandRows = {}

    local defaultSetCollapsed = tracker.SetCollapsed
    function tracker:SetCollapsed(collapsed)
        defaultSetCollapsed(self, collapsed)
        db().settings.trackerCollapsed = collapsed and true or false
    end

    local function getRow(index)
        local row = tracker.errandRows[index]
        if row then return row end
        -- Only our own buttons are clickable, never protected quest objectives.
        row = CreateFrame("CheckButton", nil, tracker.ContentsFrame, "UICheckButtonTemplate")
        row:SetSize(20, 20)
        row.label = row:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
        row.label:SetPoint("LEFT", row, "RIGHT", 3, 0)
        row.label:SetPoint("RIGHT", tracker.ContentsFrame, "RIGHT", -6, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        if row.label.SetMaxLines then row.label:SetMaxLines(1) end
        row:SetScript("OnClick", function(self)
            local tasks = activeZone and getTasks(activeZone)
            local task = tasks and tasks[self.taskIndex]
            if task and not task.done then
                task.done = true
                updateAll()
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.taskText then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.taskText)
            GameTooltip:AddLine("Click to complete this errand", 0.8, 0.7, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row:Hide()
        tracker.errandRows[index] = row
        return row
    end

    function tracker:LayoutContents()
        local tasks = activeZone and getTasks(activeZone)
        local left = activeZone and pending(activeZone) or 0
        local shown = 0
        local headerHeight = self.headerHeight or 25
        local rowHeight = 22

        -- Native trackers hide empty categories. Errands only appears while the
        -- current zone has at least one unfinished task.
        if left > 0 then
            self.hasTriedBlocks = true
            if self.availableHeight >= headerHeight then
                self.hasContents = true
                if not self:IsCollapsed() and tasks then
                    for index, task in ipairs(tasks) do
                        if not task.done then
                            if shown >= MAX_TRACKED_ERRANDS or self.contentsHeight + rowHeight > self.availableHeight then
                                self.hasSkippedBlocks = true
                                break
                            end
                            shown = shown + 1
                            local row = getRow(shown)
                            row.taskIndex = index
                            row.taskText = task.text
                            row.label:SetText(task.text)
                            row:SetChecked(false)
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", self.ContentsFrame, "TOPLEFT", 18, -2 - (shown - 1) * rowHeight)
                            row:Show()
                            self.contentsHeight = self.contentsHeight + rowHeight
                        end
                    end
                end
            else
                self.hasSkippedBlocks = true
            end
        end
        for i = shown + 1, #self.errandRows do
            self.errandRows[i]:Hide()
        end
    end

    tracker:SetCollapsed(db().settings.trackerCollapsed == true)
    tracker:Hide()
    return true
end

local function registerTracker()
    if trackerRegistered then return true end
    if not buildTracker() then return false end
    local manager = ObjectiveTrackerManager
    local container = ObjectiveTrackerFrame
    -- Blizzard's manager finishes initialization on PLAYER_ENTERING_WORLD and
    -- VARIABLES_LOADED. Register only AFTER its container is initialized.
    if not (manager and manager.containers and manager.containers[container]
            and container.modules and manager.SetModuleContainer) then
        return false
    end
    if not (manager.GetContainerForModule and manager:GetContainerForModule(tracker) == container) then
        manager:SetModuleContainer(tracker, container)
    end
    trackerRegistered = true
    tracker:MarkDirty()
    return true
end

local function ensureTrackerRegistration()
    if registerTracker() then return end
    if not (C_Timer and C_Timer.After) then return end
    if trackerRegistrationAttempts >= 25 then return end
    trackerRegistrationAttempts = trackerRegistrationAttempts + 1
    C_Timer.After(1, ensureTrackerRegistration)
end

-- A map companion, deliberately not a standalone /we management dialog.
-- All list edits are tied to the zone currently selected on the Blizzard map.
-- The map companion mirrors Spoken Zones' actual Forever UI construction:
-- DefaultPanelFlatTemplate, its quest-details parchment, inset quest-log rim,
-- header backplate, divider and LargeSideTabButtonTemplate.
-- All references to Spoken are optional and explicit. Never scan game frames or
-- compare unknown FontString text: modern Forever can make those values secret.
local function buildMapPanel()
    local map = WorldMapFrame
    if not map then return end

    local ART = "Interface\\AddOns\\Spoken_Zones\\Textures\\Art\\"
    local COPIES = {
        ["QuestDetailsBackgrounds"] = { file = ART .. "QuestDetailsBackgrounds", u = 0.560547, v = 0.90625 },
        ["spellbook-list-backplate"] = { file = ART .. "spellbook-list-backplate", u = 0.617188, v = 0.828125 },
        ["spellbook-divider"] = { file = ART .. "spellbook-divider", u = 0.641602, v = 0.6875 },
        ["questlog-frame-filigree"] = { file = ART .. "questlog-frame-filigree", u = 0.75, v = 0.59375 },
    }
    local function spokenArt()
        return _G.SpokenZones and _G.SpokenZones.Art
    end
    local function artCopy(name)
        local art = spokenArt()
        return (art and art.COPIES and art.COPIES[name]) or COPIES[name]
    end
    local function unsnap(texture)
        if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
        if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    end
    local function parchment(parent)
        local background = parent:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        local art = spokenArt()
        local copy = art and art.COPIES and art.COPIES["QuestDetailsBackgrounds"]
        -- If Spoken is present, this is its very same Forever texture, not an
        -- approximation. The copy coordinates cut the original image correctly.
        if copy then
            background:SetTexture(copy.file)
            background:SetTexCoord(copy.leftTexCoord, copy.rightTexCoord,
                copy.topTexCoord, copy.bottomTexCoord)
        else
            -- On a game without Spoken, prefer the native client atlas if present.
            local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
                and C_Texture.GetAtlasInfo("QuestDetailsBackgrounds")
            if hasAtlas and background.SetAtlas then
                background:SetAtlas("QuestDetailsBackgrounds")
            else
                background:SetTexture("Interface\\AddOns\\WoWErrands\\parchment")
            end
        end
        unsnap(background)
        return background
    end
    local function ink(font, r, g, b)
        local art = spokenArt()
        local original = art and art.INK
        if original then
            r, g, b = r or original[1], g or original[2], b or original[3]
        elseif SPELLBOOK_FONT_COLOR and SPELLBOOK_FONT_COLOR.GetRGB then
            local a, c, d = SPELLBOOK_FONT_COLOR:GetRGB()
            r, g, b = r or a, g or c, b or d
        end
        font:SetTextColor(r or 0.25, g or 0.16, b or 0.08, 1)
        font:SetShadowColor(0, 0, 0, 0)
    end
    local function isGamepadUI()
        if not GetCVar then return false end
        local ok, value = pcall(GetCVar, "InputDeviceInterfaceStyle")
        return ok and value == "1"
    end
    local function host()
        return isGamepadUI() and UIParent or map
    end
    local function lorePanel()
        -- Exact name from Spoken_Zones/UI/MapPanel.lua, unlike the previous
        -- guessed names and its unsafe font-string scan.
        local panel = _G.SpokenZonesPanel
        if panel and panel.IsShown and panel:IsShown() then return panel end
        return nil
    end
    local function canShow()
        return map:IsShown() and not (map.IsMaximized and map:IsMaximized())
    end
    local function widthToMatch()
        local panel = _G.SpokenZonesPanel
        if panel and panel.GetWidth and panel:GetWidth() > 0 then
            return panel:GetWidth()
        end
        local spoken = _G.SpokenZones
        if spoken and spoken.Get then
            local ok, value = pcall(spoken.Get, spoken, "panelWidth")
            if ok and type(value) == "number" and value > 0 then return value end
        end
        return 390
    end

    local ok, frame = pcall(CreateFrame, "Frame", "WoWErrandsMapPanel", UIParent, "DefaultPanelFlatTemplate")
    local templated = ok and frame and frame.SetTitle
    if not templated then
        frame = CreateFrame("Frame", "WoWErrandsMapPanel", UIParent, "BackdropTemplate")
        frame:SetBackdrop({
            bgFile = [[Interface\DialogFrame\UI-DialogBox-Background-Dark]],
            edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    else
        frame:SetTitle("Zone Errands")
    end
    mapPanel = frame
    mapPanel:SetWidth(widthToMatch())
    mapPanel:SetHeight(math.max(map:GetHeight(), 360))
    mapPanel:EnableMouse(true)
    if not templated then
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", frame, "TOP", 0, -13)
        title:SetText("Zone Errands")
    end
    local close = CreateFrame("Button", nil, mapPanel,
        templated and "UIPanelCloseButtonDefaultAnchors" or "UIPanelCloseButton")
    if not templated then close:SetPoint("TOPRIGHT", mapPanel, "TOPRIGHT", -8, -8) end
    close:SetScript("OnClick", function() mapPanel:Hide() end)
    mapPanel.close = close

    -- Exactly the holder dimensions used in Spoken_Zones/UI/MapPanel.lua.
    local holder = CreateFrame("Frame", nil, mapPanel)
    if templated then
        holder:SetPoint("TOPLEFT", mapPanel, "TOPLEFT", 7, -25)
        holder:SetPoint("BOTTOMRIGHT", mapPanel, "BOTTOMRIGHT", -5, 6)
    else
        holder:SetPoint("TOPLEFT", mapPanel, "TOPLEFT", 12, -32)
        holder:SetPoint("BOTTOMRIGHT", mapPanel, "BOTTOMRIGHT", -12, 12)
    end
    local page = CreateFrame("Frame", nil, holder)
    page:SetAllPoints()
    parchment(page)

    -- Spoken's faded spellbook backplate, cropped, not stretched. The parchment
    -- remains opaque and extends right up against the same ornate inner rim.
    local backplate = page:CreateTexture(nil, "BORDER")
    local backInfo = artCopy("spellbook-list-backplate")
    if backInfo then
        local left = backInfo.leftTexCoord or 0
        local right = backInfo.rightTexCoord or backInfo.u
        local top = backInfo.topTexCoord or 0
        local bottom = backInfo.bottomTexCoord or backInfo.v
        backplate:SetTexture(backInfo.file)
        backplate:SetHeight(80)
        backplate:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
        backplate:SetAlpha(0.55)
        local function fitBackplate()
            local whole, crop = 300, 40
            local shown = math.min(whole - crop, math.max(0, page:GetWidth() or 0))
            backplate:SetWidth(shown)
            backplate:SetTexCoord(left + (right-left)*crop/whole,
                left + (right-left)*(crop+shown)/whole, top, bottom)
        end
        page:HookScript("OnSizeChanged", fitBackplate)
        fitBackplate()
    end

    -- The original questlog-frame nine-slice and filigree. Use Spoken's own
    -- Art.NineSlice helper, so every corner/edge is exactly the Zone Lore art.
    local rim = CreateFrame("Frame", nil, holder)
    rim:SetPoint("TOPLEFT", holder, "TOPLEFT", -2, 3)
    rim:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 2, -3)
    rim:SetFrameLevel(holder:GetFrameLevel() + 12)
    rim:EnableMouse(false)
    local art = spokenArt()
    if art and art.NineSlice then
        rim.border = art.NineSlice(rim, "questlog-frame", "OVERLAY")
    elseif rim.SetBackdrop then
        rim:SetBackdrop({ edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
            edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    else
        -- Add BackdropTemplate only for this standalone fallback.
        local fallback = CreateFrame("Frame", nil, rim, "BackdropTemplate")
        fallback:SetAllPoints()
        fallback:SetBackdrop({ edgeFile = [[Interface\DialogFrame\UI-DialogBox-Border]],
            edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    local filigree = rim:CreateTexture(nil, "OVERLAY", nil, 1)
    if art and art.Atlas then
        art.Atlas(filigree, "questlog-frame-filigree", true)
    else
        local info = artCopy("questlog-frame-filigree")
        if info then
            filigree:SetTexture(info.file)
            filigree:SetSize(48, 19)
            filigree:SetTexCoord(0, info.u, 0, info.v)
        end
    end
    filigree:SetPoint("TOP", rim, "TOP", 0, 1)
    mapPanel.rim = rim

    -- Title, subtitle and illustrated divider are placed exactly like LorePage
    -- (24 px left, 28 px top). The panel body below is an editable checklist.
    local heading = page:CreateFontString(nil, "ARTWORK", _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge")
    local fontFile = _G.QuestTitleFont and _G.QuestTitleFont.GetFont and _G.QuestTitleFont:GetFont()
    if fontFile then heading:SetFont(fontFile, 20, "") end
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", 24, -28)
    heading:SetPoint("RIGHT", page, "RIGHT", -28, 0)
    heading:SetJustifyH("LEFT")
    heading:SetWordWrap(false)
    if heading.SetMaxLines then heading:SetMaxLines(1) end
    ink(heading)
    local subtitle = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    subtitle:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -2)
    subtitle:SetPoint("RIGHT", page, "RIGHT", -28, 0)
    subtitle:SetHeight(16)
    subtitle:SetJustifyH("LEFT")
    ink(subtitle)
    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -6, -10)
    divider:SetHeight(11)
    local dividerInfo = artCopy("spellbook-divider")
    if dividerInfo then
        divider:SetTexture(dividerInfo.file)
        local left = dividerInfo.leftTexCoord or 0
        local right = dividerInfo.rightTexCoord or dividerInfo.u
        local top = dividerInfo.topTexCoord or 0
        local bottom = dividerInfo.bottomTexCoord or dividerInfo.v
        local function fitDivider()
            local visible = math.min(657, math.max(1, (page:GetWidth() or 0) - 18 - 28))
            divider:SetWidth(visible)
            divider:SetTexCoord(left, left + (right - left) * visible/657, top, bottom)
        end
        page:HookScript("OnSizeChanged", fitDivider)
        fitDivider()
    end

    local scroll = CreateFrame("ScrollFrame", "WoWErrandsMapScroll", page)
    scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 6, -7)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -42, 96)
    scroll:EnableMouseWheel(true)
    local contents = CreateFrame("Frame", nil, scroll)
    contents:SetSize(320, 1)
    scroll:SetScrollChild(contents)

    -- Spoken's TextView scrollbar uses the same minimalist track and small
    -- thumb atlases, not UIPanelScrollFrameTemplate's large square arrows.
    local function hasAtlas(name)
        return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
    end
    local function piece(parent, layer, atlas)
        if not hasAtlas(atlas) then return nil end
        local texture = parent:CreateTexture(nil, layer)
        texture:SetAtlas(atlas, true)
        return texture
    end
    local function threePiece(parent, layer, a, b, c)
        local top = piece(parent, layer, a)
        local middle = piece(parent, layer, b)
        local bottom = piece(parent, layer, c)
        if not (top and middle and bottom) then
            if top then top:Hide() end
            if middle then middle:Hide() end
            if bottom then bottom:Hide() end
            return nil
        end
        top:SetPoint("TOP", parent, "TOP")
        bottom:SetPoint("BOTTOM", parent, "BOTTOM")
        middle:ClearAllPoints()
        middle:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
        middle:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
        return {top, middle, bottom}
    end
    local bar = CreateFrame("Frame", nil, page)
    bar:SetWidth(8)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
    bar:SetFrameLevel(scroll:GetFrameLevel() + 8)
    bar:EnableMouse(true)
    local track = threePiece(bar, "BACKGROUND", "minimal-scrollbar-track-top",
        "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom")
    if not track then
        local fallback = bar:CreateTexture(nil, "BACKGROUND")
        fallback:SetAllPoints()
        fallback:SetColorTexture(0.3, 0.2, 0.1, 0.17)
    end
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(8)
    thumb:SetHeight(20)
    thumb:SetPoint("TOP", bar, "TOP")
    local thumbParts = threePiece(thumb, "ARTWORK", "minimal-scrollbar-small-thumb-top",
        "minimal-scrollbar-small-thumb-middle", "minimal-scrollbar-small-thumb-bottom")
    if not thumbParts then
        local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(0.36, 0.24, 0.13, 0.65)
    end
    local range = 0
    local updatingScrollbar = false
    local function refreshScrollBar()
        if updatingScrollbar then return end
        updatingScrollbar = true
        local viewHeight = scroll:GetHeight() or 0
        local contentHeight = contents:GetHeight() or 0
        range = math.max(0, contentHeight - viewHeight)
        if range < 1 or viewHeight < 1 then
            bar:Hide()
            if (scroll:GetVerticalScroll() or 0) > 0 then scroll:SetVerticalScroll(0) end
            updatingScrollbar = false
            return
        end
        bar:Show()
        local height = bar:GetHeight() or 0
        local thumbHeight = math.min(height, math.max(20, (viewHeight/contentHeight)*height))
        thumb:SetHeight(thumbHeight)
        local fraction = math.min(1, math.max(0, (scroll:GetVerticalScroll() or 0)/range))
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(height-thumbHeight)*fraction)
        updatingScrollbar = false
    end
    local function setScroll(value)
        scroll:SetVerticalScroll(math.min(range, math.max(0, value)))
        refreshScrollBar()
    end
    scroll:SetScript("OnMouseWheel", function(self, delta)
        setScroll((self:GetVerticalScroll() or 0) - delta*32)
    end)
    scroll:SetScript("OnVerticalScroll", refreshScrollBar)
    scroll:HookScript("OnSizeChanged", function()
        contents:SetWidth(math.max(1, scroll:GetWidth()))
        refreshScrollBar()
    end)
    local dragging = false
    local function cursorY()
        local _, y = GetCursorPosition()
        return y / (bar:GetEffectiveScale() or 1)
    end
    local grab
    thumb:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        grab = (self:GetTop() or 0) - cursorY()
        dragging = true
        bar:SetScript("OnUpdate", function()
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                dragging = false
                bar:SetScript("OnUpdate", nil)
                return
            end
            local travel = math.max(1, bar:GetHeight() - thumb:GetHeight())
            local amount = math.min(1, math.max(0, ((bar:GetTop() or 0) - cursorY() - grab)/travel))
            setScroll(amount*range)
        end)
    end)
    thumb:SetScript("OnMouseUp", function()
        dragging = false
        bar:SetScript("OnUpdate", nil)
    end)
    bar:SetScript("OnMouseDown", function()
        local direction = cursorY() > (thumb:GetTop() or 0) and -1 or 1
        setScroll((scroll:GetVerticalScroll() or 0) + direction*math.max(32, scroll:GetHeight()-32))
    end)

    -- The footer sits on the same parchment; no separate black dialog box.
    local footerLabel = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footerLabel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 24, 64)
    footerLabel:SetText("Add an errand")
    ink(footerLabel)
    local entry = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    entry:SetHeight(25)
    entry:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 29, 30)
    entry:SetPoint("RIGHT", page, "RIGHT", -105, 0)
    entry:SetAutoFocus(false)
    entry:SetMaxLetters(160)
    local add = button(page, "Add", 62, 24)
    add:SetPoint("LEFT", entry, "RIGHT", 9, 0)
    local currentMapZone
    local rowHeight = 34
    local entryRows = {}
    local render
    local function selectedMapZone()
        local mapID = (map.GetMapID and map:GetMapID()) or map.mapID
        if not mapID or not C_Map or not C_Map.GetMapInfo then return nil end
        local info = C_Map.GetMapInfo(mapID)
        if not info or not info.name then return nil end
        local t = Enum and Enum.UIMapType
        if t and info.mapType and
            (info.mapType == t.World or info.mapType == t.Continent or info.mapType == t.Cosmic) then
            return nil
        end
        return info.name
    end
    local function trim(value)
        return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    local function addTask()
        local value = trim(entry:GetText())
        if not currentMapZone or value == "" then return end
        table.insert(getTasks(currentMapZone, true), { text = value, done = false })
        entry:SetText("")
        entry:ClearFocus()
        updateAll()
    end
    add:SetScript("OnClick", addTask)
    entry:SetScript("OnEnterPressed", addTask)
    entry:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local empty = contents:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, -9)
    empty:SetPoint("RIGHT", contents, "RIGHT", -6, 0)
    empty:SetJustifyH("LEFT")
    empty:SetText("No errands yet. Add one below.")
    ink(empty)
    local function createRow(i)
        local row = CreateFrame("Frame", nil, contents)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, -(i-1)*rowHeight)
        row:SetPoint("RIGHT", contents, "RIGHT", 0, 0)
        row.tick = check(row, 270)
        row.tick:SetPoint("LEFT", row, "LEFT", -2, 0)
        row.tick.label:ClearAllPoints()
        row.tick.label:SetPoint("LEFT", row.tick, "RIGHT", 0, 0)
        row.tick.label:SetPoint("RIGHT", row, "RIGHT", -28, 0)
        row.tick.label:SetJustifyH("LEFT")
        row.tick.label:SetFontObject(_G.QuestFont and "QuestFont" or "GameFontHighlight")
        row.tick:SetScript("OnClick", function(self)
            local tasks = getTasks(currentMapZone)
            if tasks and tasks[i] then tasks[i].done = self:GetChecked() and true or false end
            updateAll()
        end)
        row.remove = button(row, "x", 24, 21)
        row.remove:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.remove:SetScript("OnClick", function()
            local tasks = getTasks(currentMapZone)
            if tasks then table.remove(tasks, i) end
            updateAll()
        end)
        row.remove:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove errand")
            GameTooltip:Show()
        end)
        row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)
        entryRows[i] = row
    end
    render = function()
        if not mapPanel:IsShown() then return end
        currentMapZone = selectedMapZone()
        heading:SetText(currentMapZone or "Choose a zone")
        local tasks = currentMapZone and getTasks(currentMapZone) or nil
        local count = tasks and #tasks or 0
        local unfinished = 0
        for i = 1, count do if not tasks[i].done then unfinished = unfinished + 1 end end
        if not currentMapZone then
            subtitle:SetText("Select a zone on the map")
            empty:SetText("Select a zone on the map to manage its errands.")
        else
            subtitle:SetText(unfinished == 1 and "1 unfinished errand" or (unfinished .. " unfinished errands"))
            empty:SetText("No errands yet. Add one below.")
        end
        entry:SetEnabled(currentMapZone ~= nil)
        add:SetEnabled(currentMapZone ~= nil)
        empty:SetShown(count == 0)
        for i = 1, count do
            if not entryRows[i] then createRow(i) end
            local row = entryRows[i]
            row.tick:SetChecked(tasks[i].done)
            row.tick.label:SetText(tasks[i].text)
            local value = tasks[i].done and 0.45 or 0.25
            row.tick.label:SetTextColor(value, tasks[i].done and 0.34 or 0.16, tasks[i].done and 0.23 or 0.08)
            row.tick.label:SetShadowColor(0, 0, 0, 0)
            row:Show()
        end
        for i = count+1, #entryRows do entryRows[i]:Hide() end
        contents:SetHeight(math.max(1, count*rowHeight, scroll:GetHeight()))
        refreshScrollBar()
    end
    mapPanel.render = render

    -- Precisely the same tab button template and icon placement as Zone Lore.
    local tabOK, tab = pcall(CreateFrame, "Frame", "WoWErrandsMapTab", UIParent, "LargeSideTabButtonTemplate")
    if tabOK and tab and tab.Icon and tab.Icon.SetTexture and tab.SetCustomOnMouseUpHandler then
        mapTab = tab
        mapTab.fillToInterior = true
        mapTab.tooltipText = "Show Zone Errands"
        mapTab.Icon:SetTexture("Interface\\AddOns\\WoWErrands\\icon")
        if mapTab.SetChecked then mapTab:SetChecked(false) end
        mapTab:SetCustomOnMouseUpHandler(function()
            mapTab:Hide()
            mapPanel:Show()
        end)
    else
        mapTab = CreateFrame("Button", "WoWErrandsMapTab", UIParent)
        mapTab:SetSize(40, 40)
        local glyph = mapTab:CreateTexture(nil, "ARTWORK")
        glyph:SetAllPoints()
        glyph:SetTexture("Interface\\AddOns\\WoWErrands\\icon")
        glyph:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local border = mapTab:CreateTexture(nil, "OVERLAY")
        border:SetTexture([[Interface\Buttons\UI-Quickslot2]])
        border:SetSize(74, 74)
        border:SetPoint("CENTER")
        mapTab:SetPushedTexture([[Interface\Buttons\UI-Quickslot-Depress]])
        mapTab:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
        mapTab:SetScript("OnClick", function()
            mapTab:Hide()
            mapPanel:Show()
        end)
        mapTab:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Show Zone Errands")
            GameTooltip:Show()
        end)
        mapTab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    mapTab:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    local function place()
        local parent = host()
        if mapPanel:GetParent() ~= parent then mapPanel:SetParent(parent) end
        if mapTab:GetParent() ~= parent then mapTab:SetParent(parent) end
    end
    local function matchMapAppearance()
        local strata, level = map:GetFrameStrata(), map:GetFrameLevel()
        local mapScale, uiScale = map:GetEffectiveScale(), UIParent:GetEffectiveScale()
        for _, element in ipairs({mapPanel, mapTab}) do
            if strata then element:SetFrameStrata(strata) end
            if level then element:SetFrameLevel(level+10) end
            if element:GetParent() == map then
                element:SetScale(1)
                element:SetAlpha(1)
            elseif mapScale and uiScale and uiScale > 0 then
                element:SetScale(mapScale/uiScale)
                element:SetAlpha(map:GetAlpha() or 1)
            end
        end
    end
    local function positionPanel()
        place()
        mapPanel:SetWidth(widthToMatch())
        mapPanel:ClearAllPoints()
        local lore = lorePanel()
        if lore then
            mapPanel:SetPoint("TOPLEFT", lore, "TOPRIGHT", 2, 0)
            mapPanel:SetPoint("BOTTOMLEFT", lore, "BOTTOMRIGHT", 2, 0)
        else
            mapPanel:SetPoint("TOPLEFT", map, "TOPRIGHT", 2, 0)
            mapPanel:SetPoint("BOTTOMLEFT", map, "BOTTOMRIGHT", 2, 0)
        end
        matchMapAppearance()
    end
    mapPanel.positionPanel = positionPanel
    local function positionTab()
        place()
        mapTab:ClearAllPoints()
        local lore = lorePanel()
        if lore then
            -- When Zone Lore is open, the tab extends from the outermost panel.
            mapTab:SetPoint("TOPLEFT", lore, "TOPRIGHT", 0, -30)
        else
            -- When both are collapsed, follow Spoken's exact side-tab anchor
            -- and sit below it, joined to the same map-edge metal artwork.
            local loreToggle = _G.SpokenZonesPanelToggle
            if loreToggle and loreToggle.GetHeight then
                mapTab:SetPoint("TOPLEFT", loreToggle, "BOTTOMLEFT", 0, -2)
            else
                mapTab:SetPoint("TOPLEFT", map, "TOPRIGHT", 0, -104)
            end
        end
        matchMapAppearance()
    end
    mapTab.positionTab = positionTab
    local function syncTab()
        if canShow() and not mapPanel:IsShown() then
            positionTab()
            mapTab:Show()
        else
            mapTab:Hide()
        end
    end
    mapTab.sync = syncTab
    mapPanel:HookScript("OnShow", function()
        positionPanel()
        syncTab()
        render()
    end)
    mapPanel:HookScript("OnHide", syncTab)

    -- Only re-check explicit public map and Spoken frame references. Do not use
    -- EnumerateFrames()/FontString:GetText(), which caused the secret-string error.
    local elapsed, priorMapID = 0, nil
    mapPanel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if not canShow() then
            mapPanel:Hide()
            return
        end
        positionPanel()
        local mapID = map.GetMapID and map:GetMapID() or map.mapID
        if mapID ~= priorMapID then
            priorMapID = mapID
            render()
        end
    end)
    local tabElapsed = 0
    mapTab:SetScript("OnUpdate", function(self, dt)
        if not canShow() or mapPanel:IsShown() then self:Hide(); return end
        tabElapsed = tabElapsed + dt
        if tabElapsed > 0.3 then
            tabElapsed = 0
            positionTab()
        end
    end)
    map:HookScript("OnShow", function()
        if canShow() then
            positionPanel()
            mapPanel:Show()
            render()
        end
        syncTab()
    end)
    map:HookScript("OnHide", function()
        mapPanel:Hide()
        mapTab:Hide()
    end)
    map:HookScript("OnSizeChanged", function()
        if not canShow() then
            mapPanel:Hide()
            mapTab:Hide()
        elseif mapPanel:IsShown() then
            positionPanel()
        elseif not mapTab:IsShown() then
            -- A minimised world map should open the panel, unless the user
            -- deliberately folded it to a tab earlier in this map session.
            positionPanel()
            mapPanel:Show()
        else
            syncTab()
        end
    end)
    if hooksecurefunc then
        hooksecurefunc(map, "SetAlpha", function()
            if mapPanel and mapPanel:GetParent() ~= map then
                local alpha = map:GetAlpha() or 1
                mapPanel:SetAlpha(alpha)
                mapTab:SetAlpha(alpha)
            end
        end)
    end
    mapTab:Hide()
    mapPanel:Hide()
    if canShow() then
        positionPanel()
        mapPanel:Show()
        render()
    end
end

updateAll = function()
    if not activeZone then return end
    local tasks = getTasks(activeZone)
    local left = pending(activeZone)
    if popup then
        popup.zone:SetText(activeZone)
        local shown, extra = 0, 0
        if tasks then
            for index, task in ipairs(tasks) do
                if not task.done then
                    if shown < MAX_ROWS then
                        shown = shown + 1
                        local row = rows[shown]
                        row.index = index
                        row:SetChecked(false)
                        row.label:SetText(task.text)
                        row:Show()
                    else extra = extra + 1 end
                end
            end
        end
        for i = shown + 1, MAX_ROWS do rows[i]:Hide() end
        popup.empty:SetShown(shown == 0)
        popup.more:SetText(extra > 0 and ("+ " .. extra .. " more errands") or "")
    end
    -- Ask the real Blizzard objective tracker to lay out our module alongside
    -- the other categories. No separate frame outside All Objectives is shown.
    if trackerRegistered and tracker then tracker:MarkDirty() end
    if mapPanel and mapPanel:IsShown() then mapPanel.render() end
end

local function changeZone()
    local zone = zoneName()
    if zone == activeZone then return end
    activeZone = zone
    updateAll()
    if pending(zone) > 0 and lastAlertZone ~= zone then
        if not InCombatLockdown or not InCombatLockdown() then
            popup:Show()
            lastAlertZone = zone
        end
    else
        popup:Hide()
    end
end

addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon:RegisterEvent("ZONE_CHANGED")
addon:RegisterEvent("ZONE_CHANGED_INDOORS")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        db()
        buildPopup()
        -- Register the native module once Blizzard has initialized the tracker.
        -- PLAYER_ENTERING_WORLD may occur before its manager Init callback.
        buildMapPanel()
        SLASH_WOWERRANDS1 = "/we"
        SLASH_WOWERRANDS2 = "/wowerrands"
        SlashCmdList.WOWERRANDS = function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                if mapPanel then mapPanel:SetShown(not mapPanel:IsShown()) end
            elseif ToggleWorldMap then
                ToggleWorldMap()
            elseif WorldMapFrame then
                WorldMapFrame:Show()
            end
        end
        changeZone()
        ensureTrackerRegistration()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ensureTrackerRegistration()
        changeZone()
    elseif popup then
        if event == "PLAYER_REGEN_ENABLED" and activeZone and pending(activeZone) > 0 and lastAlertZone ~= activeZone then
            popup:Show()
            lastAlertZone = activeZone
        else
            changeZone()
        end
    end
end)
