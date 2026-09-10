OSF Autonomous NPC Interactions
v1.0.4 — Spaceflight Critical Hotfix
Author: Botan

Includes one custom solo self-touch animation with audio. Paired scenes are
sourced from installed OSF animation packs.
More solo animations are planned for future updates.

ADULT MOD (18+) — Requires the OSF ecosystem.

================================================================================
REQUIREMENTS (ALL HARD — mod will not load without every one)
================================================================================

  1. SFSE (Starfield Script Extender) — launch via sfse_loader.exe
  2. OSF Animation - Native Scene Framework — native animation engine (SFSE DLL)
  3. OSFUI — settings system + F10 in-game menu (script will not bind without it)

Recommended animation packs (mod works with any OSF pack):
  - GE Animation Pack — 388+ MF scenes with furniture (primary source)
  - SnuSnu Field — femdom scenes + strapon + native FF
  - Body replacer (SFF/SFM) — enhanced visuals

Note: Strapon/dildo equipment models are provided by scene packs like
  SnuSnu Field (attachments.osfgear.json). This mod includes automatic
  cleanup for stuck attachments (Dick.esm / Haters Body) to safely unequip
  them when scenes conclude.

================================================================================
INSTALLATION
================================================================================

Vortex: Click "Mod Manager Download" on Nexus. FOMOD guides you. Enable
        OSFAutonomous.esm in load order. Launch via sfse_loader.exe.

Manual:  Extract to Data\ folder. Add *OSFAutonomous.esm to plugins.txt.
         Ensure StarfieldCustom.ini has bInvalidateOlderFiles=1.

Distributed Data files:
  Data\OSFAutonomous.esm
  Data\Scripts\OSF_AutonomousManagerScript.pex
  Data\OSF\osfautonomous-solo.osf.json
  Data\OSF\osfautonomous-solo.sounds.json
  Data\OSF\Autonomous\Animations\solo_standing_touch.glb
  Data\Sound\OSF\Autonomous\Female\*.wem
  Data\SFSE\Plugins\OSFUI\settings\osf.autonomous.json

Load order: Place after any OSF animation pack ESMs.
  Example: *SnuSnuField.esm -> *OSFAutonomous.esm

================================================================================
DEFAULT SETTINGS (20 in-game settings — change via F10 menu)
================================================================================

[General]
  bEnabled             = true     Master switch for autonomous scenes
  sLocationMode        = "ship"   "ship" (Ship Only), "interiors", "everywhere"
  bCompanionsOnly      = false    Restrict only to named companions
  bIncludeOutpostNPC   = false    Include nearby humanoid settlers/outpost NPCs
  iChancePercent       = 25       Trigger probability % per pair per scan

[Frequency & Limits]
  iMaxConcurrentScenes = 2        Max concurrent scenes (slider: 1 to 4)
  fActorCooldownMinutes= 10.0     Minutes before same actor can participate again
  fMinSceneSpacing     = 500.0    Min distance between scenes (~7m) to avoid overlap

[Scene Options]
  bRequireFurniture    = true     Only start scenes at beds/couches
  bUseMFForFF          = true     FF pairs use MF animations as fallback
  iStripMode           = -1       -1 = Inherit pack default, 0 = Off, 1 = On
  fLoopScale           = 1.0      Multiplier for scene duration (0.25 to 3.0)
  bAllowForeplay       = true     Include kissing, oral, handjob tags
  bAllowClassic        = true     Include missionary, cowgirl, spoon tags
  bAllowIntense        = true     Include doggy, reversecowgirl, riding tags
  sSpeedMode           = "static" "static", "dynamic" (accelerating), "random"

[Romance & Solo]
  bRomanceExclusivity  = true     Romanced companions (rank >= 3) excluded
  bStopOnPlayerWalkIn  = false    Interrupt scene if player walks into the room
  bSoloDowntime        = true     Solo downtime when no pairs are available
  fSoloChance          = 20.0     Chance % for solo scene during scan cycle

Note: Advanced engine values (scan interval: 45s, scene timeout: 3m, max start
  distance: 2000 units) are internally fixed in v1.0.x for optimal performance.

================================================================================
WHO DOES THIS MOD AFFECT?
================================================================================

Included: companion crew, generic crew, elite crew, active followers.
          Outpost NPCs only if bIncludeOutpostNPC=on (off by default).

Never affected: player, children, robots, crowd NPCs, mannequins, dead/
  combat/dialogue/hostile actors, MM pairs (no compatible animations).

Conditionally excluded: romanced companions (if exclusivity on), non-
  companions (if companionsOnly on).

================================================================================
TROUBLESHOOTING
================================================================================

Mod doesn't start? Verify ALL hard requirements installed (SFSE, OSF
  Animation, OSFUI). Check SFSE logs for binding errors.

No scenes? Verify OSF Animation.dll is loaded (check SFSE logs for
  "OSF not ready" messages). Try sLocationMode="everywhere". Set
  iChancePercent=100 for paired-scene testing, or enable bSoloDowntime and
  raise fSoloChance for solo-scene testing.

Performance? Set iMaxConcurrentScenes=1. Keep bRequireFurniture=true (beds/couches).
  Lower iChancePercent (e.g. 15-20%) if running with many crew members.

================================================================================
UNINSTALL
================================================================================

1. While still in-game, open console (` or ~) and stop the manager quest:
     help OSF_AutonomousManager_Quest QUST
   Note the FormID shown and run:
     StopQuest <FormID>
2. Create a fresh clean save and exit the game.
3. Remove/disable OSFAutonomous.esm and delete mod files from Data\.
4. Load your clean save. No vanilla game records are modified.
   As with any scripted mod, keeping a backup save is always good practice.

================================================================================
CREDITS
================================================================================

ozooma10 — OSF Animation Framework and OSFUI (schema-driven MCM, no C++ needed)
SFSE Team (ianpatt, behippo, scripthoge) — Starfield Script Extender
GE Animation Pack authors — 388+ furniture-supported scenes
SnuSnu Field author — femdom content and strapon support

This is a v1.0.1 bugfix release. Bug reports and feedback welcome
on the Nexus mod page.
