# Changelog

## v0.1.13
- Updated the GitHub README/version heading to match the actual resource version.
- Rewrote the README around the current SignalPreempt implementation instead of leaving obsolete experimental notes in the main documentation.
- Documented the current `prop_traffic_01d` proxy strategy and diagnostic commands.
- No pre-emption, acquisition-distance, AI traffic, networking, or signal-control behaviour changed from v0.1.12.

## v0.1.12
- Redesigned `prop_traffic_01d` handling instead of applying `SET_ENTITY_TRAFFICLIGHT_OVERRIDE` directly to that model.
- Active `01d` map instances are temporarily swapped to a compatible vanilla `prop_traffic_01a` proxy, the proxy receives the signal override, and the original `01d` is restored when pre-emption ends.
- Added `/spproxies` to inspect active traffic-light proxy swaps.
- Updated `/spprobe` to test the new proxy strategy instead of deliberately overriding `01d` directly.
- Corrected the traffic-light override state mapping to the official FiveM/Cfx values: red `0`, amber `1`, green `2`, reset/no override `3`.
- Startup and `/spcleanup` no longer directly touch `01d` proxy-source models.
- Preserved the established early intersection acquisition, server synchronisation, and AI cross-traffic logic.

## v0.1.11
- Added `/spprobe`, a one-command diagnostic that isolates the nearest `prop_traffic_01d` and cycles it through RESET, GREEN, RED, YELLOW, then RESET.
- The probe prints each state to F8 so the low-mounted ghost glow can be matched to the exact native override state without changing normal SignalPreempt behaviour.
- No acquisition-distance, multiplayer, AI traffic, or normal pre-emption logic was changed from v0.1.10.
- This diagnostic specifically targets the remaining `prop_traffic_01d` rendering issue shown by `/spinspect`.

## v0.1.10
- Restored `prop_traffic_01d` to active signal control after v0.1.8/v0.1.9 proved that excluding it leaves many vanilla approach heads on GTA's normal cycle and makes pre-emption look incomplete.
- Reworked signal application so `SET_ENTITY_TRAFFICLIGHT_OVERRIDE` is only called when an entity's desired state actually changes instead of being re-applied every 200 ms.
- Stopped continuously resetting detection-only traffic-light assemblies while an intersection is active; they are cleaned on resource start/cleanup instead.
- Added `/spstatus` to print vehicle eligibility, siren state, qualification state, current request, active intersection count, and the current candidate intersection.
- Preserved the v0.1.3 acquisition-distance tuning and existing multiplayer/AI control behaviour.

## v0.1.9
- Fixed a Lua syntax error in `config.lua` caused by an uncommented `03a/03b are kept here` note.
- Restored normal loading of the shared configuration and client script.
- No traffic-light detection, acquisition-distance, or override behaviour was otherwise changed from v0.1.8.

## v0.1.8
- Used `/spinspect` field data to isolate the remaining low-mounted ghost lamp to actively overridden `prop_traffic_01d` pole assemblies.
- `prop_traffic_01d` is now detection-only and is explicitly reset instead of being forced by `SET_ENTITY_TRAFFICLIGHT_OVERRIDE`.
- Active signal override is limited to `prop_traffic_01a` and `prop_traffic_01b`.
- Added `prop_traffic_lightset_01` to the reset/inspection set so hidden traffic-light support props can be identified without influencing intersection detection.
- Removed the ineffective entity-light and particle-FX suppression workarounds from v0.1.6/v0.1.7.
- Kept v0.1.3 acquisition timing and AI traffic control unchanged.

## v0.1.7
- Fixed the next rendering layer behind the low-mounted green/amber ghost glow.
- Controlled traffic-light props now remove particle FX attached to that entity while the native traffic-light override is active.
- Keeps particle cleanup entity-scoped so unrelated map/resource effects are not touched.
- Normal GTA rendering is handed back on reset; entity light spots are still restored as before.
- Added `/spinspect` to print the exact nearby traffic-light model names, hashes, coordinates, and whether SignalPreempt is allowed to override them.
- Kept v0.1.3 acquisition distance/tuning unchanged.

## v0.1.6
- Reworked traffic-light rendering to address the low-mounted green/amber glow created by forced traffic-light entities.
- SignalPreempt now suppresses each controlled prop's auxiliary entity light spots/coronas while its traffic-light state is overridden, while keeping the traffic-light emissive state controlled by GTA.
- Restores normal entity lighting automatically when an intersection is released, the resource stops, or a signal is reset.
- Startup cleanup now resets all loaded SignalPreempt traffic-light models rather than only previously excluded models.
- Added `/spcleanup` to manually reset all currently loaded traffic-light overrides and entity light spots during testing.
- Kept the v0.1.3 intersection acquisition tuning unchanged.

## v0.1.5
- Separated traffic-light detection models from models that are actually overridden.
- `prop_traffic_03a` and `prop_traffic_03b` remain usable for intersection detection but are no longer forced with `SET_ENTITY_TRAFFICLIGHT_OVERRIDE`.
- Prevents orphaned green/amber coronas appearing low on traffic-signal poles where no vehicle signal head exists.
- Resets excluded signal assemblies around active intersections so stale overrides from older builds are cleared.
- Debug signal labels now include the traffic-light model suffix to make future model-specific issues easier to identify.

## v0.1.4

- Removed `prop_traffic_02a` and `prop_traffic_02b` from the active traffic-light override set.
- These legacy/beta signal assets can expose orphaned green/yellow emissive bulbs near pole bases when forced by GTA's traffic-light override native.
- Added a one-time client startup reset for the ignored signal models so ghost lamps left by an older build are cleared after restart.
- Kept the standard in-world signal props (`01a`, `01b`, `01d`, `03a`, `03b`) under SignalPreempt control.

## v0.1.3

- Improved early intersection acquisition by requesting GTA path nodes along the emergency vehicle's approach corridor each frame while the emitter is active.
- Changed node probing from one centreline to a multi-lane corridor with lateral probes, reducing missed signal nodes on wide roads.
- Added a safe provisional-centre fallback when a traffic-light node flag is available before an exact node position can be resolved.
- Tuned the effective pre-emption range for a noticeably earlier but not excessive trigger distance.
- Increased the local signal-resolution radius and matching server validation distance for the earlier lock.

## v0.1.2

- Added traffic-light road-node look-ahead so signalised intersections can be acquired before their physical props are fully streamed.
- Increased default acquisition range from 185 m to 240 m and tightened the detection tick for earlier activation.
- Added provisional intersection centring from GTA traffic-light path nodes.
- Removed the large debug spheres that appeared as fake/invisible coloured lights near traffic-light pole bases.
- Debug mode now uses a small intersection crosshair and `[G]` / `[R]` labels positioned near the top of each traffic-light prop.
- Increased nearby light resolution radius and refresh rate.

## v0.1.1

- Added a formatted SignalPreempt startup banner to the FiveM server console.
- Startup banner reads the version directly from `fxmanifest.lua` resource metadata.
- Bumped resource version to `0.1.1`.

## v0.1.0

- Initial standalone SignalPreempt resource.
- Emergency-class and custom-model vehicle eligibility.
- Siren-based automatic activation.
- Dynamic upcoming-intersection detection and traffic-light clustering.
- Server-owned intersection leases and multiplayer state broadcast.
- Conflicting-approach lockout with same-road multi-unit support.
- All-red clearance phase, priority green phase, and recovery yellow/reset.
- Supplemental ambient AI cross-traffic braking.
- Player, emergency, mission-entity, and non-owned vehicle exclusions.
- Custom lighting-resource emitter export.
- Local debug intersection and signal visualisation.
