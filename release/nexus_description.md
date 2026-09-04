[color=#ffff00][size=5][b][u][i][Adult / NSFW Content (18+)][/i][/u][/b][/size][/color]

[b]Note:[/b] This mod requires the OSF ecosystem and compatible animation packs to work. It includes one custom solo self-touch animation with audio; all paired scenes are driven using whatever OSF animation packs you have installed.

[heading][center][color=#ff7700]Description[/color][/center]
[/heading]
[b]OSF Autonomous NPC Interactions[/b] is an extension for the OSF ecosystem that brings autonomous intimacy scenes between NPCs to Starfield. When your companions and crew are idle - hanging out on your ship, lounging at an outpost, or sandboxing in a player home - this mod gives them a life of their own without requiring player interaction.

The mod periodically checks for eligible NPC pairs nearby and, based on your configured chance, starts OSF animation scenes between them. You can walk around your ship and catch your crew in the act, or just let things happen naturally in the background while you go about your playthrough.

[b]Default Location:[/b] Out of the box, the mod is set to "Ship Only" mode so scenes only trigger inside your ship interior. If you want scenes to happen in player homes, outposts, or elsewhere, you can easily change the location mode to "Ship + Outposts + Homes" or "Everywhere" in the in-game settings menu (press [b]F10[/b]).

Built on top of the OSF Animation Framework and OSFUI, the mod uses a tier-based scene selection system designed to work with [b]any[/b] OSF animation pack - whether that's the GE (Gentle Embrace) pack with its 388+ furniture-supported scenes, SnuSnu Field's femdom content, or future custom packs. If a dedicated pack scene isn't found for a specific tag, fallback tiers ensure a matching scene will still play.

[heading][center][color=#ff7700]Who does this mod affect?[/color][/center]
[/heading]
[b]Included as scene participants:[/b]
[list]
[*]Named companion crew (Sarah, Barrett, Sam, Andreja, etc.) - actors with the Crew_CrewTypeCompanion keyword[/*]
[*]Generic hireable crew specialists - actors with Crew_CrewTypeGeneric[/*]
[*]Elite crew - actors with Crew_CrewTypeElite[/*]
[*]Active followers from multi-follower mods (e.g. The Gang's All Here)[/*]
[*]Outpost settlers, lodge residents, and other nearby humanoid NPCs - [b]only if[/b] enabled in settings (bIncludeOutpostNPC, off by default)[/*]
[/list]

[b]Never affected (hardcoded exclusions):[/b]
[list]
[*]The player character - never selected, never participates[/*]
[*]Children (Cora Coe and any child actor) - blocked via IsChild() and ActorTypeChild keyword[/*]
[*]Robots (Vasco, Kaiser, security bots) - blocked by ActorTypeRobot keyword on actor and race[/*]
[*]Crowd NPCs (HumanCrowdRace) - excluded to avoid skeleton mismatch crashes with OSF[/*]
[*]Mannequins (MannequinRace) - excluded to avoid skeleton issues[/*]
[*]Dead, unconscious, bleeding out, or arrested actors[/*]
[*]Actors in combat (player combat or actor combat)[/*]
[*]Actors in dialogue with the player or actively speaking sandbox barks[/*]
[*]Actors already participating in an OSF scene[/*]
[*]Hostile actors (even unalerted enemies)[/*]
[*]Actors currently sitting or transitioning to/from seats, sleeping, running, or sneaking[/*]
[*]Male-male (MM) pairs - skipped automatically since no compatible animation packs currently exist[/*]
[/list]

[b]Conditionally excluded (configurable via settings):[/b]
[list]
[*]Romanced companions (relationship rank >= 3) - blocked while the romance exclusivity guard is active (default: on)[/*]
[*]Non-companion NPCs - blocked if the "Companions Only" filter is turned on (default: off)[/*]
[/list]

[heading][center][color=#ff7700]Installation instructions[/color][/center]
[/heading]
[b]Hard Requirements (the mod will not function without these):[/b]
[list=1]
[*][b]Starfield Script Extender (SFSE)[/b] - required by OSF Animation and OSFUI.[/*]
[*][b]OSF Animation - Native Scene Framework[/b] - the core animation engine. This mod calls OSF API functions directly (OSF.IsReady(), OSF.StartSceneByTags(), OSF.StartSceneAtAnchor(), etc.).[/*]
[*][b]OSFUI[/b] - the settings UI plugin. This mod reads all of its configuration values via OSFUI and uses its in-game menu (press [b]F10[/b]). Without OSFUI.pex, the Papyrus script will fail to bind and the manager quest will not start.[/*]
[/list]

[b]Recommended Animation Packs & Addons:[/b]
[list=1]
[*][b]GE Animation Pack[/b] - 388+ MF scenes with furniture support. Highly recommended as the primary animation source for furniture-anchored scenes (beds and other sleep furniture).[/*]
[*][b]SnuSnu Field[/b] - Femdom-oriented scenes with strapon support. Adds role-reversed MF scenes and native FF content.[/*]
[*][b]Body replacer (SFF / SFM) or Milky Wixens[/b] - Optional, but improves visual presentation.[/*]
[/list]

[b]Note on FF scenes & Gear Cleanup:[/b] When female-female pairs use MF fallback animations, strapon equipment (provided by SnuSnu Field's gear file or other OSF gear packs) improves visual consistency. While gear models are supplied by those packs, this mod features an automatic attachment cleanup routine (for Dick.esm and Haters Body) to safely unequip any stuck strapon/gear pieces after a scene ends.

[b]Manual Installation:[/b]
[list=1]
[*]Extract the downloaded archive into your Starfield [b]Data\[/b] directory, keeping the folder structure:
[list]
[*]OSFAutonomous.esm → Data\[/*]
[*]OSF_AutonomousManagerScript.pex → Data\Scripts\[/*]
[*]osfautonomous-solo.osf.json → Data\OSF\[/*]
[*]osfautonomous-solo.sounds.json → Data\OSF\[/*]
[*]solo_standing_touch.glb → Data\OSF\Autonomous\Animations\[/*]
[*]Sound\OSF\Autonomous\Female\*.wem → Data\Sound\OSF\Autonomous\Female\[/*]
[*]osf.autonomous.json → Data\SFSE\Plugins\OSFUI\settings\[/*]
[/list]
[/*]
[*]Add [b]*OSFAutonomous.esm[/b] to your [b]plugins.txt[/b] (located in %LOCALAPPDATA%\Starfield\).[/*]
[*]Make sure your [b]StarfieldCustom.ini[/b] has loose file loading enabled:
[code][Archive]
bInvalidateOlderFiles=1
sResourceDataDirsFinal=[/code]
[/*]
[*]Launch the game via [b]sfse_loader.exe[/b].[/*]
[/list]

[b]In-Game Usage & Settings:[/b]
[list]
[*]The mod starts automatically upon loading your save (via a Start Game Enabled quest).[/*]
[*]Press [b]F10[/b] at any time to open the OSFUI settings menu and configure settings under "OSF Autonomous NPC".[/*]
[*]Default settings are balanced out of the box, so no manual configuration is required to get started.[/*]
[/list]

[b]Load Order:[/b]
[list]
[*]Place [b]OSFAutonomous.esm[/b] after any OSF animation pack plugins in your load order.[/*]
[*]Example: *SnuSnuField.esm → *OSFAutonomous.esm[/*]
[/list]
[heading][center][color=#ff7700]Main features[/color][/center]
[/heading]
[list]
[*][b]Autonomous NPC Scenes[/b] - Eligible NPC pairs initiate OSF scenes naturally on their own, completely independent of the player.[/*]
[*][b]Tier-Based Scene Selection[/b] - Intelligently resolves the best available scene from your installed packs:
[list=1]
[*]T1/T2: Furniture-anchored scenes (beds / sleep furniture), matched by OSF to the anchor reference.[/*]
[*]T3: Pack-specific paired scenes (GE standard [m, f], SnuSnu femdom [f, m], and generic catch-all fallbacks).[/*]
[*]T4: Standing scenes (pack-specific + fallback).[/*]
[*]T5: Baseline paired scenes (universal fallback).[/*]
[/list]
[/*]
[*][b]Broad Animation Pack Compatibility[/b] - Generic fallback tiers query without pack-specific tags, allowing custom and future OSF-compatible packs to work without hardcoded rules.[/*]
[*][b]Female-Female (FF) Support via MF Fallback[/b] - FF pairs can fall back to MF animations (unlocking 388+ GE scenes for FF pairs). Since Starfield shares skeleton structures between genders, animations align cleanly (best paired with a strapon/dildo attachment mod).[/*]
[*][b]Role Ordering Detection[/b] - Automatically recognizes pack conventions (e.g. GE standard [m, f] vs. SnuSnu femdom [f, m]) to assign male and female actors to their intended roles.[/*]
[*][b]Solo Downtime Scenes[/b] - If no suitable pair is available, an idle NPC has a chance to play a custom solo self-touch animation with audio. More solo animations are planned for future updates. Configurable chance, restricted to private/interior spaces by default.[/*]
[*][b]Inter-Scene Proximity Guard[/b] - Enforces minimum physical spacing between active scenes (~7m default) so multiple pairs don't crowd or overlap on top of each other.[/*]
[*][b]Optimized Scan Range[/b] - The scan radius is tied to the scene start distance (2000 units by default), so far-away NPCs are filtered out before the Papyrus scan runs.[/*]
[*][b]Romance Exclusivity Guard[/b] - Keeps romanced companions (relationship rank >= 3) exclusive to the player while the guard is active (default: on).[/*]
[*][b]Optional Walk-In Interrupt[/b] - When enabled, approaching a room where a scene is taking place will immediately stop the scene ("caught in the act" dynamic for extra immersion). Disabled by default.[/*]
[*][b]Multi-Stage Advancement & Tag Rotation[/b] - Scenes progress through sequence stages automatically, and the system rotates action tags (cowgirl, missionary, doggy, blowjob, etc.) to keep consecutive scenes varied.[/*]
[*][b]Natural Finale[/b] - Scenes smoothly advance to their climax stage before concluding, avoiding abrupt scene cutoffs.[/*]
[*][b]Flexible Speed Control[/b] - Choose between fixed speed, dynamic acceleration per stage, or randomized pacing per scene.[/*]
[*][b]In-Game Settings (F10 Menu)[/b] - 20 customizable settings organized into 4 intuitive categories:
[list=1]
[*][b]General[/b]: Master enable toggle, location mode (Ship / Interiors / Everywhere), companions-only filter, outpost NPC inclusion, trigger chance %.[/*]
[*][b]Frequency & Limits[/b]: Max concurrent scenes (1-4), actor cooldown, minimum scene spacing.[/*]
[*][b]Scene Options[/b]: Furniture requirement, FF fallback to MF, strip mode, scene duration scale, action tag filters (foreplay / classic / intense), speed mode.[/*]
[*][b]Romance & Solo[/b]: Romance exclusivity guard, walk-in interrupt, solo downtime toggle and trigger chance.[/*]
[/list]
Note: Several advanced behaviors (scan interval, scene timeout, max start distance, pair distance, furniture height limit, stage advancement, tag rotation, sequence preference, natural finale, pair cooldown, walk-in distance, base speed, solo private-only) are fixed in this version and are not exposed as settings.
[/*]
[/list]
[heading][center][color=#ff7700]For mod authors: Creating compatible animation packs[/color][/center]
[/heading]
[b]This mod utilizes OSF's tag query system. Any animation pack adhering to the standard OSF JSON format will work automatically. The manager queries scenes using prioritized tag combinations:[/b]

[b]Required tags in your scene JSON:[/b]
[list]
[*]"paired" - marks the scene as a 2-actor interaction.[/*]
[*]"mf" or "ff" - specifies the gender pairing.[/*]
[/list]

[b]Optional tags that enhance scene selection:[/b]
[list]
[*]Pack identifier: "ge" or "snusnu" - enables specialized role ordering. If your pack uses inverted roles (such as SnuSnu's [f, m] femdom setup), including a unique pack tag allows the script to map actors accurately. Packs without special tags default to standard [m, f] ordering via generic tiers.[/*]
[*]Action tags: "blowjob", "cowgirl", "doggy", "missionary", "kissing", "oral", "spoon", "facedown", "reversecowgirl", "riding", "scissors", "standing" - enables tag rotation and filtered selection.[/*]
[*]"sequence" - denotes multi-stage scenes that progress across stages.[/*]
[*]Furniture tags: resolved automatically by OSF when anchoring to nearby furniture references.[/*]
[/list]

[b]Example minimal scene JSON for a custom pack:[/b]
[code]{
  "schema": 1,
  "name": "My Custom Pack",
  "pack": "mycustompack",
  "scenes": [
    {
      "id": "mycustompack.mf.cowgirl01",
      "name": "Custom Cowgirl 01",
      "tags": ["paired", "mf", "cowgirl", "mycustompack"],
      "roles": [{"name": "male"}, {"name": "female"}],
      "stages": [
        {
          "loops": 0,
          "name": "cowgirl01",
          "tags": ["cowgirl"],
          "clips": ["MyPack/Animations/cowgirl01.glb"]
        }
      ]
    }
  ]
}[/code]

Generic fallback tiers (T3c, T4c, T5c) query standard tags like ["paired", "mf", actionTag], meaning custom packs work out of the box without requiring manual script updates.

[heading][center][color=#ff7700]Requirements:[/color][/center]
[/heading]
[b]Starfield (Base Game)[/b] - v1.16.244 (tested only on this release)

[b]Compatibility & Save Safety:[/b]
[list]
[*]Does not alter vanilla game records (clean, conflict-free integration).[/*]
[*]Does not overwrite any third-party mod files.[/*]
[*]Safe to install on existing saves. (As with any scripted mod, keeping a backup save before installing is always good practice).[/*]
[*][color=#cc0000][b][u]Uninstalling: [/u][/b]The mod's quest (Start Game Enabled) is saved with your game while the mod is active. Cleanest removal: with the mod still enabled, open the console and type:[/color]
[quote][color=#ffffff]help OSF_AutonomousManager_Quest QUST[/color][/quote]
[color=#cc0000]Note the FormID shown for the quest, then stop it by running:[/color]
[quote][color=#ffffff]StopQuest <FormID>[/color][/quote]
[color=#cc0000]Make a clean save, then exit, disable/remove the mod files, and load that clean save. No vanilla records are ever modified.[/color][/*]
[*]Automatically cancels active scenes during combat, ship takeoff/landing, grav jumps, docking, or transitions to disallowed locations.[/*]
[*]Fully compatible alongside other OSF addons and extensions.[/*]
[/list]
[heading][center][color=#ff0000]Shout outs:[/color][/center]
[/heading]
[list]
[*][b][url=https://www.nexusmods.com/starfield/users/142700858]ozooma10[/url] - [/b]For creating the OSF Animation framework and OSFUI. The schema-driven MCM system made it straightforward to build a comprehensive in-game configuration menu without needing custom DLL work. And, of course, for the great animation packs for OSF too! ;)[/*]
[*][b]Gergel Ebanex authors - [/b]For creating an expansive library of 388+ furniture-supported animations that provide the backbone of scene variety.[/*]
[*][b]SnuSnu Field author[/b] - For the great femdom animations, strapon integration, and demonstrating effective tag-based pack conventions.[/*]
[/list]
[center][b]Feedback & Support[/b]
This is a v1.0.0 initial release built and tested during my own playthroughs. If you encounter any bugs, weird edge cases, or have suggestions for new features, please drop a comment or bug report on the mod page. [/center]
[center][b]Remember, this mod DEPENDS on OSF so not all magic can be done by my side ;)[/b][/center]
