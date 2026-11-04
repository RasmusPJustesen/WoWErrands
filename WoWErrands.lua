-- WoWErrands: small, native-styled zone todo lists for WoW: Forever (Interface 16001).
local addon = CreateFrame("Frame")
local tracker, questLog
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

-- Errands live inside the world map's quest log, as a collapsible category on
-- the same level as the quest headers. Our frames are appended to the public
-- QuestScrollFrame.Contents layout through a high layoutIndex; Blizzard's own
-- quest rows are never modified, scanned or compared against secret strings.
-- Every action is a plain left-click (no modifier keys), so the section works
-- with the gamepad virtual cursor as well as with a mouse.
local LAYOUT_BASE = 100000

local function buildQuestLogSection()
    local map = WorldMapFrame
    local scrollFrame = _G.QuestScrollFrame
    local contents = scrollFrame and scrollFrame.Contents
    if not (map and contents) then return false end

    local section = { frames = {} }
    questLog = section
    local INK_R, INK_G, INK_B = 1, 0.82, 0
    local placingID, placingZone, placingMapID
    local expandedID
    local mapPins = {}
    local render

    local function notice(message)
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("WoWErrands: " .. message, 1, 0.65, 0.25)
        end
    end
    local function mapID()
        return (map.GetMapID and map:GetMapID()) or map.mapID
    end
    local function selectedMapZone()
        local id = mapID()
        if not id or not C_Map or not C_Map.GetMapInfo then return nil end
        local info = C_Map.GetMapInfo(id)
        if not info or not info.name then return nil end
        local t = Enum and Enum.UIMapType
        if t and info.mapType and
            (info.mapType == t.World or info.mapType == t.Continent or info.mapType == t.Cosmic) then
            return nil
        end
        return info.name
    end
    local function width()
        local w = contents:GetWidth() or 0
        if w < 100 then w = (scrollFrame:GetWidth() or 0) - 12 end
        return math.max(200, w)
    end
    local function tooltip(owner, title, ...)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        for i = 1, select("#", ...) do
            GameTooltip:AddLine((select(i, ...)), 0.8, 0.7, 0.5, true)
        end
        GameTooltip:Show()
    end
    local function hideTooltip() GameTooltip:Hide() end
    local function collapsed() return db().settings.questLogCollapsed == true end

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

    -- Map pins for the errands of the zone currently shown on the map.
    local function ensurePin(task, zone)
        local loc = task.location
        local container = map.ScrollContainer
        if type(container) ~= "table" and type(container) ~= "userdata" then return end
        local canvas = container.GetCanvas and container:GetCanvas()
        if not canvas then return end
        local pin = mapPins[task.id]
        if not pin then
            pin = CreateFrame("Button", nil, canvas)
            pin:SetSize(26, 26)
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
                if selected then tooltip(self, selected.text, "Click to set a Blizzard waypoint") end
            end)
            pin:SetScript("OnLeave", hideTooltip)
            mapPins[task.id] = pin
        elseif pin:GetParent() ~= canvas then
            pin:SetParent(canvas)
        end
        pin:SetFrameLevel(canvas:GetFrameLevel() + 25)
        pin.taskID, pin.zone = task.id, zone
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * loc.x, -canvas:GetHeight() * loc.y)
        pin:Show()
    end
    local function refreshPins()
        for _, pin in pairs(mapPins) do pin:Hide() end
        local zone, id = selectedMapZone(), mapID()
        if not zone or not id or not map:IsShown() then return end
        for _, task in ipairs(getTasks(zone) or {}) do
            if not task.done and task.location and task.location.mapID == id then
                ensurePin(task, zone)
            end
        end
    end

    local function cancelPlacement()
        if not placingID then return end
        placingID, placingZone, placingMapID = nil, nil, nil
        if render then render() end
    end
    local function beginPlacement(zone, id)
        if not Core.Find(zone, id) then return end
        if zone ~= selectedMapZone() then
            notice("Open the errand's zone on the map first.")
            return
        end
        placingID, placingZone, placingMapID = id, zone, mapID()
        render()
    end

    -- The same public map scroll handlers Spoken uses for subzone clicks.
    local mapClickHooked = false
    local function hookMapClicks()
        if mapClickHooked then return end
        local container = map.ScrollContainer
        if type(container) ~= "table" and type(container) ~= "userdata" then return end
        if not container.GetNormalizedCursorPosition then return end
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
            if not x or not y or mapID() ~= startMap
                or startMap ~= placingMapID or selectedMapZone() ~= placingZone then return end
            if math.abs(startX - x) + math.abs(startY - y) > 0.012 then return end
            if Core.SetLocation(placingZone, placingID, startMap, x, y) then
                placingID, placingZone, placingMapID = nil, nil, nil
                updateAll()
            end
        end)
    end
    hookMapClicks()
    map:HookScript("OnShow", hookMapClicks)

    -- Category header. Prefer the quest log's own header template for an
    -- identical look; its scripts are replaced so it never touches quest data.
    local ok, header = pcall(CreateFrame, "Button", nil, contents, "QuestLogHeaderCodeTemplate")
    if not ok or not header then
        header = CreateFrame("Button", nil, contents)
        header:SetNormalFontObject("GameFontNormalMed3")
        header:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        header.Icon = header:CreateTexture(nil, "ARTWORK")
        header.Icon:SetSize(16, 16)
        header.Icon:SetPoint("LEFT", header, "LEFT", 4, 0)
    end
    header:SetHeight(header:GetHeight() > 0 and header:GetHeight() or 30)
    header:SetText("Errands")
    local headerText = header.ButtonText or header:GetFontString()
    if headerText and not header.ButtonText and header.Icon then
        headerText:ClearAllPoints()
        headerText:SetPoint("LEFT", header.Icon, "RIGHT", 6, 0)
    end
    header.layoutIndex = LAYOUT_BASE
    header.topPadding = 6
    if header.RegisterForClicks then header:RegisterForClicks("LeftButtonUp") end
    local function toggleCollapsed()
        db().settings.questLogCollapsed = not collapsed()
        expandedID = nil
        render()
    end
    header:SetScript("OnClick", toggleCollapsed)
    if header.CollapseButton then header.CollapseButton:SetScript("OnClick", toggleCollapsed) end
    header:SetScript("OnEnter", function(self)
        tooltip(self, "Errands", collapsed() and "Click to expand" or "Click to collapse")
    end)
    header:SetScript("OnLeave", hideTooltip)
    local function updateHeaderState()
        local isCollapsed = collapsed()
        local button = header.CollapseButton
        if button and button.UpdateCollapsedState then
            if pcall(button.UpdateCollapsedState, button, isCollapsed) then return end
        end
        if header.Icon then
            header.Icon:SetTexture(isCollapsed and "Interface\\Buttons\\UI-PlusButton-Up"
                or "Interface\\Buttons\\UI-MinusButton-Up")
        end
    end

    local function place(frame, index)
        frame.layoutIndex = LAYOUT_BASE + index
        frame.leftPadding = frame.leftPadding or 0
        frame:SetWidth(width() - (frame.leftPadding or 0))
        frame:Show()
    end

    local function smallButton(parent, label, w)
        local b = button(parent, label, w, 20)
        b:SetScript("OnLeave", hideTooltip)
        return b
    end

    -- Errand rows: [x] Errand text. Clicking the text expands a row of action
    -- buttons, so tracking, pins and ordering never require Shift or right-click.
    local rows, zoneRows = {}, {}
    local function getRow(index)
        if rows[index] then return rows[index] end
        local row = CreateFrame("Frame", nil, contents)
        row.leftPadding = 10
        row:SetHeight(24)
        row.tick = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.tick:SetSize(22, 22)
        row.tick:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        row.tick:SetScript("OnClick", function(self)
            if Core.SetDone(row.zone, row.taskID, self:GetChecked()) then updateAll() end
        end)
        row.tick:SetScript("OnEnter", function(self)
            tooltip(self, row.text or "", "Click to toggle completion")
        end)
        row.tick:SetScript("OnLeave", hideTooltip)
        row.name = CreateFrame("Button", nil, row)
        row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -1)
        row.name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -1)
        row.name:SetHeight(22)
        row.name:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.name:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.label = row.name:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.label:SetPoint("LEFT", row.name, "LEFT", 2, 0)
        row.label:SetPoint("RIGHT", row.name, "RIGHT", -2, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.name:SetScript("OnClick", function(_, which)
            if which == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
                toggleTracking(row.zone, row.taskID)
                return
            end
            expandedID = (expandedID == row.taskID) and nil or row.taskID
            render()
        end)
        row.name:SetScript("OnEnter", function(self)
            local lines = { "Click to show actions" }
            if row.zone ~= selectedMapZone() then lines[2] = "Zone: " .. (row.zone or "") end
            tooltip(self, row.text or "", unpack(lines))
        end)
        row.name:SetScript("OnLeave", hideTooltip)

        -- Action strip: [Track] [Go] [Pin]            [^] [v] [x]
        local actions = CreateFrame("Frame", nil, row)
        actions:SetPoint("TOPLEFT", row, "TOPLEFT", 24, -24)
        actions:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -24)
        actions:SetHeight(22)
        row.actions = actions
        row.track = smallButton(actions, "Track", 62)
        row.track:SetPoint("LEFT", actions, "LEFT", 0, 0)
        row.track:SetScript("OnClick", function() toggleTracking(row.zone, row.taskID) end)
        row.track:SetScript("OnEnter", function(self)
            tooltip(self, "All Objectives", "Keep this errand in the objective tracker, even in other zones.")
        end)
        row.go = smallButton(actions, "Go", 36)
        row.go:SetPoint("LEFT", row.track, "RIGHT", 3, 0)
        row.go:SetScript("OnClick", function()
            local task = Core.Find(row.zone, row.taskID)
            if task and task.location then setWaypoint(task.location) end
        end)
        row.go:SetScript("OnEnter", function(self) tooltip(self, "Set waypoint") end)
        row.pin = smallButton(actions, "Pin", 40)
        row.pin:SetPoint("LEFT", row.go, "RIGHT", 3, 0)
        row.pin:SetScript("OnClick", function() beginPlacement(row.zone, row.taskID) end)
        row.pin:SetScript("OnEnter", function(self)
            tooltip(self, "Place map pin", "Then click a point on this zone's map.")
        end)
        row.remove = smallButton(actions, "x", 24)
        row.remove:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
        row.remove:SetScript("OnClick", function()
            if Core.Remove(row.zone, row.taskID) then expandedID = nil; updateAll() end
        end)
        row.remove:SetScript("OnEnter", function(self) tooltip(self, "Remove errand") end)
        row.down = smallButton(actions, "v", 24)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -3, 0)
        row.down:SetScript("OnClick", function()
            if Core.Move(row.zone, row.taskID, 1) then updateAll() end
        end)
        row.down:SetScript("OnEnter", function(self) tooltip(self, "Move errand down") end)
        row.up = smallButton(actions, "^", 24)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -3, 0)
        row.up:SetScript("OnClick", function()
            if Core.Move(row.zone, row.taskID, -1) then updateAll() end
        end)
        row.up:SetScript("OnEnter", function(self) tooltip(self, "Move errand up") end)
        rows[index] = row
        return row
    end

    -- Zone sub-headings, used when the map shows a continent or the world.
    local function getZoneRow(index)
        if zoneRows[index] then return zoneRows[index] end
        local row = CreateFrame("Button", nil, contents)
        row.leftPadding = 6
        row:SetHeight(22)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local id = Core.MapID(self.zone)
            if id and map.SetMapID then
                map:SetMapID(id)
            else
                notice("Open this zone on the map once to link it to its map.")
            end
        end)
        row:SetScript("OnEnter", function(self) tooltip(self, self.zone or "", "Click to open this zone on the map") end)
        row:SetScript("OnLeave", hideTooltip)
        zoneRows[index] = row
        return row
    end

    -- Footer: add an errand, or the pin placement prompt.
    local footer = CreateFrame("Frame", nil, contents)
    footer.leftPadding = 10
    footer:SetHeight(30)
    local message = footer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    message:SetPoint("LEFT", footer, "LEFT", 4, 0)
    message:SetPoint("RIGHT", footer, "RIGHT", -70, 0)
    message:SetJustifyH("LEFT")
    local entry = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
    entry:SetHeight(22)
    entry:SetPoint("LEFT", footer, "LEFT", 6, 0)
    entry:SetPoint("RIGHT", footer, "RIGHT", -60, 0)
    entry:SetAutoFocus(false)
    entry:SetMaxLetters(160)
    local add = smallButton(footer, "Add", 52)
    add:SetPoint("RIGHT", footer, "RIGHT", -2, 0)
    local cancel = smallButton(footer, "Cancel", 62)
    cancel:SetPoint("RIGHT", footer, "RIGHT", -2, 0)
    cancel:SetScript("OnClick", cancelPlacement)
    local function addTask()
        local zone = selectedMapZone()
        if not zone then return end
        if Core.Add(zone, entry:GetText()) then
            entry:SetText("")
            entry:ClearFocus()
            updateAll()
        end
    end
    add:SetScript("OnClick", addTask)
    entry:SetScript("OnEnterPressed", addTask)
    entry:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    render = function()
        local zone = selectedMapZone()
        local id = mapID()
        if zone and id then Core.RememberMap(zone, id) end
        if placingID and (zone ~= placingZone or id ~= placingMapID) then
            placingID, placingZone, placingMapID = nil, nil, nil
        end
        updateHeaderState()
        for _, row in ipairs(rows) do row:Hide() end
        for _, row in ipairs(zoneRows) do row:Hide() end
        footer:Hide()

        local pending = 0
        local groups
        if zone then
            pending = Core.Pending(zone)
        else
            groups, pending = Core.AllPending()
        end
        header:SetText(pending > 0 and ("Errands (" .. pending .. ")") or "Errands")
        header:SetWidth(width())
        header:Show()

        if not collapsed() then
            local index, rowCount, zoneCount = 0, 0, 0
            local function addTaskRow(task, taskZone)
                rowCount = rowCount + 1
                local row = getRow(rowCount)
                row.zone, row.taskID, row.text = taskZone, task.id, task.text
                row.tick:SetChecked(task.done)
                row.label:SetText((task.tracked == true and "|cffffd100> |r" or "") .. task.text
                    .. (task.location and " |cff9d9d9d[pin]|r" or ""))
                if task.done then
                    row.label:SetTextColor(0.5, 0.5, 0.5)
                else
                    row.label:SetTextColor(0.9, 0.9, 0.9)
                end
                local expanded = expandedID == task.id
                row.actions:SetShown(expanded)
                row:SetHeight(expanded and 48 or 24)
                if expanded then
                    local _, position, list = Core.Find(taskZone, task.id)
                    row.track:SetText(task.tracked == true and "Untrack" or "Track")
                    row.track:SetEnabled(not task.done)
                    row.go:SetEnabled(task.location ~= nil)
                    row.pin:SetText(task.location and "Move" or "Pin")
                    row.pin:SetEnabled(taskZone == zone and not task.done)
                    row.up:SetEnabled(position and position > 1 or false)
                    row.down:SetEnabled(position and list and position < #list or false)
                end
                index = index + 1
                place(row, index)
            end
            if zone then
                for _, task in ipairs(getTasks(zone) or {}) do addTaskRow(task, zone) end
            else
                for _, group in ipairs(groups) do
                    zoneCount = zoneCount + 1
                    local zoneRow = getZoneRow(zoneCount)
                    zoneRow.zone = group.zone
                    zoneRow.label:SetText(group.zone .. " (" .. group.count .. ")")
                    index = index + 1
                    place(zoneRow, index)
                    for _, task in ipairs(group.tasks) do
                        if not task.done then addTaskRow(task, group.zone) end
                    end
                end
            end

            message:SetTextColor(INK_R, INK_G, INK_B)
            if placingID then
                message:SetText("Click the map to place the pin.")
                message:Show(); cancel:Show(); entry:Hide(); add:Hide()
            elseif zone then
                message:Hide(); cancel:Hide(); entry:Show(); add:Show()
            else
                message:SetText(pending == 0 and "No unfinished errands. Open a zone to add one."
                    or "Open a zone on the map to add errands.")
                message:Show(); cancel:Hide(); entry:Hide(); add:Hide()
            end
            index = index + 1
            place(footer, index)
        end
        if contents.Layout then contents:Layout() end
        refreshPins()
    end
    section.render = render
    section.toggle = toggleCollapsed
    section.expand = function()
        if collapsed() then toggleCollapsed() else render() end
    end

    if hooksecurefunc and type(_G.QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", render)
    end
    scrollFrame:HookScript("OnShow", render)

    -- Re-render when the map changes zones; this driver only runs while the
    -- map is open and never inspects Blizzard frame text.
    local driver = CreateFrame("Frame", nil, map)
    local elapsed, priorMapID = 0, nil
    driver:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        local id = mapID()
        if id ~= priorMapID then
            priorMapID = id
            expandedID = nil
            render()
        end
    end)
    map:HookScript("OnHide", function()
        placingID, placingZone, placingMapID = nil, nil, nil
        for _, pin in pairs(mapPins) do pin:Hide() end
    end)
    render()
    return true
end

updateAll = function()
    -- The tracker is the only zone-arrival UI; no extra popup is created.
    if trackerRegistered and tracker then tracker:MarkDirty() end
    if questLog then questLog.render() end
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
        if not buildQuestLogSection() and UIParentLoadAddOn then
            -- The world map may be load-on-demand; build once it is loaded.
            pcall(UIParentLoadAddOn, "Blizzard_WorldMap")
            buildQuestLogSection()
        end
        SLASH_WOWERRANDS1 = "/we"
        SLASH_WOWERRANDS2 = "/wowerrands"
        SlashCmdList.WOWERRANDS = function()
            if WorldMapFrame and WorldMapFrame:IsShown() then
                if questLog then questLog.toggle() end
                return
            end
            if questLog then questLog.expand() end
            if OpenQuestLog then
                OpenQuestLog()
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
