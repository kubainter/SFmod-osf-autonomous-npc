# OSF Autonomous NPC

Starfield mod — autonomous solo animations for NPC actors using the OSF framework.

## Repository Structure

```
├── release/              # Distributable mod files (what goes into the ZIP)
│   ├── Data/
│   │   ├── OSFAutonomous.esm              # Mod plugin
│   │   ├── OSF/                           # OSF manifests + animations
│   │   │   ├── osfautonomous-solo.osf.json
│   │   │   ├── osfautonomous-solo.sounds.json
│   │   │   └── Autonomous/Animations/
│   │   │       └── solo_standing_touch.glb
│   │   ├── Scripts/                       # Compiled Papyrus (.pex only, no .psc)
│   │   │   └── OSF_AutonomousManagerScript.pex
│   │   ├── SFSE/Plugins/OSFUI/settings/   # MCM settings
│   │   │   └── osf.autonomous.json
│   │   └── Sound/OSF/Autonomous/Female/   # Audio assets (.wem)
│   ├── fomod/             # FOMOD installer config
│   ├── CHANGELOG.txt
│   ├── README.txt
│   └── nexus_description.md
├── src/                   # Full development source (for mod reconstruction)
│   ├── OSF_AutonomousManagerScript.psc    # Papyrus source (pre-compile)
│   ├── modify_standself01.py              # Standing-touch animation builder
│   ├── modify_chair_touch.py              # Chair-touch animation builder (WIP)
│   ├── modify_bed_touch.py                # Bed-touch animation builder (WIP)
│   ├── generate_osf_solo_animations.py    # OSF solo animation generator
│   ├── build.ps1                          # Build script
│   ├── build_esm.ps1                      # ESM build script
│   ├── build_script_only.ps1              # Papyrus-only compile script
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
├── assets/                # Mod assets (banners, promo)
│   ├── banner_new.png                     # Nexus mod banner
│   ├── generate_banner.py                 # Banner generation script
│   └── apply_promo_banners.py             # Promo banner applier
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

## Current Release: v1.0.1

- Solo standing touch animation (`solo_standing_touch`)
- OSF framework integration
- MCM configuration via SFSE
- Custom sound effects

## Reconstructing the Mod from Source

1. **Papyrus script**: Compile `src/OSF_AutonomousManagerScript.psc` using
   `Tools\Papyrus Compiler\PapyrusCompiler.exe` (see `docs/papyrus_build.md`)
2. **Animations**: Run `src/modify_standself01.py` to generate
   `solo_standing_touch.glb` from source GLB files
3. **Build ZIP**: Use `src/build.ps1` to assemble the distributable package
4. **Install**: Copy `release/Data/` contents into Starfield's `Data/` folder,
   or use the FOMOD installer with Vortex/MO2

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
