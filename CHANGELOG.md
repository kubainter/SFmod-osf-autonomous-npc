# OSF Autonomous NPC Interactions — Changelog

All notable changes to this project will be documented in this file.

---

# v1.2.0 — 2026-10-09 — Location Gating & Lifecycle Hardening

## Bug fixes
- **Migrated all settings reads to the new `OSFSettings` plugin API (SF-TIK-009 — P1 hotfix).** OSF UI 2.0 removed `OSFUI.GetBool/GetInt/GetFloat/GetString/RegisterForSettingChanges/Unregister`; every settings call failed with `Static function not found`, `IsEnabled()` evaluated to false, and the scan timer never started — the mod was completely dead. All 20 readers now call `OSFSettings.Get*`/`GetEnum`, the listener uses session-scoped `OSFSettings.RegisterForChanges` with the fixed `OnOSFSettingChanged` callback (empty key = reread-all, re-evaluating enable + location gates), startup retries registration bounded (3×5s) so the transient init race at VM thaw cannot permanently disable the mod — retry eligibility no longer depends on OSF UI at all, because OSF Settings is a standalone plugin — and once retries are exhausted a one-time in-game notification plus an OSF Settings "Mod Issues" entry tell the player exactly what is wrong (`OSFUI.GetVersion`/`GetVersionString` pick the message: outdated OSF UI vs missing OSFSettings). **Requires OSF UI 2.0+.**
- Fixed ship ownership detection (SF-TIK-008): the own-ship check compared the cell's parent reference to `GetCurrentShipRef()`, which returns that same cell parent inside ANY vessel — so every ship interior (e.g. the Deimos showroom ship, boarded NPC ships, docked vessels) was treated as the player's own and companions could pair with random NPC clients aboard. Ownership now uses `Game.IsPlayerSpaceshipOwner()` in `IsPlayerInOwnShip`, `OnEnterShipInterior` and `OnExitShipInterior`.
- Scene lifecycle hardening: a per-tick `AuditActiveScenes` pass (plus once on load) reaps ghost scenes that lost their participants, participant lookups happen before `StopScene`, parallel tracking arrays stay aligned, and emergency stops snapshot actors before clearing.
- Fixed strip-mode intent leak (SF-TIK-010): `StripMode=OFF` was decided once from the intended action, but action-agnostic fallback tiers (generic furniture, standing/floor catch-alls) can start an explicit scene instead — actors then stayed fully dressed and no gear was equipped. Strip mode now follows the scene actually started: foreplay-matched queries keep actors dressed for kissing, generic tiers use the configured strip mode.
- Gear-plugin diagnostics (SF-TIK-010 follow-up): when none of the known strap-on/erection plugins resolve at load (Dick.esm, Haters Body.esm), a warning is posted to OSF Settings "Mod Issues" explaining that paired scenes will play without auto-equipped gear and how to fix it (install a gear mod or point pack `equip` strings at gear you have). Cleared automatically once gear resolves.
- Ghost-instance detection is now variant-safe: `IsBoundInstance()` leads with the native `IsBoundGameObjectAvailable()` check and only then de-duplicates against the canonical quest record — a mod variant whose manager quest has a different FormID (e.g. a LIGHT build) can no longer mark its own bound instance as a ghost and silently disable itself. The canonical-quest probe is resolved once and cached (previously `Game.GetFormFromFile` ran on every call — and `IsBoundInstance` is called from `OnTimer` and every event entry point). The settings retry/notification state also resets on every load (persisted script vars could otherwise grant zero retries or swallow the dependency alert for the rest of the save's life), and `OnOSFSettingChanged` is bound-guarded like every other event entry point.
- Wave diagnostics and player exclusion (SF-TIK-011): a failed chance roll is now logged even when no scene has started yet (previously the log only appeared when at least one scene had already begun, so chance-terminated ticks looked like "no compatible actors"); the random pair search reports its top rejection reason (already used this tick / pair cooldown / distance / Z offset / actor base / gender) instead of silently retrying 10x; and the player is excluded at candidate-collection time instead of being collected and silently rejected by the eligibility check every tick. Wave semantics are unchanged - a failed roll still ends the wave.
- Settings parity (SF-TIK-011 follow-up): `fCheckInterval`, `fSceneTimeoutMinutes`, `fPairCooldownMinutes`, `fMaxStartDistance`, `fMaxZOffset`, `fWalkInDistance` and `bSoloPrivateOnly` are now read from settings (previously hardcoded fallbacks) and declared in the settings schema, so values set in OSF Settings now actually take effect. Setting `fMaxZOffset` to 0 disables the vertical-distance pair check. `fMinStartDistance` and `bProximityShield` remain declared-but-unwired upstream concepts (documented, no behavior change).
- Save/load migration to tracking version 4 no longer wipes tracked actors (gear/cooldown cleanup still reaches them).
- Furniture queries sanitized; unanchored fallbacks require explicit position tags so actors no longer float (SF-TIK-007).
- `OSFAutonomous.esm` is now a Small Master, freeing a full plugin slot (SF-TIK-003).
- Added `None` guards on `GetLeveledActorBase()` results; minor performance cleanups — `GetRelationshipRank()` result is now cached per eligibility check (previously queried per actor per guard), single `GetRace` call, removed per-tick log spam.

## Performance & build
- Scan timer restarts are gated on the mod being enabled; event handlers no longer revive the scan while disabled.

## Dev tooling (not shipped in the ZIP)
- `tests/papyrus/OSF_E2ETests.psc` — console-driven in-game E2E harness (`bat osfe2e`, or `cgf "OSF_E2ETests.RunAll"`): forces an FF scene through the production `TryStartScene` path and asserts the strap-on lands on the 'm' role (`IsEquipped` on `Dick.esm|0x81D`), demonstrates the eligibility-pool concurrency cap, echoes OSFSettings wiring, and verifies stuck-gear cleanup. Deploy via `tests/papyrus/deploy_e2e.ps1`.

## Affected files
- `Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
- `Data/Scripts/OSF_AutonomousManagerScript.pex`
- `Data/OSFAutonomous.esm`
- `Data/SFSE/Plugins/OSFUI/settings/osf.autonomous.json`

## [Nexus Mods Changelog Snippet]

> *Ready-to-paste text for the Nexus Mods "Change Log" section:*

```text
v1.2.0 — 2026-10-09
* IMPORTANT: OSF UI 2.0 is now required — the mod migrates all settings reads to the new OSFSettings plugin (OSF UI 1.x is no longer supported and the mod will stay disabled there).
* Fixed ship ownership detection: scenes no longer trigger on random station/ship interiors you don't own (only your own ship, outposts and homes count as private locations).
* Fixed dressed-sex-scene bug: actors could stay fully dressed when a generic fallback scene started instead of the intended foreplay scene; strip mode now follows the scene that actually starts.
* Fixed unanchored scenes floating actors — standing fallbacks now require explicit standing/floor tags, and the furniture search is sanitized.
* OSFAutonomous.esm is now a Small Master (frees a full plugin slot).
* More settings are now real in-game options (scan interval, scene timeout, pair cooldown, max start distance, Z offset, walk-in distance, solo-private-only) — set them in the F10 menu.
* Better diagnostics: failed chance rolls and pair rejections now log their reason; OSF Settings "Mod Issues" reports missing gear plugins.
* Save hardening: script updates no longer wipe tracked actors, and ghost scenes are audited every scan tick.

v1.1.2 — 2026-09-19
* Corrected the tar packaging script which previously prefixed all internal zip paths with `./`, causing Mod Organizer 2 FOMOD extraction errors.

v1.1.1 — 2026-09-19
* Migrated the build script to use 7-Zip instead of PowerShell Compress-Archive to prevent Mod Organizer 2 and Vortex from incorrectly flattening the directory structure upon installation (SF-TIK-002). No mod files were changed, only the ZIP packaging method.
```

---

## v1.1.2 — 2026-09-19 — Packaging Hotfix 2

### Build & deployment
- **Corrected the tar packaging script** which previously prefixed all internal zip paths with `./`, causing Mod Organizer 2 FOMOD extraction errors (SF-TIK-004).

---

## v1.1.1 — 2026-09-19 — Packaging Hotfix

### Build & deployment
- **Migrated the build script to use 7-Zip** instead of PowerShell `Compress-Archive` to prevent Mod Organizer 2 and Vortex from incorrectly flattening the directory structure upon installation (SF-TIK-002). No mod files were changed, only the ZIP packaging method.

---

## v1.1.0 — 2026-09-15 — Furniture Discovery & Crew Eligibility Fixes

### Bug fixes
- **Furniture discovery now finds all common furniture types**, not only beds: chairs, couches, benches, stools, bar stools, desk/table chairs, beds, and cockpit seats. Previously only `IsSleepFurniture` was searched, so most Gergel Ebanex furniture scenes never had a chance to trigger.
- **Paired scenes now iterate through nearby furniture candidates** and use `StartSceneAtAnchor`, instead of falling back to standing scenes after the first mismatched bed. This allows GE furniture animations to actually start.
- **FF pairs can now use MF-tagged furniture scenes** from external packs via gender fallback, matching the existing standing-scene fallback.
- **Recruited ship/outpost crew are no longer rejected by the crew guard.** The old guard required `IsPlayerTeammate()` to be true, which only covers the active follower. We now accept actors in `CurrentCrewFaction`, so recruited but unassigned crew on your ship/outpost are eligible while still rejecting random NPCs with crew keywords in cities.
- **Stuck attachment cleanup** (`Dick.esm` / `Haters Body.esm`) now runs reliably in every emergency and timeout path. Previously the script cleared the internal scene handle before calling `OSF.StopScene()`, so the scene-end callback could not find the scene and skipped `UnequipStuckAttachments()`. The script now tracks scene participants itself and unequips before clearing handles.
- **After save+quit mid-scene, ghost scenes are properly cleaned up on the next load.** Tracked participants are unequipped even when `OSF.GetSceneParticipants()` returns an empty array.
- **Removed empty placeholder sound pools** from `osfautonomous-solo.sounds.json` that caused OSF sound-validator pack-load errors (SF-TIK-001).

### Performance & build
- **Capped furniture candidate search to the 15 closest pieces** to avoid multi-minute hangs in dense cells like Cydonia that can contain 80+ furniture refs.
- **Papyrus build policy updated** — `.pex` is compiled with `-final -optimize` only, **never** with `-release`, so Debug user logging remains available for diagnostics.

### Affected files
- `Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
- `Data/Scripts/OSF_AutonomousManagerScript.pex`
- `Data/OSF/osfautonomous-solo.sounds.json`

---

## v1.0.3 — 2026-09-08 — Header cleanup (removed legacy TES4.DATA subrecord)

### Bug fix
- Removed the legacy `DATA` subrecord from the TES4 header in `OSFAutonomous.esm`.
  - Root cause: previous release builds included an 8-byte `DATA` subrecord after the `MAST` entry, a carryover from Skyrim/Fallout 4 plugin conventions. Starfield's Creation Engine 2 does not use this subrecord, and mod tools such as Wrye Bash rejected the plugin with: `Unexpected subrecord: TES4.DATA`.
  - Fix: rebuilt plugin header with only canonical Starfield subrecords (`HEDR`, `CNAM`, `MAST`, `BNAM`, `INCC`). File size reduced from 316 B to 311 B. Clean and error-free in all mod managers and diagnostic tools.

### Affected files
- `Data/OSFAutonomous.esm` — updated ESM without legacy `DATA` subrecord
- `fomod/info.xml` — version bumped to 1.0.3
- `README.txt` — version bumped to 1.0.3

---

## v1.0.1 — 2026-09-03 — FOMOD fix for MO2 + Vortex compatibility

### Bug fixes
- **FOMOD installer no longer blocked in Mod Organizer 2.**
  - Root cause: `<fileDependency>` entries in `ModuleConfig.xml` checked for physical presence of `SFSE\Plugins\OSF Animation.dll` and `OSFUI.dll`. MO2 uses a virtual file system (VFS) — mod files are not physically in `Data\`, so the FOMOD dependency check failed even when the DLLs were correctly installed through MO2.
  - Fix: removed all `<fileDependency>` entries from `<moduleDependencies>`. The "Requirements Check" install step is now always visible and informational only — the user acknowledges dependencies manually. Runtime dependency validation via `OSF.IsReady()` in the Papyrus script is unaffected and still catches missing OSF at game load.
- **Vortex no longer reports Invalid XML** (`Sch_UndeclaredAttribute` / `Sch_MissRequiredAttribute`).
  - Root cause: attributes not declared in the `ModConfig5.0.xsd` schema:
    - `name` on `<gameDependency>` — undeclared (`versionDependency` type only declares `version` as required)
    - `display` on `<fileDependency>` — undeclared (only `file` and `state` are declared)
  - Fix: removed the entire `<moduleDependencies>` block. `<gameDependency>` could not be made schema-compliant without introducing a version string that Vortex would also validate. The dependency check was redundant with the informational "Requirements Check" install step.
  - Note: the first v1.0.1 build uploaded to Nexus still contained `<gameDependency name="Starfield" />`. It was replaced with a fully schema-compliant build (no `<moduleDependencies>` at all).

### Chores
- Renamed solo animation from `solo_breathe_idle` to `solo_standing_touch`.
  - GLB file: `solo_breathe_idle.glb` → `solo_standing_touch.glb`
  - Scene ID: `osfautonomous.solo.breathe_idle` → `osfautonomous.solo.standing_touch`
  - Scene name: "Solo Natural Breathing Idle" → "Solo Standing Touch"
  - Tags: removed `idle`/`breathe`/`neutral`, added `standing`/`touch`
  - All source tools, manifests, and documentation synchronized.
- Updated public descriptions (README, Nexus) to use "custom solo self-touch animation" instead of "breathing/self-touch".

### Affected files
- `fomod/ModuleConfig.xml` — removed `fileDependency`, always-visible check
- `fomod/info.xml` — version 1.0.0 → 1.0.1
- `README.txt` — version header + troubleshooting text
- `nexus_description.md` — version reference
- `Data/OSF/osfautonomous-solo.osf.json` — scene ID, name, tags, clip path
- `Data/OSF/Autonomous/Animations/solo_standing_touch.glb` — renamed

### Notes
- No script changes: `OSF_AutonomousManagerScript.pex` unchanged from v1.0.0.
- No new content: same single solo animation, same audio files.

---

## v1.0.0 — Initial Release

- Autonomous NPC intimacy scenes using OSF Animation Framework.
- Tier-based scene selection (T1–T5) with pack-specific and fallback tiers.
- FF support via MF fallback animations.
- Solo downtime scenes (one custom solo self-touch animation with audio).
- 20 configurable settings via OSFUI (F10 menu).
- Automatic equipment cleanup (`Dick.esm` / `Haters Body`) after scenes.
- Romance exclusivity guard, walk-in interrupt, inter-scene proximity guard.
- 4 custom female voice clips (mono WEM).
- FOMOD installer with Vortex support.
- Requires: SFSE, OSF Animation, OSFUI.
