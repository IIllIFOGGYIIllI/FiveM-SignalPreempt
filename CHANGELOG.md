# Changelog

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
