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
    MaxAcquireDistance = 185.0,
    MinAcquireDistance = 12.0,
    MaxLateralOffset = 32.0,
    LateralPenalty = 2.25,
    ClusterRadius = 34.0,
    MinSignals = 2,
    ReleaseBehindDistance = 24.0,
    IntersectionIdGrid = 5.0,
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

    LightModels = {
        'prop_traffic_01a',
        'prop_traffic_01b',
        'prop_traffic_01d',
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
    MaxRequestDistance = 260.0,
    SameRoadAlignmentThreshold = 0.65,

    -- Optional ACE gate. Example server.cfg line when enabled:
    -- add_ace group.leo signalpreempt.use allow
    RequireAce = false,
    AcePermission = 'signalpreempt.use',
}

Config.Performance = {
    ClientTickMs = 200,
    LightPoolRefreshMs = 1200,
    LightPoolRadius = 240.0,
    SignalApplyMs = 250,
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
