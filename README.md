# OSF Autonomous NPC

Starfield mod — autonomous solo animations for NPC actors using the OSF framework.

## Repository Structure

```
├── build_zip.ps1          # Release ZIP builder (run: powershell -File build_zip.ps1 -Version 1.0.4)
├── sync_to_game.ps1       # Sync release/Data/ -> game Data/ (run after edits)
├── release/              # 1:1 copy of game Data/ — edit here, sync to game
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
│   ├── CHANGELOG.txt
│   └── README.txt
├── src/                   # Build tools, animation scripts, manifests
│   ├── build_esm.ps1                      # ESM build script
│   ├── build.ps1                          # Full build script
│   ├── build_script_only.ps1              # Papyrus-only compile script
│   ├── modify_standself01.py              # Standing-touch animation builder
│   ├── modify_chair_touch.py              # Chair-touch animation builder (WIP)
│   ├── modify_bed_touch.py                # Bed-touch animation builder (WIP)
│   ├── generate_osf_solo_animations.py    # OSF solo animation generator
│   ├── osf.autonomous.json                # MCM config source
│   ├── osfautonomous-solo.osf.json        # Solo scene manifest
│   ├── osfautonomous-solo.sounds.json     # Sound mapping
│   ├── osfautonomous-chairoffice.osf.json # Chair scene manifest (WIP)
│   ├── osfautonomous-doublebed.osf.json   # Bed scene manifest (WIP)
│   ├── verify_glb.py                      # GLB structural verifier
│   ├── verify_glb_structures.py           # Detailed GLB structure check
│   ├── verify_frame_counts.py             # Frame count verifier
│   ├── verify_timestamps.py               # Timestamp alignment verifier
│   ├── verify_chair_touch.py              # Chair animation verifier
│   ├── verify_bed_touch.py                # Bed animation verifier
│   ├── verify_bed_donor.py                # Bed donor verifier
│   ├── verify_new_clips.py                # New clip verifier
│   ├── analyze_*.py                       # Various analysis scripts
│   ├── compare_*.py                       # GLB comparison scripts
│   ├── kinematic_profiles.json            # Kinematic parameter profiles
│   ├── kinematic_profiles_all.json        # All kinematic profiles
│   ├── agy_chair_analysis.md              # AGY kinematic analysis (chair)
│   ├── agy_chair_final_review.md          # AGY final review (chair)
│   ├── agy_bed_analysis.md                # AGY kinematic analysis (bed)
│   ├── rest_pose.py                       # Rest pose extraction
│   ├── skeleton_nodes.py                  # Skeleton node mapping
│   ├── extract_nodes.py                   # Node extraction utility
│   ├── extract_rest_pose.py               # Rest pose extraction utility
│   └── TODO.md                            # Future tasks
├── docs/                  # Project documentation
│   ├── AGENTS.md                          # Agent rules and conventions
│   ├── directory_map.md                   # Workspace directory map
│   ├── papyrus_build.md                   # Papyrus compilation guide
│   ├── anti_patterns.md                   # Anti-patterns to avoid
│   ├── lessons_learned.md                 # Lessons learned
│   └── agy_cooperation.md                 # AGY collaboration protocol
├── .gitignore
├── LICENSE
└── README.md
```

## Build

1. **Papyrus script**: Compile `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
   using PapyrusCompiler.exe (see `docs/papyrus_build.md`)
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
