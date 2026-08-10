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
    MaxAcquireDistance = 300.0,
    MinAcquireDistance = 10.0,
    MaxLateralOffset = 38.0,
    LateralPenalty = 2.25,
    ClusterRadius = 36.0,
    MinSignals = 2,
    ReleaseBehindDistance = 24.0,
    -- Stable server/inter-client intersection identity grid.
    --
    -- 10 m was too fine for large junctions: the early traffic-light-node centre and
    -- the later prop-derived canonical centre could differ by only ~3 m yet fall on
    -- opposite rounding boundaries (e.g. 21:19 vs 20:20). A 20 m identity grid keeps
    -- those representations under one lease while the precise centre is still retained
    -- separately for signal selection, distance checks and approach geometry.
    IntersectionIdGrid = 20.0,

    -- v0.1.28 canonical intersection grouping.
    --
    -- A seed-facing cluster can represent only one edge of a large junction. SignalPreempt
    -- now performs a second deterministic pass around that raw cluster centre so the
    -- north/south/east/west signal groups resolve to one physical intersection.
    CanonicalizeIntersections = true,
    CanonicalSearchRadius = 48.0,
    CanonicalMaxSignalRadius = 34.0,
    CanonicalMaxSpan = 64.0,
    CanonicalMaxVerticalSpan = 12.0,

    -- Once a canonical centre is known, this radius is used to resolve the actual signal
    -- objects controlled for that junction. Keeping it separate from ClusterRadius avoids
    -- needing to enlarge the seed detector and accidentally merge neighbouring junctions.
    IntersectionControlRadius = 42.0,

    -- Some large GTA junctions place an additional mast-arm / side-mounted head just
    -- outside the core control radius. Do not widen the acquisition cluster; instead
    -- allow a one-hop control fringe. A fringe light is included only when it is close
    -- to an already-confirmed core light, which is safer than blindly controlling every
    -- traffic light inside a large circle.
    IntersectionControlFringeRadius = 60.0,
    IntersectionControlLinkRadius = 34.0,
    IntersectionControlMaxVerticalOffset = 12.0,

    -- Road-node look-ahead lets the resource identify signalised junctions before the
    -- physical traffic-light props have streamed into the client's object pool.
    UseTrafficLightNodes = true,
    TrafficLightNodeFlag = 256, -- eVehicleNodeProperties.TRAFFIC_LIGHT (1 << 8)

    -- Ask GTA to keep the road/path nodes in the approach corridor available while an
    -- eligible emergency vehicle is responding. This makes the node look-ahead useful
    -- before the physical traffic-light props enter the local object pool.
    RequestPathNodesAhead = true,
    PathRequestExtraDistance = 80.0,
    PathRequestPadding = 60.0,

    -- Probe the road corridor rather than only a single centreline. Multi-lane roads
    -- often place the traffic-light node on an adjacent lane.
    NodeProbeStartDistance = 36.0,
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
    -- Empirically verified on the user's current FiveM/GTA build and the vanilla
    -- traffic-light props used by SignalPreempt:
    -- 0 = green, 1 = red, 2 = amber/yellow, 3 = reset/no override.
    --
    -- Note: current Cfx native documentation lists a different enum ordering, but
    -- repeated in-game tests on these props showed state 2 rendering amber while
    -- state 0 renders green. SignalPreempt follows the observed game behaviour here.
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

    -- Models used to *detect* signalised intersections. 03a/03b are kept here
    -- because they are useful landmarks for intersection acquisition.
    DetectionModels = {
        'prop_traffic_01a',
        'prop_traffic_01b',
        'prop_traffic_01d',
        'prop_traffic_03a',
        'prop_traffic_03b',
    },

    -- Primary traffic-light props that can safely use the native override directly.
    OverrideModels = {
        'prop_traffic_01a',
        'prop_traffic_01b',
    },

    -- Some vanilla heads can visually fall dark even though the requested override
    -- state is still cached. Reassert the configured direct-safe models while an
    -- intersection is actively controlled.
    RefreshOverrideModels = {
        'prop_traffic_01a',
        'prop_traffic_01b',
    },
    RefreshOverrideMs = 400,

    -- Legacy model-swap definition retained for diagnostics/future map-specific
    -- experimentation only. No swap zones are configured in the current architecture,
    -- so no broad/world model swap is registered at runtime.
    WorldModelSwaps = {
        ['prop_traffic_01d'] = 'prop_traffic_01b',
    },
    ModelSwapZones = {},

    -- v0.1.37 guaranteed-housing normalisation.
    --
    -- Create and verify the clean 01b housing FIRST. Only after that object exists
    -- do we register an exact-location model hide for the source 01d. If the clean
    -- housing ever disappears, the hide is removed before rebuilding it so GTA can
    -- never be left with a lamp/corona and no physical signal housing.
    Stubborn01dFallback = true,
    Stubborn01dScanMs = 100,
    Stubborn01dHideRadius = 2.25,
    Stubborn01dQuantize = 0.5,
    Stubborn01dSessionPersistent = true,
    Stubborn01dProxyLodDistance = 1000,


    -- Detection-only / integrated assemblies that SignalPreempt never forces.
    NoOverrideModels = {
        'prop_traffic_02a',
        'prop_traffic_02b',
        'prop_traffic_03a',
        'prop_traffic_03b',
        'prop_traffic_lightset_01',
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
    MaxRequestDistance = 340.0,
    SameRoadAlignmentThreshold = 0.65,

    -- Optional ACE gate. Example server.cfg line when enabled:
    -- add_ace group.leo signalpreempt.use allow
    RequireAce = false,
    AcePermission = 'signalpreempt.use',
}

Config.Performance = {
    ClientTickMs = 150,
    LightPoolRefreshMs = 350,
    LightPoolRadius = 420.0,
    SignalApplyMs = 200,
    ActiveLightResolveMs = 450,
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
