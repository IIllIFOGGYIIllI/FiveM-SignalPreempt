# SignalPreempt v1.0.1

Standalone emergency-vehicle traffic-signal pre-emption for FiveM.

SignalPreempt detects a signalised junction ahead of an eligible emergency vehicle, establishes a server-owned priority lease, places conflicting approaches on red, gives the emergency vehicle's roadway green after an all-red clearance phase, and then returns the intersection to normal GTA control after the vehicle clears it.

## Links

- **Cfx.re Release:** https://forum.cfx.re/t/free-standalone-signalpreempt-emergency-traffic-signal-pre-emption/5420622
- **GitHub Releases:** https://github.com/IIllIFOGGYIIllI/FiveM-SignalPreempt/releases

## Current status

v1.0.1 is the first post-release maintenance update. It adds the project's custom source-available licence and does not change the tested traffic-pre-emption runtime from v1.0.0.

Current tested architecture:

- 300 m client intersection acquisition.
- 340 m server request-distance ceiling.
- 20 m stable intersection identity grid.
- Canonical grouping for large multi-head intersections.
- 1.2 second all-red clearance before priority green.
- Direct native control only for `prop_traffic_01a` and `prop_traffic_01b`.
- `prop_traffic_01d` is never directly passed to `SetEntityTrafficlightOverride`.
- Guaranteed-housing normalisation for streamed `prop_traffic_01d`.
- Supplemental ambient AI cross-traffic braking.
- Server-owned intersection leases and multiplayer state broadcast.
- Optional ACE permission gate.
- Optional manual emitter integration for custom lighting resources.

## Verified traffic-light state mapping

SignalPreempt intentionally uses the values repeatedly verified in-game on the target FiveM/GTA build:

```text
0 = GREEN
1 = RED
2 = YELLOW / AMBER
3 = RESET / NO OVERRIDE
```

Do not change these values solely to match a different enum ordering documented elsewhere unless the target game build has been tested and confirmed to behave differently.

## `prop_traffic_01d` handling

Directly overriding `prop_traffic_01d` was confirmed to produce unwanted low-mounted/ghost traffic-light lamps.

The current implementation uses a housing-first replacement strategy:

```text
streamed prop_traffic_01d detected
        ↓
load prop_traffic_01b
        ↓
create a full replacement 01b at the exact source transform
        ↓
verify that the replacement entity exists
        ↓
mark it persistent, visible, frozen and long-LOD
        ↓
only then hide the source 01d map model
```

If the replacement housing disappears, SignalPreempt removes the source model hide before rebuilding the replacement. This prevents the resource from intentionally leaving a traffic-light position with only a lamp/corona and no physical housing.

The original `01d` remains detection-only. Active signal state is applied to the verified `01b` replacement.

Broad/world-sized model swaps are disabled:

```text
ModelSwapZones = {}
```

## Installation

Copy the resource into your FiveM resources directory using the folder name exactly:

```text
SignalPreempt
```

Then add:

```cfg
ensure SignalPreempt
```

to `server.cfg`.

A successful startup should show the SignalPreempt version banner. With the current architecture the broad swap registration count should be zero.

## Vehicle eligibility

By default, GTA emergency-class vehicles are allowed:

```lua
Config.Vehicle.AllowEmergencyClass = true
```

Custom models can be explicitly allowed or denied in `config.lua`:

```lua
AllowedModels = {
    -- [`your_custom_model`] = true,
},

DeniedModels = {
    -- [`policeold1`] = true,
},
```

The driver must normally be in the driver seat and the siren must be active.

## Activation and emitter integration

Normal automatic activation uses the vehicle siren.

Manual/custom-lighting integration is available through:

```lua
exports['SignalPreempt']:SetEmitterEnabled(true)
exports['SignalPreempt']:SetEmitterEnabled(false)
```

Manual command support is disabled by default:

```lua
Config.Activation.AllowManualEmitter = false
```

If enabled, the default command is:

```text
/signalpreempt
```

## Exports

### `SetEmitterEnabled(state)`

Allows another resource to explicitly enable or disable the local SignalPreempt emitter state.

### `IsPreemptionActive()`

Returns whether the local client currently has an active pre-emption request/intersection.

### `GetCurrentIntersection()`

Returns the local client's current active intersection data when available.

## Server synchronisation

Intersection ownership is coordinated server-side.

The server:

- validates request data and request distance;
- normalises the approach axis;
- creates a time-limited intersection lease;
- allows same-road compatible requesters to share the lease;
- rejects conflicting approach claims while the lease is active;
- broadcasts clearance/priority state to clients;
- removes stale leases when requesters release, disconnect, or expire.

Current defaults:

```text
LeaseSeconds               4
RefreshMs               1000
MaxRequestDistance       340 m
SameRoadAlignmentThreshold 0.65
```

## Intersection detection

SignalPreempt combines physical traffic-light objects with GTA traffic-light road-node look-ahead.

Important defaults:

```text
MaxAcquireDistance             300 m
ClusterRadius                   36 m
IntersectionIdGrid              20 m
CanonicalSearchRadius           48 m
IntersectionControlRadius       42 m
IntersectionControlFringeRadius 60 m
LightPoolRadius                420 m
```

Canonical grouping is used so large intersections whose corner/mast-arm heads fall into several raw clusters can still resolve to one physical junction.

## Signal control

Direct-safe override models:

```text
prop_traffic_01a
prop_traffic_01b
```

Detection-only / non-direct models include:

```text
prop_traffic_01d
prop_traffic_02a
prop_traffic_02b
prop_traffic_03a
prop_traffic_03b
prop_traffic_lightset_01
```

Both `01a` and `01b` active states are periodically refreshed while an intersection is controlled.

## AI cross-traffic

FiveM's traffic-light override does not reliably force every ambient driver to obey a scripted red signal, so SignalPreempt includes supplemental AI handling.

By default it avoids:

- emergency vehicles;
- mission entities;
- vehicles containing players;
- vehicles the local client cannot network-control.

This is intended to reduce interference with pursuit/mission resources while still helping ambient cross-traffic stop for the pre-empted junction.

## ACE permission gate

ACE checking is disabled by default.

To enable it:

```lua
Config.Server.RequireAce = true
Config.Server.AcePermission = 'signalpreempt.use'
```

Example `server.cfg` permission:

```cfg
add_ace group.leo signalpreempt.use allow
```

## Diagnostic commands

The diagnostic commands are intended for development/troubleshooting and can be run from the client console/chat as appropriate.

| Command | Purpose |
|---|---|
| `/spstatus` | Current vehicle eligibility, siren/emitter state, request, candidate and active intersection information. |
| `/spinspect` | Lists nearby recognised traffic-light props, models, coordinates and control mode. |
| `/spdecisions` | Prints the live per-head priority/conflict classification and desired traffic-light state. |
| `/spfallbacks` | Lists guaranteed `01d` replacement housings and source-hide state. |
| `/spprobe` | Cycles a nearby clean `01b` through reset/green/red/yellow/reset for diagnostics. |
| `/spcleanup` | Resets loaded direct-safe traffic-light overrides. |
| `/spswaps` | Reports configured broad model-swap definitions/zones; current builds should report zero active zones. |
| `/spproxies` | Backwards-compatible alias for the model-swap diagnostic command. |
| `/spdebug` | Toggles debug drawing when debug command access is enabled. |

`/spfallbacks` healthy entries should show a valid replacement housing entity and `hiddenSource=true` only after that housing exists.

## Performance defaults

```text
ClientTickMs             150
LightPoolRefreshMs       350
LightPoolRadius          420 m
SignalApplyMs            200
ActiveLightResolveMs     450
AITrafficMs              250
01d housing scan         100 ms
01d replacement LOD     1000
```

## Resource layout

```text
SignalPreempt/
├── client/
│   └── main.lua
├── server/
│   └── main.lua
├── config.lua
├── fxmanifest.lua
├── README.md
├── CHANGELOG.md
└── .gitignore
```

## Development history

SignalPreempt went through several approaches to `prop_traffic_01d`, including direct override, temporary proxies, visual shells, broad model swaps, and per-pole model swaps. Those experiments are retained in `CHANGELOG.md` for traceability.

The current implementation is the tested v0.1.37 guaranteed-housing architecture, carried through the v0.1.38 repository cleanup and promoted as v1.0.0.

## Licence

SignalPreempt is distributed under the **SignalPreempt Non-Commercial Source Licence v1.0**. See [`LICENSE`](LICENSE) for the complete terms.

In practical terms, the licence allows you to:

- use SignalPreempt on private or public FiveM servers;
- modify it for your own/server use;
- redistribute it non-commercially if the full licence and attribution are retained; and
- use it on monetised FiveM servers, provided SignalPreempt itself is not being sold or separately paywalled.

Without separate written permission, you may not sell SignalPreempt, put it in a paid resource pack/bundle, charge people to obtain it, or redistribute it as though it were your own original work.

This is a **source-available licence, not an OSI-approved open-source licence**, because it restricts commercial distribution.

The `LICENSE` file is the controlling legal text if this summary and the licence differ.
