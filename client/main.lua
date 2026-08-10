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
local appliedSignalStates = {}
local refreshOverrideModelHashes = {}
local lastForcedSignalRefresh = {}
local configuredModelSwaps = {}
local modelSwapsApplied = false
local stubborn01dFallbacks = {}
local guaranteedHousingEntities = {}

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
    refreshOverrideModelHashes = {}
    lightModelNames = {}

    for _, modelName in ipairs(Config.Signals.DetectionModels or {}) do
        addNamedModel(detectionLightModelHashes, modelName)
    end

    for _, modelName in ipairs(Config.Signals.OverrideModels or {}) do
        addNamedModel(overrideLightModelHashes, modelName)
        detectionLightModelHashes[GetHashKey(modelName)] = true
    end

    for _, modelName in ipairs(Config.Signals.RefreshOverrideModels or {}) do
        addNamedModel(refreshOverrideModelHashes, modelName)
    end

    for _, modelName in ipairs(Config.Signals.NoOverrideModels or {}) do
        addNamedModel(noOverrideLightModelHashes, modelName)
    end

    configuredModelSwaps = {}
    for sourceName, replacementName in pairs(Config.Signals.WorldModelSwaps or {}) do
        if type(sourceName) == 'string' and type(replacementName) == 'string' then
            local sourceHash = GetHashKey(sourceName)
            local replacementHash = GetHashKey(replacementName)
            configuredModelSwaps[#configuredModelSwaps + 1] = {
                sourceName = sourceName,
                sourceHash = sourceHash,
                replacementName = replacementName,
                replacementHash = replacementHash,
            }
            lightModelNames[sourceHash] = sourceName
            lightModelNames[replacementHash] = replacementName
        end
    end
end

local function requestConfiguredSwapModels()
    local requested = {}

    local fallbackHash = GetHashKey('prop_traffic_01b')
    RequestModel(fallbackHash)
    requested[fallbackHash] = true

    for _, swap in ipairs(configuredModelSwaps) do
        if not requested[swap.replacementHash] then
            RequestModel(swap.replacementHash)
            requested[swap.replacementHash] = true
        end
    end

    if not next(requested) then
        return true
    end

    local started = nowMs()
    local timeout = 2500

    while nowMs() - started < timeout do
        local loaded = true
        for modelHash in pairs(requested) do
            if not HasModelLoaded(modelHash) then
                RequestModel(modelHash)
                loaded = false
            end
        end

        if loaded then
            return true
        end

        Wait(0)
    end

    return false
end

local function applyConfiguredModelSwaps()
    if modelSwapsApplied then
        return 0
    end

    local zones = Config.Signals.ModelSwapZones or {}
    local count = 0

    for _, swap in ipairs(configuredModelSwaps) do
        for _, zone in ipairs(zones) do
            CreateModelSwap(
                tonumber(zone.x) or 0.0,
                tonumber(zone.y) or 0.0,
                tonumber(zone.z) or 0.0,
                tonumber(zone.radius) or 12000.0,
                swap.sourceHash,
                swap.replacementHash,
                zone.lazy == true
            )
            count = count + 1
        end
    end

    modelSwapsApplied = count > 0
    return count
end

local function removeConfiguredModelSwaps()
    if not modelSwapsApplied then
        return 0
    end

    local zones = Config.Signals.ModelSwapZones or {}
    local count = 0

    for _, swap in ipairs(configuredModelSwaps) do
        for _, zone in ipairs(zones) do
            RemoveModelSwap(
                tonumber(zone.x) or 0.0,
                tonumber(zone.y) or 0.0,
                tonumber(zone.z) or 0.0,
                tonumber(zone.radius) or 12000.0,
                swap.sourceHash,
                swap.replacementHash,
                zone.lazy == true
            )
            count = count + 1
        end
    end

    modelSwapsApplied = false
    return count
end

local function stubborn01dKey(coords)
    local q = Config.Signals.Stubborn01dQuantize or 0.5
    local function quantize(value)
        return math.floor((value / q) + 0.5) * q
    end

    return ('%.1f:%.1f:%.1f'):format(
        quantize(coords.x),
        quantize(coords.y),
        quantize(coords.z)
    )
end

local function getGuaranteedHousingForSource(sourceObject)
    if sourceObject == 0 or not DoesEntityExist(sourceObject) then
        return 0
    end

    if GetEntityModel(sourceObject) ~= GetHashKey('prop_traffic_01d') then
        return 0
    end

    local record = stubborn01dFallbacks[stubborn01dKey(GetEntityCoords(sourceObject))]
    if record and record.housingObject ~= 0 and DoesEntityExist(record.housingObject) then
        return record.housingObject
    end

    return 0
end

local function removeGuaranteedHousingHide(record)
    if not record or not record.hideRegistered then
        return
    end

    RemoveModelHide(
        record.coords.x,
        record.coords.y,
        record.coords.z,
        Config.Signals.Stubborn01dHideRadius or 2.25,
        GetHashKey('prop_traffic_01d'),
        true
    )
    record.hideRegistered = false
end

local function createGuaranteedHousing(record)
    if not record then
        return 0
    end

    local replacementHash = GetHashKey('prop_traffic_01b')
    if not HasModelLoaded(replacementHash) then
        RequestModel(replacementHash)
        return 0
    end

    local housing = CreateObjectNoOffset(
        replacementHash,
        record.coords.x,
        record.coords.y,
        record.coords.z,
        false,
        false,
        false
    )

    if housing == 0 or not DoesEntityExist(housing) then
        return 0
    end

    -- Treat the replacement as persistent world geometry for the client session.
    SetEntityAsMissionEntity(housing, true, true)
    SetEntityRotation(
        housing,
        record.rotation.x,
        record.rotation.y,
        record.rotation.z,
        2,
        true
    )
    FreezeEntityPosition(housing, true)
    SetEntityCollision(housing, true, true)
    SetEntityVisible(housing, true, false)
    SetEntityAlpha(housing, 255, false)
    SetEntityLodDist(housing, Config.Signals.Stubborn01dProxyLodDistance or 1000)

    record.housingObject = housing
    guaranteedHousingEntities[housing] = true

    -- Put the clean housing under normal GTA traffic-light control until a live
    -- SignalPreempt intersection claims it.
    SetEntityTrafficlightOverride(housing, Config.Signals.ResetState)

    return housing
end

local function ensureGuaranteed01dHousing(sourceObject)
    if sourceObject == 0 or not DoesEntityExist(sourceObject) then
        return 0
    end

    if GetEntityModel(sourceObject) ~= GetHashKey('prop_traffic_01d') then
        return 0
    end

    local coords = GetEntityCoords(sourceObject)
    local key = stubborn01dKey(coords)
    local record = stubborn01dFallbacks[key]

    if not record then
        local rotation = GetEntityRotation(sourceObject, 2)
        record = {
            key = key,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            rotation = { x = rotation.x, y = rotation.y, z = rotation.z },
            sourceObject = sourceObject,
            housingObject = 0,
            hideRegistered = false,
        }
        stubborn01dFallbacks[key] = record
    else
        record.sourceObject = sourceObject
        local rotation = GetEntityRotation(sourceObject, 2)
        record.rotation = { x = rotation.x, y = rotation.y, z = rotation.z }
    end

    -- Safety invariant: NEVER hide the original before a verified clean housing exists.
    if record.housingObject == 0 or not DoesEntityExist(record.housingObject) then
        removeGuaranteedHousingHide(record)

        if record.housingObject ~= 0 then
            guaranteedHousingEntities[record.housingObject] = nil
            record.housingObject = 0
        end

        local housing = createGuaranteedHousing(record)
        if housing == 0 then
            return 0
        end
    end

    -- Only now that the full replacement housing is alive do we suppress the source map
    -- model. This removes the original traffic-light drawable/corona without creating
    -- a period where there is no physical signal housing.
    if not record.hideRegistered then
        CreateModelHide(
            record.coords.x,
            record.coords.y,
            record.coords.z,
            Config.Signals.Stubborn01dHideRadius or 2.25,
            GetHashKey('prop_traffic_01d'),
            true
        )
        record.hideRegistered = true
    end

    return record.housingObject
end

local function maintainStubborn01dFallbacks()
    if Config.Signals.Stubborn01dFallback ~= true then
        return
    end

    local sourceHash = GetHashKey('prop_traffic_01d')
    local replacementHash = GetHashKey('prop_traffic_01b')

    if not HasModelLoaded(replacementHash) then
        RequestModel(replacementHash)
    end

    -- Discover every source 01d that enters the stream.
    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object)
            and not guaranteedHousingEntities[object]
            and GetEntityModel(object) == sourceHash then
            ensureGuaranteed01dHousing(object)
        end
    end

    -- Guarantee the replacement remains a real, visible housing for the whole session.
    for _, record in pairs(stubborn01dFallbacks) do
        if record.housingObject == 0 or not DoesEntityExist(record.housingObject) then
            -- Reveal the original BEFORE rebuilding. This is what prevents missing
            -- housings / standalone lamp orbs if GTA ever removes the local object.
            removeGuaranteedHousingHide(record)

            if record.housingObject ~= 0 then
                guaranteedHousingEntities[record.housingObject] = nil
                record.housingObject = 0
            end

            if HasModelLoaded(replacementHash) then
                local housing = createGuaranteedHousing(record)
                if housing ~= 0 and not record.hideRegistered then
                    CreateModelHide(
                        record.coords.x,
                        record.coords.y,
                        record.coords.z,
                        Config.Signals.Stubborn01dHideRadius or 2.25,
                        sourceHash,
                        true
                    )
                    record.hideRegistered = true
                end
            end
        else
            SetEntityVisible(record.housingObject, true, false)
            SetEntityAlpha(record.housingObject, 255, false)
            FreezeEntityPosition(record.housingObject, true)
            SetEntityLodDist(
                record.housingObject,
                Config.Signals.Stubborn01dProxyLodDistance or 1000
            )
        end
    end
end

local function restoreAllStubborn01dFallbacks()
    for _, record in pairs(stubborn01dFallbacks) do
        removeGuaranteedHousingHide(record)

        if record.housingObject ~= 0 and DoesEntityExist(record.housingObject) then
            guaranteedHousingEntities[record.housingObject] = nil
            SetEntityAsMissionEntity(record.housingObject, true, true)
            DeleteEntity(record.housingObject)
        end
    end

    stubborn01dFallbacks = {}
    guaranteedHousingEntities = {}
end

local function applyTrafficLightState(object, state, force)
    if object == 0 or not DoesEntityExist(object) then
        return false
    end

    -- The override persists until it is changed/reset. Re-applying it every few hundred
    -- milliseconds is unnecessary and can repeatedly retrigger rendering state on the
    -- traffic-light archetype. Only touch an entity when its desired state actually
    -- changes (or when cleanup explicitly forces a reset).
    if not force and appliedSignalStates[object] == state then
        return false
    end

    SetEntityTrafficlightOverride(object, state)

    if state == Config.Signals.ResetState then
        appliedSignalStates[object] = nil
        lastForcedSignalRefresh[object] = nil
    else
        appliedSignalStates[object] = state
    end

    return true
end

local function resetAllLoadedTrafficLights()
    local resetCount = 0

    -- Proxy sources such as prop_traffic_01d are intentionally NOT touched here.
    -- Even a direct override on that model is what causes the low ghost lamp.
    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local model = GetEntityModel(object)
            if overrideLightModelHashes[model] then
                applyTrafficLightState(object, Config.Signals.ResetState, true)
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
                applyTrafficLightState(object, Config.Signals.ResetState, true)
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
    local seen = {}

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object)
            and detectionLightModelHashes[GetEntityModel(object)] then

            local effectiveObject = object

            if GetEntityModel(object) == GetHashKey('prop_traffic_01d') then
                local housing = getGuaranteedHousingForSource(object)
                if housing ~= 0 then
                    effectiveObject = housing
                end
            end

            if effectiveObject ~= 0
                and DoesEntityExist(effectiveObject)
                and not seen[effectiveObject] then
                local coords = GetEntityCoords(effectiveObject)
                if distance3D(coords, origin) <= Config.Performance.LightPoolRadius then
                    seen[effectiveObject] = true
                    nearbyLights[#nearbyLights + 1] = effectiveObject
                end
            end
        end
    end
end

local function addLightIfUnique(light, seen)
    if light == 0 or not DoesEntityExist(light) then
        return
    end

    if GetEntityModel(light) == GetHashKey('prop_traffic_01d') then
        local housing = getGuaranteedHousingForSource(light)
        if housing ~= 0 then
            light = housing
        end
    end

    if seen[light] then
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

local function calculateClusterGeometry(lights)
    if not lights or #lights == 0 then
        return nil
    end

    local sumX, sumY, sumZ = 0.0, 0.0, 0.0
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

    for _, light in ipairs(lights) do
        if not DoesEntityExist(light) then
            return nil
        end

        local coords = GetEntityCoords(light)
        sumX = sumX + coords.x
        sumY = sumY + coords.y
        sumZ = sumZ + coords.z

        minX = math.min(minX, coords.x)
        minY = math.min(minY, coords.y)
        minZ = math.min(minZ, coords.z)
        maxX = math.max(maxX, coords.x)
        maxY = math.max(maxY, coords.y)
        maxZ = math.max(maxZ, coords.z)
    end

    local center = {
        x = sumX / #lights,
        y = sumY / #lights,
        z = sumZ / #lights,
    }

    local maxDistance = 0.0
    local farthestIndex = nil

    for index, light in ipairs(lights) do
        local coords = GetEntityCoords(light)
        local distance = distance3D(coords, center)
        if distance > maxDistance then
            maxDistance = distance
            farthestIndex = index
        end
    end

    return {
        center = center,
        maxDistance = maxDistance,
        farthestIndex = farthestIndex,
        spanX = maxX - minX,
        spanY = maxY - minY,
        spanZ = maxZ - minZ,
    }
end

local function findCanonicalClusterAroundCenter(rawCenter)
    if not Config.Detection.CanonicalizeIntersections then
        return nil
    end

    local searchRadius = Config.Detection.CanonicalSearchRadius or 48.0
    local selected = {}

    for _, light in ipairs(nearbyLights) do
        if DoesEntityExist(light) then
            local coords = GetEntityCoords(light)
            if distance3D(coords, rawCenter) <= searchRadius then
                selected[#selected + 1] = light
            end
        end
    end

    if #selected < Config.Detection.MinSignals then
        return nil
    end

    -- A nearby real intersection can occasionally contribute one outlying light.
    -- Iteratively remove the geometric outlier until the remaining set fits within
    -- the configured physical-junction envelope.
    while #selected >= Config.Detection.MinSignals do
        local geometry = calculateClusterGeometry(selected)
        if not geometry then
            return nil
        end

        local withinRadius = geometry.maxDistance
            <= (Config.Detection.CanonicalMaxSignalRadius or 34.0)
        local withinSpan = geometry.spanX <= (Config.Detection.CanonicalMaxSpan or 64.0)
            and geometry.spanY <= (Config.Detection.CanonicalMaxSpan or 64.0)
        local withinVertical = geometry.spanZ
            <= (Config.Detection.CanonicalMaxVerticalSpan or 12.0)

        if withinRadius and withinSpan and withinVertical then
            return {
                lights = selected,
                center = geometry.center,
            }
        end

        if not geometry.farthestIndex or #selected <= Config.Detection.MinSignals then
            break
        end

        table.remove(selected, geometry.farthestIndex)
    end

    return nil
end

local function canonicalizeCandidate(candidate)
    if not candidate or not candidate.center then
        return candidate
    end

    local rawCenter = {
        x = candidate.center.x,
        y = candidate.center.y,
        z = candidate.center.z,
    }
    local rawId = candidate.id or makeIntersectionId(rawCenter)

    local canonicalCluster = findCanonicalClusterAroundCenter(rawCenter)
    if not canonicalCluster then
        candidate.rawId = rawId
        candidate.rawCenter = rawCenter
        candidate.canonicalized = false
        return candidate
    end

    candidate.rawId = rawId
    candidate.rawCenter = rawCenter
    candidate.center = canonicalCluster.center
    candidate.id = makeIntersectionId(canonicalCluster.center)
    candidate.lights = canonicalCluster.lights
    candidate.canonicalized = candidate.id ~= rawId
        or distance3D(rawCenter, canonicalCluster.center) > 0.5

    return candidate
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

                    return canonicalizeCandidate({
                        id = makeIntersectionId(center),
                        center = center,
                        axis = { x = fx, y = fy },
                        lights = {},
                        source = node and 'traffic_light_node' or 'traffic_light_probe',
                    })
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

    return canonicalizeCandidate({
        id = makeIntersectionId(cluster.center),
        center = cluster.center,
        axis = { x = fx, y = fy },
        lights = cluster.lights,
        source = 'object_cluster',
    })
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
        rawId = candidate.rawId or candidate.id,
        rawCenter = candidate.rawCenter or candidate.center,
        source = candidate.source or 'unknown',
        canonicalized = candidate.canonicalized == true,
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

    local coreRadius = Config.Detection.IntersectionControlRadius
        or (Config.Detection.ClusterRadius + 4.0)
    local fringeRadius = Config.Detection.IntersectionControlFringeRadius or coreRadius
    local linkRadius = Config.Detection.IntersectionControlLinkRadius or 0.0
    local maxVerticalOffset = Config.Detection.IntersectionControlMaxVerticalOffset or 12.0

    local core = {}
    local fringeCandidates = {}
    local seen = {}

    for _, light in ipairs(nearbyLights) do
        if DoesEntityExist(light) then
            local model = GetEntityModel(light)
            if overrideLightModelHashes[model] then
                local coords = GetEntityCoords(light)
                local distance = distance3D(coords, intersection.center)
                local verticalOffset = math.abs(coords.z - intersection.center.z)

                if verticalOffset <= maxVerticalOffset then
                    if distance <= coreRadius then
                        core[#core + 1] = light
                        seen[light] = true
                    elseif distance <= fringeRadius then
                        fringeCandidates[#fringeCandidates + 1] = light
                    end
                end
            end
        end
    end

    -- Include only fringe lights physically linked to an already-confirmed core light.
    -- This catches wide mast-arm / corner heads at the same junction without turning the
    -- whole fringe radius into a blind neighbouring-intersection merge.
    if linkRadius > 0.0 and #core > 0 then
        for _, candidate in ipairs(fringeCandidates) do
            if DoesEntityExist(candidate) and not seen[candidate] then
                local candidateCoords = GetEntityCoords(candidate)
                local linked = false

                for _, coreLight in ipairs(core) do
                    if DoesEntityExist(coreLight)
                        and distance3D(candidateCoords, GetEntityCoords(coreLight)) <= linkRadius then
                        linked = true
                        break
                    end
                end

                if linked then
                    core[#core + 1] = candidate
                    seen[candidate] = true
                end
            end
        end
    end

    return core
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

local function describeSignalDecision(light, intersection)
    local forward = GetEntityForwardVector(light)
    local lx, ly = normalize2(forward.x, forward.y)
    local alignment = math.abs(dot2(lx, ly, intersection.axis.x, intersection.axis.y))
    local parallel = alignment >= Config.Signals.AlignmentThreshold
    local green = signalShouldBeGreen(light, intersection)

    local classification
    if green then
        classification = 'priority'
    elseif parallel then
        classification = 'conflict_parallel'
    else
        classification = 'conflict_perpendicular'
    end

    local state
    if intersection.phase == 'clearance' then
        state = Config.Signals.RedState
    elseif intersection.phase == 'recovery' then
        state = Config.Signals.YellowState
    elseif green then
        state = Config.Signals.GreenState
    else
        state = Config.Signals.RedState
    end

    return alignment, parallel, green, classification, state
end

local function signalStateName(state)
    if state == Config.Signals.GreenState then
        return 'GREEN'
    elseif state == Config.Signals.RedState then
        return 'RED'
    elseif state == Config.Signals.YellowState then
        return 'YELLOW'
    elseif state == Config.Signals.ResetState then
        return 'RESET'
    end
    return tostring(state)
end

local function applyManagedTrafficLightState(light, state, force)
    if light == 0 or not DoesEntityExist(light) then
        return false
    end

    -- v0.1.27: prop_traffic_01d is already replaced by prop_traffic_01b through
    -- CREATE_MODEL_SWAP, so all controllable signals use the normal direct path.
    -- If an unswapped 01d somehow exists outside the configured zones it is detection-only
    -- and is never included here because it is not in OverrideModels.
    return applyTrafficLightState(light, state, force)
end

local function shouldForceRefreshSignal(light)
    if light == 0 or not DoesEntityExist(light) then
        return false
    end

    if not refreshOverrideModelHashes[GetEntityModel(light)] then
        return false
    end

    local now = nowMs()
    local refreshMs = Config.Signals.RefreshOverrideMs or 400
    local last = lastForcedSignalRefresh[light] or 0

    if now - last < refreshMs then
        return false
    end

    lastForcedSignalRefresh[light] = now
    return true
end

local function applySignalStates()
    local playerCoords = GetEntityCoords(PlayerPedId())

    for _, intersection in pairs(activeIntersections) do
        if distance3D(playerCoords, intersection.center) <= Config.Performance.LightPoolRadius then
            if not intersection.lights
                or nowMs() - (intersection.lastLightResolve or 0)
                    > (Config.Performance.ActiveLightResolveMs or 450) then
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

                    local forceRefresh = shouldForceRefreshSignal(light)
                    applyManagedTrafficLightState(light, state, forceRefresh)
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
                applyManagedTrafficLightState(light, Config.Signals.YellowState)
                yellowLights[#yellowLights + 1] = light
            else
                applyManagedTrafficLightState(light, Config.Signals.RedState)
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
                    applyManagedTrafficLightState(light, Config.Signals.ResetState, true)
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
    print(('[SignalPreempt] Reset %d direct traffic-light objects. World 01d->01b model swap remains active.'):format(count))
end, false)

RegisterCommand('spinspect', function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local entries = {}

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local model = GetEntityModel(object)
            if detectionLightModelHashes[model]
                or overrideLightModelHashes[model]
                or noOverrideLightModelHashes[model] then
                local coords = GetEntityCoords(object)
                local distance = distance3D(coords, playerCoords)
                if distance <= 90.0 then
                    entries[#entries + 1] = {
                        object = object,
                        model = model,
                        name = lightModelNames[model] or tostring(model),
                        coords = coords,
                        distance = distance,
                        controlMode = model == GetHashKey('prop_traffic_01d')
                            and 'housing-source'
                            or (overrideLightModelHashes[model] and 'direct' or 'none'),
                    }
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.distance < b.distance
    end)

    print(('[SignalPreempt] Nearby traffic-light objects: %d'):format(#entries))
    for _, entry in ipairs(entries) do
        print(('[SignalPreempt] %s hash=%s entity=%s dist=%.1fm control=%s @ %.2f %.2f %.2f'):format(
            entry.name,
            tostring(entry.model),
            tostring(entry.object),
            entry.distance,
            entry.controlMode,
            entry.coords.x,
            entry.coords.y,
            entry.coords.z
        ))
    end
end, false)


local function getModelDimensionSummary(modelHash)
    local ok, minDim, maxDim = pcall(GetModelDimensions, modelHash)
    if not ok or not minDim or not maxDim then
        return 'dimensions unavailable'
    end

    local width = math.abs(maxDim.x - minDim.x)
    local depth = math.abs(maxDim.y - minDim.y)
    local height = math.abs(maxDim.z - minDim.z)

    return ('%.2f x %.2f x %.2f'):format(width, depth, height)
end

local function printConfiguredModelSwaps()
    local zones = Config.Signals.ModelSwapZones or {}
    print(('[SignalPreempt] broad world model swaps active=%s definitions=%d zones=%d perPole01d=true'):format(
        tostring(modelSwapsApplied),
        #configuredModelSwaps,
        #zones
    ))

    for _, swap in ipairs(configuredModelSwaps) do
        print(('[SignalPreempt] model swap %s -> %s'):format(
            swap.sourceName,
            swap.replacementName
        ))
    end

    for index, zone in ipairs(zones) do
        print(('[SignalPreempt] swap zone #%d center=%.1f %.1f %.1f radius=%.1f lazy=%s'):format(
            index,
            tonumber(zone.x) or 0.0,
            tonumber(zone.y) or 0.0,
            tonumber(zone.z) or 0.0,
            tonumber(zone.radius) or 12000.0,
            tostring(zone.lazy == true)
        ))
    end
end

RegisterCommand('spswaps', function()
    printConfiguredModelSwaps()
end, false)

-- Backwards-compatible diagnostic alias used throughout development.
RegisterCommand('spproxies', function()
    printConfiguredModelSwaps()
end, false)

RegisterCommand('spprobe', function()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local targetHash = GetHashKey('prop_traffic_01b')
    local target = 0
    local bestDistance = nil

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) and GetEntityModel(object) == targetHash then
            local distance = distance3D(GetEntityCoords(object), playerCoords)
            if distance <= 60.0 and (not bestDistance or distance < bestDistance) then
                target = object
                bestDistance = distance
            end
        end
    end

    if target == 0 then
        print('[SignalPreempt] /spprobe: no prop_traffic_01b found within 60m.')
        return
    end

    print(('[SignalPreempt] /spprobe: testing nearest clean 01b entity=%s dist=%.1fm. Sequence RESET -> GREEN -> RED -> YELLOW -> RESET.'):format(
        tostring(target),
        bestDistance or -1.0
    ))

    CreateThread(function()
        applyTrafficLightState(target, Config.Signals.ResetState, true)
        print('[SignalPreempt] /spprobe state: RESET')
        Wait(2000)

        if not DoesEntityExist(target) then return end
        applyTrafficLightState(target, Config.Signals.GreenState, true)
        print(('[SignalPreempt] /spprobe state: GREEN (%d)'):format(Config.Signals.GreenState))
        Wait(2500)

        if not DoesEntityExist(target) then return end
        applyTrafficLightState(target, Config.Signals.RedState, true)
        print(('[SignalPreempt] /spprobe state: RED (%d)'):format(Config.Signals.RedState))
        Wait(2500)

        if not DoesEntityExist(target) then return end
        applyTrafficLightState(target, Config.Signals.YellowState, true)
        print(('[SignalPreempt] /spprobe state: YELLOW (%d)'):format(Config.Signals.YellowState))
        Wait(2500)

        if DoesEntityExist(target) then
            applyTrafficLightState(target, Config.Signals.ResetState, true)
            print('[SignalPreempt] /spprobe state: RESET (finished)')
        end
    end)
end, false)

RegisterCommand('spdecisions', function()
    if not currentRequest then
        print('[SignalPreempt] /spdecisions: no current request.')
        return
    end

    local intersection = activeIntersections[currentRequest.id]
    if not intersection then
        print(('[SignalPreempt] /spdecisions: request=%s has no active intersection state.'):format(
            tostring(currentRequest.id)
        ))
        return
    end

    local lights = findLightsForIntersection(intersection)
    print(('[SignalPreempt] /spdecisions: intersection=%s phase=%s lights=%d center=%.2f %.2f %.2f axis=%.3f %.3f core=%.1fm fringe=%.1fm'):format(
        tostring(currentRequest.id),
        tostring(intersection.phase or 'unknown'),
        #lights,
        intersection.center.x,
        intersection.center.y,
        intersection.center.z,
        intersection.axis.x,
        intersection.axis.y,
        Config.Detection.IntersectionControlRadius or 42.0,
        Config.Detection.IntersectionControlFringeRadius
            or (Config.Detection.IntersectionControlRadius or 42.0)
    ))

    for _, light in ipairs(lights) do
        if DoesEntityExist(light) then
            local alignment, parallel, green, classification, state = describeSignalDecision(light, intersection)
            local coords = GetEntityCoords(light)
            local heading = GetEntityHeading(light)

            print(('[SignalPreempt] decision: entity=%s model=%s heading=%.1f alignment=%.3f parallel=%s classification=%s desired=%s(%s) refresh=%s dist=%.1fm @ %.2f %.2f %.2f'):format(
                tostring(light),
                lightModelNames[GetEntityModel(light)] or tostring(GetEntityModel(light)),
                heading,
                alignment,
                tostring(parallel),
                classification,
                signalStateName(state),
                tostring(state),
                refreshOverrideModelHashes[GetEntityModel(light)] and 'targeted' or 'change-only',
                distance3D(GetEntityCoords(PlayerPedId()), coords),
                coords.x,
                coords.y,
                coords.z
            ))
        end
    end
end, false)

RegisterCommand('spfallbacks', function()
    local count = 0

    for _, record in pairs(stubborn01dFallbacks) do
        count = count + 1
        print(('[SignalPreempt] housing01d: key=%s source=%s housing=%s visible=%s hiddenSource=%s @ %.2f %.2f %.2f'):format(
            record.key,
            tostring(record.sourceObject or 0),
            tostring(record.housingObject or 0),
            tostring(record.housingObject ~= 0 and DoesEntityExist(record.housingObject)),
            tostring(record.hideRegistered == true),
            record.coords.x,
            record.coords.y,
            record.coords.z
        ))
    end

    print(('[SignalPreempt] guaranteed 01d housings: %d sessionPersistent=%s scanMs=%d'):format(
        count,
        tostring(Config.Signals.Stubborn01dSessionPersistent == true),
        Config.Signals.Stubborn01dScanMs or 100
    ))
end, false)

RegisterCommand('spstatus', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local allowed = vehicle ~= 0 and isAllowedVehicle(vehicle)
    local driver = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
    local siren = vehicle ~= 0 and IsVehicleSirenOn(vehicle) or false
    local qualified = vehicle ~= 0 and isQualifiedEmergencyVehicle(ped, vehicle)

    local activeCount = 0
    for _ in pairs(activeIntersections) do
        activeCount = activeCount + 1
    end

    local phases = {}
    for id, intersection in pairs(activeIntersections) do
        phases[#phases + 1] = ('%s:%s'):format(id, intersection.phase or 'unknown')
    end
    table.sort(phases)

    print(('[SignalPreempt] identityGrid=%.1fm'):format(Config.Detection.IntersectionIdGrid or 20.0))
    print(('[SignalPreempt] status: vehicle=%s class=%s allowed=%s driver=%s siren=%s emitter=%s qualified=%s request=%s activeIntersections=%d phases=%s'):format(
        tostring(vehicle),
        vehicle ~= 0 and tostring(GetVehicleClass(vehicle)) or 'n/a',
        tostring(allowed),
        tostring(driver),
        tostring(siren),
        tostring(emitterOverride),
        tostring(qualified),
        currentRequest and currentRequest.id or 'none',
        activeCount,
        #phases > 0 and table.concat(phases, ',') or 'none'
    ))

    if activeCount > 1 then
        print('[SignalPreempt] note: activeIntersections is the client-visible server set and may include intersections requested by other emergency vehicles/players.')
    end

    if vehicle ~= 0 and qualified then
        local coords = GetEntityCoords(vehicle)

        if currentRequest and activeIntersections[currentRequest.id] then
            local active = activeIntersections[currentRequest.id]
            print(('[SignalPreempt] activeRequest: id=%s phase=%s distance=%.1fm center=%.2f %.2f %.2f source=%s'):format(
                currentRequest.id,
                active.phase or 'unknown',
                distance3D(coords, active.center),
                active.center.x,
                active.center.y,
                active.center.z,
                currentRequest.source or 'unknown'
            ))

            if currentRequest.rawId and currentRequest.rawId ~= currentRequest.id then
                print(('[SignalPreempt] activeRequest canonicalized: raw=%s @ %.2f %.2f %.2f -> canonical=%s @ %.2f %.2f %.2f'):format(
                    currentRequest.rawId,
                    currentRequest.rawCenter.x,
                    currentRequest.rawCenter.y,
                    currentRequest.rawCenter.z,
                    currentRequest.id,
                    currentRequest.center.x,
                    currentRequest.center.y,
                    currentRequest.center.z
                ))
            end
        end

        local candidate = detectUpcomingIntersection(vehicle)
        if candidate then
            if candidate.rawId and candidate.rawId ~= candidate.id then
                print(('[SignalPreempt] rawCandidate: id=%s source=%s distance=%.1fm center=%.2f %.2f %.2f'):format(
                    candidate.rawId,
                    candidate.source or 'object_cluster',
                    distance3D(coords, candidate.rawCenter),
                    candidate.rawCenter.x,
                    candidate.rawCenter.y,
                    candidate.rawCenter.z
                ))
                print(('[SignalPreempt] canonicalCandidate: id=%s distance=%.1fm center=%.2f %.2f %.2f%s'):format(
                    candidate.id,
                    distance3D(coords, candidate.center),
                    candidate.center.x,
                    candidate.center.y,
                    candidate.center.z,
                    currentRequest and candidate.id ~= currentRequest.id and ' (different from active request)' or ''
                ))
            else
                print(('[SignalPreempt] detectedCandidate: id=%s source=%s distance=%.1fm center=%.2f %.2f %.2f%s'):format(
                    candidate.id,
                    candidate.source or 'object_cluster',
                    distance3D(coords, candidate.center),
                    candidate.center.x,
                    candidate.center.y,
                    candidate.center.z,
                    currentRequest and candidate.id ~= currentRequest.id and ' (different from active request)' or ''
                ))
            end
        else
            print('[SignalPreempt] detectedCandidate: none')
        end
    end
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

    if not requestConfiguredSwapModels() then
        print('[SignalPreempt] WARNING: model-swap replacement model did not finish loading before timeout.')
    end

    local swapCount = applyConfiguredModelSwaps()
    print(('[SignalPreempt] Applied %d broad world model swap registration(s) (0 expected).'):format(swapCount))
    print(('[SignalPreempt] Intersection identity grid: %.1fm'):format(
        Config.Detection.IntersectionIdGrid or 20.0
    ))

    -- Give the streaming system one frame to apply the replacement before resetting
    -- any already-loaded controllable traffic lights.
    Wait(0)
    maintainStubborn01dFallbacks()
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
        if Config.Enabled and Config.Signals.Stubborn01dFallback == true then
            maintainStubborn01dFallbacks()
            Wait(Config.Signals.Stubborn01dScanMs or 100)
        else
            Wait(1000)
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
            if DoesEntityExist(light) and overrideLightModelHashes[GetEntityModel(light)] then
                applyTrafficLightState(light, Config.Signals.ResetState, true)
            end
        end
    end

    restoreAllStubborn01dFallbacks()

    local removed = removeConfiguredModelSwaps()
    if removed > 0 then
        print(('[SignalPreempt] Removed %d world model swap registration(s).'):format(removed))
    end
end)
