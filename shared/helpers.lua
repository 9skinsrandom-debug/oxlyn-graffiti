GraffitiShared = GraffitiShared or {}

local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function GraffitiShared.GetChunkKey(coords, chunkSize)
    local size = chunkSize or Config.ChunkSize or 80.0
    return string.format("%d:%d", math.floor(coords.x / size), math.floor(coords.y / size))
end

function GraffitiShared.GetChunkCoords(coords, chunkSize)
    local size = chunkSize or Config.ChunkSize or 80.0
    return {
        x = math.floor(coords.x / size),
        y = math.floor(coords.y / size),
    }
end

function GraffitiShared.Distance(a, b)
    if not a or not b then return 999999.0 end
    return math.sqrt(((a.x - b.x) ^ 2) + ((a.y - b.y) ^ 2) + ((a.z - b.z) ^ 2))
end

function GraffitiShared.GetAveragePoint(points)
    if not points or #points == 0 then
        return vector3(0.0, 0.0, 0.0)
    end

    local total = vector3(0.0, 0.0, 0.0)
    for i = 1, #points do
        total = total + vector3(points[i].x, points[i].y, points[i].z)
    end

    return total / #points
end

function GraffitiShared.NormalizeVector(vec)
    if not vec then return vector3(0.0, 0.0, 1.0) end
    local len = math.sqrt((vec.x ^ 2) + (vec.y ^ 2) + (vec.z ^ 2))
    if len < 0.0001 then
        return vector3(0.0, 0.0, 1.0)
    end
    return vector3(vec.x / len, vec.y / len, vec.z / len)
end

function GraffitiShared.IsFiniteVec(vec)
    if type(vec) ~= "vector3" then return false end
    return math.abs(vec.x) < 100000 and math.abs(vec.y) < 100000 and math.abs(vec.z) < 100000
end

function GraffitiShared.IsFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function GraffitiShared.Clamp(value, min, max)
    return clamp(value, min, max)
end

function GraffitiShared.GetColorTable(colorName)
    if not colorName or not Config.Colors[colorName] then
        return Config.Colors.spraycan_black
    end
    return Config.Colors[colorName]
end

function GraffitiShared.InterpolatePoints(points, step)
    if not points or #points < 2 then
        return points or {}
    end

    local interp = {}
    for i = 1, #points do
        if points[i] then
            interp[#interp + 1] = { x = points[i].x, y = points[i].y, z = points[i].z }
        end
    end

    if #interp < 2 then
        return interp
    end

    local final = {}
    final[#final + 1] = interp[1]

    for i = 2, #interp do
        local a = interp[i - 1]
        local b = interp[i]
        local delta = vector3(b.x - a.x, b.y - a.y, b.z - a.z)
        local distance = math.sqrt((delta.x ^ 2) + (delta.y ^ 2) + (delta.z ^ 2))

        if distance > 0.0001 then
            local amount = math.max(1, math.ceil(distance / (step or Config.InterpolationStep)))
            for s = 1, amount do
                local t = s / amount
                local nextPoint = {
                    x = a.x + ((b.x - a.x) * t),
                    y = a.y + ((b.y - a.y) * t),
                    z = a.z + ((b.z - a.z) * t),
                }
                local last = final[#final]
                if not last or GraffitiShared.Distance(vector3(last.x, last.y, last.z), vector3(nextPoint.x, nextPoint.y, nextPoint.z)) > (Config.LineMinDistance * 0.9) then
                    final[#final + 1] = nextPoint
                end
            end
        end
    end

    if #final < 2 then
        final[#final + 1] = interp[#interp]
    end

    return final
end

function GraffitiShared.MakePoint(x, y, z, normalX, normalY, normalZ)
    return {
        x = x,
        y = y,
        z = z,
        nx = normalX or 0.0,
        ny = normalY or 0.0,
        nz = normalZ or 1.0,
    }
end

function GraffitiShared.SafeJsonEncode(data)
    local ok, encoded = pcall(json.encode, data)
    if ok then
        return encoded
    end
    return "{}"
end

function GraffitiShared.SafeJsonDecode(str)
    if type(str) ~= "string" then return {} end
    local ok, decoded = pcall(json.decode, str)
    if ok then
        return decoded
    end
    return {}
end

function GraffitiShared.ChunkArray(coords, chunkSize)
    local key = GraffitiShared.GetChunkKey(coords, chunkSize)
    return key
end
