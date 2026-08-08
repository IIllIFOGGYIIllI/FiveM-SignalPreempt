# SignalPreempt v0.1.11

Standalone emergency vehicle traffic signal pre-emption for FiveM.

## Install

1. Copy the `SignalPreempt` folder into your server's `resources` directory.
2. Add `ensure SignalPreempt` to `server.cfg`.
3. Restart the server or run `ensure SignalPreempt` from the server console.

No ESX, QBCore, ELS, or other framework is required.

## Startup log

When the resource starts, SignalPreempt prints its resource name and version from `fxmanifest.lua` directly to the FiveM server console. This keeps the startup version display in sync with the resource metadata.

## Default behaviour

- Emergency-class vehicles are eligible.
- The driver must have the vehicle siren state active.
- The client detects the next traffic-signal cluster in the vehicle's direction of travel.
- The server locks the intersection to that roadway and broadcasts the pre-emption state.
- All approaches receive a short all-red clearance phase.
- Signals aligned with the emergency roadway receive green; conflicting approaches remain red.
- Nearby ambient AI traffic is temporarily braked on conflicting approaches.
- The intersection automatically returns to normal after the requesting emergency vehicle passes or stops refreshing its lease.

## Important GTA limitation

`SetEntityTrafficlightOverride` changes the traffic-light state visually, but GTA does not always make ambient traffic obey the override. SignalPreempt therefore includes a separate ambient-AI braking layer.

The AI layer deliberately ignores:

- player-occupied vehicles,
- emergency-class vehicles,
- mission entities by default,
- networked vehicles the local client does not control.

This is intended to reduce interference with scripted pursuits and other mission resources.

## Debug

Run `/spdebug` to toggle local intersection diagnostics when `Config.Debug.AllowCommand` is enabled.

Run `/spcleanup` to force-reset all currently loaded SignalPreempt traffic-light overrides during testing.

Run `/spinspect` near a junction to print the exact loaded traffic-light models, hashes, coordinates, and whether each model is in SignalPreempt's override set.

Debug mode shows the detected intersection centre, priority axis, phase, and signal classification.

## Custom emergency lighting resources

A client lighting resource can explicitly set the SignalPreempt emitter state:

```lua
exports['SignalPreempt']:SetEmitterEnabled(true)
exports['SignalPreempt']:SetEmitterEnabled(false)
```

You can also query the local state:

```lua
local active = exports['SignalPreempt']:IsPreemptionActive()
local intersection = exports['SignalPreempt']:GetCurrentIntersection()
```

## Tuning

The main values to tune first are in `config.lua`:

- `Config.Detection.MaxAcquireDistance`
- `Config.Detection.MaxLateralOffset`
- `Config.Detection.ClusterRadius`
- `Config.Signals.AlignmentThreshold`
- `Config.Signals.SignalHeadingParallelToTraffic`
- `Config.AITraffic.StopMaxDistance`

If traffic signals on a custom map appear to classify the wrong roadway as green, switch `Config.Signals.SignalHeadingParallelToTraffic` to `false` and test again.


## v0.1.6 signal rendering cleanup

SignalPreempt continues to use GTA vehicle-node traffic-light flags for early look-ahead. v0.1.6 also suppresses the auxiliary light spots/coronas on a traffic-light prop while that prop is being forced, then restores normal entity lighting when pre-emption ends. This targets the extra low-mounted green/amber glow that can appear on some vanilla pole assemblies when `SET_ENTITY_TRAFFICLIGHT_OVERRIDE` is active.


## Traffic-light compatibility
The default override set is now limited to `prop_traffic_01a` and `prop_traffic_01b`. `prop_traffic_01d`, `03a`, and `03b` remain usable for detection but are not forced, because field testing showed the 01d pole assembly can expose a low-mounted ghost lamp when the entire entity is overridden. AI cross-traffic control remains independent.


## v0.1.7 ghost-light suppression

The GTA traffic-light override native can activate more than the visible signal material on some vanilla traffic-light archetypes. v0.1.7 therefore suppresses both the entity light spots and particle FX attached to a traffic-light object while it is forced. Cleanup is entity-scoped to avoid removing unrelated visual effects in the area.


## v0.1.8 01d compatibility change

Field inspection identified `prop_traffic_01d` as the closest actively overridden model at intersections showing the low-mounted green ghost lamp. SignalPreempt now leaves 01d rendering under GTA control and only forces 01a/01b vehicle-signal props. This is intentionally conservative: correct, clean signal rendering is preferred over forcing every auxiliary signal head.


## v0.1.10 signal-control test

v0.1.10 restores `prop_traffic_01d` because field testing showed that many vanilla intersections rely on that model for the actual approach-side signal heads. SignalPreempt now treats traffic-light overrides as persistent state: it writes a new native override only when a signal changes phase, rather than hammering the same entity every signal tick.

Diagnostic commands:

- `/spdebug` toggles world-space intersection/signal debugging.
- `/spinspect` prints nearby traffic-light models and whether SignalPreempt controls them.
- `/spstatus` prints whether the current vehicle is allowed, whether FiveM reports its siren active, whether it qualifies for pre-emption, and what intersection SignalPreempt is requesting/detecting.
- `/spcleanup` force-resets loaded traffic-light objects back to GTA control.


## Diagnostic probe

Run `/spprobe` near an intersection with the siren off. It cycles the nearest `prop_traffic_01d` through reset, green, red, yellow, and reset so model-specific rendering artifacts can be isolated.
