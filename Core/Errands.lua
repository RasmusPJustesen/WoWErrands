-- WoWErrands core data: saved errands, tracking, map pins and waypoints.
-- SavedVariablesPerCharacter is kept unchanged so older lists survive upgrades.
local Core = {}
_G.WoWErrandsCore = Core

local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

function Core.DB()
    if type(WoWErrandsDB) ~= "table" then WoWErrandsDB = {} end
    local store = WoWErrandsDB
    if type(store.zones) ~= "table" then store.zones = {} end
    if type(store.settings) ~= "table" then store.settings = {} end
    if type(store.zoneMapIDs) ~= "table" then store.zoneMapIDs = {} end
    -- Older auto rules are intentionally left untouched in SavedVariables;
    -- automatic completion has been removed, so they are never evaluated.
    if store.schemaVersion ~= 3 then
        local used, biggest = {}, tonumber(store.nextID) or 0
        for _, list in pairs(store.zones) do
            if type(list) == "table" then
                for _, task in ipairs(list) do
                    if type(task) == "table" and type(task.id) == "number" and
                        task.id > 0 and task.id == math.floor(task.id) and not used[task.id] then
                        used[task.id] = true
                        if task.id > biggest then biggest = task.id end
                    elseif type(task) == "table" then
                        task.id = nil
                    end
                end
            end
        end
        for _, list in pairs(store.zones) do
            if type(list) == "table" then
                for _, task in ipairs(list) do
                    if type(task) == "table" then
                        if not task.id then
                            biggest = biggest + 1
                            task.id = biggest
                        end
                        if type(task.text) ~= "string" then task.text = tostring(task.text or "") end
                        task.done = task.done == true
                    end
                end
            end
        end
        store.nextID = biggest
        store.schemaVersion = 3
    end
    return store
end

function Core.Tasks(zone, create)
    if type(zone) ~= "string" or zone == "" or isSecret(zone) then return nil end
    local zones = Core.DB().zones
    if create and not zones[zone] then zones[zone] = {} end
    return zones[zone]
end

function Core.Pending(zone)
    local tasks, count = Core.Tasks(zone), 0
    if tasks then
        for _, task in ipairs(tasks) do
            if type(task) == "table" and not task.done then count = count + 1 end
        end
    end
    return count
end

function Core.Find(zone, id)
    local tasks = Core.Tasks(zone)
    if tasks then
        for index, task in ipairs(tasks) do
            if task.id == id then return task, index, tasks end
        end
    end
    return nil
end

function Core.Add(zone, text)
    if type(text) ~= "string" or isSecret(text) then return nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local tasks = Core.Tasks(zone, true)
    if not tasks then return nil end
    local store = Core.DB()
    store.nextID = (store.nextID or 0) + 1
    local task = { id = store.nextID, text = text, done = false }
    table.insert(tasks, task)
    return task
end

function Core.SetDone(zone, id, done)
    local task = Core.Find(zone, id)
    if task then task.done = done == true; return true end
    return false
end

function Core.Remove(zone, id)
    local _, index, tasks = Core.Find(zone, id)
    if index then table.remove(tasks, index); return true end
    return false
end

function Core.Move(zone, id, delta)
    local _, index, tasks = Core.Find(zone, id)
    if not index then return false end
    local to = index + delta
    if to < 1 or to > #tasks then return false end
    tasks[index], tasks[to] = tasks[to], tasks[index]
    return true
end

-- Map Shift-click tracking. nil means show automatically in the current zone;
-- true persists on the tracker anywhere; false is an explicit manual untrack.
function Core.ToggleTracked(zone, id)
    local task = Core.Find(zone, id)
    if not task or task.done then return false, nil end
    task.tracked = task.tracked ~= true
    return true, task.tracked
end

function Core.TrackerItems(currentZone)
    local list = {}
    local tasks = currentZone and Core.Tasks(currentZone)
    if tasks then
        for _, task in ipairs(tasks) do
            if not task.done and task.tracked ~= false then
                list[#list + 1] = { zone = currentZone, task = task }
            end
        end
    end
    local otherZones = {}
    for zone in pairs(Core.DB().zones) do
        if zone ~= currentZone then otherZones[#otherZones + 1] = zone end
    end
    table.sort(otherZones)
    for _, zone in ipairs(otherZones) do
        for _, task in ipairs(Core.Tasks(zone) or {}) do
            if not task.done and task.tracked == true then
                list[#list + 1] = { zone = zone, task = task }
            end
        end
    end
    return list
end

function Core.SetLocation(zone, id, mapID, x, y)
    local task = Core.Find(zone, id)
    if not task then return false end
    if not (type(mapID) == "number" and type(x) == "number" and type(y) == "number")
        or isSecret(mapID) or isSecret(x) or isSecret(y)
        or x < 0 or x > 1 or y < 0 or y > 1 then return false end
    task.location = { mapID = mapID, x = x, y = y }
    Core.RememberMap(zone, mapID)
    return true
end

function Core.RememberMap(zone, mapID)
    if type(zone) ~= "string" or isSecret(zone) or type(mapID) ~= "number" or isSecret(mapID) then return end
    Core.DB().zoneMapIDs[zone] = mapID
end

-- The names of zones pre-date map IDs in SavedVariables. Resolve those lazily
-- using C_Map's public map hierarchy, and remember successful matches.
local catalog
local function buildCatalog()
    catalog = {}
    if not (C_Map and C_Map.GetMapChildrenInfo) then return end
    for _, root in ipairs({ 947, 1414, 1415 }) do
        local ok, children = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        if ok and type(children) == "table" then
            for _, info in ipairs(children) do
                if type(info.name) == "string" and not isSecret(info.name) and
                    type(info.mapID) == "number" and not isSecret(info.mapID) then
                    if not catalog[info.name] or (info.mapType == 3) then
                        catalog[info.name] = info.mapID
                    end
                end
            end
        end
    end
end

function Core.MapID(zone)
    local store = Core.DB()
    local id = store.zoneMapIDs[zone]
    if id then return id end
    if not catalog then buildCatalog() end
    local resolved = catalog[zone]
    if resolved then store.zoneMapIDs[zone] = resolved end
    return resolved
end

function Core.AllPending()
    local list, total = {}, 0
    for zone, tasks in pairs(Core.DB().zones) do
        local count = 0
        for _, task in ipairs(tasks) do
            if not task.done then count = count + 1 end
        end
        if count > 0 then
            table.insert(list, { zone = zone, count = count, tasks = tasks })
            total = total + count
        end
    end
    table.sort(list, function(a, b) return a.zone < b.zone end)
    return list, total
end

function Core.SetWaypoint(loc)
    if not loc then return false, "This errand has no map pin." end
    if not (C_Map and C_Map.SetUserWaypoint and C_Map.CanSetUserWaypointOnMap) then
        return false, "Waypoints are unavailable in this client."
    end
    if not C_Map.CanSetUserWaypointOnMap(loc.mapID) then
        return false, "The game does not allow waypoints on this map."
    end
    local position
    if CreateVector2D then
        position = CreateVector2D(loc.x, loc.y)
    elseif Vector2D then
        position = Vector2D(loc.x, loc.y)
    end
    if not position then return false, "Map vector API unavailable." end
    local point
    if UiMapPoint and UiMapPoint.CreateFromVector2D then
        point = UiMapPoint.CreateFromVector2D(loc.mapID, position)
    else
        point = { uiMapID = loc.mapID, position = position }
    end
    if C_Map.SetUserWaypoint(point) then return true end
    return false, "Unable to place waypoint."
end

return Core
