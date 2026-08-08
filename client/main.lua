local activeIntersections = {}
local currentRequest = nil
local emitterOverride = false
local debugEnabled = Config.Debug.Enabled
local blockedUntil = 0
local lastRequestRefresh = 0
local lastLightPoolRefresh = 0
local nearbyLights = {}
local lightModelHashes = {}
local lastSignalApply = 0
local lastAITraffic = 0

local function nowMs()
    return GetGameTimer()
end

local function normalize2(x, y)
    local length = math.sqrt((x * x) + (y * y))
    if length < 0.001 then
        return 0.0, 0.0
    end
    return x / length, y / length
end

local function dot2(ax, ay, bx, by)
    return (ax * bx) + (ay * by)
end

local function distance2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt((dx * dx) + (dy * dy))
end

local function distance3D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function logDebug(message)
    if Config.Debug.PrintRequests then
        print(('[SignalPreempt] %s'):format(message))
    end
end

local function buildModelHashSet()
    lightModelHashes = {}
    for _, modelName in ipairs(Config.Signals.LightModels) do
        lightModelHashes[GetHashKey(modelName)] = true
    end
end

local function refreshNearbyLights(origin)
    local now = nowMs()
    if now - lastLightPoolRefresh < Config.Performance.LightPoolRefreshMs then
        return
    end

    lastLightPoolRefresh = now
    nearbyLights = {}

    local pool = GetGamePool('CObject')
    for _, object in ipairs(pool) do
        if DoesEntityExist(object) and lightModelHashes[GetEntityModel(object)] then
            local coords = GetEntityCoords(object)
            if distance3D(coords, origin) <= Config.Performance.LightPoolRadius then
                nearbyLights[#nearbyLights + 1] = object
            end
        end
    end
end

local function addLightIfUnique(light, seen)
    if light == 0 or not DoesEntityExist(light) or seen[light] then
        return
    end

    seen[light] = true
    nearbyLights[#nearbyLights + 1] = light
end

local function fallbackProbeTrafficLights(vehicleCoords, fx, fy)
    local seen = {}
    for _, light in ipairs(nearbyLights) do
        seen[light] = true
    end

    local distance = 25.0
    while distance <= Config.Detection.MaxAcquireDistance do
        local sampleX = vehicleCoords.x + (fx * distance)
        local sampleY = vehicleCoords.y + (fy * distance)

        for modelHash in pairs(lightModelHashes) do
            local object = GetClosestObjectOfType(
                sampleX,
                sampleY,
                vehicleCoords.z,
                Config.Detection.MaxLateralOffset + 12.0,
                modelHash,
                false,
                false,
                false
            )
            addLightIfUnique(object, seen)
        end

        distance = distance + 30.0
    end
end

local function isAllowedVehicle(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local model = GetEntityModel(vehicle)
    if Config.Vehicle.DeniedModels[model] then
        return false
    end

    if Config.Vehicle.AllowedModels[model] then
        return true
    end

    if Config.Vehicle.AllowEmergencyClass and GetVehicleClass(vehicle) == 18 then
        return true
    end

    return false
end

local function isQualifiedEmergencyVehicle(ped, vehicle)
    if not Config.Enabled or not isAllowedVehicle(vehicle) then
        return false
    end

    if Config.Activation.RequireDriver and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return false
    end

    if Config.Activation.RequireSiren and not emitterOverride and not IsVehicleSirenOn(vehicle) then
        return false
    end

    return true
end

local function makeIntersectionId(center)
    local grid = Config.Detection.IntersectionIdGrid
    local qx = math.floor((center.x / grid) + 0.5)
    local qy = math.floor((center.y / grid) + 0.5)
    return ('%d:%d'):format(qx, qy)
end

local function findClusterAround(seedObject)
    local seedCoords = GetEntityCoords(seedObject)
    local cluster = {}
    local sumX, sumY, sumZ = 0.0, 0.0, 0.0

    for _, light in ipairs(nearbyLights) do
        if DoesEntityExist(light) then
            local coords = GetEntityCoords(light)
            if distance3D(coords, seedCoords) <= Config.Detection.ClusterRadius then
                cluster[#cluster + 1] = light
                sumX = sumX + coords.x
                sumY = sumY + coords.y
                sumZ = sumZ + coords.z
            end
        end
    end

    if #cluster < Config.Detection.MinSignals then
        return nil
    end

    return {
        lights = cluster,
        center = {
            x = sumX / #cluster,
            y = sumY / #cluster,
            z = sumZ / #cluster,
        },
    }
end

local function detectUpcomingIntersection(vehicle)
    local vehicleCoords = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local fx, fy = normalize2(forward.x, forward.y)
    if fx == 0.0 and fy == 0.0 then
        return nil
    end

    refreshNearbyLights(vehicleCoords)

    local bestLight = nil
    local bestScore = nil

    for _, light in ipairs(nearbyLights) do
        if DoesEntityExist(light) then
            local coords = GetEntityCoords(light)
            local dx = coords.x - vehicleCoords.x
            local dy = coords.y - vehicleCoords.y
            local longitudinal = dot2(dx, dy, fx, fy)

            if longitudinal >= Config.Detection.MinAcquireDistance
                and longitudinal <= Config.Detection.MaxAcquireDistance then

                local lateral = math.abs((dx * fy) - (dy * fx))
                if lateral <= Config.Detection.MaxLateralOffset then
                    local score = longitudinal + (lateral * Config.Detection.LateralPenalty)
                    if not bestScore or score < bestScore then
                        bestScore = score
                        bestLight = light
                    end
                end
            end
        end
    end

    if not bestLight then
        fallbackProbeTrafficLights(vehicleCoords, fx, fy)

        for _, light in ipairs(nearbyLights) do
            if DoesEntityExist(light) then
                local coords = GetEntityCoords(light)
                local dx = coords.x - vehicleCoords.x
                local dy = coords.y - vehicleCoords.y
                local longitudinal = dot2(dx, dy, fx, fy)

                if longitudinal >= Config.Detection.MinAcquireDistance
                    and longitudinal <= Config.Detection.MaxAcquireDistance then

                    local lateral = math.abs((dx * fy) - (dy * fx))
                    if lateral <= Config.Detection.MaxLateralOffset then
                        local score = longitudinal + (lateral * Config.Detection.LateralPenalty)
                        if not bestScore or score < bestScore then
                            bestScore = score
                            bestLight = light
                        end
                    end
                end
            end
        end
    end

    if not bestLight then
        return nil
    end

    local cluster = findClusterAround(bestLight)
    if not cluster then
        return nil
    end

    local centerDx = cluster.center.x - vehicleCoords.x
    local centerDy = cluster.center.y - vehicleCoords.y
    local centerLongitudinal = dot2(centerDx, centerDy, fx, fy)

    if centerLongitudinal < Config.Detection.MinAcquireDistance - 8.0
        or centerLongitudinal > Config.Detection.MaxAcquireDistance + 20.0 then
        return nil
    end

    return {
        id = makeIntersectionId(cluster.center),
        center = cluster.center,
        axis = { x = fx, y = fy },
        lights = cluster.lights,
    }
end

local function releaseCurrentRequest(reason)
    if not currentRequest then
        return
    end

    logDebug(('release %s (%s)'):format(currentRequest.id, reason or 'unknown'))
    TriggerServerEvent('SignalPreempt:server:release', currentRequest.id)
    currentRequest = nil
end

local function requestIntersection(candidate)
    currentRequest = {
        id = candidate.id,
        center = candidate.center,
        axis = candidate.axis,
    }

    lastRequestRefresh = nowMs()
    logDebug(('request %s'):format(candidate.id))
    TriggerServerEvent('SignalPreempt:server:request', candidate.id, candidate.center, candidate.axis)
end

local function refreshCurrentRequest()
    if not currentRequest then
        return
    end

    local now = nowMs()
    if now - lastRequestRefresh < Config.Server.RefreshMs then
        return
    end

    lastRequestRefresh = now
    TriggerServerEvent(
        'SignalPreempt:server:request',
        currentRequest.id,
        currentRequest.center,
        currentRequest.axis
    )
end

local function findLightsForIntersection(intersection)
    local playerPed = PlayerPedId()
    local origin = GetEntityCoords(playerPed)
    refreshNearbyLights(origin)

    local lights = {}
    for _, light in ipairs(nearbyLights) do
        if DoesEntityExist(light) then
            local coords = GetEntityCoords(light)
            if distance3D(coords, intersection.center) <= Config.Detection.ClusterRadius + 4.0 then
                lights[#lights + 1] = light
            end
        end
    end

    return lights
end

local function signalShouldBeGreen(light, intersection)
    local forward = GetEntityForwardVector(light)
    local lx, ly = normalize2(forward.x, forward.y)
    local alignment = math.abs(dot2(lx, ly, intersection.axis.x, intersection.axis.y))
    local parallel = alignment >= Config.Signals.AlignmentThreshold

    if Config.Signals.SignalHeadingParallelToTraffic then
        return parallel
    end

    return not parallel
end

local function applySignalStates()
    local playerCoords = GetEntityCoords(PlayerPedId())

    for _, intersection in pairs(activeIntersections) do
        if distance3D(playerCoords, intersection.center) <= Config.Performance.LightPoolRadius then
            if not intersection.lights or nowMs() - (intersection.lastLightResolve or 0) > 2500 then
                intersection.lights = findLightsForIntersection(intersection)
                intersection.lastLightResolve = nowMs()
            end

            for _, light in ipairs(intersection.lights) do
                if DoesEntityExist(light) then
                    local state
                    if intersection.phase == 'clearance' then
                        state = Config.Signals.RedState
                    elseif signalShouldBeGreen(light, intersection) then
                        state = Config.Signals.GreenState
                    else
                        state = Config.Signals.RedState
                    end

                    SetEntityTrafficlightOverride(light, state)
                    intersection.lastStates = intersection.lastStates or {}
                    intersection.lastStates[light] = state
                end
            end
        end
    end
end

local function recoverAndResetIntersection(intersection)
    local lights = intersection.lights or findLightsForIntersection(intersection)
    local yellowLights = {}

    for _, light in ipairs(lights) do
        if DoesEntityExist(light) then
            local previousState = intersection.lastStates and intersection.lastStates[light]
            if previousState == Config.Signals.GreenState then
                SetEntityTrafficlightOverride(light, Config.Signals.YellowState)
                yellowLights[#yellowLights + 1] = light
            else
                SetEntityTrafficlightOverride(light, Config.Signals.RedState)
            end
        end
    end

    CreateThread(function()
        Wait(Config.Signals.RecoveryYellowMs)

        for _, light in ipairs(lights) do
            if DoesEntityExist(light) then
                local claimedByAnotherIntersection = false

                for _, active in pairs(activeIntersections) do
                    if distance3D(GetEntityCoords(light), active.center) <= Config.Detection.ClusterRadius + 4.0 then
                        claimedByAnotherIntersection = true
                        break
                    end
                end

                if not claimedByAnotherIntersection then
                    SetEntityTrafficlightOverride(light, Config.Signals.ResetState)
                end
            end
        end
    end)
end

local function vehicleHasPlayerOccupant(vehicle)
    if not Config.AITraffic.IgnoreVehiclesWithPlayers then
        return false
    end

    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxPassengers - 1 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant ~= 0 and IsPedAPlayer(occupant) then
            return true
        end
    end

    return false
end

local function shouldControlAIVehicle(vehicle, driver)
    if driver == 0 or not DoesEntityExist(driver) or IsPedAPlayer(driver) then
        return false
    end

    if Config.AITraffic.IgnoreEmergencyVehicles and GetVehicleClass(vehicle) == 18 then
        return false
    end

    if Config.AITraffic.IgnoreMissionEntities and IsEntityAMissionEntity(vehicle) then
        return false
    end

    if vehicleHasPlayerOccupant(vehicle) then
        return false
    end

    if Config.AITraffic.RequireNetworkControl
        and NetworkGetEntityIsNetworked(vehicle)
        and not NetworkHasControlOfEntity(vehicle) then
        return false
    end

    return true
end

local function brakeAIVehicle(driver, vehicle)
    TaskVehicleTempAction(
        driver,
        vehicle,
        Config.AITraffic.BrakeAction,
        Config.AITraffic.BrakeActionMs
    )
end

local function controlAITraffic()
    if not Config.AITraffic.Enabled then
        return
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local vehicles = GetGamePool('CVehicle')

    for _, intersection in pairs(activeIntersections) do
        if distance3D(playerCoords, intersection.center) <= Config.Performance.LightPoolRadius then
            for _, vehicle in ipairs(vehicles) do
                if DoesEntityExist(vehicle) then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local distance = distance2D(vehicleCoords, intersection.center)

                    if distance >= Config.AITraffic.StopMinDistance
                        and distance <= Config.AITraffic.StopMaxDistance then

                        local driver = GetPedInVehicleSeat(vehicle, -1)
                        if shouldControlAIVehicle(vehicle, driver) then
                            local forward = GetEntityForwardVector(vehicle)
                            local vx, vy = normalize2(forward.x, forward.y)
                            local toCenterX = intersection.center.x - vehicleCoords.x
                            local toCenterY = intersection.center.y - vehicleCoords.y
                            local toCenterXn, toCenterYn = normalize2(toCenterX, toCenterY)
                            local approaching = dot2(vx, vy, toCenterXn, toCenterYn)

                            if approaching >= Config.AITraffic.ApproachDotThreshold then
                                local alignment = math.abs(dot2(
                                    vx,
                                    vy,
                                    intersection.axis.x,
                                    intersection.axis.y
                                ))

                                local shouldBrake = intersection.phase == 'clearance'
                                    or alignment < Config.AITraffic.ConflictAlignmentThreshold

                                if shouldBrake then
                                    brakeAIVehicle(driver, vehicle)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function drawText3D(coords, text)
    local visible, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible then
        return
    end

    SetTextScale(0.30, 0.30)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function drawDebug()
    if not debugEnabled then
        return
    end

    for id, intersection in pairs(activeIntersections) do
        if Config.Debug.DrawIntersection then
            DrawMarker(
                28,
                intersection.center.x,
                intersection.center.y,
                intersection.center.z + 0.5,
                0.0, 0.0, 0.0,
                0.0, 0.0, 0.0,
                1.5, 1.5, 1.5,
                255, 255, 255, 180,
                false, false, 2, false, nil, nil, false
            )

            local endX = intersection.center.x + (intersection.axis.x * 18.0)
            local endY = intersection.center.y + (intersection.axis.y * 18.0)
            DrawLine(
                intersection.center.x,
                intersection.center.y,
                intersection.center.z + 1.0,
                endX,
                endY,
                intersection.center.z + 1.0,
                255, 255, 255, 220
            )

            drawText3D(
                {
                    x = intersection.center.x,
                    y = intersection.center.y,
                    z = intersection.center.z + 2.0,
                },
                ('%s | %s'):format(id, intersection.phase)
            )
        end

        if Config.Debug.DrawSignals then
            local lights = intersection.lights or {}
            for _, light in ipairs(lights) do
                if DoesEntityExist(light) then
                    local coords = GetEntityCoords(light)
                    local green = intersection.phase == 'priority' and signalShouldBeGreen(light, intersection)
                    local r, g, b = 255, 50, 50
                    if green then
                        r, g, b = 50, 255, 80
                    end

                    DrawMarker(
                        28,
                        coords.x,
                        coords.y,
                        coords.z + 1.0,
                        0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0,
                        0.45, 0.45, 0.45,
                        r, g, b, 190,
                        false, false, 2, false, nil, nil, false
                    )
                end
            end
        end
    end
end

RegisterNetEvent('SignalPreempt:client:setIntersection', function(data)
    if type(data) ~= 'table' or not data.id then
        return
    end

    local existing = activeIntersections[data.id] or {}
    existing.id = data.id
    existing.center = data.center
    existing.axis = data.axis
    existing.phase = data.phase or 'clearance'
    existing.expiresAt = data.expiresAt
    existing.lastLightResolve = 0
    activeIntersections[data.id] = existing
end)

RegisterNetEvent('SignalPreempt:client:clearIntersection', function(id)
    local intersection = activeIntersections[id]
    if not intersection then
        return
    end

    activeIntersections[id] = nil
    recoverAndResetIntersection(intersection)

    if currentRequest and currentRequest.id == id then
        currentRequest = nil
    end
end)

RegisterNetEvent('SignalPreempt:client:sync', function(intersections)
    if type(intersections) ~= 'table' then
        return
    end

    for _, data in ipairs(intersections) do
        if data.id then
            activeIntersections[data.id] = {
                id = data.id,
                center = data.center,
                axis = data.axis,
                phase = data.phase or 'priority',
                expiresAt = data.expiresAt,
                lastLightResolve = 0,
            }
        end
    end
end)

RegisterNetEvent('SignalPreempt:client:requestDenied', function(id, reason)
    if currentRequest and currentRequest.id == id then
        logDebug(('request denied %s (%s)'):format(id, reason or 'unknown'))
        currentRequest = nil
        blockedUntil = nowMs() + 1200
    end
end)

RegisterNetEvent('SignalPreempt:client:setEmitterEnabled', function(enabled)
    emitterOverride = enabled == true
end)

exports('SetEmitterEnabled', function(enabled)
    emitterOverride = enabled == true
end)

exports('IsPreemptionActive', function()
    return currentRequest ~= nil
end)

exports('GetCurrentIntersection', function()
    if not currentRequest then
        return nil
    end

    return {
        id = currentRequest.id,
        center = currentRequest.center,
        axis = currentRequest.axis,
    }
end)

if Config.Activation.AllowManualEmitter then
    RegisterCommand(Config.Activation.ManualCommand, function()
        emitterOverride = not emitterOverride
        print(('[SignalPreempt] Manual emitter %s'):format(emitterOverride and 'enabled' or 'disabled'))
    end, false)
end

if Config.Debug.AllowCommand then
    RegisterCommand(Config.Debug.Command, function()
        debugEnabled = not debugEnabled
        print(('[SignalPreempt] Debug %s'):format(debugEnabled and 'enabled' or 'disabled'))
    end, false)
end

CreateThread(function()
    buildModelHashSet()
    Wait(1000)
    TriggerServerEvent('SignalPreempt:server:sync')

    while true do
        Wait(Config.Performance.ClientTickMs)

        if not Config.Enabled then
            releaseCurrentRequest('disabled')
        else
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle == 0 or not isQualifiedEmergencyVehicle(ped, vehicle) then
                releaseCurrentRequest('vehicle_not_qualified')
            else
                local vehicleCoords = GetEntityCoords(vehicle)
                local forward = GetEntityForwardVector(vehicle)
                local fx, fy = normalize2(forward.x, forward.y)

                if currentRequest then
                    local dx = currentRequest.center.x - vehicleCoords.x
                    local dy = currentRequest.center.y - vehicleCoords.y
                    local longitudinal = dot2(dx, dy, fx, fy)

                    if longitudinal < -Config.Detection.ReleaseBehindDistance then
                        releaseCurrentRequest('intersection_passed')
                    else
                        refreshCurrentRequest()
                    end
                elseif nowMs() >= blockedUntil then
                    local candidate = detectUpcomingIntersection(vehicle)
                    if candidate then
                        requestIntersection(candidate)
                    end
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Performance.SignalApplyMs)
        if next(activeIntersections) then
            applySignalStates()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Performance.AITrafficMs)
        if next(activeIntersections) then
            controlAITraffic()
        end
    end
end)

CreateThread(function()
    while true do
        if debugEnabled and next(activeIntersections) then
            Wait(0)
            drawDebug()
        else
            Wait(250)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    if currentRequest then
        TriggerServerEvent('SignalPreempt:server:release', currentRequest.id)
    end

    for _, intersection in pairs(activeIntersections) do
        local lights = intersection.lights or {}
        for _, light in ipairs(lights) do
            if DoesEntityExist(light) then
                SetEntityTrafficlightOverride(light, Config.Signals.ResetState)
            end
        end
    end
end)
