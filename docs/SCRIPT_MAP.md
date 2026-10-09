# OSF_AutonomousManagerScript — Script Map

> Architecture map of the manager quest script. **Read this BEFORE re-analyzing the .psc** —
> it exists specifically to avoid full-file rescans every session.
> Update this file whenever functions, state vars or timers change.
>
> Source of truth: `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc` (~3200 lines)
> Map generated: 2026-10-09 (v1.2.0-dev, CURRENT_VERSION=4)

## Identity

- `ScriptName OSF_AutonomousManagerScript Extends Quest`
- Manager quest FormID: `0x01000801` (file-local in `OSFAutonomous.esm`, Small Master since v1.2.0)
- `CURRENT_VERSION = 4` — save-migration counter; **bump when adding instance vars**
- Settings mod id: `osf.autonomous` via **OSFSettings** API (NOT OSFUI — removed in OSF UI 2.0)
- User log: `OSF_Autonomous` → `Logs/Script/User/OSF_Autonomous.0.log` via `Log()`

## Timers

| ID | Constant | Purpose |
|---:|:---|:---|
| 1 | `TIMER_ID_SCAN` | Main scan loop, interval = `fCheckInterval` setting |
| 2 | `TIMER_ID_SCENE_TIMEOUT` | `EnforceSceneTimeouts()` periodic check |
| 3 | `TIMER_ID_SETTINGS_RETRY` | Bounded retry of `OSFSettings.RegisterForChanges` (max 3 × 5s at VM thaw) |

## Instance state (serialized into saves!)

Parallel arrays — **alignment invariant**, all indexed by scene position:
- `int[] activeSceneHandles`, `float[] sceneStartTimes`, `Actor[] sceneActorA`, `Actor[] sceneActorB`
- `int[] finaleTriggeredHandles` — handle-based (immune to array shifts)

Cooldowns:
- `Actor[] cooldownActors` + `float[] cooldownEndTimes`
- `String[] pairCooldownKeys` (`"FormID_A:FormID_B"` via `GetPairKey`) + `float[] pairCooldownEndTimes`

Flags/counters:
- `bIsOnShip`, `bSettingsWarned`, `bDependencyNotified`, `iSettingsRetryCount`, `iSceneCallbackToken`, `iTagRotationIndex`
- `iInstalledVersion` (Auto Property = serialized instance var — the migration cursor paired with `CURRENT_VERSION`)
- `managerQuestCache` / `managerQuestLookedUp` — canonical quest probe, resolved once (no `GetFormFromFile` in hot paths)

**INVARIANT:** every new instance var → bump `CURRENT_VERSION` + add reset to migration block in
`OnPlayerLoadGame` + `None`-check in `EnsureArraysInitialized()`. (lessons_learned #16–20 —
a `while` on a `None` array bakes an unkillable stuck thread into the save.)

## Cached forms (loaded once — `InitKeywords` / `InitGearForms`)

- Keywords: `ActorTypeRobot`, `IsSleepFurniture`, `Crew_CrewType{Companion,Generic,Elite}`,
  `ActorType{Human,Child}`, `LocTypePlayer{Outpost,House}`, `AnimFurn{Chair,Bench}`,
  `PlanetAtmosphereType{05O2,06HighO2,07LowO2}`, AV `HideHelmetBreathable`
- Races: `kHumanCrowdRace`, `kMannequinRace` (foreign skeletons — OSF crash risk)
- Factions: `kCurrentCompanionFaction`, `kCurrentCrewFaction` (0x00014312)
- Gear: `Dick.esm` 0x800/0x81B/0x81D/0x820, `Haters Body.esm` 0x804

## Function / event index (line → role)

### Lifecycle
| Line | Member | Role |
|---:|:---|:---|
| 95 | `OnQuestInit` | Init keywords+gear, `RegisterOSFCallbacks`, `RegisterSettingsListener`, start scan |
| 394 | `IsBoundInstance` | `IsBoundGameObjectAvailable()` first, then canonical-quest dedup — variant-safe (LIGHT builds) |
| 597 | `OnOSFSettingChanged` | Settings listener callback (empty key = reread-all); bound-guarded |
| 636 | `EnsureArraysInitialized` | Central `None`-checks for every array |
| 666 | `SyncSceneTracking` | Realigns parallel arrays vs live OSF handles |
| 699 | `OnPlayerLoadGame` | **Order matters:** migration → arrays init → re-register → init keywords → ghost audit → `ResumeScanTimer` |
| 299 | `RegisterOSFCallbacks` | Mask = `EVENT_SCENE_BEGIN + END + CUE + NODE_EXIT` |
| 327 | `RegisterSettingsListener` | Session-scoped `OSFSettings.RegisterForChanges`; bounded retry via TIMER 3 |

### Scan pipeline — `OnTimer` :1030 (`TIMER_ID_SCAN`)
1. Gates: bound instance → `IsEnabled` → location (`IsLocationAllowed` :2799) → ship/combat/menu state.
2. Candidate collection :1136–1227 — `FindAllReferencesWithKeyword` on crew keywords ×3 + `Game.GetPlayerFollowers()` + generic `ActorTypeHuman` scan **only in private player location**. Scan range = `fMaxStartDistance + 200` (dynamic, see lessons #22). Player excluded at collection time.
3. `IsActorEligible` :1354 per candidate.
4. Wave loop :1254 — per wave: chance roll (`iChancePercent`; a failed roll ends the wave) → random pair search (≤10 attempts; checks pair distance, `fMaxZOffset`, `IsPairOnCooldown`, used-this-tick; top rejection reason is logged) → `TryStartScene` :1558 or `TryStartSoloScene` :2149. Cap = `GetMaxConcurrent()`, pool capped at 3 eligible actors (SF-TIK-011, by design).

### `IsActorEligible` :1354
sit/sleep states, robot/child/crowd/mannequin exclusion, crew guards (`IsPlayerTeammate` OR
`CurrentCrewFaction` — recruited unassigned crew OK), `GetRelationshipRank` cached once (TODO-001),
romance exclusivity guard + polyamory bypass.

### `TryStartScene` :1558 — tiered OSF query fallback
1. Distance/spacing guards (`fMaxStartDistance`, `fMinSceneSpacing`, active-scene proximity).
2. Furniture anchor via `FindNearbyFurniture` :2251 — chair/bench keywords, cap 15 nearest.
3. Role order: `standardOrder [m,f]` (GE convention) vs `femdomOrder [f,m]` (SnuSnu) — lessons #24.
4. Query tiers (tags built by `BuildQueryTags` :3110 / `BuildQueryTagsWithPack` :3143):
   `t1` furniture+action → `t2` furniture generic → `t3` standing/floor (ge → snusnu → catch-all → ff→mf) → `t4`/`t45` position-only fallbacks. Unanchored tiers require explicit `standing`/`floor` tags (SF-TIK-007).
5. `OSF.StartScene` → append tracking arrays → `StartSceneTimeoutTimer` :2529.
   `StripMode` follows the scene that *actually* started (SF-TIK-010).

### Scene events — `OnSceneEvent` :412
- `BEGIN`: participants, `CalculateInitialSpeed` :3179, optional stage/edge advance.
- `CUE` / `NODE_EXIT`: +0.15 speed bump; finale detection → `finaleTriggeredHandles`.
- `END`: duration log, `ApplyCooldownToActor` :2645 + `SetPairCooldown` :3000, `UnequipStuckAttachments` :261.

### Teardown paths
- `EmergencyStopAll` :2319 — snapshot arrays → `OSF.StopScene` each → unequip gear → clear. Called from `OnLocationChange` :781 (space/exterior transitions), ship events `OnShipGravJump` :958 / `OnShipTakeOff` :978 / `OnShipDock` :994 / `OnShipLanding` :1010, `OnCombatStateChanged` :936, disable path.
- `AuditActiveScenes` :2364 — ghost-scene cleanup on load; falls back to tracked actors when `OSF.GetSceneParticipants` returns empty.
- `EnforceSceneTimeouts` :2534 — per-handle timeout (`fSceneTimeoutMinutes`), player walk-in (`bStopOnPlayerWalkIn` + `fWalkInDistance`), natural-finale grace (`fFinaleGracePeriod`).

### Location / misc events
`OnLocationChange` :781, `OnMenuOpenCloseEvent` :820, `OnSit` :839, `OnEnterShipInterior` :854,
`OnExitShipInterior` :887. Ship ownership = `Game.IsPlayerSpaceshipOwner()` (`IsPlayerInOwnShip` :2730) — SF-TIK-008.

### Settings getters :2829–2972 (~40 wrappers)
All read `OSFSettings.Get*` with hardcoded fallbacks; keys must exist in the
`osf.autonomous.json` schema. Declared-but-unwired upstream concepts: `fMinStartDistance`,
`bProximityShield` (no behavior — do not "fix" without a ticket).

## Hot rules when editing this file
- Never `while` without a safety counter; never call `.Length`/`.Add` on possibly-`None` arrays.
- No `Game.GetFormFromFile` in timers/events — cache in `Init*()`.
- Every event/timer entry point must be bound-guarded (`IsBoundInstance`).
- Event handlers must not revive the scan timer while the mod is disabled.
- `InPlaceMode = OSF.OFF()` for BOTH paired and solo scenes — OSF semantics are inverted vs the name: `ON` *disables* pinning, `OFF` keeps the root/heading lock so actors don't drift (`soloOpts` comment ~line 2231). On paired scenes `ON` additionally skips position alignment → instant abort (lessons #21).
- Never modify third-party packs (`snusnufield.osf.json` etc.) — solve in this script (lessons #24).
