# OSF Autonomous NPC

Starfield mod — autonomous solo animations for NPC actors using the OSF framework.

## Build

1. **Papyrus script**: Compile `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
   using PapyrusCompiler.exe
2. **ESM**: Run `src/build_esm.ps1` to generate `release/Data/OSFAutonomous.esm`
3. **Animations**: Run `src/modify_standself01.py` to generate
   `solo_standing_touch.glb` from source GLB files
4. **Release ZIP**: `powershell -File build_zip.ps1 -Version X.Y.Z`
   — packages `release/` into a distributable ZIP (excludes `.psc` source)

## Development

Animation files are built programmatically using Python scripts in `src/`.
The builders read source GLB files, modify animation channels (quaternions,
translations), and output compressed GLB files ready for the game.

### Work in Progress (not yet released)

- `solo_chair_touch` — seated chair animation (HUSH gesture + groin massage)
- `solo_bed_touch` — supine bed animation (HUSH gesture + groin massage)

These are built by `modify_chair_touch.py` and `modify_bed_touch.py`
respectively, using kinematic analysis from AGY (Google Gemini).

## License

MIT License — see LICENSE file for details.
