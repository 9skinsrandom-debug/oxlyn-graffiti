local QBCore = exports['qb-core']:GetCoreObject()

local GraffitiState = {
    loaded = false,
    byId = {},
    byChunk = {},
}

local function logDebug(message)
    if Config.Debug then
        print(string.format('[oxlyn-graffiti][server] %s', message))
    end
end

local function getPlayerName(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        return 'Unknown'
    end

    local charinfo = player.PlayerData and player.PlayerData.charinfo or {}
    local firstname = charinfo.firstname or ''
    local lastname = charinfo.lastname or ''
    if firstname ~= '' or lastname ~= '' then
        return firstname .. (lastname ~= '' and ' ' .. lastname or '')
    end

    return tostring(source)
end

local function ensureTablesExist()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `oxlyn_graffiti` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `author` VARCHAR(96) NOT NULL DEFAULT 'Unknown',
            `author_id` INT NOT NULL DEFAULT 0,
            `color` VARCHAR(32) NOT NULL DEFAULT 'spraycan_black',
            `thickness` FLOAT NOT NULL DEFAULT 0.12,
            `x_pos` FLOAT NOT NULL DEFAULT 0,
            `y_pos` FLOAT NOT NULL DEFAULT 0,
            `z_pos` FLOAT NOT NULL DEFAULT 0,
            `chunk_key` VARCHAR(64) NOT NULL DEFAULT '0:0',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_chunk` (`chunk_key`),
            KEY `idx_author` (`author_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function() end)

    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `oxlyn_graffiti_strokes` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `graffiti_id` INT NOT NULL,
            `stroke_index` INT NOT NULL DEFAULT 0,
            `points` LONGTEXT NOT NULL,
            `surface_normal` LONGTEXT NOT NULL,
            `thickness` FLOAT NOT NULL DEFAULT 0.12,
            `color` VARCHAR(32) NOT NULL DEFAULT 'spraycan_black',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_graffiti` (`graffiti_id`),
            CONSTRAINT `fk_graffiti_strokes` FOREIGN KEY (`graffiti_id`) REFERENCES `oxlyn_graffiti` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {}, function() end)
end

local function chunkKey(coords)
    return GraffitiShared.GetChunkKey(coords, Config.ChunkSize)
end

local function validatePayload(source, payload)
    if not payload or type(payload) ~= 'table' then
        return false, 'invalid payload'
    end

    if not payload.points or type(payload.points) ~= 'table' or #payload.points < 2 then
        return false, 'not enough spray points'
    end

    if #payload.points > Config.MaxStrokePoints then
        return false, 'stroke too large'
    end

    local colorName = payload.color or 'spraycan_black'
    if not Config.Colors[colorName] then
        return false, 'invalid color'
    end

    local player = QBCore.Functions.GetPlayer(source)
    if not player then
        return false, 'player not found'
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then
        return false, 'ped invalid'
    end

    local coords = GetEntityCoords(ped)
    local avg = GraffitiShared.GetAveragePoint(payload.points)
    local dist = GraffitiShared.Distance(coords, avg)
    if dist > Config.MaxPaintDistance + 1.5 then
        return false, 'too far from wall'
    end

    local maxRadius = 0.0
    for _, point in ipairs(payload.points) do
        local d = GraffitiShared.Distance(avg, vector3(point.x, point.y, point.z))
        if d > maxRadius then
            maxRadius = d
        end
    end

    if maxRadius > Config.MaxGraffitiArea then
        return false, 'graffiti exceeds max area'
    end

    local currentCount = 0
    for _, item in pairs(GraffitiState.byId) do
        if item.authorId == source then
            currentCount = currentCount + 1
        end
    end

    if currentCount >= Config.MaxGraffitiPerPlayer then
        return false, 'player reached graffiti limit'
    end

    return true, payload.points
end

local function saveStrokeRows(graffitiId, strokeData)
    local rows = {}
    for idx, stroke in ipairs(strokeData) do
        rows[#rows + 1] = {
            graffiti_id = graffitiId,
            stroke_index = idx,
            points = GraffitiShared.SafeEncode(stroke.points),
            surface_normal = GraffitiShared.SafeEncode(stroke.normal or vector3(0.0, 0.0, 1.0)),
            thickness = stroke.thickness or Config.LineThickness,
            color = stroke.color or 'spraycan_black',
            created_at = os.date('!%Y-%m-%d %H:%M:%S', os.time()),
        }
    end
    return rows
end

local function buildRecord(source, payload, graffitiId)
    local avg = GraffitiShared.GetAveragePoint(payload.points)
    return {
        id = graffitiId,
        author = getPlayerName(source),
        authorId = source,
        coords = avg,
        chunk = GraffitiShared.GetChunkKey(avg, Config.ChunkSize),
        color = payload.color or 'spraycan_black',
        thickness = payload.thickness or Config.LineThickness,
        strokes = {
            {
                color = payload.color or 'spraycan_black',
                thickness = payload.thickness or Config.LineThickness,
                points = payload.points,
                normal = payload.normal or vector3(0.0, 0.0, 1.0),
            }
        },
    }
end

local function loadExistingGraffiti()
    MySQL.query('SELECT * FROM ' .. Config.Db.TableName .. ' ORDER BY created_at DESC LIMIT 1500', {}, function(result)
        if not result or #result == 0 then
            GraffitiState.loaded = true
            return
        end

        local processed = 0
        for _, row in ipairs(result) do
            local x, y, z = row.x_pos or 0.0, row.y_pos or 0.0, row.z_pos or 0.0
            local record = {
                id = row.id,
                author = row.author or 'Unknown',
                authorId = row.author_id or 0,
                coords = vector3(x, y, z),
                chunk = row.chunk_key or GraffitiShared.GetChunkKey(vector3(x, y, z), Config.ChunkSize),
                color = row.color or 'spraycan_black',
                thickness = row.thickness or Config.LineThickness,
                strokes = {},
            }

            GraffitiState.byId[row.id] = record

            if not GraffitiState.byChunk[record.chunk] then
                GraffitiState.byChunk[record.chunk] = {}
            end
            GraffitiState.byChunk[record.chunk][row.id] = record

            processed = processed + 1
        end

        local pending = 0
        for _, row in ipairs(result) do
            pending = pending + 1
            MySQL.query('SELECT * FROM ' .. Config.Db.StrokeTableName .. ' WHERE graffiti_id = ? ORDER BY stroke_index ASC', { row.id }, function(strokeRows)
                if strokeRows then
                    local record = GraffitiState.byId[row.id]
                    if record then
                        for _, strokeRow in ipairs(strokeRows) do
                            record.strokes[#record.strokes + 1] = {
                                color = strokeRow.color or record.color,
                                thickness = strokeRow.thickness or record.thickness,
                                points = GraffitiShared.SafeDecode(strokeRow.points),
                                normal = GraffitiShared.SafeDecode(strokeRow.surface_normal),
                            }
                        end
                    end
                end

                pending = pending - 1
                if pending <= 0 then
                    GraffitiState.loaded = true
                    logDebug('Loaded graffiti: ' .. tostring(processed))
                end
            end)
        end
    end)
end

local function getNearby(coords)
    local list = {}
    local cx = math.floor(coords.x / Config.ChunkSize)
    local cy = math.floor(coords.y / Config.ChunkSize)
    local offsets = {
        {0, 0}, {1, 0}, {-1, 0}, {0, 1}, {0, -1},
        {1, 1}, {-1, 1}, {1, -1}, {-1, -1},
    }

    for _, off in ipairs(offsets) do
        local key = string.format('%d:%d', cx + off[1], cy + off[2])
        local group = GraffitiState.byChunk[key]
        if group then
            for _, item in pairs(group) do
                local d = GraffitiShared.Distance(item.coords, coords)
                if d <= Config.RenderDistance then
                    list[#list + 1] = item
                end
            end
        end
    end

    return list
end

local function pushNearbyToClient(src, coords)
    TriggerClientEvent('oxlyn-graffiti:client:syncNearby', src, getNearby(coords))
end

RegisterNetEvent('oxlyn-graffiti:server:requestNearby', function(requestCoords)
    local src = source
    if not src then return end
    local coords = requestCoords or GetEntityCoords(GetPlayerPed(src))
    pushNearbyToClient(src, coords)
end)

RegisterNetEvent('oxlyn-graffiti:server:saveGraffiti', function(payload)
    local src = source
    local valid, result = validatePayload(src, payload)
    if not valid then
        logDebug('Rejected from ' .. tostring(src) .. ': ' .. tostring(result))
        return
    end

    local avg = GraffitiShared.GetAveragePoint(payload.points)
    local chunk = GraffitiShared.GetChunkKey(avg, Config.ChunkSize)
    local colorName = payload.color or 'spraycan_black'

    MySQL.insert('INSERT INTO ' .. Config.Db.TableName .. ' (author, author_id, color, thickness, x_pos, y_pos, z_pos, chunk_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        getPlayerName(src),
        src,
        colorName,
        payload.thickness or Config.LineThickness,
        avg.x,
        avg.y,
        avg.z,
        chunk,
        os.date('!%Y-%m-%d %H:%M:%S', os.time())
    }, function(insertId)
        if not insertId then
            logDebug('Failed to insert graffiti for source ' .. tostring(src))
            return
        end

        local strokeData = {
            {
                color = colorName,
                thickness = payload.thickness or Config.LineThickness,
                points = payload.points,
                normal = payload.normal or vector3(0.0, 0.0, 1.0),
            }
        }

        local rows = saveStrokeRows(insertId, strokeData)
        for _, row in ipairs(rows) do
            MySQL.insert('INSERT INTO ' .. Config.Db.StrokeTableName .. ' (graffiti_id, stroke_index, points, surface_normal, thickness, color, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)', {
                row.graffiti_id,
                row.stroke_index,
                row.points,
                row.surface_normal,
                row.thickness,
                row.color,
                row.created_at,
            }, function() end)
        end

        local record = buildRecord(src, payload, insertId)
        GraffitiState.byId[insertId] = record
        if not GraffitiState.byChunk[chunk] then
            GraffitiState.byChunk[chunk] = {}
        end
        GraffitiState.byChunk[chunk][insertId] = record

        TriggerClientEvent('oxlyn-graffiti:client:syncNearby', -1, getNearby(avg))
        logDebug('Saved graffiti #' .. tostring(insertId) .. ' for ' .. tostring(src))
    end)
end)

RegisterNetEvent('oxlyn-graffiti:server:removeGraffiti', function(id)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    local record = GraffitiState.byId[id]
    if not record then return end
    if record.authorId ~= src then
        return
    end

    MySQL.query('DELETE FROM ' .. Config.Db.TableName .. ' WHERE id = ?', { id }, function()
        MySQL.query('DELETE FROM ' .. Config.Db.StrokeTableName .. ' WHERE graffiti_id = ?', { id }, function()
            GraffitiState.byId[id] = nil
            if GraffitiState.byChunk[record.chunk] then
                GraffitiState.byChunk[record.chunk][id] = nil
            end
            TriggerClientEvent('oxlyn-graffiti:client:syncNearby', -1, getNearby(record.coords))
        end)
    end)
end)

for _, itemName in ipairs(Config.Items.ColorItems) do
    QBCore.Functions.CreateUseableItem(itemName, function(source)
        TriggerClientEvent('oxlyn-graffiti:client:useSprayCan', source, itemName)
    end)
end

QBCore.Functions.CreateUseableItem(Config.Items.SprayCan, function(source)
    TriggerClientEvent('oxlyn-graffiti:client:useSprayCan', source, 'spraycan_black')
end)

QBCore.Functions.CreateUseableItem(Config.Items.GraffitiRemover, function(source)
    TriggerClientEvent('oxlyn-graffiti:client:prepareRemoval', source)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    Wait(200)
    pushNearbyToClient(src, GetEntityCoords(GetPlayerPed(src)))
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    ensureTablesExist()
    loadExistingGraffiti()
end)

CreateThread(function()
    ensureTablesExist()
    Wait(500)
    loadExistingGraffiti()
end)
