# v1.2.0 — unreleased — Location Gating & Lifecycle Hardening

## Bug fixes
- Migrated all settings reads to the new `OSFSettings` plugin API (SF-TIK-009 — P1 hotfix). OSF UI 2.0 removed `OSFUI.GetBool/GetInt/GetFloat/GetString/RegisterForSettingChanges/Unregister`; every settings call failed with `Static function not found`, `IsEnabled()` evaluated to false, and the scan timer never started — the mod was completely dead. All 20 readers now call `OSFSettings.Get*`/`GetEnum`, the listener uses session-scoped `OSFSettings.RegisterForChanges` with the fixed `OnOSFSettingChanged` callback (empty key = reread-all, re-evaluating enable + location gates), startup retries registration bounded (3×5s) so the transient init race at VM thaw cannot permanently disable the mod — retry eligibility no longer depends on OSF UI at all, because OSF Settings is a standalone plugin — and once retries are exhausted a one-time in-game notification plus an OSF Settings "Mod Issues" entry tell the player exactly what is wrong (`OSFUI.GetVersion`/`GetVersionString` pick the message: outdated OSF UI vs missing OSFSettings). **Requires OSF UI 2.0+.**
- Fixed ship ownership detection (SF-TIK-008): the own-ship check compared the cell's parent reference to `GetCurrentShipRef()`, which returns that same cell parent inside ANY vessel — so every ship interior (e.g. the Deimos showroom ship, boarded NPC ships, docked vessels) was treated as the player's own and companions could pair with random NPC clients aboard. Ownership now uses `Game.IsPlayerSpaceshipOwner()` in `IsPlayerInOwnShip`, `OnEnterShipInterior` and `OnExitShipInterior`.
- Scene lifecycle hardening: ghost scenes are audited once on load, participant lookups happen before `StopScene`, parallel tracking arrays stay aligned, and emergency stops snapshot actors before clearing.
- Fixed strip-mode intent leak (SF-TIK-010): `StripMode=OFF` was decided once from the intended action, but action-agnostic fallback tiers (generic furniture, standing/floor catch-alls) can start an explicit scene instead — actors then stayed fully dressed and no gear was equipped. Strip mode now follows the scene that actually started: foreplay-matched queries keep actors dressed for kissing, generic tiers use the configured strip mode.
- Gear-plugin diagnostics (SF-TIK-010 follow-up): when none of the known strap-on/erection plugins resolve at load (Dick.esm, Haters Body.esm), a warning is posted to OSF Settings "Mod Issues" explaining that paired scenes will play without auto-equipped gear and how to fix it (install a gear mod or point pack `equip` strings at gear you have). Cleared automatically once gear resolves.
- Ghost-instance detection is now variant-safe: `IsBoundInstance()` leads with the native `IsBoundGameObjectAvailable()` check and only then de-duplicates against the canonical quest record — a mod variant whose manager quest has a different FormID (e.g. a LIGHT build) can no longer mark its own bound instance as a ghost and silently disable itself. The canonical-quest probe is resolved once and cached (previously `Game.GetFormFromFile` ran on every call — and `IsBoundInstance` is called from `OnTimer` and every event entry point). The settings retry/notification state also resets on every load (persisted script vars could otherwise grant zero retries or swallow the dependency alert for the rest of the save's life), and `OnOSFSettingChanged` is bound-guarded like every other event entry point.
- Wave diagnostics and player exclusion (SF-TIK-011): a failed chance roll is now logged even when no scene has started yet (previously the log only appeared when at least one scene had already begun, so chance-terminated ticks looked like "no compatible actors"); the random pair search reports its top rejection reason (already used this tick / pair cooldown / distance / Z offset / actor base / gender) instead of silently retrying 10x; and the player is excluded at candidate-collection time instead of being collected and silently rejected by the eligibility check every tick. Wave semantics are unchanged - a failed roll still ends the wave.
- Settings parity (SF-TIK-011 follow-up): `fCheckInterval`, `fSceneTimeoutMinutes`, `fPairCooldownMinutes`, `fMaxStartDistance`, `fMaxZOffset`, `fWalkInDistance` and `bSoloPrivateOnly` are now read from settings (previously hardcoded fallbacks) and declared in the settings schema, so values set in OSF Settings now actually take effect. Setting `fMaxZOffset` to 0 disables the vertical-distance pair check. `fMinStartDistance` and `bProximityShield` remain declared-but-unwired upstream concepts (documented, no behavior change).
- Save/load migration to tracking version 4 no longer wipes tracked actors (gear/cooldown cleanup still reaches them).
- Furniture queries sanitized; unanchored fallbacks require explicit position tags so actors no longer float (SF-TIK-007).
- `OSFAutonomous.esm` is now a Small Master, freeing a full plugin slot (SF-TIK-003).
- Added `None` guards on `GetLeveledActorBase()` results; minor performance cleanups (single `GetRace` call, removed per-tick log spam).

## Performance & build
- Scan timer restarts are gated on the mod being enabled; event handlers no longer revive the scan while disabled.

## Dev tooling (not shipped in the ZIP)
- `tests/papyrus/OSF_E2ETests.psc` — console-driven in-game E2E harness (`bat osfe2e`, or `cgf "OSF_E2ETests.RunAll"`): forces an FF scene through the production `TryStartScene` path and asserts the strap-on lands on the 'm' role (`IsEquipped` on `Dick.esm|0x81D`), demonstrates the eligibility-pool concurrency cap, echoes OSFSettings wiring, and verifies stuck-gear cleanup. Deploy via `tests/papyrus/deploy_e2e.ps1`.

## Affected files
- `Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
- `Data/Scripts/OSF_AutonomousManagerScript.pex`
- `Data/OSFAutonomous.esm`
- `Data/SFSE/Plugins/OSFUI/settings/osf.autonomous.json`

# v1.1.2 — 2026-09-19 — Packaging Hotfix 2

## Build & deployment
- Corrected the `tar` packaging script which previously prefixed all internal zip paths with `./`, causing Mod Organizer 2 FOMOD extraction errors (SF-TIK-004).

# v1.1.1 — 2026-09-19 — Packaging Hotfix

## Build & deployment
- Migrated the build script to use 7-Zip instead of PowerShell `Compress-Archive` to prevent Mod Organizer 2 and Vortex from incorrectly flattening the directory structure upon installation (SF-TIK-002). No mod files were changed, only the ZIP packaging method.

# v1.1.0 — 2026-09-15 — Furniture Discovery & Crew Eligibility Fixes

## Bug fixes
- Furniture discovery now finds all common furniture types, not only beds: chairs, couches, benches, stools, bar stools, desk/table chairs, beds, and cockpit seats. Previously only `IsSleepFurniture` was searched, so most Gergel Ebanex furniture scenes never had a chance to trigger.
- FF pairs can now use MF-tagged furniture scenes from external packs via gender fallback, matching the existing standing-scene fallback.
- Recruited ship/outpost crew are no longer rejected by the crew guard. The old guard required `IsPlayerTeammate()` to be true, which only covers the active follower. We now accept actors in `CurrentCrewFaction`, so recruited but unassigned crew on your ship/outpost are eligible while still rejecting random NPCs with crew keywords in cities.
- Stuck attachment cleanup (`Dick.esm` / `Haters Body.esm`) now runs reliably in every emergency and timeout path. Previously the script cleared the internal scene handle before calling `OSF.StopScene()`, so the scene-end callback could not find the scene and skipped `UnequipStuckAttachments()`. The script now tracks scene participants itself and unequips before clearing handles.
- After save+quit mid-scene, ghost scenes are properly cleaned up on the next load. Tracked participants are unequipped even when `OSF.GetSceneParticipants()` returns an empty array.
- Removed empty placeholder sound pools from `osfautonomous-solo.sounds.json` that caused OSF sound-validator pack-load errors (SF-TIK-001).

## Performance & build
- Capped furniture candidate search to the 15 closest pieces to avoid multi-minute hangs in dense cells like Cydonia that can contain 80+ furniture refs.

## Affected files
- `Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
- `Data/Scripts/OSF_AutonomousManagerScript.pex`
- `Data/OSF/osfautonomous-solo.sounds.json`
