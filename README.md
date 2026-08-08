# SignalPreempt v0.1.2

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


## v0.1.2 detection update

SignalPreempt now uses GTA vehicle-node traffic-light flags as an early look-ahead source. This allows it to acquire a signalised junction before the physical traffic-light objects are close enough to appear in the normal client object pool. Debug mode also uses text labels rather than large coloured sphere markers.
