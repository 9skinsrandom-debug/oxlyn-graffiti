local QBCore = exports['qb-core']:GetCoreObject()

local GraffitiRuntime = {
    loaded = false,
    byId = {},
    chunkMap = {},
    pending = {},
}

local function LogDebug(message)
    if Config.Debug then
        print(string.format("[oxlyn-graffiti][server] %s", message))
    end
end

local function GetPlayerNameBySource(source)
    local player = QBCore.Functions.GetPlayer(source)
    if player and player.PlayerData and player.PlayerData.charinfo then
        local first = player.PlayerData.charinfo.firstname or ''
        local last = player.PlayerData.charinfo.lastname or ''
        if first ~= '' or last ~= '' then
            return first .. (last ~= '' and ' ' .. last or '')
        end
    end
    return 'Unknown'
end

local function GetChunkKey(coords)
    return GraffitiShared.GetChunkKey(coords, Config.ChunkSize)
end

local function NormalizeChunkMap(paint)
    if not paint or not paint.points or #paint.points < 2 then
        return nil
    end

    local validatedPoints = {}
    for i = 1, #paint.points do
        local point = paint.points[i]
        if type(point) ~= 'table' then
            return nil
        end
        if not GraffitiShared.IsFiniteNumber(point.x) or not GraffitiShared.IsFiniteNumber(point.y) or not GraffitiShared.IsFiniteNumber(point.z) then
            return nil
        end
        validatedPoints[#validatedPoints + 1] = {
            x = point.x,
            y = point.y,
            z = point.z,
            nx = point.nx or 0.0,
            ny = point.ny or 0.0,
            nz = point.nz or 1.0,
        }
    end

    if #validatedPoints > Config.MaxStrokePoints then
        return nil
    end

    return validatedPoints
end

local function ValidateGraffitiPayload(source, payload)
    if not payload or type(payload) ~= 'table' then
        return false, 'invalid payload'
    end

    if not payload.points or #payload.points < 2 then
        return false, 'not enough points'
    end

    local validated = NormalizeChunkMap(payload)
    if not validated then
        return false, 'invalid points'
    end

    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        return false, 'no player'
    end

    local coords = GetEntityCoords(GetPlayerPed(source))
    local avg = GraffitiShared.GetAveragePoint(validated)
    local distance = GraffitiShared.Distance(coords, avg)
    if distance > Config.MaxPaintDistance + 1.0 then
        return false, 'too far from graffiti position'
    end

    local color = payload.color or 'spraycan_black'
    if not Config.Colors[color] then
        return false, 'invalid color'
    end

    local area = 0.0
    for _, point in ipairs(validated) do
        local vector = vector3(point.x, point.y, point.z)
        local delta = GraffitiShared.Distance(vector, avg)
        if delta > area then area = delta end
    end

    if area > Config.MaxGraffitiArea then
        return false, 'graffiti too large'
    end

    local playerCount = 0
    for _, graffiti in pairs(GraffitiRuntime.byId) do
        if graffiti.authorId == source then
            playerCount = playerCount + 1
        end
    end
    if playerCount >= Config.MaxGraffitiPerPlayer then
        return false, 'max graffiti reached'
    end

    return true, validated
end

local function SaveStrokeRows(graffitiId, strokeData)
    local strokeRows = {}
    for index, stroke in ipairs(strokeData) do
        local payload = {
            graffiti_id = graffitiId,
            stroke_index = index,
            points = GraffitiShared.SafeJsonEncode(stroke.points),
            surface_normal = GraffitiShared.SafeJsonEncode(stroke.normal or vector3(0.0, 0.0, 1.0)),
            thickness = stroke.thickness or Config.LineThickness,
            color = stroke.color or 'spraycan_black',
            created_at = os.date('!%Y-%m-%d %H:%M:%S', os.time())
        }
        strokeRows[#strokeRows + 1] = payload
    end
    return strokeRows
end

local function BuildClientGraffitiRecord(source, payload, graffitiId)
    local validated = payload.points
    local avg = GraffitiShared.GetAveragePoint(validated)
    local chunkKey = GetChunkKey(avg)

    local record = {
        id = graffitiId,
        author = GetPlayerNameBySource(source),
        authorId = source,
        coords = avg,
        chunk = chunkKey,
        color = payload.color or 'spraycan_black',
        thickness = payload.thickness or Config.LineThickness,
        strokes = {
            {
                color = payload.color or 'spraycan_black',
                thickness = payload.thickness or Config.LineThickness,
                points = validated,
                normal = payload.normal or vector3(0.0, 0.0, 1.0),
            },
        },
    }

    return record
end

local function LoadExistingGraffiti()
    local query = 'SELECT * FROM ' .. Config.Db.TableName .. ' ORDER BY created_at DESC LIMIT 1200'
    MySQL.query(query, {}, function(result)
        if not result or #result == 0 then
            GraffitiRuntime.loaded = true
            return
        end

        local chunkMap = {}
        for _, row in ipairs(result) do
            local strokes = {}
            local rawStrokeRows = MySQL.query('SELECT * FROM ' .. Config.Db.StrokeTableName .. ' WHERE graffiti_id = ? ORDER BY stroke_index ASC', { row.id }, function(strokesResult)
                if strokesResult then
                    for _, strokeRow in ipairs(strokesResult) do
                        local pts = GraffitiShared.SafeJsonDecode(strokeRow.points)
                        local normal = GraffitiShared.SafeJsonDecode(strokeRow.surface_normal)
                        strokes[#strokes + 1] = {
                            color = strokeRow.color or row.color,
                            thickness = strokeRow.thickness or row.thickness,
                            points = pts,
                            normal = normal,
                        }
                    end
                end
            end)

            local coords = vector3(row.x_pos or row.world_x or 0.0, row.y_pos or row.world_y or 0.0, row.z_pos or row.world_z or 0.0)
            local record = {
                id = row.id,
                author = row.author or 'Unknown',
                authorId = row.author_id or 0,
                coords = coords,
                chunk = row.chunk_key or GetChunkKey(coords),
                color = row.color or 'spraycan_black',
                thickness = row.thickness or Config.LineThickness,
                strokes = strokes,
            }

            GraffitiRuntime.byId[record.id] = record
            local chunkKey = record.chunk
            if not chunkMap[chunkKey] then chunkMap[chunkKey] = {} end
            chunkMap[chunkKey][record.id] = record
        end

        GraffitiRuntime.chunkMap = chunkMap
        GraffitiRuntime.loaded = true
        LogDebug('Loaded ' .. tostring(#result) .. ' graffiti items')
    end)
end

local function NearbyGraffitiForPosition(coords)
    local nearby = {}
    local chunk = GetChunkKey(coords)
    local checked = {
        chunk,
        string.format('%d:%d', math.floor(coords.x / Config.ChunkSize), math.floor(coords.y / Config.ChunkSize) + 1),
        string.format('%d:%d', math.floor(coords.x / Config.ChunkSize), math.floor(coords.y / Config.ChunkSize) - 1),
        string.format('%d:%d', math.floor(coords.x / Config.ChunkSize) + 1, math.floor(coords.y / Config.ChunkSize)),
        string.format('%d:%d', math.floor(coords.x / Config.ChunkSize) - 1, math.floor(coords.y / Config.ChunkSize)),
    }

    for _, key in ipairs(checked) do
        local set = GraffitiRuntime.chunkMap[key]
        if set then
            for _, item in pairs(set) do
                local distance = GraffitiShared.Distance(item.coords, coords)
                if distance <= Config.RenderDistance then
                    nearby[#nearby + 1] = item
                end
            end
        end
    end

    return nearby
end

local function BroadcastNearby(source)
    local coords = GetEntityCoords(GetPlayerPed(source))
    local nearby = NearbyGraffitiForPosition(coords)
    TriggerClientEvent('oxlyn-graffiti:client:syncGraffiti', source, nearby)
end

RegisterNetEvent('oxlyn-graffiti:server:requestNearby', function(sourceCoords)
    local src = source
    if not src then return end
    local coords = sourceCoords or GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('oxlyn-graffiti:client:syncGraffiti', src, NearbyGraffitiForPosition(coords))
end)

RegisterNetEvent('oxlyn-graffiti:server:saveGraffiti', function(payload)
    local src = source
    local valid, result = ValidateGraffitiPayload(src, payload)
    if not valid then
        LogDebug('Reject graffiti save from ' .. tostring(src) .. ': ' .. tostring(result))
        return
    end

    local player = QBCore.Functions.GetPlayer(src)
    local itemName = payload.color or 'spraycan_black'
    if not itemName then
        return
    end

    if player and player.Functions and player.Functions.RemoveItem then
        player.Functions.RemoveItem(itemName, 1)
    end

    local pointSet = result
    local avg = GraffitiShared.GetAveragePoint(pointSet)
    local chunkKey = GetChunkKey(avg)

    local mysqlResult = MySQL.insert(
        'INSERT INTO ' .. Config.Db.TableName .. ' (author, author_id, color, thickness, x_pos, y_pos, z_pos, chunk_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        {
            GetPlayerNameBySource(src),
            src,
            payload.color or 'spraycan_black',
            payload.thickness or Config.LineThickness,
            avg.x,
            avg.y,
            avg.z,
            chunkKey,
            os.date('!%Y-%m-%d %H:%M:%S', os.time())
        }
    )

    if not mysqlResult then
        LogDebug('Failed to insert graffiti into DB for source ' .. tostring(src))
        return
    end

    local graffitiId = mysqlResult
    local strokeGroup = {
        {
            color = payload.color or 'spraycan_black',
            thickness = payload.thickness or Config.LineThickness,
            points = pointSet,
            normal = payload.normal or vector3(0.0, 0.0, 1.0),
        }
    }

    local rows = SaveStrokeRows(graffitiId, strokeGroup)
    for _, row in ipairs(rows) do
        MySQL.insert(
            'INSERT INTO ' .. Config.Db.StrokeTableName .. ' (graffiti_id, stroke_index, points, surface_normal, thickness, color, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
            {
                row.graffiti_id,
                row.stroke_index,
                row.points,
                row.surface_normal,
                row.thickness,
                row.color,
                row.created_at,
            }
        )
    end

    local record = BuildClientGraffitiRecord(src, payload, graffitiId)
    GraffitiRuntime.byId[graffitiId] = record

    if not GraffitiRuntime.chunkMap[chunkKey] then
        GraffitiRuntime.chunkMap[chunkKey] = {}
    end
    GraffitiRuntime.chunkMap[chunkKey][graffitiId] = record

    TriggerClientEvent('oxlyn-graffiti:client:syncGraffiti', -1, NearbyGraffitiForPosition(avg))
    LogDebug('Saved graffiti #' .. tostring(graffitiId) .. ' for source ' .. tostring(src))
end)

RegisterNetEvent('oxlyn-graffiti:server:syncSprayBatch', function(data)
    local src = source
    if not data or not data.points or #data.points < 2 then
        return
    end

    local sanitized = {
        color = data.color or 'spraycan_black',
        points = data.points,
        thickness = data.thickness or Config.LineThickness,
    }

    TriggerClientEvent('oxlyn-graffiti:client:drawLiveStroke', -1, sanitized)
end)

RegisterNetEvent('oxlyn-graffiti:server:removeGraffiti', function(id)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    if not id then return end
    local record = GraffitiRuntime.byId[id]
    if not record then
        return
    end

    if record.authorId ~= src and player.PlayerData.job and player.PlayerData.job.name ~= 'police' then
        return
    end

    MySQL.Async.execute('DELETE FROM ' .. Config.Db.TableName .. ' WHERE id = @id', { ['@id'] = id }, function()
        MySQL.Async.execute('DELETE FROM ' .. Config.Db.StrokeTableName .. ' WHERE graffiti_id = @id', { ['@id'] = id }, function()
            GraffitiRuntime.byId[id] = nil
            local chunkKey = record.chunk
            if GraffitiRuntime.chunkMap[chunkKey] then
                GraffitiRuntime.chunkMap[chunkKey][id] = nil
            end
            TriggerClientEvent('oxlyn-graffiti:client:syncGraffiti', -1, NearbyGraffitiForPosition(record.coords))
        end)
    end)
end)

MySQL.ready(function()
    local tableExists = MySQL.scalar.await('SHOW TABLES LIKE ?', { Config.Db.TableName })
    if not tableExists then
        LogDebug('Database tables not found; resource will initialize on next restart')
    end

    LoadExistingGraffiti()
end)

AddEventHandler('playerJoined', function()
    Wait(1000)
    TriggerClientEvent('oxlyn-graffiti:client:syncGraffiti', source, {})
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    Wait(1000)
    BroadcastNearby(src)
end)

CreateThread(function()
    while not GraffitiRuntime.loaded do
        Wait(250)
    end

    while true do
        Wait(10000)
        -- periodic cleanup and health check
    end
end)
