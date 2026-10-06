local QBCore = exports['qb-core']:GetCoreObject()

local state = {
    active = false,
    colorName = nil,
    stroke = {},
    lastPoint = nil,
    lastNormal = nil,
    prop = nil,
    nearby = {},
    lastRequestAt = 0,
    lastPaintAt = 0,
    lastSyncAt = 0,
    lastChunkKey = nil,
}

local function logDebug(message)
    if Config.Debug then
        print(string.format('[oxlyn-graffiti] %s', message))
    end
end

local function playerHasAnySprayCan()
    local list = { Config.Items.SprayCan }
    for _, itemName in ipairs(Config.Items.ColorItems) do
        list[#list + 1] = itemName
    end

    for _, itemName in ipairs(list) do
        if QBCore.Functions.HasItem(itemName) then
            return true
        end
    end

    return false
end

local function getEquippedColor()
    if QBCore.Functions.HasItem(Config.Items.SprayCan) then
        return 'spraycan_black', true
    end

    for _, itemName in ipairs(Config.Items.ColorItems) do
        if QBCore.Functions.HasItem(itemName) then
            return itemName, true
        end
    end

    return nil, false
end

local function requestAnimDict(dict)
    if not dict or dict == '' then
        return
    end

    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
        Wait(0)
    end
end

local function attachSprayProp()
    if state.prop and DoesEntityExist(state.prop) then
        return
    end

    local ped = PlayerPedId()
    local model = Config.SprayPropModel
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    state.prop = CreateObject(model, 0.0, 0.0, 0.0, true, false, false)
    AttachEntityToEntity(state.prop, ped, GetPedBoneIndex(ped, 57005), 0.10, 0.01, 0.0, 250.0, 0.0, 0.0, true, true, false, true, 2, true)
    SetModelAsNoLongerNeeded(model)
end

local function detachSprayProp()
    if state.prop and DoesEntityExist(state.prop) then
        DeleteEntity(state.prop)
    end
    state.prop = nil
end

local function startSprayAnim()
    requestAnimDict('weapons@first_person@aim_rng@w_sp_jerrycan@')
    TaskPlayAnim(PlayerPedId(), 'weapons@first_person@aim_rng@w_sp_jerrycan@', 'idle_a', 8.0, -8.0, -1, 49, 0.0, false, false, false)
end

local function stopSprayAnim()
    ClearPedTasksImmediately(PlayerPedId())
end

local function getCameraForwardVector()
    local rot = GetGameplayCamRot(2)
    local x = -math.sin(math.rad(rot.z)) * math.cos(math.rad(rot.x))
    local y = math.cos(math.rad(rot.z)) * math.cos(math.rad(rot.x))
    local z = math.sin(math.rad(rot.x))
    return vector3(x, y, z)
end

local function doRaycast()
    local ped = PlayerPedId()
    local camPos = GetFinalRenderedCamCoord()
    local forward = getCameraForwardVector()
    local target = camPos + (forward * Config.SprayDistance)

    local ray = StartShapeTestLosProbe(camPos.x, camPos.y, camPos.z, target.x, target.y, target.z, 16, ped, 4)
    local hit, endCoords, surfaceNormal, materialHash, entityHit = GetShapeTestResultIncludingMaterial(ray)

    if hit ~= 1 and hit ~= 2 then
        return nil
    end

    if not endCoords or not surfaceNormal then
        return nil
    end

    local normal = GraffitiShared.NormalizeVector(vector3(surfaceNormal.x, surfaceNormal.y, surfaceNormal.z))
    local point = vector3(endCoords.x, endCoords.y, endCoords.z) - (normal * Config.ClipOffset)
    local distance = GraffitiShared.Distance(camPos, point)

    if distance > Config.MaxPaintDistance then
        return nil
    end

    return {
        point = point,
        normal = normal,
        distance = distance,
        materialHash = materialHash,
        entityHit = entityHit,
    }
end

local function finishStroke()
    if not state.active then
        return
    end

    local polished = GraffitiShared.InterpolatePoints(state.stroke, Config.InterpolationStep)
    if #polished < 2 then
        state.active = false
        state.stroke = {}
        state.lastPoint = nil
        state.lastNormal = nil
        state.colorName = nil
        detachSprayProp()
        stopSprayAnim()
        return
    end

    TriggerServerEvent('oxlyn-graffiti:server:saveGraffiti', {
        color = state.colorName,
        points = polished,
        thickness = Config.LineThickness,
        normal = state.lastNormal or vector3(0.0, 0.0, 1.0),
    })

    state.active = false
    state.stroke = {}
    state.lastPoint = nil
    state.lastNormal = nil
    state.colorName = nil
    detachSprayProp()
    stopSprayAnim()
end

local function beginStroke()
    if state.active then
        return
    end

    if not playerHasAnySprayCan() then
        return
    end

    local colorName, hasColor = getEquippedColor()
    if not hasColor then
        return
    end

    local hit = doRaycast()
    if not hit then
        return
    end

    state.active = true
    state.colorName = colorName
    state.stroke = {}
    state.lastPoint = hit.point
    state.lastNormal = hit.normal

    state.stroke[#state.stroke + 1] = {
        x = hit.point.x,
        y = hit.point.y,
        z = hit.point.z,
        nx = hit.normal.x,
        ny = hit.normal.y,
        nz = hit.normal.z,
    }

    attachSprayProp()
    startSprayAnim()
    logDebug('started painting with ' .. tostring(colorName))
end

local function addPaintPoint()
    if not state.active then
        return
    end

    local hit = doRaycast()
    if not hit then
        return
    end

    if state.lastPoint then
        local distance = GraffitiShared.Distance(state.lastPoint, hit.point)
        if distance < Config.MinPointDistance then
            return
        end
    end

    state.lastPoint = hit.point
    state.lastNormal = hit.normal

    state.stroke[#state.stroke + 1] = {
        x = hit.point.x,
        y = hit.point.y,
        z = hit.point.z,
        nx = hit.normal.x,
        ny = hit.normal.y,
        nz = hit.normal.z,
    }

    if #state.stroke >= Config.MaxStrokePoints then
        finishStroke()
    end
end

local function renderNearbyPaint()
    local pedCoords = GetEntityCoords(PlayerPedId())
    for _, item in ipairs(state.nearby or {}) do
        if item and item.coords then
            local dist = GraffitiShared.Distance(item.coords, pedCoords)
            if dist <= Config.RenderDistance then
                for _, stroke in ipairs(item.strokes or {}) do
                    if stroke and stroke.points and #stroke.points > 1 then
                        local color = Config.Colors[stroke.color] or Config.Colors.spraycan_black
                        for i = 2, #stroke.points do
                            local prev = stroke.points[i - 1]
                            local curr = stroke.points[i]
                            DrawLine(prev.x, prev.y, prev.z, curr.x, curr.y, curr.z, color.r, color.g, color.b, color.a)
                        end
                    end
                end
            end
        end
    end
end

local function drawDebugGeometry()
    if not Config.Debug then
        return
    end

    local hit = doRaycast()
    if hit then
        DrawMarker(28, hit.point.x, hit.point.y, hit.point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.12, 255, 255, 255, 200, false, false, 2, false, false, false, false)
        DrawLine(hit.point.x, hit.point.y, hit.point.z, hit.point.x + (hit.normal.x * 0.35), hit.point.y + (hit.normal.y * 0.35), hit.point.z + (hit.normal.z * 0.35), 255, 0, 0, 255)
    end

    SetTextFont(4)
    SetTextScale(Config.DebugTextScale, Config.DebugTextScale)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    local chunk = GraffitiShared.GetChunkKey(GetEntityCoords(PlayerPedId()), Config.ChunkSize)
    AddTextComponentSubstringPlayerName(string.format('Chunk: %s | Points: %d | Distance: %.2f', chunk, #state.stroke, hit and hit.distance or 0.0))
    EndTextCommandDisplayText(0.02, 0.03)
end

local function requestNearbyPaint()
    local now = GetGameTimer()
    if now - state.lastRequestAt < 1200 then
        return
    end

    state.lastRequestAt = now
    local coords = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('oxlyn-graffiti:server:requestNearby', coords)
end

RegisterNetEvent('oxlyn-graffiti:client:syncNearby', function(graffiti)
    if type(graffiti) ~= 'table' then
        return
    end
    state.nearby = graffiti
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(750)
    requestNearbyPaint()
end)

RegisterNetEvent('oxlyn-graffiti:client:useSprayCan', function(colorName)
    if not colorName then
        return
    end
    state.colorName = colorName
end)

CreateThread(function()
    while true do
        requestNearbyPaint()

        if IsControlPressed(0, 24) and not IsPauseMenuActive() then
            if not state.active then
                beginStroke()
            else
                addPaintPoint()
            end
        elseif state.active and not IsControlPressed(0, 24) then
            finishStroke()
        end

        renderNearbyPaint()
        drawDebugGeometry()

        Wait(0)
    end
end)
