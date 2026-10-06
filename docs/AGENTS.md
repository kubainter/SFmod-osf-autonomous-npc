# Starfield Workspace Agent Rules

Condensed instructions and a hard rulebook for all operations on this Starfield workspace.

> Paths use placeholders: `<GAME_ROOT>` = Starfield install dir (locally the
> `STARFIELD_ROOT` env var), `<WORKSPACE>` = the dev workspace containing this
> repo clone.

## Table of contents

1. [Directory map](#directory-map)
2. [Absolute basics](#absolute-basics)
3. [Conditional instructions / decision tree](#conditional-instructions--decision-tree)
4. [Engine & tools](#engine--tools)
5. [Performance](#performance)
6. [Anti-patterns and lessons](#anti-patterns-and-lessons)
7. [Working with agy (MCP)](#working-with-agy-mcp)
8. [Detailed repository structure](#detailed-repository-structure)

---

## Directory map

(relative to repo root)

- `release/` — distributable files, 1:1 with the game's `Data/` directory
  - `release/Data/` — ESM, scripts (.pex + .psc), OSF manifests, animations, sounds
  - `release/fomod/` — FOMOD installer config
  - `release/README.txt`, `release/CHANGELOG.md` — distribution docs
- `src/` — build tooling, Python scripts, source manifests
- `docs/` — project documentation
- `tests/` — pytest suite + Papyrus self-test/E2E harness
- `build_zip.ps1` — builds ZIP from `release/` (excludes `.psc`)
- `sync_to_game.ps1` — copies `release/Data/` into the game directory (`-GameData` required)
- `run_tests.ps1` — runs the pytest suite

---

## Absolute basics

These rules always apply, without exception.

1. **No assumptions**: Never rely on guesses or assumptions. Always verify the actual state — source files, logs, documentation.
2. **Log analysis first**: The primary source of truth about errors and game behavior is SFSE logs, Papyrus logs and related mod logs. Always check log files before making decisions.
3. **Mod safety**: Every change must be carefully verified for stability and impact on game saves. Changes must not cause CTDs (Crash to Desktop) or corrupt saves.
4. **Only modify mods**: We only modify scripts and files belonging to mods. Base game files (*Starfield.esm*, base scripts etc.) stay untouched. When modifying base game content is required, create a dedicated patch.
5. **Optimization & performance**: Always care about engine performance (Creation Engine/Papyrus) — avoid expensive loops, excessive calls in short intervals, and background operations that burden the engine.
6. **Mod context**: Starfield runs the latest version with many mods. When analyzing problems, consider the active mod list from *plugins.txt*.
7. **Move logic from Papyrus to xEdit (CTDA)**: Instead of burdening Papyrus scripts with complicated filtering and actor rejection (e.g. `GetFormFromFile`, loops, keyword checks), put exclusion logic (player, companions, already-processed objects) directly into Alias and Quest Conditions in the `.esm`. This avoids "Papyrus spam" and massively improves performance.

---

## Conditional instructions / decision tree

When the user asks for:

### Fixing/changing a Papyrus script

1. Read the relevant logs: `Papyrus.0.log`, other mod logs in `Logs\Script\User\`, `sfse_plugin_console.log`.
2. Check `plugins.txt` and confirm which plugins and modules are active.
3. Locate the `.psc` source (first `Data\Scripts\Source\`, then mod folders).
4. Before changing anything, check:
   - whether the timer is started in more than one place (`OnInit` and `OnQuestInit` together is a bug);
   - whether `GetFormFromFile` runs frequently (loop/timer);
   - whether actor filters can move to alias conditions (CTDA).
5. After changing a script remember `StopQuest <FormID>` + `StartQuest <FormID>` or `sqv` after loading a save.
6. Produce a test save instead of overwriting the main one when the change affects a running quest.

### Performance debugging / lag hunting

1. Open `Papyrus.0.log` and look for repeated, frequent entries.
2. Look for sub-1s timers, `GetFormFromFile` in loops, `Debug.Trace` in hot paths.
3. Move logic to CTDA conditions in the `.esm` before optimizing Papyrus.

### Changing an `.esm` / quest

1. Check whether it's a mod (name contains the mod name) or base game.
2. For base game, create a patch `.esp` / `.esm`.
3. Save a backup (`*.BACK` / `*.bak`) before editing in xEdit.
4. After the change, if the quest already runs in the save, use `StopQuest` + `StartQuest` or load a clean save.

### Building an SFSE/C++ plugin

1. Build script sources live in `src/`.
2. Build from the repo root, not directly inside the game directory.

### Building a release (ZIP)

1. `release/` is 1:1 with the game directory — edit files there.
2. **Sync to game**: `powershell -File sync_to_game.ps1 -GameData "<GAME_ROOT>\Data"` — copies `release/Data/` into the game dir.
3. **Build ZIP**: `powershell -File build_zip.ps1 -Version X.Y.Z` — packages `release/` into a ZIP (no `.psc`).
4. **Forbidden in ZIP**: `.psc` (the script auto-removes it from staging), Python tools, build scripts.
5. After every change **update `release/CHANGELOG.md`**. Format:
   ```
   vX.Y.Z — YYYY-MM-DD — short title
   ------------------------------------------------------
   ADDED: what was added
   CHANGED: what was changed
   BUGFIX: what was fixed (without the cause)
   ```
6. After building the ZIP, verify contents by extracting it and checking the file list plus version in `fomod/info.xml`.

### Crash / CTD analysis

1. Read the last SFSE log in `<GAME_ROOT>/Data/SFSE/Plugins/*.log`.
2. Check the last `Papyrus.0.log` entries before the crash time.
3. Never delete or overwrite `Starfield.exe`, `bink2w64.dll` or other base DLLs.

---

## Engine & tools

- **Engine**: Creation Engine / Starfield (`Starfield.exe` and `sfse_1_*.dll`).
- **Scripts**: Papyrus (compiler: `PapyrusCompiler.exe`, under `<GAME_ROOT>\Tools\`).
- **Data editor**: xEdit / SF1Edit, Archive2 for `*.ba2`.
- **SFSE**: `sfse_loader.exe`, `sfse_1_*.dll`, plugins in `Data/SFSE/Plugins/`.
- **Script decompiler**: Champollion (`Champollion.exe`).
- **Game config**: `StarfieldCustom.ini`, `StarfieldPrefs.ini` in `%USERPROFILE%\Documents\My Games\Starfield\`.
- **Mod list**: `%LOCALAPPDATA%\Starfield\plugins.txt`.

Constraints to always keep in mind:

- Papyrus is single-threaded; long/blocking operations kill frame pacing.
- `Game.GetFormFromFile` scans the form table — never in hot loops or timers.
- Alias Conditions (CTDA) in `.esm` are filtered by the engine and don't burden Papyrus.
- Save Game Caching: script/quest changes often require a full `StopQuest`/`StartQuest` or a clean save, because the engine caches script state in saves.
- Papyrus logs are written in UTC; compare times against local time.

---

## Performance

- Avoid `GetFormFromFile` in timers / loops.
- Use `Faction` / `Keyword` `Properties` instead of querying `Game.GetFormFromFile`.
- Never `StartTimer` more than once for the same ID (e.g. not in `OnInit` and `OnQuestInit` simultaneously).
- Don't leave `Debug.Trace` running in hot loops for long.
- Actor filtering (player, companions, `SFF_ProcessedKeyword` keyword etc.) happens first in CTDA in the `.esm`; Papyrus receives an already-filtered set.

---

## Anti-patterns and lessons

Full lists: `docs/anti_patterns.md` and `docs/lessons_learned.md` (local dev docs, not in the repo).
The most important hazards to watch:

- `GetFormFromFile` in fast timers / loops → initialize forms once in `OnInit` / `Properties`.
- Double `StartTimer` in `OnInit` and `OnQuestInit` → use only one event or check whether the timer already runs.
- Filtering in Papyrus instead of CTDA → move it to alias conditions.
- Modifying base game files → make a patch.
- Believing `StartQuest` resets a quest → use `StopQuest` + `StartQuest`.
- Skipping state verification after a script change → always `sqv` / logs / test save.
- Pack BA2 archives only with `Archive2.exe` (`-format=DDS -compression=Default`) and the correct `-root` (the parent dir above `textures/`), so DirectStorage works in hardware.
- Keep a stable VRAM margin (~6.0-6.5 GB in cities) and avoid external "Memory Cleaners" / aggressive tier-6 lighting presets in `StarfieldPrefs.ini`.
- Packing BA2 with `BSArch` or skipping DirectStorage → use `Archive2.exe`.
- Wrong `-root` in `Archive2.exe` (pointing at `textures/` itself) → loses paths in the name table.
- Global texture recompression or `-pow2` on faces/bodies → destroys PBR (BC4/BC5) and misaligns UVs.
- "Memory Cleaners" (`WorkingSet`) or old binary patchers (`StarfieldKit.dll`) → cause Page Faults and I/O stalls.

---

## 7. Working with agy (MCP)

**[CRITICAL]: The rules below are ABSOLUTE. Violating them is a critical error and aborts the task.**

Google Antigravity (`agy`) is an external tool based on Google Gemini. Remember: agy does not see our conversation history (your previous prompts) or your session context.

### 7.1. Automatic triggers (when you MUST call agy)
You are **CATEGORICALLY FORBIDDEN** from closing code-related tasks without first consulting agy via `run_subagent_task` when any of these occurs:
- The user uses the `@Agy` tag or asks for "peer review", "second opinion" or "cross-model verification".
- You modify Papyrus scripts affecting performance (timers, loops, `GetFormFromFile`).
- You change conditions in `.esm` files (CTDA, actor filtering).
- You analyze Crash to Desktop (CTD) causes.
- You make a **comprehensive / wholesale change** (e.g. full refactor of the Nexus description, rebuild of large logic sections, mass documentation update, syncing `release/` with sources) — before declaring the task done, run a review by the other agent (agy) with a prompt containing: self-contained context (file paths + before/after state), the list of changes, and a request to verify each claim against the code.

### 7.2. Peer review procedure (workflow)
If you write or change any code, before reporting completion you must follow this protocol:

1. **Self-contained prompt**: Build a query for `run_subagent_task`. It must contain the task, the context (changed code), and the hard constraints from this file (e.g. Papyrus is single-threaded, no GetFormFromFile in timers, use Archive2.exe for BA2).
2. **Capture the ID**: Always remember the returned `conversation_id` from the first call — it is your key to context for follow-up queries.
3. **Serialization**: Never run two parallel queries on the same `conversation_id`.
4. **Rule Zero (VERIFICATION)**: Agy can hallucinate FormIDs and ESM structure. You must verify every agy claim with your own tools (`read`, `grep`, verification scripts in `src/`) BEFORE applying its advice to code.

### 7.3. AGY as kinematic sub-agent (pre-implementation protocol)

Beyond post-implementation peer review, AGY MUST be used **BEFORE** changing animation parameters (bone positions, amplitudes, frequencies, quaternion offsets). Protocol:

1. **Clash assumptions**: Before generating a new GLB candidate, send AGY (continuing the existing `conversation_id` if available):
   - Current parameter values from `modify_standself01.py`
   - The user's Definition of Done (hand position, speed, no penetration)
   - Iteration history (which values were tested, what the user said)
   - Reference rig: `sf_animation_io_src/sf_animation_io-master/API/Assets/Rigs/human_female.rig`
2. **AGY's own math**: AGY should run FK (Forward Kinematics) on the rig and compute the real end-of-chain bone position (e.g. hand/fingers) for the proposed values.
3. **Recommendations**: AGY suggests concrete numeric values with kinematic reasoning (cm offsets, rotation degrees, penetration risk).
4. **Clash with my assumptions**: Compare AGY's recommendations with mine. If they differ — trust AGY's FK math (it has the rig as a base), but sanity-check the logic.
5. **Pre-emptive tuning**: If the user asked for "more" 3+ times in a row, AGY should suggest a value large enough to avoid another round-trip.
6. **Verification**: After generating the candidate, verify structurally (quaternion norms, loop seam, unexpected channel changes) with local scripts.

### 7.4. Mandatory response format (exit ticket)
To prove you performed the mandatory audit, every final answer closing a task described in 7.1 MUST end with this block:

```text
---
[AGY-AUDIT-STATUS: PRZEPROWADZONO]
[CONVERSATION_ID: <paste the exact ID returned by agy here>]
[WYNIK WERYFIKACJI: <confirm in one sentence that you used scripts/read to verify Agy's claims>]
---
```

---

## 8. Detailed repository structure

(Moved out of the public README — dev-facing information, not for mod users.)

```
├── build_zip.ps1          # Release ZIP builder (run: powershell -File build_zip.ps1 -Version 1.1.0)
├── sync_to_game.ps1       # Sync release/Data/ -> game Data/ (run after edits; -GameData required)
├── run_tests.ps1          # pytest suite (104 tests: static Papyrus, compile, schema parity, zip)
├── release/               # 1:1 copy of game Data/ — edit here, sync to game
│   ├── Data/
│   │   ├── OSFAutonomous.esm              # Mod plugin
│   │   ├── OSF/                           # OSF manifests + animations
│   │   │   ├── osfautonomous-solo.osf.json
│   │   │   ├── osfautonomous-solo.sounds.json
│   │   │   └── Autonomous/Animations/
│   │   │       └── solo_standing_touch.glb
│   │   ├── Scripts/                       # Papyrus (.pex + .psc source)
│   │   │   ├── OSF_AutonomousManagerScript.pex
│   │   │   └── Source/
│   │   │       └── OSF_AutonomousManagerScript.psc
│   │   ├── SFSE/Plugins/OSFUI/settings/   # MCM settings
│   │   │   └── osf.autonomous.json
│   │   └── Sound/OSF/Autonomous/Female/   # Audio assets (.wem)
│   ├── fomod/             # FOMOD installer config
│   ├── CHANGELOG.md
│   └── README.txt
├── src/                   # Build tools, animation scripts, manifests
│   ├── build_esm.ps1                      # ESM build script
│   ├── build.ps1                          # Full build script
│   ├── build_script_only.ps1              # Papyrus-only compile script (temp dir, deploys .pex)
│   ├── modify_standself01.py              # Standing-touch animation builder
│   ├── modify_chair_touch.py              # Chair-touch animation builder (WIP)
│   ├── modify_bed_touch.py                # Bed-touch animation builder (WIP)
│   ├── generate_osf_solo_animations.py    # OSF solo animation generator
│   ├── osf.autonomous.json                # MCM config source
│   ├── osfautonomous-solo.osf.json        # Solo scene manifest
│   ├── osfautonomous-solo.sounds.json     # Sound mapping
│   ├── osfautonomous-chairoffice.osf.json # Chair scene manifest (WIP)
│   ├── osfautonomous-doublebed.osf.json   # Bed scene manifest (WIP)
│   ├── verify_*.py                        # GLB/clip/frame verifiers
│   ├── analyze_*.py                       # Analysis scripts (OSF scenes, PKIN, ESM)
│   ├── compare_*.py                       # GLB comparison scripts
│   ├── parse_pkin*.py, dump_pkin.py       # PKIN navmesh parsers
│   ├── kinematic_profiles*.json           # Kinematic parameter profiles
│   ├── rest_pose.py, skeleton_nodes.py    # Rig/pose utilities
│   └── extract_*.py                       # Node/rest-pose extraction
├── docs/                  # Project documentation
│   ├── AGENTS.md                          # Agent rules — THIS FILE
│   ├── directory_map.md                   # Workspace directory map
│   ├── agy_cooperation.md                 # AGY collaboration protocol
│   ├── agy_*.md                           # AGY kinematic analyses
│   ├── TESTING.md                         # Test guide
│   └── TODO*.md                           # Task lists
├── tests/                 # pytest suite + Papyrus selftest/e2e harness
├── .gitignore
├── LICENSE
└── README.md
```

Local-only docs (present in the working tree, gitignored — never pushed):
`docs/anti_patterns.md`, `docs/lessons_learned.md`, `docs/papyrus_build.md`,
`docs/nexus_description.md`.
