GraffitiShared = GraffitiShared or {}

function GraffitiShared.Distance(a, b)
    if not a or not b then
        return 999999.0
    end
    return math.sqrt(((a.x - b.x) ^ 2) + ((a.y - b.y) ^ 2) + ((a.z - b.z) ^ 2))
end

function GraffitiShared.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function GraffitiShared.NormalizeVector(vec)
    if not vec then
        return vector3(0.0, 0.0, 1.0)
    end

    local len = math.sqrt((vec.x ^ 2) + (vec.y ^ 2) + (vec.z ^ 2))
    if len < 0.0001 then
        return vector3(0.0, 0.0, 1.0)
    end

    return vector3(vec.x / len, vec.y / len, vec.z / len)
end

function GraffitiShared.GetAveragePoint(points)
    if not points or #points == 0 then
        return vector3(0.0, 0.0, 0.0)
    end

    local totalX, totalY, totalZ = 0.0, 0.0, 0.0
    for _, point in ipairs(points) do
        totalX = totalX + point.x
        totalY = totalY + point.y
        totalZ = totalZ + point.z
    end

    return vector3(totalX / #points, totalY / #points, totalZ / #points)
end

function GraffitiShared.GetChunkKey(coords, chunkSize)
    local size = chunkSize or Config.ChunkSize
    if not coords then
        return '0:0'
    end
    return string.format('%d:%d', math.floor(coords.x / size), math.floor(coords.y / size))
end

function GraffitiShared.InterpolatePoints(points, step)
    if not points or #points < 2 then
        return points or {}
    end

    local output = {}
    output[#output + 1] = { x = points[1].x, y = points[1].y, z = points[1].z }

    for i = 2, #points do
        local prev = points[i - 1]
        local curr = points[i]
        local delta = vector3(curr.x - prev.x, curr.y - prev.y, curr.z - prev.z)
        local dist = math.sqrt((delta.x ^ 2) + (delta.y ^ 2) + (delta.z ^ 2))

        if dist > 0.001 then
            local segments = math.max(1, math.ceil(dist / (step or Config.InterpolationStep)))
            for s = 1, segments do
                local t = s / segments
                local newPoint = {
                    x = prev.x + ((curr.x - prev.x) * t),
                    y = prev.y + ((curr.y - prev.y) * t),
                    z = prev.z + ((curr.z - prev.z) * t),
                }
                local last = output[#output]
                if not last then
                    output[#output + 1] = newPoint
                else
                    local d = GraffitiShared.Distance(vector3(last.x, last.y, last.z), vector3(newPoint.x, newPoint.y, newPoint.z))
                    if d >= Config.MinPointDistance * 0.75 then
                        output[#output + 1] = newPoint
                    end
                end
            end
        end
    end

    if #output > Config.MaxStrokePoints then
        local trimmed = {}
        for i = 1, Config.MaxStrokePoints do
            trimmed[#trimmed + 1] = output[i]
        end
        return trimmed
    end

    return output
end

function GraffitiShared.SafeDecode(jsonString)
    if type(jsonString) ~= 'string' or jsonString == '' then
        return {}
    end

    local ok, data = pcall(function()
        return json.decode(jsonString)
    end)

    if ok then
        return data
    end

    return {}
end

function GraffitiShared.SafeEncode(data)
    local ok, encoded = pcall(function()
        return json.encode(data)
    end)

    if ok then
        return encoded
    end

    return '{}'
end

function GraffitiShared.HitPointAllowed(surfaceName)
    if not surfaceName then
        return true
    end

    for _, disabled in ipairs(Config.DisabledSurfaceTypes or {}) do
        if disabled == surfaceName then
            return false
        end
    end

    if Config.AllowedSurfaceTypes then
        for _, allowed in ipairs(Config.AllowedSurfaceTypes) do
            if allowed == surfaceName then
                return true
            end
        end
    end

    return true
end
