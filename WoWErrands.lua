-- WoWErrands: small, native-styled zone todo lists for WoW: Forever (Interface 16001).
local addon = CreateFrame("Frame")
local tracker, mapPanel, mapTab
local activeZone
local Core = _G.WoWErrandsCore

local function zoneName()
    local name = GetZoneText()
    if name and name ~= "" then return name end
    return GetRealZoneText() or "Unknown Zone"
end

local function db() return Core.DB() end
local function getTasks(zone, create) return Core.Tasks(zone, create) end

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

-- No zone-entry popup: arrival attention happens within the native objective tracker.
local requestTrackerAttention
local queuedAttention

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
            local task = self.taskZone and Core.Find(self.taskZone, self.taskID)
            if task and not task.done then
                if task.location and IsShiftKeyDown and IsShiftKeyDown() then
                    local ok, message = Core.SetWaypoint(task.location)
                    if not ok and UIErrorsFrame then
                        UIErrorsFrame:AddMessage(message or "Waypoint unavailable", 1, 0.65, 0.25)
                    end
                else
                    Core.SetDone(self.taskZone, self.taskID, true)
                    updateAll()
                end
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.taskText then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.taskText)
            GameTooltip:AddLine("Click to complete this errand", 0.8, 0.7, 0.5)
            local task = self.taskZone and Core.Find(self.taskZone, self.taskID)
            if self.taskZone ~= activeZone then
                GameTooltip:AddLine("Zone: " .. self.taskZone, 0.8, 0.7, 0.5)
            end
            if task and task.location then
                GameTooltip:AddLine("Shift-click to set a waypoint", 0.8, 0.7, 0.5)
            end
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
        local available = Core.TrackerItems(activeZone)
        local shown = 0
        local headerHeight = self.headerHeight or 25
        local rowHeight = 22

        -- Local errands appear automatically; explicitly tracked errands in
        -- other zones remain on the tracker until untracked or completed.
        if #available > 0 then
            self.hasTriedBlocks = true
            if self.availableHeight >= headerHeight then
                self.hasContents = true
                if not self:IsCollapsed() then
                    for _, item in ipairs(available) do
                        if shown >= MAX_TRACKED_ERRANDS or self.contentsHeight + rowHeight > self.availableHeight then
                            self.hasSkippedBlocks = true
                            break
                        end
                        shown = shown + 1
                        local row = getRow(shown)
                        row.taskZone = item.zone
                        row.taskID = item.task.id
                        row.taskText = item.task.text
                        row.label:SetText(item.task.text .. (item.zone ~= activeZone and (" (" .. item.zone .. ")") or ""))
                        row:SetChecked(false)
                        row:ClearAllPoints()
                        row:SetPoint("TOPLEFT", self.ContentsFrame, "TOPLEFT", 18, -2 - (shown - 1) * rowHeight)
                        row:Show()
                        self.contentsHeight = self.contentsHeight + rowHeight
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

    -- A brief golden text pulse uses our own objective rows. No screen-sized
    -- overlay or replacement tracker UI is created.
    local flashDriver = CreateFrame("Frame", nil, UIParent)
    flashDriver:Hide()
    tracker.flashDriver = flashDriver
    local fontR, fontG, fontB = 1, 1, 1
    if ObjectiveTrackerLineFont and ObjectiveTrackerLineFont.GetTextColor then
        fontR, fontG, fontB = ObjectiveTrackerLineFont:GetTextColor()
    end
    local function restoreLabels()
        for _, row in ipairs(tracker.errandRows) do
            row.label:SetTextColor(fontR, fontG, fontB)
        end
    end
    flashDriver:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        local duration = 2.4
        local remaining = math.max(0, 1 - self.elapsed / duration)
        local intensity = math.abs(math.sin(self.elapsed * 7.8)) * remaining
        local r = fontR + (1 - fontR) * intensity
        local g = fontG + (0.72 - fontG) * intensity
        local b = fontB + (0.08 - fontB) * intensity
        for _, row in ipairs(tracker.errandRows) do
            if row:IsShown() and row.taskZone == self.zone
                and (not self.taskID or row.taskID == self.taskID) then
                row.label:SetTextColor(r, g, b)
            else
                row.label:SetTextColor(fontR, fontG, fontB)
            end
        end
        if self.elapsed >= duration then
            self:Hide()
            restoreLabels()
        end
    end)
    function tracker:FlashErrands(zone, taskID)
        flashDriver.zone = zone
        flashDriver.taskID = taskID
        flashDriver.elapsed = 0
        restoreLabels()
        flashDriver:Show()
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
    if queuedAttention and requestTrackerAttention then
        local queued = queuedAttention
        queuedAttention = nil
        requestTrackerAttention(queued.zone, queued.id, queued.requireCurrent)
    end
    return true
end

local function ensureTrackerRegistration()
    if registerTracker() then return end
    if not (C_Timer and C_Timer.After) then return end
    if trackerRegistrationAttempts >= 25 then return end
    trackerRegistrationAttempts = trackerRegistrationAttempts + 1
    C_Timer.After(1, ensureTrackerRegistration)
end

-- Ensure the real All Objectives tracker and our Errands category are open.
-- Combat lockdown and early addon initialization defer, rather than drop, alerts.
requestTrackerAttention = function(zone, taskID, requireCurrent)
    if not zone or (requireCurrent and zone ~= activeZone) then return end
    if not trackerRegistered or (InCombatLockdown and InCombatLockdown()) then
        queuedAttention = { zone = zone, id = taskID, requireCurrent = requireCurrent }
        return
    end
    local found = false
    for _, item in ipairs(Core.TrackerItems(activeZone)) do
        if item.zone == zone and (not taskID or item.task.id == taskID) then
            found = true
            break
        end
    end
    if not found then return end

    local container = ObjectiveTrackerFrame
    if container and container.SetCollapsed then
        local collapsed = container.isCollapsed
        if container.IsCollapsed then collapsed = container:IsCollapsed() end
        if collapsed then container:SetCollapsed(false) end
    end
    if tracker:IsCollapsed() then tracker:SetCollapsed(false) end
    tracker:MarkDirty()

    local function highlightAfterLayout()
        if not trackerRegistered or (requireCurrent and zone ~= activeZone) then return end
        -- A zone transition or a manual completion may have removed the entry.
        for _, item in ipairs(Core.TrackerItems(activeZone)) do
            if item.zone == zone and (not taskID or item.task.id == taskID) then
                tracker:FlashErrands(zone, taskID)
                return
            end
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, highlightAfterLayout)
    else
        highlightAfterLayout()
    end
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
        Core.Add(currentMapZone, value)
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
    -- v3: Everything stays within this single native-styled map companion.
    -- Stable IDs keep pins and reordering attached to the right errand.
    local overviewMode = false
    local placingID, placingZone, placingMapID
    local mapPins, overviewRows = {}, {}
    local rowHeight = 56
    local currentMapID

    local function notice(message)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("WoWErrands: " .. message, 1, 0.65, 0.25)
        end
    end

    local function trackingHint(task, zone)
        if task.tracked == true then return "Shift-click to untrack" end
        if task.tracked == nil and zone == activeZone then
            return "Shift-click to keep tracking after leaving this zone"
        end
        return "Shift-click to track in All Objectives"
    end

    local function toggleTracking(zone, taskID)
        local ok, tracked = Core.ToggleTracked(zone, taskID)
        if not ok then
            notice("Completed errands cannot be tracked.")
            return
        end
        updateAll()
        if tracked then requestTrackerAttention(zone, taskID, false) end
    end

    local function setWaypoint(loc)
        local ok, errorMessage = Core.SetWaypoint(loc)
        if not ok then notice(errorMessage or "Unable to set waypoint.") end
    end

    local function mapID()
        return (map.GetMapID and map:GetMapID()) or map.mapID
    end

    local function ensurePin(task, zone)
        local loc = task.location
        if not loc or not task.id then return end
        local container = map.ScrollContainer
        local available = type(container) == "table" or type(container) == "userdata"
        local canvas = available and container.GetCanvas and container:GetCanvas()
        if not canvas then return end
        local pin = mapPins[task.id]
        if not pin then
            pin = CreateFrame("Button", nil, canvas)
            pin:SetSize(26, 26)
            pin:SetFrameLevel(canvas:GetFrameLevel() + 25)
            local artwork = pin:CreateTexture(nil, "ARTWORK")
            artwork:SetPoint("CENTER")
            artwork:SetSize(22, 22)
            artwork:SetTexture("Interface\\AddOns\\WoWErrands\\icon")
            artwork:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local rim = pin:CreateTexture(nil, "OVERLAY")
            rim:SetTexture("Interface\\Buttons\\UI-Quickslot2")
            rim:SetSize(42, 42)
            rim:SetPoint("CENTER")
            pin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            pin:SetScript("OnClick", function(self)
                local selected = Core.Find(self.zone, self.taskID)
                if selected and selected.location then setWaypoint(selected.location) end
            end)
            pin:SetScript("OnEnter", function(self)
                local selected = Core.Find(self.zone, self.taskID)
                if selected then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(selected.text)
                    GameTooltip:AddLine("Click to set a Blizzard waypoint", 0.8, 0.7, 0.5)
                    GameTooltip:Show()
                end
            end)
            pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
            mapPins[task.id] = pin
        elseif pin:GetParent() ~= canvas then
            pin:SetParent(canvas)
        end
        pin.taskID, pin.zone = task.id, zone
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * loc.x,
            -canvas:GetHeight() * loc.y)
        pin:Show()
    end

    local function refreshPins()
        for _, pin in pairs(mapPins) do pin:Hide() end
        local zone = selectedMapZone()
        local id = mapID()
        if not zone or not id or overviewMode then return end
        local tasks = getTasks(zone)
        if not tasks then return end
        for _, task in ipairs(tasks) do
            if not task.done and task.location and task.location.mapID == id then
                ensurePin(task, zone)
            end
        end
    end

    local placeCancel = button(page, "Cancel", 72, 23)
    placeCancel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -18, 30)
    placeCancel:Hide()

    local function cancelPlacement()
        placingID, placingZone, placingMapID = nil, nil, nil
        footerLabel:SetText("Add an errand")
        entry:Show()
        add:Show()
        placeCancel:Hide()
    end
    placeCancel:SetScript("OnClick", cancelPlacement)

    local function beginPlacement(zone, id)
        local task = Core.Find(zone, id)
        if not task then return end
        if zone ~= selectedMapZone() then
            notice("Select the errand's zone on the map first.")
            return
        end
        placingID, placingZone, placingMapID = id, zone, mapID()
        footerLabel:SetText("Click a location on the map to pin this errand")
        entry:Hide()
        add:Hide()
        placeCancel:Show()
    end

    -- Spoken uses this same public map scroll handler to resolve subzone clicks.
    -- Do not replace Blizzard handlers or read any protected frame text.
    local mapClickHooked = false
    local function hookMapClicks()
        if mapClickHooked then return end
        local container = map.ScrollContainer
        local available = type(container) == "table" or type(container) == "userdata"
        if not available or not container.GetNormalizedCursorPosition then return end
        mapClickHooked = true
        local clickX, clickY, clickMap
        container:HookScript("OnMouseDown", function(self, which)
            if placingID and which == "LeftButton" then
                clickX, clickY = self:GetNormalizedCursorPosition()
                clickMap = mapID()
            end
        end)
        container:HookScript("OnMouseUp", function(self, which)
            if which ~= "LeftButton" or not placingID or not clickX then return end
            local x, y = self:GetNormalizedCursorPosition()
            local startX, startY, startMap = clickX, clickY, clickMap
            clickX, clickY, clickMap = nil, nil, nil
            if not x or not y or not startX or not startY or mapID() ~= startMap
                or startMap ~= placingMapID or selectedMapZone() ~= placingZone then return end
            if math.abs(startX - x) + math.abs(startY - y) > 0.012 then return end
            local zone, id = placingZone, placingID
            if Core.SetLocation(zone, id, startMap, x, y) then
                cancelPlacement()
                updateAll()
            end
        end)
    end
    hookMapClicks()
    map:HookScript("OnShow", hookMapClicks)

    local overviewButton = button(page, "All zones", 90, 22)
    overviewButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -25, -31)
    heading:ClearAllPoints()
    heading:SetPoint("TOPLEFT", page, "TOPLEFT", 24, -28)
    heading:SetPoint("RIGHT", overviewButton, "LEFT", -8, 0)

    local function overviewRow(index)
        if overviewRows[index] then return overviewRows[index] end
        local row = CreateFrame("Button", nil, contents)
        row:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, 0)
        row:SetPoint("RIGHT", contents, "RIGHT", 0, 0)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", row, "LEFT", 5, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetTextColor(0.26, 0.16, 0.07)
        row.label = label
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if not self.zone then return end
            if self.task and IsShiftKeyDown and IsShiftKeyDown() then
                toggleTracking(self.zone, self.task.id)
                return
            end
            local id = Core.MapID(self.zone)
            if id and map.SetMapID then
                overviewMode = false
                map:SetMapID(id)
                render()
                if self.task and self.task.location then setWaypoint(self.task.location) end
            else
                notice("Open this zone on the map once to link it to its map.")
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.zone or "")
            GameTooltip:AddLine("Click to open this zone on the map", 0.8, 0.7, 0.5)
            if self.task then
                GameTooltip:AddLine(trackingHint(self.task, self.zone), 1, 0.82, 0.25)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        overviewRows[index] = row
        return row
    end

    local function renderOverview()
        local groups, total = Core.AllPending()
        heading:SetText("All Errands")
        subtitle:SetText(total .. " errands across " .. #groups .. " zones")
        empty:SetShown(total == 0)
        empty:SetText("No unfinished errands anywhere in Azeroth.")
        for _, row in ipairs(entryRows) do row:Hide() end
        local index, y = 0, 0
        for _, group in ipairs(groups) do
            index = index + 1
            local header = overviewRow(index)
            header.zone, header.task = group.zone, nil
            header:SetHeight(29)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, -y)
            header:SetPoint("RIGHT", contents, "RIGHT", 0, 0)
            header.label:SetFontObject("GameFontNormal")
            header.label:SetText(group.zone .. "  (" .. group.count .. ")")
            header:Show()
            y = y + 29
            for _, task in ipairs(group.tasks) do
                if not task.done then
                    index = index + 1
                    local item = overviewRow(index)
                    item.zone, item.task = group.zone, task
                    item:SetHeight(23)
                    item:ClearAllPoints()
                    item:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, -y)
                    item:SetPoint("RIGHT", contents, "RIGHT", 0, 0)
                    item.label:SetFontObject("GameFontHighlight")
                    item.label:SetText("    " .. (task.tracked == true and "|cffffd100> |r" or "- ")
                        .. task.text .. (task.location and "  [pin]" or ""))
                    item:Show()
                    y = y + 23
                end
            end
            y = y + 4
        end
        for i = index + 1, #overviewRows do overviewRows[i]:Hide() end
        contents:SetHeight(math.max(1, y, scroll:GetHeight()))
        refreshScrollBar()
    end

    overviewButton:SetScript("OnClick", function()
        overviewMode = not overviewMode
        cancelPlacement()
        render()
    end)

    local function createRow(i)
        local row = CreateFrame("Frame", nil, contents)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", contents, "TOPLEFT", 0, -(i-1)*rowHeight)
        row:SetPoint("RIGHT", contents, "RIGHT", 0, 0)
        row.tick = check(row, 270)
        row.tick:SetPoint("TOPLEFT", row, "TOPLEFT", -2, -2)
        row.tick.label:ClearAllPoints()
        row.tick.label:SetPoint("LEFT", row.tick, "RIGHT", 0, 0)
        row.tick.label:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.tick.label:SetJustifyH("LEFT")
        row.tick.label:SetFontObject(_G.QuestFont and "QuestFont" or "GameFontHighlight")
        row.tick:SetScript("OnClick", function(self)
            if IsShiftKeyDown and IsShiftKeyDown() then
                local task = Core.Find(currentMapZone, row.taskID)
                if task then self:SetChecked(task.done) end
                toggleTracking(currentMapZone, row.taskID)
            elseif Core.SetDone(currentMapZone, row.taskID, self:GetChecked()) then
                updateAll()
            end
        end)
        -- WoW checkboxes do not include their adjacent FontString in the hit
        -- rectangle. An invisible text button makes Shift-click work on the
        -- actual errand name, just like Shift-clicking a quest in the log.
        row.nameButton = CreateFrame("Button", nil, row)
        row.nameButton:SetPoint("TOPLEFT", row, "TOPLEFT", 27, -1)
        row.nameButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -1)
        row.nameButton:SetHeight(23)
        row.nameButton:SetScript("OnClick", function()
            local task = Core.Find(currentMapZone, row.taskID)
            if not task then return end
            if IsShiftKeyDown and IsShiftKeyDown() then
                toggleTracking(currentMapZone, row.taskID)
            elseif Core.SetDone(currentMapZone, row.taskID, not task.done) then
                updateAll()
            end
        end)
        local function trackingTooltip(control)
            local task = Core.Find(currentMapZone, row.taskID)
            if not task then return end
            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
            GameTooltip:SetText(task.text)
            GameTooltip:AddLine("Click to toggle completion", 0.8, 0.7, 0.5)
            if not task.done then
                GameTooltip:AddLine(trackingHint(task, currentMapZone), 1, 0.82, 0.25)
            end
            GameTooltip:Show()
        end
        row.tick:SetScript("OnEnter", trackingTooltip)
        row.tick:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.nameButton:SetScript("OnEnter", trackingTooltip)
        row.nameButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.pin = button(row, "Pin", 49, 20)
        row.pin:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -28)
        row.pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.pin:SetScript("OnClick", function(_, which)
            local task = Core.Find(currentMapZone, row.taskID)
            if not task then return end
            if task.location and which ~= "RightButton" then
                setWaypoint(task.location)
            else
                beginPlacement(currentMapZone, row.taskID)
            end
        end)
        row.pin:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local task = Core.Find(currentMapZone, row.taskID)
            GameTooltip:SetText(task and task.location and "Map waypoint" or "Place map pin")
            if task and task.location then
                GameTooltip:AddLine("Left-click: set waypoint. Right-click: move pin.", 0.8, 0.7, 0.5, true)
            else
                GameTooltip:AddLine("Click a point on the zone map after selecting Pin.", 0.8, 0.7, 0.5, true)
            end
            GameTooltip:Show()
        end)
        row.pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Keep the reorder controls next to Remove, on the right side of the
        -- second row: [Pin]                         [^] [v] [x].
        row.remove = button(row, "x", 24, 20)
        row.remove:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -28)
        row.remove:SetScript("OnClick", function()
            if Core.Remove(currentMapZone, row.taskID) then updateAll() end
        end)
        row.down = button(row, "v", 24, 20)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -3, 0)
        row.down:SetScript("OnClick", function()
            if Core.Move(currentMapZone, row.taskID, 1) then updateAll() end
        end)
        row.up = button(row, "^", 24, 20)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -3, 0)
        row.up:SetScript("OnClick", function()
            if Core.Move(currentMapZone, row.taskID, -1) then updateAll() end
        end)
        for _, control in ipairs({ row.up, row.down, row.remove }) do
            control:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self == row.up then GameTooltip:SetText("Move errand up")
                elseif self == row.down then GameTooltip:SetText("Move errand down")
                else GameTooltip:SetText("Remove errand") end
                GameTooltip:Show()
            end)
            control:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        entryRows[i] = row
    end
    render = function()
        if not mapPanel:IsShown() then return end
        currentMapID = mapID()
        currentMapZone = selectedMapZone()
        if currentMapZone and currentMapID then Core.RememberMap(currentMapZone, currentMapID) end
        overviewButton:SetText(overviewMode and "Zone" or "All zones")
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 6, -7)
        scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -42, overviewMode and 18 or 96)
        contents:SetWidth(math.max(1, scroll:GetWidth()))
        local showEntry = not overviewMode and not placingID
        footerLabel:SetShown(not overviewMode)
        entry:SetShown(showEntry)
        add:SetShown(showEntry)
        placeCancel:SetShown(placingID ~= nil and not overviewMode)
        if overviewMode then
            renderOverview()
            refreshPins()
            return
        end
        for _, row in ipairs(overviewRows) do row:Hide() end
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
            local task = tasks[i]
            row.taskID = task.id
            row.tick:SetChecked(task.done)
            row.tick.label:SetText((task.tracked == true and "|cffffd100> |r" or "")
                .. task.text)
            local value = task.done and 0.45 or 0.25
            row.tick.label:SetTextColor(value, task.done and 0.34 or 0.16, task.done and 0.23 or 0.08)
            row.tick.label:SetShadowColor(0, 0, 0, 0)
            row.pin:SetText(task.location and "Go" or "Pin")
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < count)
            row:Show()
        end
        for i = count+1, #entryRows do entryRows[i]:Hide() end
        contents:SetHeight(math.max(1, count*rowHeight, scroll:GetHeight()))
        refreshScrollBar()
        refreshPins()
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
            if placingID then cancelPlacement() end
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
            refreshPins()
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
        cancelPlacement()
        for _, pin in pairs(mapPins) do pin:Hide() end
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
    -- The tracker is the only zone-arrival UI; no extra popup is created.
    if trackerRegistered and tracker then tracker:MarkDirty() end
    if mapPanel and mapPanel:IsShown() then mapPanel.render() end
end

local function changeZone()
    local zone = zoneName()
    if zone == activeZone then return end
    activeZone = zone
    updateAll()
    if #Core.TrackerItems(activeZone) > 0 then
        -- Only pulse when this zone has new unfinished errands. Manually
        -- tracked out-of-zone errands remain visible but do not pulse on entry.
        for _, item in ipairs(Core.TrackerItems(activeZone)) do
            if item.zone == activeZone then
                requestTrackerAttention(activeZone, nil, true)
                break
            end
        end
    end
end

addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
addon:RegisterEvent("ZONE_CHANGED")
addon:RegisterEvent("ZONE_CHANGED_INDOORS")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        db()
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        changeZone()
        if queuedAttention then
            local queued = queuedAttention
            queuedAttention = nil
            requestTrackerAttention(queued.zone, queued.id, queued.requireCurrent)
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS" then
        changeZone()
    end
end)
