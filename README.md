# SignalPreempt v0.1.15

Standalone emergency vehicle traffic signal pre-emption for FiveM.

SignalPreempt detects the signalised intersection an authorised emergency vehicle is approaching, requests server-synchronised priority, controls the relevant traffic signals, manages conflicting ambient AI traffic, and restores normal GTA traffic control after the emergency vehicle clears the junction.

## Features

- Standalone FiveM resource — no ESX or QBCore dependency
- Emergency-vehicle and driver validation
- Siren-based automatic activation
- Direction-aware intersection acquisition
- Early look-ahead detection for upcoming signalised junctions
- Server-synchronised intersection locking and pre-emption state
- All-red clearance phase before priority
- Green priority for the emergency vehicle's roadway
- Red conflicting approaches
- Ambient AI cross-traffic braking
- Automatic recovery and release
- Multi-vehicle intersection lease handling
- Custom emergency-vehicle support
- Debug and diagnostic commands
- Startup version banner read from `fxmanifest.lua`

## Install

1. Copy the `SignalPreempt` folder into your server's `resources` directory.
2. Add `ensure SignalPreempt` to `server.cfg`.
3. Restart the resource or start the server.

The resource folder name should remain exactly:

```text
SignalPreempt
```

## Current traffic-light handling

Vanilla `prop_traffic_01d` has a GTA rendering quirk: directly applying the traffic-light override can expose an unwanted low-mounted lamp/corona.

SignalPreempt therefore does **not** directly override `prop_traffic_01d` during normal operation. When an affected `01d` signal must be controlled, SignalPreempt temporarily swaps that local map instance to a compatible vanilla `prop_traffic_01b` proxy, controls the proxy, and restores the original `01d` when pre-emption ends.

Directly controlled vanilla models currently include:

```text
prop_traffic_01a
prop_traffic_01b
```

`prop_traffic_01d` remains available for intersection detection and is handled through the proxy system.

## Traffic-light state mapping

SignalPreempt uses the FiveM/GTA traffic-light override values:

```text
0 = Red
1 = Amber
2 = Green
3 = Reset / no override
```

## Startup log

On resource start, the server console displays the current version from `fxmanifest.lua`, for example:

```text
SignalPreempt | Version v0.1.15
Emergency Vehicle Traffic Signal Pre-emption
Resource started successfully.
```

## Diagnostic commands

### `/spdebug`
Toggles world-space intersection and signal diagnostics.

### `/spstatus`
Shows current emergency-vehicle eligibility, siren state, qualification state, active request, and detected intersection.

### `/spinspect`
Lists nearby traffic-light objects and reports whether each is controlled directly, through the proxy system, or not controlled.


### `/spproxycompare`
With no active pre-emption and the siren off, compares the configured `prop_traffic_01d` proxy candidates one after another. Each candidate is shown green for five seconds and its model dimensions are printed to F8 so pole/arm/head alignment can be compared directly.

### `/spproxies`
Lists currently active `prop_traffic_01d` proxy swaps.

### `/spprobe`
Runs an isolated test of the `01d` proxy strategy near the closest compatible signal.

### `/spcleanup`
Restores active proxy swaps and resets directly controlled traffic-light objects back to normal GTA control.

## Custom emergency lighting resources

A client lighting resource can explicitly set the SignalPreempt emitter state:

```lua
exports['SignalPreempt']:SetEmitterEnabled(true)
exports['SignalPreempt']:SetEmitterEnabled(false)
```

You can query local state with:

```lua
local active = exports['SignalPreempt']:IsPreemptionActive()
local intersection = exports['SignalPreempt']:GetCurrentIntersection()
```

## Configuration

Primary tuning values are in `config.lua`, including acquisition distance, lateral detection width, signal cluster radius, signal heading/alignment threshold, AI traffic stopping distance, emergency vehicle/model allow-lists, and clearance/priority/recovery timings.

## Compatibility notes

SignalPreempt deliberately avoids controlling player-driven civilian vehicles, emergency-class vehicles in the AI braking layer, mission/scripted vehicles by default, and networked vehicles the local client does not control. This reduces the chance of interfering with pursuit resources and other scripted vehicle behaviour.

## Version history

See `CHANGELOG.md` for patch-by-patch development history.
