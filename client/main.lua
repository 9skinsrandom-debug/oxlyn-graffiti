local QBCore = exports['qb-core']:GetCoreObject()

local sprayProp = nil
local sprayState = {
    active = false,
    currentStroke = {},
    lastPoint = nil,
    lastNormal = nil,
    colorName = nil,
    canPaint = false,
    startedAt = 0,
    lastSyncAt = 0,
    activeChunk = nil,
    renderList = {},
    liveStrokes = {},
    nextRequestAt = 0,
}

local function LogDebug(message)
    if Config.Debug then
        print(string.format("[oxlyn-graffiti] %s", message))
    end
end

local function IsPlayerAlive()
    return not IsEntityDead(PlayerPedId())
end

local function GetPlayerHasItem(itemName)
    if not itemName then return false end

    if QBCore and QBCore.Functions and QBCore.Functions.HasItem then
        local ok, result = pcall(function()
            return QBCore.Functions.HasItem(itemName)
        end)
        if ok and result then
            return true
        end
    end

    if exports and exports['qb-inventory'] and exports['qb-inventory'].HasItem then
        local ok, result = pcall(function()
            return exports['qb-inventory']:HasItem(itemName)
        end)
        if ok and result then
            return true
        end
    end

    if QBCore and QBCore.Functions and QBCore.Functions.GetPlayerData then
        local playerData = QBCore.Functions.GetPlayerData()
        if playerData and playerData.items then
            for _, item in ipairs(playerData.items) do
                if item and item.name == itemName then
                    return true
                end
            end
        end
    end

    return false
end

local function GetEquippedSprayColor()
    for itemName, colorData in pairs(Config.Colors) do
        if GetPlayerHasItem(itemName) then
            return itemName, colorData
        end
    end
    return nil, nil
end

local function GetPlayerChunkCoords()
    local coords = GetEntityCoords(PlayerPedId())
    return GraffitiShared.GetChunkKey(coords, Config.ChunkSize)
end

local function PrepareAnimDict(animDict)
    if not animDict or animDict == "" then return end
    RequestAnimDict(animDict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < timeout do
        Wait(0)
    end
end

local function SpawnSprayProp()
    if sprayProp and DoesEntityExist(sprayProp) then
        return
    end

    local model = `prop_cs_spray_01`
    if not IsModelValid(model) then
        model = `prop_spray_01`
    end

    if not IsModelValid(model) then
        return
    end

    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    local ped = PlayerPedId()
    sprayProp = CreateObject(model, 0.0, 0.0, 0.0, true, false, false)
    AttachEntityToEntity(sprayProp, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.02, 0.0, 252.0, 0.0, 0.0, true, true, false, true, 2, true)
    SetModelAsNoLongerNeeded(model)
end

local function RemoveSprayProp()
    if sprayProp and DoesEntityExist(sprayProp) then
        DeleteEntity(sprayProp)
    end
    sprayProp = nil
end

local function StartSprayAnim()
    PrepareAnimDict('weapons@first_person@aim_rng@w_sp_jerrycan@')
    local ped = PlayerPedId()
    TaskPlayAnim(ped, 'weapons@first_person@aim_rng@w_sp_jerrycan@', 'idle_a', 8.0, -8.0, -1, 49, 0.0, false, false, false)
end

local function CancelSprayAnim()
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
end

local function GetCameraForward()
    local camRot = GetGameplayCamRot(2)
    local x = -math.sin(math.rad(camRot.z)) * math.cos(math.rad(camRot.x))
    local y = math.cos(math.rad(camRot.z)) * math.cos(math.rad(camRot.x))
    local z = math.sin(math.rad(camRot.x))
    return vector3(x, y, z)
end

local function IsSurfaceAllowed(materialHash)
    if not materialHash or materialHash == 0 then
        return true
    end

    local name = tostring(materialHash)
    if Config.DisabledSurfaceTypes and Config.DisabledSurfaceTypes[name] then
        return false
    end

    if Config.AllowedSurfaceTypes then
        for _, allowed in ipairs(Config.AllowedSurfaceTypes) do
            if tostring(allowed) == name then
                return true
            end
        end
    end

    return true
end

local function GetCurrentSurfaceHit()
    local ped = PlayerPedId()
    local camPos = GetFinalRenderedCamCoord()
    local forward = GetCameraForward()
    local target = camPos + (forward * Config.SprayDistance)

    local ray = StartShapeTestLosProbe(camPos.x, camPos.y, camPos.z, target.x, target.y, target.z, 0, ped, 4)
    local hit, endCoords, surfaceNormal, materialHash, entityHit = GetShapeTestResultIncludingMaterial(ray)

    if hit ~= 1 and hit ~= 2 then
        return nil
    end

    if entityHit and entityHit ~= 0 and not IsEntityAPed(entityHit) then
        -- allow world surfaces and static props, but reject certain invalid cases
    end

    if not IsSurfaceAllowed(materialHash) then
        return nil
    end

    local point = vector3(endCoords.x, endCoords.y, endCoords.z)
    local normal = GraffitiShared.NormalizeVector(vector3(surfaceNormal.x, surfaceNormal.y, surfaceNormal.z))
    local distance = GraffitiShared.Distance(camPos, point)

    if distance > Config.MaxPaintDistance then
        return nil
    end

    return {
        point = point - (normal * Config.ClipOffset),
        normal = normal,
        distance = distance,
        material = materialHash,
    }
end

local function OptimizeStroke(points)
    if not points or #points < 2 then
        return points or {}
    end

    local result = {}
    local last = nil

    for i = 1, #points do
        local current = points[i]
        if current then
            if not last then
                result[#result + 1] = current
                last = current
            else
                local distance = GraffitiShared.Distance(vector3(last.x, last.y, last.z), vector3(current.x, current.y, current.z))
                if distance >= Config.LineMinDistance then
                    result[#result + 1] = current
                    last = current
                end
            end
        end
    end

    if #result > Config.MaxStrokePoints then
        local cropped = {}
        for i = 1, Config.MaxStrokePoints do
            cropped[#cropped + 1] = result[i]
        end
        return cropped
    end

    return result
end

local function SendLiveStrokeBatch()
    if not sprayState.active or not sprayState.currentStroke or #sprayState.currentStroke < 2 then
        return
    end

    local now = GetGameTimer()
    if now - sprayState.lastSyncAt < Config.ClientBatchInterval then
        return
    end

    local dense = OptimizeStroke(sprayState.currentStroke)
    local data = {
        color = sprayState.colorName,
        points = dense,
        thickness = Config.LineThickness,
        normal = sprayState.lastNormal or vector3(0.0, 0.0, 1.0),
    }

    TriggerServerEvent('oxlyn-graffiti:server:syncSprayBatch', data)
    sprayState.lastSyncAt = now
end

local function FinishStroke()
    if not sprayState.active then
        return
    end

    sprayState.active = false
    RemoveSprayProp()
    CancelSprayAnim()

    local points = OptimizeStroke(sprayState.currentStroke)
    if not points or #points < 2 then
        sprayState.currentStroke = {}
        sprayState.lastPoint = nil
        sprayState.lastNormal = nil
        sprayState.colorName = nil
        return
    end

    local payload = {
        color = sprayState.colorName,
        points = points,
        thickness = Config.LineThickness,
        normal = sprayState.lastNormal or vector3(0.0, 0.0, 1.0),
        createdAt = os.time(),
    }

    TriggerServerEvent('oxlyn-graffiti:server:saveGraffiti', payload)

    sprayState.currentStroke = {}
    sprayState.lastPoint = nil
    sprayState.lastNormal = nil
    sprayState.colorName = nil
    sprayState.startedAt = 0
    sprayState.lastSyncAt = 0
end

local function BeginStroke()
    if sprayState.active then
        return
    end

    local colorName, colorData = GetEquippedSprayColor()
    if not colorName or not colorData then
        return
    end

    if not IsPlayerAlive() then
        return
    end

    local hit = GetCurrentSurfaceHit()
    if not hit then
        return
    end

    sprayState.active = true
    sprayState.colorName = colorName
    sprayState.currentStroke = {}
    sprayState.lastPoint = hit.point
    sprayState.lastNormal = hit.normal
    sprayState.startedAt = GetGameTimer()
    sprayState.lastSyncAt = 0

    SpawnSprayProp()
    StartSprayAnim()
    LogDebug('Stroke started on ' .. colorName)
end

local function AddStrokePoint()
    if not sprayState.active then
        return
    end

    local hit = GetCurrentSurfaceHit()
    if not hit then
        return
    end

    local point = hit.point
    if sprayState.lastPoint then
        local distance = GraffitiShared.Distance(sprayState.lastPoint, point)
        if distance < Config.LineMinDistance then
            return
        end
    end

    sprayState.lastPoint = point
    sprayState.lastNormal = hit.normal
    sprayState.currentStroke[#sprayState.currentStroke + 1] = {
        x = point.x,
        y = point.y,
        z = point.z,
        nx = hit.normal.x,
        ny = hit.normal.y,
        nz = hit.normal.z,
    }

    if #sprayState.currentStroke > Config.MaxStrokePoints then
        FinishStroke()
        return
    end

    SendLiveStrokeBatch()
end

local function RenderGraffiti()
    if not sprayState.renderList then
        return
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    for _, graffiti in ipairs(sprayState.renderList) do
        if graffiti and graffiti.coords then
            local dist = GraffitiShared.Distance(pedCoords, graffiti.coords)
            if dist <= Config.RenderDistance then
                for _, stroke in ipairs(graffiti.strokes or {}) do
                    if stroke and stroke.points and #stroke.points > 1 then
                        local color = GraffitiShared.GetColorTable(stroke.color or graffiti.color or 'spraycan_black')
                        for i = 2, #stroke.points do
                            local prev = stroke.points[i - 1]
                            local current = stroke.points[i]
                            DrawLine(prev.x, prev.y, prev.z, current.x, current.y, current.z, color.r, color.g, color.b, color.a)
                        end
                    end
                end
            end
        end
    end

    for _, liveStroke in ipairs(sprayState.liveStrokes or {}) do
        if liveStroke and liveStroke.points and #liveStroke.points > 1 then
            local color = GraffitiShared.GetColorTable(liveStroke.color or 'spraycan_black')
            for i = 2, #liveStroke.points do
                local prev = liveStroke.points[i - 1]
                local current = liveStroke.points[i]
                DrawLine(prev.x, prev.y, prev.z, current.x, current.y, current.z, color.r, color.g, color.b, color.a)
            end
        end
    end
end

local function DrawDebugInfo()
    if not Config.Debug then
        return
    end

    local hit = GetCurrentSurfaceHit()
    if hit then
        local point = hit.point
        local normal = hit.normal
        DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.12, 255, 255, 255, 200, false, false, 2, false, false, false, false)
        DrawLine(point.x, point.y, point.z, point.x + (normal.x * 0.35), point.y + (normal.y * 0.35), point.z + (normal.z * 0.35), 255, 0, 0, 255)
    end

    SetTextFont(4)
    SetTextScale(Config.DebugTextScale, Config.DebugTextScale)
    SetTextColour(255, 255, 255, 255)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(string.format('Chunk: %s | Points: %d | Dist: %.2f', sprayState.activeChunk or GetPlayerChunkCoords(), #sprayState.currentStroke or 0, hit and hit.distance or 0.0))
    EndTextCommandDisplayText(0.02, 0.02)
end

local function RequestNearbyChunks()
    local coords = GetEntityCoords(PlayerPedId())
    local chunkKey = GraffitiShared.GetChunkKey(coords, Config.ChunkSize)
    if sprayState.activeChunk == chunkKey then
        return
    end

    sprayState.activeChunk = chunkKey
    TriggerServerEvent('oxlyn-graffiti:server:requestNearby', coords)
end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(500)
    TriggerServerEvent('oxlyn-graffiti:server:requestNearby', GetEntityCoords(PlayerPedId()))
end)

RegisterNetEvent('oxlyn-graffiti:client:syncGraffiti', function(graffitiList)
    if type(graffitiList) ~= 'table' then
        return
    end
    sprayState.renderList = graffitiList
    LogDebug('Synced ' .. tostring(#graffitiList) .. ' graffiti objects')
end)

RegisterNetEvent('oxlyn-graffiti:client:drawLiveStroke', function(data)
    if not data or not data.points or #data.points < 2 then
        return
    end

    sprayState.liveStrokes[#sprayState.liveStrokes + 1] = {
        color = data.color,
        points = data.points,
    }

    if #sprayState.liveStrokes > 4 then
        table.remove(sprayState.liveStrokes, 1)
    end
end)

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        if IsPlayerAlive() and ped and ped ~= 0 then
            RequestNearbyChunks()

            if IsControlPressed(0, 24) then
                if not sprayState.active then
                    BeginStroke()
                else
                    AddStrokePoint()
                end
            elseif sprayState.active then
                FinishStroke()
            end

            if not GetPlayerHasItem('spraycan') and not sprayState.active then
                RemoveSprayProp()
            end
        end

        Wait(0)
    end
end)

CreateThread(function()
    while true do
        RenderGraffiti()
        DrawDebugInfo()
        Wait(0)
    end
end)
