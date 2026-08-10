# Changelog

## v0.1.38
- Repository/documentation maintenance release built on the tested v0.1.37 runtime.
- Rewrote `README.md` around the current guaranteed-housing architecture instead of obsolete world-swap/proxy experiments.
- Documented current installation, configuration, exports, diagnostics, server synchronisation, AI handling, performance defaults and verified traffic-light state mapping.
- Corrected stale `config.lua` comments that still described v0.1.27/v0.1.36 model-swap behaviour.
- Restored missing historical changelog entries for v0.1.20, v0.1.21 and v0.1.22.
- Added a repository `.gitignore` for packaged releases and common editor/OS files.
- No traffic-control, acquisition, canonicalisation, AI, networking, signal-state, or guaranteed-housing runtime behaviour changed from v0.1.37.

## v0.1.37
- Removed per-pole `CreateModelSwap` 01d normalisation after field testing found occasional detached lamp/corona artifacts.
- Added guaranteed-housing normalisation: create and verify a persistent `prop_traffic_01b` first, then hide the source `prop_traffic_01d`.
- Replacement housings are marked mission entities, forced visible, given a long LOD distance, frozen and collision-enabled.
- If a replacement housing disappears, SignalPreempt removes the source model hide before rebuilding it, preventing a no-housing state.
- Source `01d` objects remain detection-only and are never directly overridden.
- Nearby-light detection substitutes the verified clean `01b` housing for its source `01d`.
- `/spfallbacks` now reports housing existence and source-hide state.
- Preserves 300 m acquisition, 340 m server request ceiling, canonical grouping, stable 20 m IDs, complete junction control, active-state refresh, AI handling and server synchronisation.

## v0.1.36
- Removed the broad 12 km `prop_traffic_01d -> prop_traffic_01b` model swap.
- Every streamed `01d` now receives its own exact-location 2.25 m `CreateModelSwap`.
- No manual traffic-light source hiding is used.
- No scripted traffic-light housing/proxy objects are used.
- Reduced 01d discovery interval to 100 ms.
- Reduced traffic-light pool refresh from 900 ms to 350 ms.
- Added 450 ms active-junction light re-resolution so newly swapped `01b` heads join control almost immediately.
- Increased server request-distance ceiling from 285 m to 340 m to support the 300 m client acquisition range.
- Updated diagnostics for the per-pole normalisation architecture.
- Preserves canonical grouping, stable 20 m IDs, complete junction control, active-state refresh, AI handling and server synchronisation.

## v0.1.35
- Replaced the stubborn-`01d` manual hide + scripted `01b` proxy fallback with exact-location `CreateModelSwap`.
- Removed `SetEntityVisible`, alpha-zero, and collision suppression from stubborn traffic-light handling.
- Removed scripted `CreateObjectNoOffset` traffic-light replacements that could leave detached emissive/corona orbs.
- Stubborn locations now reinforce the global `01d -> 01b` replacement through a tiny persistent local model swap.
- `/spfallbacks` now reports local model swaps rather than proxy entities.
- `/spinspect` reports any still-streamed raw `01d` as `local-swap-pending`.
- Preserves 300 m acquisition, canonical grouping, stable 20 m IDs, complete junction control, targeted active-state refresh, AI handling and server synchronisation.

## v0.1.34
- Reduced stubborn-`01d` detection interval from 500 ms to 175 ms.
- Preloads the clean `prop_traffic_01b` fallback model during startup.
- Runs an immediate stubborn-`01d` maintenance pass after global model-swap registration.
- Keeps discovered stubborn fallback locations for the full client session instead of removing them after travelling away.
- Reasserts exact-location model hides and recreates missing fallback proxies automatically.
- `/spfallbacks` now reports session persistence and scan interval.
- Preserves global `01d -> 01b` model swapping, canonical grouping, stable IDs, 300 m early acquisition, active-state refresh, AI handling and server synchronisation.

## v0.1.33
- Added a targeted fallback for rare `prop_traffic_01d` instances that survive the global world model swap.
- Registers an exact-location `CreateModelHide` for the surviving source and creates one clean `prop_traffic_01b` replacement at the same transform.
- The original `01d` is never passed to `SetEntityTrafficlightOverride`.
- Fallback locations are cached by quantised coordinates to survive GTA entity-handle changes without duplication.
- Nearby-light detection substitutes the clean fallback `01b` for the hidden source, allowing the full junction to participate in canonicalisation and control.
- Added `/spfallbacks`; `/spinspect` labels a surviving raw `01d` as `fallback-source`.
- Preserves the global v0.1.27 world swap, canonical grouping, stable IDs, targeted refresh, earlier acquisition and server/AI logic.

## v0.1.32
- Increased emergency intersection acquisition from 210 m to 300 m.
- Increased path-node request look-ahead/padding and light-pool radius so priority can be established much earlier at response speed.
- Kept the 1.2 second all-red clearance phase.
- Added a 60 m one-hop junction-control fringe around the existing 42 m core radius.
- Fringe lights are included only when within 34 m of a confirmed core light, reducing the risk of controlling a neighbouring real intersection.
- Added `prop_traffic_01b` to the targeted 400 ms active-state refresh so every direct-safe head is continually reasserted while priority is active.
- `prop_traffic_01d` remains excluded from direct overrides and continues to use the v0.1.27 world model swap.
- Preserves canonical grouping, stable 20 m identity IDs, AI traffic handling and server synchronisation.

## v0.1.31
- Added targeted periodic state refresh for `prop_traffic_01a`.
- Reasserts the active desired state every 400 ms only for configured refresh models, fixing cases where an `01a` head can visually fall dark despite still being assigned `RED(1)` or `GREEN(0)`.
- `prop_traffic_01b` remains change-only and the v0.1.27 `01d -> 01b` world model swap is unchanged.
- `/spdecisions` now reports `refresh=targeted` or `refresh=change-only`.
- No canonical intersection grouping, identity-grid, approach classification, AI traffic, or server synchronisation logic was changed.
- Preserves verified signal mapping (`0=green`, `1=red`, `2=yellow`, `3=reset`).

## v0.1.30
- Added `/spdecisions` for one-shot per-signal diagnostics on the current active intersection.
- Reports model, entity, heading, alignment, parallel classification, priority/conflict classification, desired state, distance and coordinates for every controlled light.
- The diagnostic reuses the exact `signalShouldBeGreen()` logic used by live signal control.
- No traffic-light control behaviour was changed.
- Preserves v0.1.27 world model swapping, v0.1.28 canonical grouping, v0.1.29 stable 20 m intersection IDs, AI handling and server synchronisation.
- Preserves verified state mapping (`0=green`, `1=red`, `2=yellow`, `3=reset`).

## v0.1.29
- Increased `IntersectionIdGrid` from 10 m to 20 m to stabilise server/inter-client intersection IDs.
- Fixes cases where an early traffic-light-node centre and later canonical prop centre represent the same physical junction but previously rounded to different IDs.
- Verified against Vinewood/Alta: `205.75, 193.92` and `203.04, 195.30` both resolve to `10:10`.
- Precise canonical XYZ centres remain unchanged for signal selection, approach geometry, distance checks and AI handling.
- Does not broaden physical-junction clustering, so it does not intentionally merge nearby real intersections.
- Preserves v0.1.27 `prop_traffic_01d -> prop_traffic_01b` world model swap.
- Preserves v0.1.28 canonical intersection grouping.
- Preserves verified signal mapping (`0=green`, `1=red`, `2=yellow`, `3=reset`) and server synchronisation.

## v0.1.28
- Added deterministic large-intersection canonicalisation without changing the v0.1.27 world model-swap architecture.
- Keeps the existing 36 m seed cluster for approach acquisition, then expands around the raw cluster centre to resolve all signal groups belonging to the same physical junction.
- Added geometric span/radius checks with outlier pruning to reduce the risk of merging a nearby separate intersection.
- Server request IDs and centres are now generated from the canonical physical-junction centre when enough streamed signal geometry is available.
- Added a dedicated `IntersectionControlRadius` so all signals in a canonicalised junction are controlled without enlarging the seed detector.
- Traffic-light node candidates are also canonicalised against streamed signal geometry when available.
- `/spstatus` now reports raw and canonical candidate IDs/centres when they differ.
- Removed an obsolete unused proxy-era helper.
- Preserves the v0.1.27 `prop_traffic_01d -> prop_traffic_01b` world model swap, verified signal mapping (`0=green`, `1=red`, `2=yellow`, `3=reset`), early acquisition, AI cross-traffic handling and server synchronisation.

## v0.1.27
- Replaced the v0.1.26 runtime `01d` hide + script-created `01b` system with FiveM/GTA world model swaps.
- Registers `prop_traffic_01d -> prop_traffic_01b` at streaming level across the configured world swap volume.
- Removed the recurring 700 ms `01d` normalisation scan, far-distance proxy cleanup threads, and the obsolete runtime entity-proxy implementation.
- Emergency pre-emption now changes only the lamp state of already-streamed `01b` traffic lights; pole geometry no longer swaps when an emergency vehicle approaches.
- Original `prop_traffic_01d` remains excluded from direct traffic-light override control.
- Added `/spswaps`; `/spproxies` remains as a backwards-compatible alias.
- Reworked `/spprobe` to test a clean nearby `01b` directly instead of creating a temporary proxy.
- `/spcleanup` now resets signal overrides without removing the world model swap.
- World model swaps are removed cleanly when the resource stops.
- Preserves verified mapping (`0=green`, `1=red`, `2=yellow`, `3=reset`), early acquisition, AI cross-traffic handling, and server synchronisation.

## v0.1.26
- Removed the experimental `prop_traffic_03b` turn-head shell and all `/spturn*` tuning commands.
- Added proactive `prop_traffic_01d -> prop_traffic_01b` normalisation for every loaded/streamed `01d`.
- The clean `01b` is now already present before an emergency vehicle approaches, so players do not see the turn-head disappear when pre-emption begins.
- Priority changes only the traffic-light state of the already-present proxy.
- After recovery, the same `01b` returns to normal GTA traffic-light control and remains in place.
- Added far-distance cleanup so persistent local proxies do not accumulate indefinitely while travelling around the map.
- Script-created `01b` proxies are excluded from SignalPreempt's intersection-detection pool.
- Preserves verified state mapping (`0=green`, `1=red`, `2=yellow`, `3=reset`), early acquisition, AI cross-traffic handling and server synchronisation.

## v0.1.25
- Fixed `/spturnoffset` and `/spturnrotation` selecting an arbitrary active shell when multiple `01d` proxies were loaded.
- Turn-shell tuning now targets the nearest loaded shell to the local player, preferring active over parked shells.
- Added `/spturntarget` to print the exact shell target, distance, coordinates, proxy entity, shell entity, and model.
- Alignment query/change commands now print their selected target for unambiguous live testing.
- `/spstatus` now notes that multiple active intersections may legitimately belong to other emergency vehicles/players.
- No changes to pre-emption acquisition, signal phasing, `01d -> 01b` functional proxy behavior, parked-proxy release, AI traffic handling, or server synchronisation.

## v0.1.24
- Locked `prop_traffic_03b` as the only visual turn-head shell and removed the experimental `03a` comparison path.
- Keeps the clean v0.1.19 functional architecture: original `01d` hidden, `01b` controlled, `03b` visual-only.
- Added `/spturnoffset <x> <y> <z>` for live local-space shell alignment.
- Added `/spturnrotation <x> <y> <z>` for live shell rotation alignment.
- Both alignment commands rebuild only the visual shell and do not touch acquisition, signal phasing, server state or AI traffic.
- `/spstatus` now distinguishes `activeRequest` from `detectedCandidate` when they differ.
- Preserves verified signal mapping, parked-proxy release behaviour, early acquisition, AI cross-traffic handling and server synchronisation.

## v0.1.23
- Rebased turn-head work on the clean v0.1.19 functional baseline.
- Keeps the original map `prop_traffic_01d` completely hidden and never overrides it.
- Keeps `prop_traffic_01b` as the only functional signal proxy.
- Uses smaller `prop_traffic_03b` as the default un-overridden visual turn-head shell instead of reusing `01d`, avoiding the known `01d` emissive overlap problem.
- Added `/spturncompare` to compare `prop_traffic_03b` and `prop_traffic_03a` for turn-head geometry while pre-emption remains active.
- Visual shells are excluded from signal detection and have collision, entity lights and attached particle FX suppressed.
- Preserves verified state mapping, parked-proxy release behaviour, early acquisition, AI cross-traffic handling, and server synchronisation.

## v0.1.22
- Tested a script-owned `prop_traffic_01d` visual shell alongside the functional clean `01b` proxy.
- Confirmed that simply recreating `01d` as a script-owned visual object does not make it safe as a cosmetic shell; its traffic-light emissive behaviour can still render unwanted signal state.
- Kept direct traffic-light override off the `01d` shell.
- This experimental path was superseded by the later `03a`/`03b` visual-shell tests and then removed entirely.

## v0.1.21
- Tested suppressing the original `prop_traffic_01d` auxiliary/entity lighting with `SetEntityLights(false)` while retaining the clean `01b` functional proxy.
- Confirmed that disabling ordinary entity lights does not suppress the traffic-light emissive/corona state responsible for the overlap/ghost behaviour.
- No change to the verified native state mapping or core acquisition/server logic.

## v0.1.20
- Tested a hybrid approach that kept the original `prop_traffic_01d` visible while a clean `prop_traffic_01b` handled functional pre-emption.
- Field testing showed overlapping signal states (for example the original red remaining visible while the proxy displayed green), so the hybrid was not suitable as the final visual solution.
- Preserved the rule that raw `01d` must not receive the traffic-light override directly.
- This experiment was superseded by the visual-shell work in v0.1.21-v0.1.25.

## v0.1.19
- Reverted the traffic-light state ordering to the values repeatedly confirmed by in-game testing on the user's current FiveM/GTA build: `0 = green`, `1 = red`, `2 = amber/yellow`, `3 = reset`.
- This targets the v0.1.12-v0.1.18 regression where SignalPreempt reported `priority` correctly but the visible signal stayed amber because the script was sending state `2` as green.
- Keeps the v0.1.18 parked-proxy workaround so the original `prop_traffic_01d` low/turn lamp does not immediately reappear after the emergency vehicle clears the intersection.
- Keeps proxy state force-refresh, early acquisition distance, server locking, AI cross-traffic handling, and the local `01d -> 01b` proxy strategy unchanged.

## v0.1.18
- Force-refreshes the traffic-light override on script-created `01b` proxies while an intersection is actively controlled, targeting the reported condition where the visible signal drifted/stayed amber despite an active siren/pre-emption request.
- Keeps a released `01d -> 01b` proxy parked and reset while the player remains near the intersection instead of immediately restoring the original `01d`.
- Restores the original `01d` only after the proxy has been idle for at least 3.5 seconds and the player is at least 155 metres away.
- This prevents the original low/turn lamp from visibly reappearing immediately after the emergency vehicle clears the junction.
- `/spproxies` now reports each proxy as `active` or `parked`.
- `/spstatus` now includes the current intersection phase(s).
- Early acquisition distance, server locking, traffic-direction classification, and AI cross-traffic logic are unchanged.

## v0.1.17
- Replaced the `CREATE_MODEL_SWAP`-based `prop_traffic_01d` workaround with a script-created local proxy.
- The original `01d` map object is hidden locally while a `prop_traffic_01b` object is created at the same position/rotation and receives the traffic-light override.
- The proxy is deleted and the original `01d` visibility/collision are restored when pre-emption ends.
- This specifically targets the final floating red/amber/green corona that remained in v0.1.16, which appeared to survive the model-swap and auxiliary-light suppression approach.
- Keeps `01d` itself completely free of `SET_ENTITY_TRAFFICLIGHT_OVERRIDE`.
- Preserves early intersection acquisition, traffic phasing, multiplayer state, and AI cross-traffic handling.

## v0.1.16
- Locked `prop_traffic_01b` as the permanent proxy for `prop_traffic_01d` after the in-game geometry comparison.
- Removed the experimental `prop_traffic_01a` proxy candidate and `/spproxycompare`.
- Suppresses the `01b` proxy entity's auxiliary light while SignalPreempt is forcing the traffic-light state, targeting the final small floating amber/green corona while retaining the signal face.
- Re-enables the proxy's normal entity lights immediately before restoring the original `01d`.
- Preserves the established early acquisition distance, traffic phasing, server synchronisation, AI cross-traffic handling, and model-swap strategy.

## v0.1.15
- Changed the default `prop_traffic_01d` geometry proxy from `prop_traffic_01a` to `prop_traffic_01b` for a closer visual match while retaining the ghost-lamp workaround.
- Added `/spproxycompare` to compare `01b` and `01a` on the nearest `01d` pole in a single test; each candidate is shown green for five seconds.
- `/spproxycompare` also prints source/candidate model dimensions to F8 for geometry comparison.
- Preserved the confirmed `01d` ghost-light fix, early acquisition tuning, AI traffic control, networking, and signal-state mapping.

## v0.1.14
- Fixed `fxmanifest.lua` after v0.1.13 accidentally set `fx_version` to the package version number.
- Restored the valid FiveM manifest declaration `fx_version 'cerulean'`.
- Set the resource metadata version to `0.1.14`.
- No SignalPreempt traffic-light, acquisition, AI traffic, proxy, networking, or pre-emption behaviour changed from v0.1.12/v0.1.13.

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
