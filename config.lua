Config = {}

Config.Enabled = true

-- Vehicle eligibility. Emergency class (18) works with vanilla and most custom emergency vehicles.
Config.Vehicle = {
    AllowEmergencyClass = true,
    AllowedModels = {
        -- [`your_custom_model`] = true,
    },
    DeniedModels = {
        -- [`policeold1`] = true,
    },
}

-- Activation rules.
Config.Activation = {
    RequireDriver = true,
    RequireSiren = true,

    -- Manual emitter support is disabled by default. When enabled, /signalpreempt toggles
    -- the local emitter state. Other resources may also use the SetEmitterEnabled export.
    AllowManualEmitter = false,
    ManualCommand = 'signalpreempt',
}

-- Automatic intersection acquisition.
Config.Detection = {
    -- How far ahead SignalPreempt starts looking for a signalised junction.
    MaxAcquireDistance = 210.0,
    MinAcquireDistance = 10.0,
    MaxLateralOffset = 38.0,
    LateralPenalty = 2.25,
    ClusterRadius = 36.0,
    MinSignals = 2,
    ReleaseBehindDistance = 24.0,
    IntersectionIdGrid = 10.0,

    -- Road-node look-ahead lets the resource identify signalised junctions before the
    -- physical traffic-light props have streamed into the client's object pool.
    UseTrafficLightNodes = true,
    TrafficLightNodeFlag = 256, -- eVehicleNodeProperties.TRAFFIC_LIGHT (1 << 8)

    -- Ask GTA to keep the road/path nodes in the approach corridor available while an
    -- eligible emergency vehicle is responding. This makes the node look-ahead useful
    -- before the physical traffic-light props enter the local object pool.
    RequestPathNodesAhead = true,
    PathRequestExtraDistance = 35.0,
    PathRequestPadding = 42.0,

    -- Probe the road corridor rather than only a single centreline. Multi-lane roads
    -- often place the traffic-light node on an adjacent lane.
    NodeProbeStartDistance = 24.0,
    NodeProbeStep = 6.0,
    NodeLateralOffsets = { 0.0, 7.0, -7.0, 14.0, -14.0 },
    NodeSearchType = 1,
    NodeSearchParam = 3.0,

    -- Traffic-light path nodes tend to sit around the stop line. Moving the provisional
    -- centre slightly forward places the lock closer to the middle of the junction.
    NodeCenterForwardOffset = 12.0,
}

-- Signal phasing.
Config.Signals = {
    -- GTA traffic light override values: 0 green, 1 red, 2 yellow, 3 reset.
    GreenState = 0,
    RedState = 1,
    YellowState = 2,
    ResetState = 3,

    -- All approaches are held red briefly before the priority approach receives green.
    ClearanceMs = 1200,
    RecoveryYellowMs = 900,

    -- A signal is considered to serve the priority roadway when its heading axis is
    -- sufficiently aligned with the emergency vehicle's approach axis.
    AlignmentThreshold = 0.60,

    -- GTA map props can vary by map/intersection. If an add-on map has traffic signal
    -- headings rotated 90 degrees relative to traffic flow, set this to false.
    SignalHeadingParallelToTraffic = true,

    -- GTA traffic-signal props also contain light-spot/corona emitters. When an
    -- entity is forced with SET_ENTITY_TRAFFICLIGHT_OVERRIDE, some map variants
    -- can expose an extra low-mounted glow on the pole. Keep the signal's
    -- emissive face under the traffic-light override while suppressing the
    -- entity light spots during pre-emption. They are restored on reset.
    SuppressEntityLightSpots = true,

    -- Models used to *detect* signalised intersections. 03a/03b are kept here
    -- because they are useful landmarks for intersection acquisition.
    DetectionModels = {
        'prop_traffic_01a',
        'prop_traffic_01b',
        'prop_traffic_01d',
        'prop_traffic_03a',
        'prop_traffic_03b',
    },

    -- Models that are safe to force with SET_ENTITY_TRAFFICLIGHT_OVERRIDE.
    -- The 03a/03b assemblies include pedestrian/crosswalk hardware on the pole.
    -- Forcing the whole entity can expose an orphaned green/amber corona lower down
    -- the pole even though no vehicle signal head exists there, so they are detected
    -- but deliberately NOT overridden.
    OverrideModels = {
        'prop_traffic_01a',
        'prop_traffic_01b',
        'prop_traffic_01d',
    },

    -- Never force these models. SignalPreempt explicitly resets them near an active
    -- junction in case an older resource build previously left an override behind.
    NoOverrideModels = {
        'prop_traffic_02a',
        'prop_traffic_02b',
        'prop_traffic_03a',
        'prop_traffic_03b',
    },
}

-- AI traffic control. This supplements the visual traffic-light override because GTA's
-- traffic-light native does not reliably make ambient drivers obey overridden states.
Config.AITraffic = {
    Enabled = true,
    ControlRadius = 62.0,
    StopMinDistance = 7.0,
    StopMaxDistance = 46.0,
    ApproachDotThreshold = 0.25,
    ConflictAlignmentThreshold = 0.58,
    BrakeAction = 27,
    BrakeActionMs = 650,

    -- Helps avoid interference with pursuit/mission scripts such as ERS-style resources.
    IgnoreEmergencyVehicles = true,
    IgnoreMissionEntities = true,
    IgnoreVehiclesWithPlayers = true,
    RequireNetworkControl = true,
}

-- Synchronisation and server-side request leases.
Config.Server = {
    LeaseSeconds = 4,
    RefreshMs = 1000,
    MaxRequestDistance = 285.0,
    SameRoadAlignmentThreshold = 0.65,

    -- Optional ACE gate. Example server.cfg line when enabled:
    -- add_ace group.leo signalpreempt.use allow
    RequireAce = false,
    AcePermission = 'signalpreempt.use',
}

Config.Performance = {
    ClientTickMs = 150,
    LightPoolRefreshMs = 900,
    LightPoolRadius = 320.0,
    SignalApplyMs = 200,
    AITrafficMs = 250,
}

Config.Debug = {
    Enabled = false,
    AllowCommand = true,
    Command = 'spdebug',
    DrawIntersection = true,
    DrawSignals = true,
    PrintRequests = false,
}
