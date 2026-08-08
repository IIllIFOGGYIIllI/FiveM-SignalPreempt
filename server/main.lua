local RESOURCE_NAME = GetCurrentResourceName()
local RESOURCE_VERSION = GetResourceMetadata(RESOURCE_NAME, 'version', 0) or 'unknown'

local function printStartupBanner()
    print('^1============================================================^7')
    print(('^3%s^7 | Version ^2v%s^7'):format(RESOURCE_NAME, RESOURCE_VERSION))
    print('^5Emergency Vehicle Traffic Signal Pre-emption^7')
    print('^2Resource started successfully.^7')
    print('^1============================================================^7')
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE_NAME then
        return
    end

    printStartupBanner()
end)

local activeIntersections = {}

local function nowSeconds()
    return os.time()
end

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function validVec2(vec)
    return type(vec) == 'table'
        and isFiniteNumber(vec.x)
        and isFiniteNumber(vec.y)
end

local function validCenter(center)
    return type(center) == 'table'
        and isFiniteNumber(center.x)
        and isFiniteNumber(center.y)
        and isFiniteNumber(center.z)
        and math.abs(center.x) < 20000.0
        and math.abs(center.y) < 20000.0
        and math.abs(center.z) < 5000.0
end

local function normalizeAxis(axis)
    local length = math.sqrt((axis.x * axis.x) + (axis.y * axis.y))
    if length < 0.001 then
        return nil
    end

    return {
        x = axis.x / length,
        y = axis.y / length,
    }
end

local function requesterCount(requesters)
    local count = 0
    for _ in pairs(requesters) do
        count = count + 1
    end
    return count
end

local function broadcastState(intersection)
    TriggerClientEvent('SignalPreempt:client:setIntersection', -1, {
        id = intersection.id,
        center = intersection.center,
        axis = intersection.axis,
        phase = intersection.phase,
        expiresAt = intersection.expiresAt,
    })
end

local function clearIntersection(id, reason)
    local intersection = activeIntersections[id]
    if not intersection then
        return
    end

    activeIntersections[id] = nil
    TriggerClientEvent('SignalPreempt:client:clearIntersection', -1, id, reason or 'released')
end

local function validateSourceDistance(src, center)
    if not Config.Server.MaxRequestDistance or Config.Server.MaxRequestDistance <= 0.0 then
        return true
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        -- Do not hard-fail servers where the player ped is temporarily unavailable.
        return true
    end

    local coords = GetEntityCoords(ped)
    local dx = coords.x - center.x
    local dy = coords.y - center.y
    local dz = coords.z - center.z
    local distance = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

    return distance <= Config.Server.MaxRequestDistance
end

local function hasPermission(src)
    if not Config.Server.RequireAce then
        return true
    end

    return IsPlayerAceAllowed(src, Config.Server.AcePermission)
end

RegisterNetEvent('SignalPreempt:server:request', function(id, center, axis)
    local src = source

    if not Config.Enabled or not hasPermission(src) then
        return
    end

    if type(id) ~= 'string' or #id < 3 or #id > 64 then
        return
    end

    if not validCenter(center) or not validVec2(axis) then
        return
    end

    if not validateSourceDistance(src, center) then
        return
    end

    local normalizedAxis = normalizeAxis(axis)
    if not normalizedAxis then
        return
    end

    local now = nowSeconds()
    local intersection = activeIntersections[id]

    if intersection and intersection.expiresAt <= now then
        clearIntersection(id, 'expired')
        intersection = nil
    end

    if intersection then
        local alignment = math.abs(
            (intersection.axis.x * normalizedAxis.x)
            + (intersection.axis.y * normalizedAxis.y)
        )

        if alignment < Config.Server.SameRoadAlignmentThreshold then
            TriggerClientEvent('SignalPreempt:client:requestDenied', src, id, 'conflicting_approach')
            return
        end

        intersection.requesters[tostring(src)] = true
        intersection.expiresAt = now + Config.Server.LeaseSeconds
        return
    end

    intersection = {
        id = id,
        center = {
            x = center.x,
            y = center.y,
            z = center.z,
        },
        axis = normalizedAxis,
        phase = 'clearance',
        expiresAt = now + Config.Server.LeaseSeconds,
        requesters = {
            [tostring(src)] = true,
        },
        generation = math.random(1, 2147483646),
    }

    activeIntersections[id] = intersection
    broadcastState(intersection)

    local generation = intersection.generation
    SetTimeout(Config.Signals.ClearanceMs, function()
        local current = activeIntersections[id]
        if not current or current.generation ~= generation then
            return
        end

        current.phase = 'priority'
        broadcastState(current)
    end)
end)

RegisterNetEvent('SignalPreempt:server:release', function(id)
    local src = source
    local intersection = activeIntersections[id]
    if not intersection then
        return
    end

    intersection.requesters[tostring(src)] = nil

    if requesterCount(intersection.requesters) == 0 then
        clearIntersection(id, 'released')
    end
end)

RegisterNetEvent('SignalPreempt:server:sync', function()
    local src = source
    local now = nowSeconds()
    local payload = {}

    for id, intersection in pairs(activeIntersections) do
        if intersection.expiresAt > now then
            payload[#payload + 1] = {
                id = id,
                center = intersection.center,
                axis = intersection.axis,
                phase = intersection.phase,
                expiresAt = intersection.expiresAt,
            }
        else
            activeIntersections[id] = nil
        end
    end

    TriggerClientEvent('SignalPreempt:client:sync', src, payload)
end)

AddEventHandler('playerDropped', function()
    local srcKey = tostring(source)
    local toClear = {}

    for id, intersection in pairs(activeIntersections) do
        intersection.requesters[srcKey] = nil
        if requesterCount(intersection.requesters) == 0 then
            toClear[#toClear + 1] = id
        end
    end

    for _, id in ipairs(toClear) do
        clearIntersection(id, 'requester_disconnected')
    end
end)

CreateThread(function()
    while true do
        Wait(1000)

        local now = nowSeconds()
        local expired = {}

        for id, intersection in pairs(activeIntersections) do
            if intersection.expiresAt <= now then
                expired[#expired + 1] = id
            end
        end

        for _, id in ipairs(expired) do
            clearIntersection(id, 'lease_expired')
        end
    end
end)
