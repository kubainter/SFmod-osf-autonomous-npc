# OSF Autonomous NPC

Starfield mod — autonomous intimacy scenes between NPCs using the OSF
Animation framework (paired scenes + solo downtime animations).

## Requirements

- **SFSE** (Starfield Script Extender)
- **OSF Animation — Native Scene Framework**
- **OSF UI 2.0+** — ships the OSFSettings plugin this mod reads all of its
  configuration from. OSF UI 1.x is not supported; the mod stays disabled
  there and reports why via the in-game "Mod Issues" panel.
- Any OSF animation pack (e.g. GE Animation Pack, SnuSnu Field) for paired
  scenes.

## Build

1. **Papyrus script**: Compile `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
   using PapyrusCompiler.exe
2. **Release ZIP**: `powershell -File build_zip.ps1 -Version X.Y.Z`
   — packages `release/` into a distributable ZIP (excludes `.psc` source).
   The script runs the pytest suite as a gate before packaging.

## Tests

`powershell -File run_tests.ps1` — pytest suite: static Papyrus checks,
script compilation, settings-schema parity, and release-build integrity.
In-game harnesses live in `tests/papyrus/` (see `docs/TESTING.md`).

## License

MIT License — see LICENSE file for details.
