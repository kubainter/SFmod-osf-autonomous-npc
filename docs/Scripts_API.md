# OSF Autonomous Manager Script API & Architecture

This document preserves the structural knowledge, limitations, and engine workarounds that govern the `OSF_AutonomousManagerScript` and its related testing harnesses. It acts as a reference to prevent regressions during future optimizations.

## Core Architecture

The `OSF_AutonomousManagerScript` is a pure Papyrus manager (no C++ DLL required) that extends `Quest`.
It scans for eligible NPC pairs during idle/sandbox situations and triggers OSF Animation scenes via OSF UI JSON settings.

### State Management
State is managed via parallel arrays (such as `activeSceneHandles`, `sceneStartTimes`, `sceneActorA`, `sceneActorB`, etc.).
- **Array Skew & Saves**: Process uptime (e.g., `Utility.GetCurrentRealTime()`) is used for timestamps. When a save is loaded, pre-restart timestamps become stale. The `SyncSceneTracking()` method realigns array lengths and resets timestamps on load to prevent bogus elapsed durations that could cause immediate, incorrect scene timeouts.
- **Ghost Instances**: Stale instances of the script attached to older quest records can persist in saves. The `IsBoundInstance()` function ensures that only the canonical, bound quest instance processes events. Unbound instances fast-fail to prevent log spam.

### OSF Settings (MCM)
- Handled via `OSFSettings`.
- Registrations (`RegisterForChanges`) are session-scoped and must be renewed on every `OnPlayerLoadGame` and `OnQuestInit`.
- Missing `OSFSettings` plugin logic incorporates bounded retries at VM thaw.

## Critical Engine Workarounds & Ticket Histories

### Location & Ship Ownership (SF-TIK-008)
- `GetCurrentShipRef()` reports the ship the player is currently inside (including stations, docked ships, and enemy vessels), *not* necessarily a ship they own.
- When validating private locations, the logic must verify against `Game.IsPlayerSpaceshipOwner(ship)`.
- Checking outposts and player homes relies on specific location keywords (`LocTypeOutpost` and `LocTypePlayerHouse`).

### Skeleton Compatibility
- **Crowds & Mannequins**: The script aggressively blocks actors with `HumanCrowdRace` and `MannequinRace`. Attempting to play OSF animations on these non-standard skeletons risks severe engine crashes.
- **Robots**: Checked both on the actor level (`Actor.HasKeyword(ActorTypeRobot)`) and the race level.

### Furniture & Anchors (SF-TIK-007)
- Gathering furniture for scene anchors strictly queries beds (`IsSleepFurniture`), couches (`AnimFurnBench`), and standalone chairs (`AnimFurnChair`).
- Bar stools, tables, and cockpit seats were explicitly removed because they produce massive rejection spam in dense interiors.
- Unanchored/standing scenes carry explicit position tags (like `standing` or `floor`) because OSF could match bed animations by mistake, causing actors to float.

### Gear / Attachment Logic (SF-TIK-010)
- FF (Female/Female) scenes require strap-on logic handled via external gear (e.g., `Dick.esm`, `Haters Body.esm`).
- If built-in stripping/restore routines fail, `UnequipStuckAttachments()` forces removal of specific known gear to prevent actors from permanently wearing scene props in standard gameplay.

### Concurrency Limit (SF-TIK-011)
- The MCM property `iMaxConcurrentScenes` acts as a hard ceiling, but actual concurrency is governed by geometric constraints.
- `fMinSceneSpacing` prevents two distinct pairs from choosing spots too close to each other, so dense groups of eligible actors will gracefully halt scene instantiation even if the concurrency cap hasn't been met yet.

## Lifecycle Events

- **Transitions**: Any menu action capable of saving the game (e.g., `PauseMenu`) instantly forces an `EmergencyStopAll()` to ensure no mid-scene state is serialized into a manual save or quicksave.
- **Ship transitions**: Scenes are stopped gracefully during ship takeoffs, landings, grav jumps, and docking sequences.
- **Timeout Enforcement**: Enforced via a 30-second ticking loop running off real-time. Checks `IsNaturalFinale()` during the last moments of a timeout to transition the animation cleanly before stopping it.
