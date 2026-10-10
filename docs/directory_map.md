# Starfield Workspace — Directory Map

Quick orientation for where game files, mods, sources and logs live.
Treat this as a map of safe vs. dangerous areas.

> Paths below use placeholders on purpose — substitute your own locations:
> - `<GAME_ROOT>` — Starfield install directory (locally provided via the
>   `STARFIELD_ROOT` environment variable)
> - `<WORKSPACE>` — the development workspace directory holding this repo clone
> - `%USERPROFILE%` / `%LOCALAPPDATA%` — standard Windows user locations

## Safety categories

- **Safe to edit** — mod files / own sources / logs.
- **Read-only / copies** — base game files; change only via patches or conservatively.
- **Generated output** — files produced by compilation or by running the game; do not hand-edit.

---

## Game root

`<GAME_ROOT>\`

- `Starfield.exe` — game executable. **Never modify.**
- `sfse_1_*.dll`, `sfse_loader.exe` — SFSE. **Never modify.**
- `CreationKit.exe` — game editor.
- `.agents\`, `.devin\` — local agent/project meta files (not in repo).
- `vortex.deployment.json` — Vortex deployment state; **never edit by hand**.
- `Starfield.ini`, `High.ini`, `Medium.ini`, `Low.ini` — preset INIs. Back up before overwriting.
- `materials\`, `meshes\`, `textures\`, `SAF\`, `Scripts\` — **Vortex-managed** (hardlinks). Do not touch manually.
- `temp-*\` — installer leftovers. Do not touch.

## Game data / mods

`<GAME_ROOT>\Data\`

- `*.esm`, `*.esp` — loaded plugins (mostly mods, some base). Check `plugins.txt` before touching.
- `*.ba2` — archived assets (textures, meshes, audio). Create with `Archive2`.
- `Scripts\` — compiled Papyrus scripts (`.pex`). **Generated.** Sources live in `Scripts\Source\` or the mod folder.
- `Scripts\Source\` — `.psc` sources (if present). Safe to edit when they belong to the mod.
- `SFSE\Plugins\` — SFSE plugin configs and logs (e.g. `sfse_plugin_console.log`).

## Own SFSE / C++ plugin sources

`<WORKSPACE>\src\`

- `sfse-*/` — unpacked SFSE sources. Treat as SDK; do not modify unless intentionally testing a build.
- Own projects — `.psc`, `.py`, `.json`, `build*.ps1` per mod.

## Developer tools

`<GAME_ROOT>\Tools\`

- `Papyrus Compiler\PapyrusCompiler.exe` — Papyrus compiler.
- `Champollion\Champollion.exe` — `.pex` -> `.psc` decompiler.
- `Archive2\Archive2.exe` — `*.ba2` packing.
- `VSCodePapyrusAddon\` — Papyrus extension for VS Code.

## User logs & config

- `%LOCALAPPDATA%\Starfield\plugins.txt` — active mod/ESL/ESM list. Read before debugging.
- `%USERPROFILE%\Documents\My Games\Starfield\Logs\Script\` — Papyrus logs (e.g. `Papyrus.0.log`).
- `%USERPROFILE%\Documents\My Games\Starfield\Logs\Script\User\` — mod logs (e.g. `OSF_Autonomous.0.log`).
- `%USERPROFILE%\Documents\My Games\Starfield\StarfieldCustom.ini` — user settings (Papyrus logging etc.).
- `%USERPROFILE%\Documents\My Games\Starfield\StarfieldPrefs.ini` — graphics preferences.

---

## Development workspace

`<WORKSPACE>\` — working directory for development, kept separate from game files.
All Python scripts, sources, release staging and backups live here.

Typical layout:

```
<WORKSPACE>\
├── repo_upload\                    — this repository (the git clone; canonical source of truth)
│   ├── release\Data\               — 1:1 copy of game Data/ — edit here, sync to game
│   ├── src\                        — build tools, Python scripts, source manifests
│   ├── docs\                       — project documentation
│   └── tests\                      — pytest suite + Papyrus test harness
├── animation_references\           — reference animations (.af + GLB from Blender)
├── extracted_vanilla\              — extracted vanilla animations (.af/.afx)
├── backups\                        — backups of game/mod files
├── temp\                           — temporary extraction output
└── archive\                        — archived releases and junk
```

### ZIP build rules

- **Whitelist only** — package only distributable files, never recursively all of `Data\`
- **Forbidden in ZIP**: `Data\Scripts\Source\` (`.psc`), `dev_source\`, `nexus_description.md`, `CHANGELOG.md`, Python scripts, build tooling
- **Required in ZIP**: `README.txt`, `Data\` (only `.esm`, `.json`, `.glb`, `.pex`, `.wem`), `fomod\info.xml`, `fomod\ModuleConfig.xml`
- **After every change**: update `release/CHANGELOG.md` with what was added/changed/fixed
