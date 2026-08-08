local activeIntersections = {}
local currentRequest = nil
local emitterOverride = false
local debugEnabled = Config.Debug.Enabled
local blockedUntil = 0
local lastRequestRefresh = 0
local lastLightPoolRefresh = 0
local nearbyLights = {}
local detectionLightModelHashes = {}
local overrideLightModelHashes = {}
local noOverrideLightModelHashes = {}
local lightModelNames = {}
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


local function hasFlag(value, flag)
    return type(value) == 'number' and (value & flag) ~= 0
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

local function addNamedModel(set, modelName)
    local hash = GetHashKey(modelName)
    set[hash] = true
    lightModelNames[hash] = modelName
end

local function buildModelHashSet()
    detectionLightModelHashes = {}
    overrideLightModelHashes = {}
    noOverrideLightModelHashes = {}
    lightModelNames = {}

    for _, modelName in ipairs(Config.Signals.DetectionModels or {}) do
        addNamedModel(detectionLightModelHashes, modelName)
    end

    for _, modelName in ipairs(Config.Signals.OverrideModels or {}) do
        addNamedModel(overrideLightModelHashes, modelName)
        detectionLightModelHashes[GetHashKey(modelName)] = true
    end

    for _, modelName in ipairs(Config.Signals.NoOverrideModels or {}) do
        addNamedModel(noOverrideLightModelHashes, modelName)
    end
end

local function applyTrafficLightState(object, state)
    if object == 0 or not DoesEntityExist(object) then
        return
    end

    SetEntityTrafficlightOverride(object, state)

    if Config.Signals.SuppressEntityLightSpots then
        -- The override native controls the traffic-signal emissive state, while
        -- SET_ENTITY_LIGHTS controls the prop's auxiliary light spots/coronas.
        -- Suppressing those spots prevents the low-mounted 'ghost' green/amber
        -- glow visible on some pole assemblies during a forced state.
        SetEntityLights(object, state == Config.Signals.ResetState)
    end
end

local function resetAllLoadedTrafficLights()
    local resetCount = 0

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local model = GetEntityModel(object)
            if detectionLightModelHashes[model]
                or overrideLightModelHashes[model]
                or noOverrideLightModelHashes[model] then
                applyTrafficLightState(object, Config.Signals.ResetState)
                SetEntityLights(object, true)
                resetCount = resetCount + 1
            end
        end
    end

    return resetCount
end

local function resetNoOverrideTrafficLights(center, radius)
    if not next(noOverrideLightModelHashes) then
        return
    end

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) and noOverrideLightModelHashes[GetEntityModel(object)] then
            if not center or distance3D(GetEntityCoords(object), center) <= radius then
                applyTrafficLightState(object, Config.Signals.ResetState)
            end
        end
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
        if DoesEntityExist(object) and detectionLightModelHashes[GetEntityModel(object)] then
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

        for modelHash in pairs(detectionLightModelHashes) do
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

local function getClosestVehicleNodePosition(x, y, z)
    local ok, found, nodePos = pcall(
        GetClosestVehicleNode,
        x,
        y,
        z,
        Config.Detection.NodeSearchType or 1,
        Config.Detection.NodeSearchParam or 3.0,
        0.0
    )

    if ok and found and nodePos and nodePos.x and nodePos.y and nodePos.z then
        return {
            x = nodePos.x,
            y = nodePos.y,
            z = nodePos.z,
        }
    end

    return nil
end

local function requestApproachPathNodes(vehicleCoords, fx, fy)
    if not Config.Detection.RequestPathNodesAhead then
        return
    end

    local requestDistance = Config.Detection.MaxAcquireDistance
        + (Config.Detection.PathRequestExtraDistance or 0.0)
    local padding = Config.Detection.PathRequestPadding or 40.0
    local endX = vehicleCoords.x + (fx * requestDistance)
    local endY = vehicleCoords.y + (fy * requestDistance)

    local minX = math.min(vehicleCoords.x, endX) - padding
    local minY = math.min(vehicleCoords.y, endY) - padding
    local maxX = math.max(vehicleCoords.x, endX) + padding
    local maxY = math.max(vehicleCoords.y, endY) + padding

    -- REQUEST_PATH_NODES_IN_AREA_THIS_FRAME is the current native name. The older
    -- FiveM alias is retained as a fallback so the resource remains tolerant of
    -- artifact/native naming differences.
    if RequestPathNodesInAreaThisFrame then
        pcall(RequestPathNodesInAreaThisFrame, minX, minY, maxX, maxY)
    elseif RequestPathsPreferAccurateBoundingstruct then
        pcall(RequestPathsPreferAccurateBoundingstruct, minX, minY, maxX, maxY)
    end
end

local function detectTrafficLightNodeAhead(vehicleCoords, fx, fy)
    if not Config.Detection.UseTrafficLightNodes then
        return nil
    end

    requestApproachPathNodes(vehicleCoords, fx, fy)

    local probeDistance = math.max(
        Config.Detection.MinAcquireDistance,
        Config.Detection.NodeProbeStartDistance or Config.Detection.MinAcquireDistance
    )
    local probeStep = math.max(4.0, Config.Detection.NodeProbeStep or 8.0)
    local trafficLightFlag = Config.Detection.TrafficLightNodeFlag or 256
    local lateralOffsets = Config.Detection.NodeLateralOffsets or { 0.0 }

    -- Right-hand vector relative to the emergency vehicle's direction of travel.
    local rx, ry = -fy, fx

    while probeDistance <= Config.Detection.MaxAcquireDistance do
        for _, lateralOffset in ipairs(lateralOffsets) do
            local sampleX = vehicleCoords.x + (fx * probeDistance) + (rx * lateralOffset)
            local sampleY = vehicleCoords.y + (fy * probeDistance) + (ry * lateralOffset)

            local ok, valid, _, flags = pcall(
                GetVehicleNodeProperties,
                sampleX,
                sampleY,
                vehicleCoords.z
            )

            if ok and valid and hasFlag(flags, trafficLightFlag) then
                local node = getClosestVehicleNodePosition(sampleX, sampleY, vehicleCoords.z)

                -- GetVehicleNodeProperties can succeed slightly before an exact node
                -- position is available. In that case the probe point itself is a
                -- better provisional stop-line estimate than throwing the detection away.
                local nodeX = node and node.x or sampleX
                local nodeY = node and node.y or sampleY
                local nodeZ = node and node.z or vehicleCoords.z

                local dx = nodeX - vehicleCoords.x
                local dy = nodeY - vehicleCoords.y
                local longitudinal = dot2(dx, dy, fx, fy)
                local lateral = math.abs((dx * fy) - (dy * fx))

                if longitudinal >= Config.Detection.MinAcquireDistance
                    and longitudinal <= Config.Detection.MaxAcquireDistance + probeStep
                    and lateral <= Config.Detection.MaxLateralOffset then

                    local centerOffset = Config.Detection.NodeCenterForwardOffset or 0.0
                    local center = {
                        x = nodeX + (fx * centerOffset),
                        y = nodeY + (fy * centerOffset),
                        z = nodeZ,
                    }

                    return {
                        id = makeIntersectionId(center),
                        center = center,
                        axis = { x = fx, y = fy },
                        lights = {},
                        source = node and 'traffic_light_node' or 'traffic_light_probe',
                    }
                end
            end
        end

        probeDistance = probeDistance + probeStep
    end

    return nil
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
        local nodeCandidate = detectTrafficLightNodeAhead(vehicleCoords, fx, fy)
        if nodeCandidate then
            return nodeCandidate
        end

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
        if DoesEntityExist(light) and overrideLightModelHashes[GetEntityModel(light)] then
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
            -- Keep integrated pedestrian/crosswalk assemblies under GTA control.
            -- This prevents the low pole-mounted ghost green/amber coronas produced
            -- when the entire 03a/03b object is forced as a vehicle traffic light.
            resetNoOverrideTrafficLights(
                intersection.center,
                Config.Detection.ClusterRadius + 6.0
            )

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

                    applyTrafficLightState(light, state)
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
                applyTrafficLightState(light, Config.Signals.YellowState)
                yellowLights[#yellowLights + 1] = light
            else
                applyTrafficLightState(light, Config.Signals.RedState)
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
                    applyTrafficLightState(light, Config.Signals.ResetState)
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

local function drawText3D(coords, text, r, g, b, a)
    local visible, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible then
        return
    end

    SetTextScale(0.28, 0.28)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextColour(r or 255, g or 255, b or 255, a or 230)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(sx, sy)
end

local function getTrafficLightDebugPoint(light)
    local coords = GetEntityCoords(light)
    local ok, minDim, maxDim = pcall(GetModelDimensions, GetEntityModel(light))

    if ok and minDim and maxDim and maxDim.z then
        local top = GetOffsetFromEntityInWorldCoords(light, 0.0, 0.0, maxDim.z + 0.35)
        if top and top.x then
            return top
        end
    end

    return {
        x = coords.x,
        y = coords.y,
        z = coords.z + 5.5,
    }
end

local function drawDebug()
    if not debugEnabled then
        return
    end

    for id, intersection in pairs(activeIntersections) do
        if Config.Debug.DrawIntersection then
            local z = intersection.center.z + 0.35
            local crossSize = 2.5

            DrawLine(
                intersection.center.x - crossSize,
                intersection.center.y,
                z,
                intersection.center.x + crossSize,
                intersection.center.y,
                z,
                255, 255, 255, 210
            )
            DrawLine(
                intersection.center.x,
                intersection.center.y - crossSize,
                z,
                intersection.center.x,
                intersection.center.y + crossSize,
                z,
                255, 255, 255, 210
            )

            local endX = intersection.center.x + (intersection.axis.x * 18.0)
            local endY = intersection.center.y + (intersection.axis.y * 18.0)
            DrawLine(
                intersection.center.x,
                intersection.center.y,
                z + 0.35,
                endX,
                endY,
                z + 0.35,
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
                    local green = intersection.phase == 'priority' and signalShouldBeGreen(light, intersection)
                    local modelName = lightModelNames[GetEntityModel(light)] or 'traffic'
                    local suffix = modelName:match('prop_traffic_(.+)') or modelName
                    local label = (green and '[G]' or '[R]') .. ' ' .. suffix
                    local r, g, b = green and 70 or 255, green and 255 or 80, green and 90 or 80
                    local debugPoint = getTrafficLightDebugPoint(light)
                    drawText3D(debugPoint, label, r, g, b, 235)
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

RegisterCommand('spcleanup', function()
    local count = resetAllLoadedTrafficLights()
    print(('[SignalPreempt] Reset %d loaded traffic-light objects.'):format(count))
end, false)

-- Keep the approach road nodes requested every frame while an eligible emergency
-- vehicle is active. GTA's path-node request native is explicitly frame-scoped.
CreateThread(function()
    while true do
        if Config.Enabled and Config.Detection.RequestPathNodesAhead then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if vehicle ~= 0 and isQualifiedEmergencyVehicle(ped, vehicle) then
                local coords = GetEntityCoords(vehicle)
                local forward = GetEntityForwardVector(vehicle)
                local fx, fy = normalize2(forward.x, forward.y)

                if fx ~= 0.0 or fy ~= 0.0 then
                    requestApproachPathNodes(coords, fx, fy)
                end

                Wait(0)
            else
                Wait(200)
            end
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    buildModelHashSet()
    resetAllLoadedTrafficLights()
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
                applyTrafficLightState(light, Config.Signals.ResetState)
            end
        end
    end
end)
