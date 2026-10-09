ScriptName OSF_AutonomousManagerScript Extends Quest
{OSF Autonomous NPC Interactions — manager quest script.
 Scans for eligible NPC pairs during idle/sandbox situations and starts
 OSF Animation scenes. Pure Papyrus + OSF UI JSON settings. No C++ DLL required.}

; --- Timer IDs (constants) ---
int Property TIMER_ID_SCAN = 1 Auto Const
{Timer ID for the scan loop.}
int Property TIMER_ID_SCENE_TIMEOUT = 2 Auto Const
{Timer ID for scene timeout enforcement.}
int Property TIMER_ID_SETTINGS_RETRY = 3 Auto Const
{Timer ID for OSFSettings registration retry (plugin may still be initing at VM thaw).}

; --- Mod ID for OSF UI settings ---
String Property MOD_ID = "osf.autonomous" Auto Const
{OSF UI settings mod id. Must match the JSON schema file.}

; --- User log name (writes to Logs/Script/User/OSF_Autonomous.log) ---
String Property LOG_NAME = "OSF_Autonomous" Auto Const

; --- Helper: trace to user log (not main Papyrus log) ---
Function Log(String asMessage, int aiSeverity = 0)
    Debug.OpenUserLog(LOG_NAME)
    Debug.TraceUser(LOG_NAME, asMessage, aiSeverity)
EndFunction

; --- Internal state (not properties — invisible to the CK, but serialized ---
; --- in saves like every script var; OnPlayerLoadGame realigns them) ---
int[] activeSceneHandles
float[] sceneStartTimes        ; REAL-time when each scene started (parallel to activeSceneHandles)
int[] finaleTriggeredHandles   ; handle-based finale tracking — immune to array shifts
Actor[] sceneActorA             ; tracked participants (parallel to activeSceneHandles) — for ghost scene cleanup
Actor[] sceneActorB             ; second actor (None for solo scenes)
Actor[] cooldownActors
float[] cooldownEndTimes
String[] pairCooldownKeys      ; pair cooldown tracking (FormID_A:FormID_B)
float[] pairCooldownEndTimes
int iTagRotationIndex = 0      ; rotates through mood tags for scene variety

; --- Manager quest record (secondary bound-vs-ghost dedup — see IsBoundInstance) ---
int Property MANAGER_QUEST_FORMID = 0x01000801 Auto Const
{File-local FormID of this quest in OSFAutonomous.esm. Optional dedup probe only —
 a variant with a different quest FormID (e.g. LIGHT) must still pass via boundness.}
OSF_AutonomousManagerScript managerQuestCache = None  ; resolved once — no GetFormFromFile in timers/events
bool managerQuestLookedUp = false

; --- Version migration (prevents save corruption on script updates) ---
int Property CURRENT_VERSION = 4 AutoReadOnly
int Property iInstalledVersion = 0 Auto
int iSceneCallbackToken = 0
bool bIsOnShip = false
bool bSettingsWarned = false          ; logs the RegisterForChanges failure once
bool bDependencyNotified = false      ; one-shot user alert for missing/old OSF UI
int iSettingsRetryCount = 0           ; bounded retries — max 3 at 5s intervals

; --- Cached keyword forms (loaded once in OnQuestInit, never in hot loops) ---
Keyword kActorTypeRobot
Keyword kIsSleepFurniture
Keyword kCrewCompanion
Keyword kCrewGeneric
Keyword kCrewElite
Keyword kActorTypeHuman
Keyword kActorTypeChild
Race kHumanCrowdRace        ; Crowd NPCs — different skeleton, OSF crash risk
Race kMannequinRace         ; Mannequins — different skeleton
Faction kCurrentCompanionFaction  ; For romance exclusivity check
Faction kCurrentCrewFaction       ; For recruited crew check (CurrentCrewFaction 0x00014312)
Keyword kLocTypePlayerOutpost     ; LocTypeOutpost — player outpost locations
Keyword kLocTypePlayerHouse       ; LocTypePlayerHouse — purchasable homes/apartments

; --- Furniture keywords (search all types, not just beds) ---
Keyword kAnimFurnChair            ; AnimFurnChair — free-standing chairs, office chairs
Keyword kAnimFurnBench            ; AnimFurnBench — couches, sofas, benches
; Removed (SF-TIK-007): AnimFurnSitTable / AnimFurnStool / AnimFurnBarStool /
; SpaceshipCockpitPilotSeat — anchors from these types produced rejection spam
; in dense interiors and are no longer queried.

; --- Planet atmosphere keywords (vacuum/suit-required guard) ---
Keyword kPlanetAtmoO2             ; PlanetAtmosphereType05O2
Keyword kPlanetAtmoHighO2         ; PlanetAtmosphereType06HighO2
Keyword kPlanetAtmoLowO2          ; PlanetAtmosphereType07LowO2
ActorValue kAvHideHelmetBreathable ; ActorShouldHideSpacesuitHelmetCosmeticBreathable_AV — engine's own "breathable zone" signal

; --- Cached gear forms (Dick/Haters attachments) ---
Form kDickGear              ; Dick.esm|0x800
Form kDickFlaccidGear       ; Dick.esm|0x81B
Form kDickErectGear         ; Dick.esm|0x81D
Form kDickErect2Gear        ; Dick.esm|0x820
Form kHatersGear            ; Haters Body.esm|0x804

; ===========================================================================
; Lifecycle
; ===========================================================================

Event OnQuestInit()
    ; --- Load keyword forms once (no GetFormFromFile in hot loops) ---
    InitKeywords()
    InitGearForms()

    ; --- Initialize state arrays ---
    EnsureArraysInitialized()
    iInstalledVersion = CURRENT_VERSION

    ; --- Register for remote events on the player ---
    Actor player = Game.GetPlayer()
    RegisterForRemoteEvent(player, "OnPlayerLoadGame")
    RegisterForRemoteEvent(player, "OnLocationChange")
    RegisterForRemoteEvent(player, "OnCombatStateChanged")
    RegisterForRemoteEvent(player, "OnEnterShipInterior")
    RegisterForRemoteEvent(player, "OnExitShipInterior")
    RegisterForRemoteEvent(player, "OnSit")

    ; Pause menu = the only reachable path to manual save and quit-to-menu.
    ; Stop all scenes when it opens so a save never captures mid-scene state.
    RegisterForMenuOpenCloseEvent("PauseMenu")

    ; --- Register for ship lifecycle events (takeoff, grav jump, dock, landing) ---
    SpaceshipReference ship = player.GetCurrentShipRef()
    if ship != None
        RegisterForRemoteEvent(ship, "OnShipGravJump")
        RegisterForRemoteEvent(ship, "OnShipTakeOff")
        RegisterForRemoteEvent(ship, "OnShipDock")
        RegisterForRemoteEvent(ship, "OnShipLanding")
    endif

    ; --- Register OSF scene callbacks (DLL forgets them on load) ---
    RegisterOSFCallbacks()

    ; --- Register OSF Settings change listener (session-scoped) ---
    RegisterSettingsListener()

    ; --- Check initial ship state ---
    ; An interior cell + an owned ship does NOT mean the player is aboard —
    ; stations, bars and clubs are interiors too. Verify the cell's parent
    ; ref is the player's current ship via Cell.GetParentRef().
    bIsOnShip = IsPlayerInOwnShip()

    ; Timer is unconditionally alive from birth — OnTimer re-evaluates the
    ; location gate every tick, so a denied initial location self-heals.
    ResumeScanTimer()
    if IsEnabled()
        Log("OnQuestInit — scan timer started (" + GetCheckInterval() + "s)")
    else
        Log("OnQuestInit — mod disabled (or OSFSettings unavailable), scan timer idle")
    endif

    Log("OnQuestInit — robotKW=" + kActorTypeRobot + " sleepKW=" + kIsSleepFurniture + " humanKW=" + kActorTypeHuman + " childKW=" + kActorTypeChild + " onShip=" + bIsOnShip)
EndEvent

Function InitKeywords()
    ; Load keyword forms once — called from OnQuestInit and OnPlayerLoadGame
    if kActorTypeRobot == None
        kActorTypeRobot    = Game.GetFormFromFile(0x002702C9, "Starfield.esm") as Keyword  ; ActorTypeRobot
    endif
    if kIsSleepFurniture == None
        kIsSleepFurniture  = Game.GetFormFromFile(0x00021B18, "Starfield.esm") as Keyword  ; IsSleepFurniture
    endif
    if kCrewCompanion == None
        kCrewCompanion     = Game.GetFormFromFile(0x002705E4, "Starfield.esm") as Keyword  ; Crew_CrewTypeCompanion
    endif
    if kCrewGeneric == None
        kCrewGeneric       = Game.GetFormFromFile(0x00270728, "Starfield.esm") as Keyword  ; Crew_CrewTypeGeneric
    endif
    if kCrewElite == None
        kCrewElite         = Game.GetFormFromFile(0x00270729, "Starfield.esm") as Keyword  ; Crew_CrewTypeElite
    endif
    if kActorTypeHuman == None
        kActorTypeHuman    = Game.GetFormFromFile(0x0025E194, "Starfield.esm") as Keyword  ; ActorTypeHuman
    endif
    if kActorTypeChild == None
        kActorTypeChild    = Game.GetFormFromFile(0x001157E8, "Starfield.esm") as Keyword  ; ActorTypeChild
    endif
    if kHumanCrowdRace == None
        kHumanCrowdRace    = Game.GetFormFromFile(0x002BBC09, "Starfield.esm") as Race     ; HumanCrowdRace
    endif
    if kMannequinRace == None
        kMannequinRace     = Game.GetFormFromFile(0x001EE4DA, "Starfield.esm") as Race     ; MannequinRace
    endif
    if kCurrentCompanionFaction == None
        kCurrentCompanionFaction = Game.GetFormFromFile(0x00023C01, "Starfield.esm") as Faction  ; CurrentCompanionFaction
    endif
    if kCurrentCrewFaction == None
        kCurrentCrewFaction = Game.GetFormFromFile(0x00014312, "Starfield.esm") as Faction  ; CurrentCrewFaction
    endif
    if kLocTypePlayerOutpost == None
        kLocTypePlayerOutpost = Game.GetFormFromFile(0x000234F1, "Starfield.esm") as Keyword  ; LocTypeOutpost (player outpost locations)
    endif
    if kLocTypePlayerHouse == None
        kLocTypePlayerHouse = Game.GetFormFromFile(0x002EF272, "Starfield.esm") as Keyword  ; LocTypePlayerHouse
    endif
    if kAnimFurnChair == None
        kAnimFurnChair    = Game.GetFormFromFile(0x00021BF1, "Starfield.esm") as Keyword  ; AnimFurnChair
    endif
    if kAnimFurnBench == None
        kAnimFurnBench    = Game.GetFormFromFile(0x003A2DF2, "Starfield.esm") as Keyword  ; AnimFurnBench
    endif
    if kPlanetAtmoO2 == None
        kPlanetAtmoO2     = Game.GetFormFromFile(0x00295EA4, "Starfield.esm") as Keyword  ; PlanetAtmosphereType05O2
    endif
    if kPlanetAtmoHighO2 == None
        kPlanetAtmoHighO2 = Game.GetFormFromFile(0x00295EA3, "Starfield.esm") as Keyword  ; PlanetAtmosphereType06HighO2
    endif
    if kPlanetAtmoLowO2 == None
        kPlanetAtmoLowO2 = Game.GetFormFromFile(0x00295EA2, "Starfield.esm") as Keyword   ; PlanetAtmosphereType07LowO2
    endif
    if kAvHideHelmetBreathable == None
        kAvHideHelmetBreathable = Game.GetFormFromFile(0x000B120B, "Starfield.esm") as ActorValue   ; ActorShouldHideSpacesuitHelmetCosmeticBreathable_AV
    endif
    if kActorTypeRobot == None
        Log("WARNING: ActorTypeRobot keyword not loaded — robot filter inactive")
    endif
    if kIsSleepFurniture == None
        Log("WARNING: IsSleepFurniture keyword not loaded — furniture detection inactive")
    endif
    if kLocTypePlayerOutpost == None
        Log("WARNING: LocTypeOutpost keyword not loaded — player outpost detection inactive")
    endif
    if kLocTypePlayerHouse == None
        Log("WARNING: LocTypePlayerHouse keyword not loaded — player home detection inactive")
    endif
    if kPlanetAtmoO2 == None || kPlanetAtmoHighO2 == None || kPlanetAtmoLowO2 == None
        Log("WARNING: planet atmosphere keywords not loaded — vacuum/suit guard will block all exteriors")
    endif
EndFunction

Function InitGearForms()
    ; Load strapon/erection gear forms once so we can safely unequip them after scenes.
    ; These are read from Data\OSF\attachments.osfgear.json mapping + Dick.esm variants.
    ; Guard with IsPluginInstalled to avoid Papyrus missing-form log spam.
    if Game.IsPluginInstalled("Dick.esm")
        if kDickGear == None
            kDickGear = Game.GetFormFromFile(0x00000800, "Dick.esm")        ; Dick
        endif
        if kDickFlaccidGear == None
            kDickFlaccidGear = Game.GetFormFromFile(0x0000081B, "Dick.esm") ; DickFlaccid
        endif
        if kDickErectGear == None
            kDickErectGear = Game.GetFormFromFile(0x0000081D, "Dick.esm")  ; DickErect
        endif
        if kDickErect2Gear == None
            kDickErect2Gear = Game.GetFormFromFile(0x00000820, "Dick.esm") ; DickErect2
        endif
    endif
    if Game.IsPluginInstalled("Haters Body.esm")
        if kHatersGear == None
            kHatersGear = Game.GetFormFromFile(0x00000804, "Haters Body.esm") ; Erection
        endif
    endif

    ; Scene packs author their own equip refs (e.g. Dick.esm|0x81D strap-on) that
    ; OSF resolves per scene. If none of the known gear plugins resolve, FF/MF
    ; scenes simply run without gear — surface that as a Mod Issues warning so
    ; the user can install a gear mod or fix their *.osf.json equip strings.
    if kDickErectGear == None && kHatersGear == None
        OSFSettings.ReportIssue(MOD_ID, "gear", "No strap-on/erection gear plugins found", false, "Paired scenes play without auto-equipped gear (FF pairs get no strap-on)", "Install Dick.esm / Haters Body.esm, or edit 'equip' strings in Data/OSF/*.osf.json to point at gear you have")
    else
        OSFSettings.ClearIssue(MOD_ID, "gear")
    endif
EndFunction

Function UnequipStuckAttachments(Actor akActor)
    ; Some SOS/strapon mods (Dick.esm, Haters Body) leave their gear equipped after a scene
    ; when OSF's built-in strip/restore fails to remove it. Force-remove known forms.
    ; Unequip alone is not enough: the item stays in inventory and the actor's AI
    ; re-equips it on the next package evaluation. This only touches these specific
    ; gear items, never the full inventory. Never touch the player.
    if akActor == None || akActor == Game.GetPlayer()
        return
    endif
    ; Scene-introduced gear — OSF equips these via pack roles; deleting is safe
    RemoveStuckGear(akActor, kDickGear)
    RemoveStuckGear(akActor, kDickErectGear)
    RemoveStuckGear(akActor, kDickErect2Gear)
    RemoveStuckGear(akActor, kHatersGear)
    ; Flaccid gear may be base anatomy auto-worn when nude — unequip only;
    ; deleting all copies could permanently strip the actor's anatomy
    UnequipOnlyGear(akActor, kDickFlaccidGear)
EndFunction

Function RemoveStuckGear(Actor akActor, Form akGear)
    if akGear != None && akActor.GetItemCount(akGear) > 0
        akActor.UnequipItem(akGear, false, true)
        akActor.RemoveItem(akGear, akActor.GetItemCount(akGear), true)
        Log("Removed stuck gear " + akGear + " from " + akActor)
    endif
EndFunction

Function UnequipOnlyGear(Actor akActor, Form akGear)
    if akGear != None && akActor.IsEquipped(akGear)
        akActor.UnequipItem(akGear, false, true)
        Log("Unequipped persistent gear " + akGear + " on " + akActor)
    endif
EndFunction

; ===========================================================================
; OSF Scene Callback Registration
; ===========================================================================

Function RegisterOSFCallbacks()
    if !OSF.IsReady()
        Log("RegisterOSFCallbacks — OSF not ready, skipping")
        return
    endif
    if iSceneCallbackToken
        OSF.UnregisterSceneCallback(iSceneCallbackToken)
        iSceneCallbackToken = 0
    endif
    ; Register for BEGIN + END + CUE + NODE_EXIT (for stage advancement)
    ; Never EVENT_ALL — prevents callback storms
    int eventMask = OSF.EVENT_SCENE_BEGIN() + OSF.EVENT_SCENE_END() + OSF.EVENT_CUE() + OSF.EVENT_NODE_EXIT()
    iSceneCallbackToken = OSF.RegisterSceneCallback(self, "OnSceneEvent", 0, eventMask)
    if iSceneCallbackToken == 0
        Log("WARNING: RegisterSceneCallback failed — scene events will not fire")
    endif
EndFunction

; ===========================================================================
; OSF Settings Listener Registration
; ===========================================================================

; OSFSettings registrations are session-scoped (auto-cleared on game load) and
; the API contract requires subscribing before the first settings read — call
; this from both OnQuestInit and OnPlayerLoadGame, ahead of ResumeScanTimer().
; A missing OSFSettings plugin fails the call: the Papyrus VM reports it in
; the main log, we mirror a readable line into the user log, and every Get*
; reader below returns the VM default — the mod stays disabled.
Function RegisterSettingsListener()
    if !IsBoundInstance()
        return  ; ghost — RegisterForChanges requires a bound receiver anyway
    endif
    if OSFSettings.RegisterForChanges(self, MOD_ID)
        iSettingsRetryCount = 0
        bSettingsWarned = false
        bDependencyNotified = false
        OSFSettings.ClearIssue(MOD_ID, "dependency")
        return
    endif
    ; Always retry (bounded) — OSF Settings is a standalone plugin that does
    ; NOT require OSF UI, so the OSFUI version cannot gate retry eligibility:
    ; an OSFSettings-only install would otherwise get zero retries on the
    ; transient init race at VM thaw. The version probe below only picks the
    ; final user-facing message.
    if !bSettingsWarned
        Log("WARNING: OSFSettings.RegisterForChanges failed — retrying")
        bSettingsWarned = true
    endif
    iSettingsRetryCount += 1
    if iSettingsRetryCount <= 3
        StartTimer(5.0, TIMER_ID_SETTINGS_RETRY)
        return
    endif
    ; Retries exhausted — classify for the message only. OSFUI.GetVersion
    ; exists on both OSF UI generations and still resolves when OSFSettings
    ; is missing entirely, so it can tell "old OSF UI install" apart.
    String reason = "OSF Settings plugin unavailable — install OSF Settings (ships with OSF UI 2.0+)"
    int uiVersion = OSFUI.GetVersion()
    if uiVersion > 0 && uiVersion < 20000
        reason = "OSF UI " + OSFUI.GetVersionString() + " too old — OSF UI 2.0+ required"
    endif
    NotifyDependencyProblem(reason)
EndFunction

; One-time per session escalation for a broken hard dependency: user log +
; visible in-game notification + an entry in the OSF Settings "Mod Issues"
; panel (the last one fails harmlessly when OSFSettings itself is absent —
; exactly the case where the notification matters most).
Function NotifyDependencyProblem(String asReason)
    if bDependencyNotified
        return
    endif
    bDependencyNotified = true
    Log("ERROR: " + asReason + " — OSF Autonomous disabled")
    Debug.Notification("OSF Autonomous: " + asReason + " — mod disabled")
    OSFSettings.ReportIssue(MOD_ID, "dependency", asReason, true, "All autonomous scenes stopped", "Install/update OSF Settings (ships with OSF UI 2.0+) and reload")
EndFunction

; Saves can carry a stale "ghost" copy of this script — an instance detached
; from the quest record (e.g. after a quest restart, or an update to a
; variant whose quest record has a different FormID). It keeps receiving
; remote events serialized in the save, but every engine-facing call on it
; fails and fills Papyrus.0.log with "unbound script" errors, so event
; handlers early-out on this check.
;
; Two layers, deliberately FormID-agnostic first:
; 1. IsBoundGameObjectAvailable() — the native check built for exactly this:
;    a ghost has no bound game object. Needs no FormID or plugin name, so a
;    quest refID change between mod variants (e.g. a LIGHT build) can never
;    brick the live instance.
; 2. When the canonical quest record resolves, additionally de-duplicate:
;    only the instance attached to it is live (a second OSFAutonomous plugin
;    would ghost the foreign instance). When it doesn't resolve — variant
;    with a different quest FormID or plugin filename — boundness alone is
;    enough; returning false there would kill the real manager.
bool Function IsBoundInstance()
    if !IsBoundGameObjectAvailable()
        return false  ; save-carried ghost — detached from any game object
    endif
    if !managerQuestLookedUp
        managerQuestLookedUp = true
        managerQuestCache = Game.GetFormFromFile(MANAGER_QUEST_FORMID, "OSFAutonomous.esm") as OSF_AutonomousManagerScript
    endif
    if managerQuestCache == None
        return true   ; quest record moved/renamed in this variant — bound is enough
    endif
    return managerQuestCache == self
EndFunction

; ===========================================================================
; OSF Scene Event Handler (called by OSF native relay)
; ===========================================================================

Function OnSceneEvent(OSFTypes:SceneEvent akEvent)
    if !IsBoundInstance()
        return  ; stale unbound instance — let the bound copy handle it
    endif
    if akEvent == None
        return
    endif

    if akEvent.eventType == OSF.EVENT_SCENE_BEGIN()
        ; Ignore foreign/untracked scenes — this manager only owns handles it
        ; registered in TryStartScene/TryStartSoloScene
        if activeSceneHandles.Find(akEvent.sceneHandle) < 0
            return  ; not our scene
        endif
        ; Scene started — handle is already tracked in TryStartScene
        Log("Scene BEGIN — handle=" + akEvent.sceneHandle)

        ; Apply initial speed to all participants (calculate ONCE for consistency)
        float initialSpeed = CalculateInitialSpeed()
        Actor[] beginParts = OSF.GetSceneParticipants(akEvent.sceneHandle)
        int bi = 0
        while bi < beginParts.Length
            if beginParts[bi] != None
                OSF.SetSpeed(beginParts[bi], initialSpeed)
            endif
            bi += 1
        endwhile
        if beginParts.Length > 0
            Log("Speed set to " + initialSpeed + " (" + GetSpeedMode() + ") for " + beginParts.Length + " actors")
        endif

    elseif akEvent.eventType == OSF.EVENT_NODE_EXIT()
        ; A stage/node ended — try to advance to the next stage if MCM enabled
        if IsAdvanceStages()
            int handle = akEvent.sceneHandle
            if handle > 0 && activeSceneHandles.Find(handle) >= 0
                int edgeCount = OSF.GetSceneEdgeCount(handle)
                if edgeCount > 0
                    ; If multiple edges, pick a random one for variety
                    bool advanced = false
                    if edgeCount > 1
                        int pickedEdge = Utility.RandomInt(0, edgeCount - 1)
                        string edgeId = OSF.GetSceneEdgeId(handle, pickedEdge)
                        advanced = OSF.NavigateScene(handle, edgeId)
                        if advanced
                            Log("Scene navigated — handle=" + handle + " edge=" + edgeId + " (" + (pickedEdge + 1) + "/" + edgeCount + ")")
                        endif
                    endif
                    if !advanced
                        ; Single edge or navigate failed — use default advance
                        advanced = OSF.AdvanceScene(handle)
                        if advanced
                            Log("Scene advanced — handle=" + handle + " edges=" + edgeCount)
                        else
                            Log("Scene advance failed — handle=" + handle + " (scene may be ending)")
                        endif
                    endif

                    ; Dynamic speed acceleration on stage advance
                    if advanced && GetSpeedMode() == "dynamic"
                        Actor[] dynParts = OSF.GetSceneParticipants(handle)
                        if dynParts.Length > 0 && dynParts[0] != None
                            float currentSpeed = OSF.GetSpeed(dynParts[0])
                            if currentSpeed < 0.5
                                currentSpeed = 0.85
                            endif
                            float newSpeed = currentSpeed + 0.15
                            if newSpeed > 1.5
                                newSpeed = 1.5
                            endif
                            int di = 0
                            while di < dynParts.Length
                                if dynParts[di] != None
                                    OSF.SetSpeed(dynParts[di], newSpeed)
                                endif
                                di += 1
                            endwhile
                            Log("Dynamic speed accelerated to " + newSpeed + " on handle " + handle)
                        endif
                    endif
                endif
            endif
        endif

    elseif akEvent.eventType == OSF.EVENT_SCENE_END()
        int handle = akEvent.sceneHandle

        ; Only process scenes we started — ignore foreign mod scenes and player manual scenes
        SyncSceneTracking()  ; heal any parallel-array skew before indexed removes
        int idx = activeSceneHandles.Find(handle)
        if idx < 0
            return  ; Not our scene — ignore
        endif

        if finaleTriggeredHandles == None
            finaleTriggeredHandles = new int[0]
        endif

        ; Capture tracked actors BEFORE removal — abort/ghost END events can
        ; arrive with OSF.GetSceneParticipants already empty; these are the
        ; cleanup fallback so cooldown/anchor/gear teardown still runs.
        Actor tA = None
        Actor tB = None
        if idx < sceneActorA.Length
            tA = sceneActorA[idx]
        endif
        if idx < sceneActorB.Length
            tB = sceneActorB[idx]
        endif

        activeSceneHandles.Remove(idx)
        if idx < sceneStartTimes.Length
            float duration = Utility.GetCurrentRealTime() - sceneStartTimes[idx]
            if duration < 0.0
                ; Start timestamp was stale (stored before process restart) — not a real early end
                Log("Scene " + handle + " duration unknown — stale start time (" + duration + "s)")
            elseif duration < 5.0
                Log("WARNING: Scene " + handle + " ended abnormally fast (" + duration + "s) — likely InPlace alignment or collision failure")
            elseif duration < 30.0
                ; Diagnostic: log participant states for short-lived scenes (5-30s)
                ; Common cause: sandbox AI pulled actor away, or OSF internal abort
                Actor[] diagParts = OSF.GetSceneParticipants(handle)
                int dp = 0
                while dp < diagParts.Length
                    Actor dpA = diagParts[dp]
                    if dpA != None
                        string dpState = "running=" + dpA.IsRunning() + " combat=" + dpA.IsInCombat() + " dialogue=" + dpA.IsInDialogueWithPlayer() + " sitState=" + dpA.GetSitState() + " isPlaying=" + OSF.IsPlaying(dpA)
                        Log("SHORT SCENE DIAG — handle=" + handle + " duration=" + duration + "s actor=" + dpA + " " + dpState)
                    endif
                    dp += 1
                endwhile
            endif
            sceneStartTimes.Remove(idx)
        endif
        if idx < sceneActorA.Length
            sceneActorA.Remove(idx)
        endif
        if idx < sceneActorB.Length
            sceneActorB.Remove(idx)
        endif
        ; Handle-based finale tracking — remove by value
        int fIdx = finaleTriggeredHandles.Find(handle)
        if fIdx >= 0
            finaleTriggeredHandles.Remove(fIdx)
        endif
        ; Set cooldowns for participants and return them to sandbox AI
        Actor[] participants = OSF.GetSceneParticipants(handle)
        int cooldownCount = 0
        int i = 0
        while i < participants.Length
            Actor p = participants[i]
            if p != None
                ApplyCooldownToActor(p)
                cooldownCount += 1
            endif
            i += 1
        endwhile
        ; Fallback for tracked actors not in the participants list (ghost ENDs)
        if tA != None && participants.Find(tA) < 0
            ApplyCooldownToActor(tA)
            cooldownCount += 1
        endif
        if tB != None && participants.Find(tB) < 0
            ApplyCooldownToActor(tB)
            cooldownCount += 1
        endif

        Log("Scene END — handle=" + handle + " cooldowns set for " + cooldownCount + " actors")

    elseif akEvent.eventType == OSF.EVENT_CUE()
        ; Optional: log orgasm cue for future affinity integration
        if akEvent.cue == "orgasm"
            Log("Cue: orgasm (scene=" + akEvent.sceneHandle + ")")
        endif
    endif
EndFunction

; ===========================================================================
; OSF Settings Change Handler (callback name fixed by OSFSettings contract)
; ===========================================================================

; Invoked by OSFSettings for each changed key. An empty asKey means "reread
; all" — including the notification sent right after RegisterForChanges — so
; it is treated as if both stateful gates (bEnabled + sLocationMode) changed.
; All other keys are read live at point of use and need no side effects here.
Function OnOSFSettingChanged(String asModId, String asKey)
    if !IsBoundInstance()
        return  ; ghost — CancelTimer/EmergencyStopAll would fail unbound
    endif
    if asModId != MOD_ID
        return
    endif

    if asKey != "" && asKey != "bEnabled" && asKey != "sLocationMode"
        return
    endif

    if !IsEnabled()
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("Mod disabled via OSF Settings")
        return
    endif
    if !IsLocationAllowed()
        ; Timer stays alive — OnTimer gates the location each tick
        EmergencyStopAll()
        ResumeScanTimer()
        Log("Location denied after settings change — scenes stopped, scan idles")
        return
    endif
    ; Timer always resumes — OnTimer gates each tick, so re-enabling while the
    ; location is denied still self-heals on the next scan.
    ResumeScanTimer()
    if asKey == "bEnabled"
        Log("Mod re-enabled via OSF Settings")
    elseif asKey == "sLocationMode"
        Log("Location mode changed — scanning active")
    endif
EndFunction

; ===========================================================================
; Remote Events (on Player Actor)
; ===========================================================================

Function EnsureArraysInitialized()
    if activeSceneHandles == None
        activeSceneHandles = new int[0]
    endif
    if sceneStartTimes == None
        sceneStartTimes = new float[0]
    endif
    if finaleTriggeredHandles == None
        finaleTriggeredHandles = new int[0]
    endif
    if sceneActorA == None
        sceneActorA = new Actor[0]
    endif
    if sceneActorB == None
        sceneActorB = new Actor[0]
    endif
    if cooldownActors == None
        cooldownActors = new Actor[0]
    endif
    if cooldownEndTimes == None
        cooldownEndTimes = new float[0]
    endif
    if pairCooldownKeys == None
        pairCooldownKeys = new String[0]
    endif
    if pairCooldownEndTimes == None
        pairCooldownEndTimes = new float[0]
    endif
EndFunction

Function SyncSceneTracking()
    ; Keep all scene-parallel arrays aligned to activeSceneHandles.
    ; Stale extra entries can persist across saves (GetCurrentRealTime is process
    ; uptime — values stored before a restart are meaningless) and then poison the
    ; elapsed math for every scene started afterwards (scenes cut early or
    ; "abnormally fast" warnings with bogus durations).
    EnsureArraysInitialized()
    int n = activeSceneHandles.Length
    while sceneStartTimes.Length > n
        sceneStartTimes.Remove(sceneStartTimes.Length - 1)
    endwhile
    while sceneActorA.Length > n
        sceneActorA.Remove(sceneActorA.Length - 1)
    endwhile
    while sceneActorB.Length > n
        sceneActorB.Remove(sceneActorB.Length - 1)
    endwhile
    float nowReal = Utility.GetCurrentRealTime()
    ; Padded scenes get a fresh start time — deliberately generous. An unknown
    ; start means tracking was corrupt; killing via elapsed=now could terminate
    ; a healthy scene, while ghost scenes are reaped by AuditActiveScenes via
    ; OSF.IsPlaying regardless of elapsed time.
    while sceneStartTimes.Length < n
        sceneStartTimes.Add(nowReal, 1)
    endwhile
    while sceneActorA.Length < n
        sceneActorA.Add(None, 1)
    endwhile
    while sceneActorB.Length < n
        sceneActorB.Add(None, 1)
    endwhile
EndFunction

Event Actor.OnPlayerLoadGame(Actor akSender)
    if !IsBoundInstance()
        return  ; stale unbound instance — let the bound copy handle it
    endif
    if akSender != Game.GetPlayer()
        return
    endif

    ; Version marker — do NOT wipe tracking arrays here. Handles saved
    ; mid-scene are dead after load anyway (OSF state is session-scoped), and
    ; clearing sceneActorA/B would orphan ghost cleanup: AuditActiveScenes
    ; below needs those tracked actors to apply cooldown + anchor/gear cleanup.
    ; EnsureArraysInitialized + SyncSceneTracking heal any array skew.
    if iInstalledVersion < CURRENT_VERSION
        Log("Script updated from v" + iInstalledVersion + " to v" + CURRENT_VERSION)
        iInstalledVersion = CURRENT_VERSION
    endif

    ; Dependency state is session-scoped — non-Property vars persist in the
    ; save, so a stale exhausted retry count would skip retries forever and a
    ; stale notified flag would swallow the alert on every later load.
    iSettingsRetryCount = 0
    bSettingsWarned = false
    bDependencyNotified = false

    ; Safety: ensure all arrays are non-None, then realign scene-parallel arrays —
    ; sceneStartTimes stores process uptime, so values saved before a restart are
    ; stale and shift every new scene's elapsed calculation (early timeouts,
    ; negative "abnormally fast" durations).
    EnsureArraysInitialized()
    SyncSceneTracking()

    ; DLL forgot all callback registrations — re-register
    RegisterOSFCallbacks()

    ; Re-initialize keywords (safeguard for existing saves)
    InitKeywords()
    InitGearForms()
    
    ; Ensure OnSit is registered for existing saves
    RegisterForRemoteEvent(Game.GetPlayer(), "OnSit")

    ; Pause menu = the only reachable path to manual save and quit-to-menu.
    ; Stop all scenes when it opens so a save never captures mid-scene state.
    RegisterForMenuOpenCloseEvent("PauseMenu")

    ; Re-register OSF Settings listener — registrations are session-scoped and
    ; cleared on every load; the new API has no token/unregister to manage.
    RegisterSettingsListener()

    ; Re-evaluate timer state.
    ; OnEnterShipInterior won't fire on load if player was already inside, so
    ; recompute here. "Interior + owns a ship" is NOT a valid check — stations,
    ; bars and clubs are interiors too. Verify the cell's parent ref is the
    ; player's own ship (SF-TIK-008).
    SpaceshipReference ship = Game.GetPlayer().GetCurrentShipRef()
    bIsOnShip = IsPlayerInOwnShip()
    if ship != None
        RegisterForRemoteEvent(ship, "OnShipGravJump")
        RegisterForRemoteEvent(ship, "OnShipTakeOff")
        RegisterForRemoteEvent(ship, "OnShipDock")
        RegisterForRemoteEvent(ship, "OnShipLanding")
    endif
    ; Keep the scan timer alive unconditionally — OnTimer re-checks
    ; IsLocationAllowed every tick, so a denied location just idles and
    ; self-heals when the check starts passing (or after a load-time misfire).
    ResumeScanTimer()
    IsLocationAllowed()  ; evaluate once now so the denial reason lands in the log

    ; Purge any scenes that exceeded timeout while cell was unloaded
    EnforceSceneTimeouts()
    AuditActiveScenes()

    Log("OnPlayerLoadGame — callbacks re-registered, active scenes=" + activeSceneHandles.Length)
EndEvent

; ===========================================================================
; OnQuestInit runs AFTER OnPlayerLoadGame on first load with a new mod.
; If OnPlayerLoadGame fired first and failed to start a timer (unbound script),
; OnQuestInit will handle it. This flag prevents duplicate timer starts.
; ===========================================================================

Event Actor.OnLocationChange(Actor akSender, Location akOldLoc, Location akNewLoc)
    if !IsBoundInstance()
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif

    ; Recompute ship state from the cell — enter/exit ship events can arrive
    ; out of order across station/docked transitions, so a cached flag alone
    ; is fragile. Cell-derived check is self-healing (SF-TIK-008).
    bIsOnShip = IsPlayerInOwnShip()

    ; On fast travel or grav jump to a new location, existing scenes may have unloaded actors
    Cell playerCell = Game.GetPlayer().GetParentCell()
    bool isInExterior = (playerCell == None || !playerCell.IsInterior())

    if IsLocationAllowed()
        if isInExterior && !IsInPrivatePlayerLocation()
            ; Purge on public exteriors — actors from the old cell unloaded.
            ; Private exteriors (outposts) keep scenes: location boundaries
            ; don't map 1:1 to cells, so participants may still be loaded.
            EmergencyStopAll()
            Log("Location change — exterior, old scenes cleared")
        else
            ; Interior (incl. own ship) — keep scenes. No eager audit here:
            ; actors may still be mid-load during the transition and would be
            ; wrongly stopped; the per-tick audit purges real ghosts anyway.
            Log("Location change — allowed interior, scanning continues")
        endif
    else
        EmergencyStopAll()
        Log("Location change — location not allowed, scenes stopped, scan idles")
    endif
    ; Timer is always alive — OnTimer re-gates each tick, so a missed resume
    ; event or a denied current cell can never strand the scanner.
    ResumeScanTimer()
EndEvent

Event OnMenuOpenCloseEvent(string asMenuName, bool abOpening)
    if !IsBoundInstance()
        return
    endif
    if asMenuName != "PauseMenu"
        return
    endif
    if abOpening
        ; Save dialog and quit-to-menu both live behind the pause menu —
        ; tear down scenes so a save never captures mid-scene state.
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("Pause menu opened — scenes stopped, scanning paused")
    else
        ResumeScanTimer()
        Log("Pause menu closed — scanning resumed")
    endif
EndEvent

Event Actor.OnSit(Actor akSender, ObjectReference akFurniture)
    if !IsBoundInstance()
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif
    ; If player takes the pilot seat, their spaceship reference becomes valid.
    ; Scenes stop; the timer stays alive — OnTimer's pilot gate idles the scan.
    if Game.GetPlayer().GetSpaceship() != None
        EmergencyStopAll()
        Log("OnSit — player started piloting, all scenes stopped")
    endif
EndEvent

Event Actor.OnEnterShipInterior(Actor akSender, ObjectReference akShip)
    if !IsBoundInstance()
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif
    ; This event also fires for starstations, docked ships and boarded NPC
    ; vessels — only flag when entering the player's own ship (SF-TIK-008).
    ; NOTE: GetCurrentShipRef() returns the ship the player is INSIDE, so
    ; comparing akShip to it is a tautology — ownership comes from the
    ; engine's player-ship registry.
    SpaceshipReference enteredShip = akShip as SpaceshipReference
    bIsOnShip = (enteredShip != None && Game.IsPlayerSpaceshipOwner(enteredShip))
    ; Register ship lifecycle events on current ship (handles ship changes mid-session)
    SpaceshipReference currentShip = Game.GetPlayer().GetCurrentShipRef()
    if currentShip != None
        RegisterForRemoteEvent(currentShip, "OnShipGravJump")
        RegisterForRemoteEvent(currentShip, "OnShipTakeOff")
        RegisterForRemoteEvent(currentShip, "OnShipDock")
        RegisterForRemoteEvent(currentShip, "OnShipLanding")
    endif
    if IsLocationAllowed()
        Log("OnEnterShipInterior — scanning started")
    else
        ; Entered a starstation or someone else's vessel — scenes stop, but the
        ; timer stays alive and OnTimer re-gates every tick (self-healing).
        EmergencyStopAll()
        Log("OnEnterShipInterior — non-player vessel/station interior, scenes stopped, scan idles")
    endif
    ResumeScanTimer()
EndEvent

Event Actor.OnExitShipInterior(Actor akSender, ObjectReference akShip)
    if !IsBoundInstance()
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif
    ; Only leaving the player's OWN ship matters — this event also fires when
    ; exiting starstations and foreign vessels, and teardown there would kill
    ; scenes running aboard the player's ship we just boarded.
    ; GetCurrentShipRef() means "ship the player is inside", not "owned" —
    ; ownership must be checked against the engine registry (SF-TIK-008).
    SpaceshipReference exitedShip = akShip as SpaceshipReference
    if exitedShip != None && !Game.IsPlayerSpaceshipOwner(exitedShip)
        return
    endif
    ; Recompute instead of blind false — cross-object enter/exit ordering is
    ; not guaranteed (e.g. station→own-ship), so derive from the actual cell.
    bIsOnShip = IsPlayerInOwnShip()
    string mode = GetLocationMode()

    ; Check if player is now in an exterior (planet surface) or interior (outpost/station)
    Cell playerCell = Game.GetPlayer().GetParentCell()
    bool isInExterior = (playerCell == None || !playerCell.IsInterior())

    if mode == "ship"
        ; Ship-only mode — always stop when leaving ship
        EmergencyStopAll()
        Log("OnExitShipInterior — mode=ship, scenes cleared, scan idles")
    elseif isInExterior
        ; Player exited to a planet surface / exterior — ship actors will unload
        ; Stop all scenes regardless of mode to prevent ghost scenes
        EmergencyStopAll()
        Log("OnExitShipInterior — exterior exit, ship scenes cleared")
    else
        ; Player moved to another interior (outpost building, docked station)
        ; Keep scenes — no eager audit during transition (actors may still be
        ; mid-load and would be wrongly stopped); per-tick audit purges ghosts.
        if !IsLocationAllowed()
            EmergencyStopAll()
            Log("OnExitShipInterior — interior transition, location not allowed, scenes cleared")
        else
            Log("OnExitShipInterior — interior transition, scenes kept")
        endif
    endif
    ; Timer never dies here — OnTimer re-gates location/combat/piloting each tick
    ResumeScanTimer()
EndEvent

Event Actor.OnCombatStateChanged(Actor akSender, ObjectReference akTarget, int aeCombatState)
    if !IsBoundInstance()
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif
    if aeCombatState == 1
        ; Entering combat — stop everything immediately; timer stays alive,
        ; OnTimer's combat gate idles the scan until fighting ends
        EmergencyStopAll()
        Log("Player entered combat — all scenes stopped")
    elseif aeCombatState == 0
        ResumeScanTimer()
        Log("Player combat ended — scanning resumed")
    endif
EndEvent

; ===========================================================================
; Ship Lifecycle Events — stop scenes during transitions
; ===========================================================================

Event SpaceshipReference.OnShipGravJump(SpaceshipReference akSender, Location aDestination, int aState)
    if !IsBoundInstance()
        return
    endif
    ; Only process events from the player's current ship
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    ; aState: 0 = departure, 1 = arrival
    if aState == 0
        ; Timer stays alive through the transition — OnTimer re-gates each
        ; tick, so a dropped arrival event can't strand the scanner.
        EmergencyStopAll()
        Log("OnShipGravJump — departure, all scenes stopped")
    elseif aState == 1
        ResumeScanTimer()
        Log("OnShipGravJump — arrival, scanning resumed")
    endif
EndEvent

Event SpaceshipReference.OnShipTakeOff(SpaceshipReference akSender, bool abComplete)
    if !IsBoundInstance()
        return
    endif
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if !abComplete
        EmergencyStopAll()
        Log("OnShipTakeOff — takeoff started, all scenes stopped")
    else
        ResumeScanTimer()
        Log("OnShipTakeOff — takeoff complete, scanning resumed")
    endif
EndEvent

Event SpaceshipReference.OnShipDock(SpaceshipReference akSender, bool abComplete, SpaceshipReference akDocking, SpaceshipReference akParent)
    if !IsBoundInstance()
        return
    endif
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if !abComplete
        EmergencyStopAll()
        Log("OnShipDock — docking started, all scenes stopped")
    else
        ResumeScanTimer()
        Log("OnShipDock — docking complete, scanning resumed")
    endif
EndEvent

Event SpaceshipReference.OnShipLanding(SpaceshipReference akSender, bool abComplete)
    if !IsBoundInstance()
        return
    endif
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if !abComplete
        EmergencyStopAll()
        Log("OnShipLanding — landing started, all scenes stopped")
    else
        ResumeScanTimer()
        Log("OnShipLanding — landing complete, scanning resumed")
    endif
EndEvent

; ===========================================================================
; Timer — Main Scan Loop
; ===========================================================================

Event OnTimer(int aiTimerID)
    if !IsBoundInstance()
        return  ; a stored timer can still fire on a stale unbound instance
    endif

    if aiTimerID == TIMER_ID_SETTINGS_RETRY
        RegisterSettingsListener()
        return
    endif

    if aiTimerID == TIMER_ID_SCENE_TIMEOUT
        EnforceSceneTimeouts()
        return
    endif

    if aiTimerID != TIMER_ID_SCAN
        return
    endif

    Log("OnTimer SCAN fired")

    if !IsEnabled()
        Log("OnTimer — mod disabled, skipping")
        return
    endif
    if !OSF.IsReady()
        Log("OnTimer — OSF not ready, rescheduling")
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    ; Don't trigger scenes while player is piloting (sit state != 0 in pilot seat)
    ; Note: IsInSpace() returns true whenever the ship is in space, even if the player
    ; is walking around the interior. We only block if the player is actually sitting.
    Actor player = Game.GetPlayer()
    if player != None
        ; Backstop: keep ship state fresh — enter/exit events can arrive out
        ; of order, and nothing else recomputes it between scans.
        bIsOnShip = IsPlayerInOwnShip()

        ; Player piloting ship (prevents scenes starting while flying)
        if player.GetSpaceship() != None
            Log("OnTimer — player is piloting ship, rescheduling")
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        ; Combat gate — OnCombatStateChanged no longer kills the timer, so the
        ; scan must idle while fighting and resume on its own afterwards.
        ; GetCombatState() != 0 also covers "searching" — NPCs shouldn't start
        ; scenes while hostiles are being hunted nearby.
        if player.GetCombatState() != 0
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        ; Location gate — re-evaluated every tick. Checks at load/event time can
        ; misfire (GetParentCell/IsInterior may not be resolved yet), so the
        ; timer stays alive and each tick decides instead of dying permanently.
        if !IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        ; Prevent scenes while ship is traveling in space (exterior cell)
        Cell playerCell = player.GetParentCell()
        if bIsOnShip && (playerCell == None || !playerCell.IsInterior())
            Log("OnTimer — ship in space exterior, rescheduling")
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        ; Ship in combat — block scenes even if player is not in pilot seat
        SpaceshipReference currentShip = player.GetCurrentShipRef()
        if currentShip != None
            if currentShip.IsInCombat()
                Log("OnTimer — ship in combat, rescheduling")
                StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
                return
            endif
            ; Note: IsDocked() returns true whenever docked to a station/ship — this is a stable
            ; state, not a transition. We allow scenes while docked. OnShipDock event handles
            ; the transition itself (abComplete=false stops scenes, abComplete=true resumes).
        endif
    endif

    ; Clean expired cooldowns
    CleanExpiredCooldowns()

    ; Audit active scenes for invalid states (combat, death, dialogue, desync)
    AuditActiveScenes()

    ; Enforce scene timeouts
    EnforceSceneTimeouts()

    ; Check concurrent scene limit
    if activeSceneHandles.Length >= GetMaxConcurrent()
        Log("OnTimer — max concurrent scenes reached (" + activeSceneHandles.Length + "/" + GetMaxConcurrent() + "), rescheduling")
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    ; Find candidate actors near the player using crew keywords.
    ; Search for Companion, Generic, and Elite crew types to cover all assignable crew.
    ; Game.GetPlayerFollowers() returns only the active accompanying follower (≤1),
    ; not ship crew. We search the loaded area for actors with crew keywords instead.
    Actor[] candidates = new Actor[0]
    int companionCount = 0
    int genericCount = 0
    int eliteCount = 0
    int followerCount = 0
    int outpostCount = 0

    ; Dynamic scan range — tie to fMaxStartDistance + buffer so C++ filters distant NPCs before Papyrus
    float scanRange = GetMaxStartDistance() + 200.0

    ; Companion crew (Sarah, Barrett, Sam, Andreja, etc.)
    if kCrewCompanion != None
        ObjectReference[] nearbyCompanions = player.FindAllReferencesWithKeyword(kCrewCompanion, scanRange)
        int i = 0
        while i < nearbyCompanions.Length
            Actor a = nearbyCompanions[i] as Actor
            if a != None && a != player && candidates.Find(a) < 0
                candidates.Add(a, 1)
                companionCount += 1
            endif
            i += 1
        endwhile
    endif

    ; Generic crew (hireable specialists)
    if kCrewGeneric != None
        ObjectReference[] nearbyGeneric = player.FindAllReferencesWithKeyword(kCrewGeneric, scanRange)
        int i = 0
        while i < nearbyGeneric.Length
            Actor a = nearbyGeneric[i] as Actor
            if a != None && a != player && candidates.Find(a) < 0
                candidates.Add(a, 1)
                genericCount += 1
            endif
            i += 1
        endwhile
    endif

    ; Elite crew (high-tier specialists)
    if kCrewElite != None
        ObjectReference[] nearbyElite = player.FindAllReferencesWithKeyword(kCrewElite, scanRange)
        int i = 0
        while i < nearbyElite.Length
            Actor a = nearbyElite[i] as Actor
            if a != None && a != player && candidates.Find(a) < 0
                candidates.Add(a, 1)
                eliteCount += 1
            endif
            i += 1
        endwhile
    endif

    ; Also include active followers (covers multi-follower mods like The Gang's All Here)
    Actor[] followers = Game.GetPlayerFollowers()
    int j = 0
    while j < followers.Length
        if followers[j] != None && candidates.Find(followers[j]) < 0
            candidates.Add(followers[j], 1)
            followerCount += 1
        endif
        j += 1
    endwhile

    ; Include all nearby humanoid NPCs if outpost NPC option is enabled
    ; Uses ActorTypeNPC keyword — children and robots are filtered in IsActorEligible
    if IsIncludeOutpostNPC() && kActorTypeHuman != None
        ; Generic humans are only ever collected in private player locations
        ; (own ship, player outposts, player homes) — never on starstations,
        ; in bars/clubs or in public city interiors (SF-TIK-008).
        bool allowGenericScan = IsInPrivatePlayerLocation()
        if allowGenericScan
            ObjectReference[] nearbyNPCs = player.FindAllReferencesWithKeyword(kActorTypeHuman, scanRange)
            int k = 0
            while k < nearbyNPCs.Length
                Actor a = nearbyNPCs[k] as Actor
                if a != None && a != player && candidates.Find(a) < 0
                    candidates.Add(a, 1)
                    outpostCount += 1
                endif
                k += 1
            endwhile
        endif
    endif

    Log("Candidates — companions=" + companionCount + " generic=" + genericCount + " elite=" + eliteCount + " followers=" + followerCount + " outpost=" + outpostCount + " total=" + candidates.Length)

    ; Solo scenes need only 1 candidate — only bail out if nobody is nearby at all
    if candidates.Length == 0
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    ; Filter eligible actors
    Actor[] eligible = new Actor[0]
    int i = 0
    while i < candidates.Length
        Actor candidate = candidates[i]
        if candidate != None && IsActorEligible(candidate)
            eligible.Add(candidate, 1)
        endif
        i += 1
    endwhile

    Log("Eligible actors: " + eligible.Length + "/" + candidates.Length)

    ; Fewer than 2 eligible actors → only solo scenes are possible
    if eligible.Length < 2
        if eligible.Length == 1 && IsSoloDowntime()
            TryStartSoloScene(eligible)
        endif
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    ; Scene wave — a single tick can start multiple scenes up to the
    ; iMaxConcurrentScenes limit. Each scene needs its own chance roll and a
    ; fresh pair; actors used this tick leave the pool for subsequent picks.
    Actor[] usedThisTick = new Actor[0]
    int startedThisTick = 0
    bool waveDone = false
    while !waveDone && activeSceneHandles.Length < GetMaxConcurrent() && (eligible.Length - usedThisTick.Length) >= 2
        ; Roll trigger chance per scene start
        int roll = Utility.RandomInt(1, 100)
        if roll > GetChancePercent()
            Log("OnTimer — scene wave ended: chance roll failed (" + roll + " > " + GetChancePercent() + ")")
            waveDone = true
        else
            ; Select a random pair — try to find one not on pair cooldown, not
            ; used this tick, within distance, and gender-compatible
            int idxA = -1
            int idxB = -1
            bool foundPair = false
            int attempts = 0
            int maxAttempts = 10
            float maxZ = GetMaxZOffset()
            string lastPairFail = ""

            while attempts < maxAttempts && !foundPair
                idxA = Utility.RandomInt(0, eligible.Length - 1)
                idxB = (idxA + Utility.RandomInt(1, eligible.Length - 1)) % eligible.Length
                Actor aA = eligible[idxA]
                Actor aB = eligible[idxB]
                if usedThisTick.Find(aA) < 0 && usedThisTick.Find(aB) < 0 && !IsPairOnCooldown(aA, aB)
                    ; Check distance and Z-offset
                    float dist = aA.GetDistance(aB as ObjectReference)
                    float zDiff = Math.abs(aA.GetPositionZ() - aB.GetPositionZ())
                    if dist <= GetMaxPairDistance() && (maxZ <= 0.0 || zDiff <= maxZ)
                        ; Check gender compatibility (skip MM pairs).
                        ; GetLeveledActorBase can return None for broken NPCs
                        ; (deleted base forms) — a None.GetSex() error-spams the
                        ; log and yields 0 (male), silently skipping the pair.
                        ActorBase baseA = aA.GetLeveledActorBase()
                        ActorBase baseB = aB.GetLeveledActorBase()
                        if baseA != None && baseB != None
                            int sexA = baseA.GetSex()
                            int sexB = baseB.GetSex()
                            if !(sexA == 0 && sexB == 0)
                                foundPair = true
                            else
                                lastPairFail = "mm pair blocked"
                            endif
                        else
                            lastPairFail = "unresolvable ActorBase"
                        endif
                    else
                        lastPairFail = "distance " + dist + "u (max " + GetMaxPairDistance() + ", z=" + zDiff + ")"
                    endif
                else
                    if usedThisTick.Find(aA) >= 0 || usedThisTick.Find(aB) >= 0
                        lastPairFail = "already used this tick"
                    else
                        lastPairFail = "pair on cooldown"
                    endif
                endif
                attempts += 1
            endwhile

            if !foundPair
                ; Solo Downtime — only when nothing started at all this tick
                if startedThisTick == 0 && IsSoloDowntime()
                    Log("Scene wave — no compatible pair (" + lastPairFail + "), trying solo")
                    TryStartSoloScene(eligible)
                elseif startedThisTick == 0
                    Log("Scene wave — no compatible pair (" + lastPairFail + ")")
                else
                    Log("Scene wave ended — no more compatible pairs (" + lastPairFail + ")")
                endif
                waveDone = true
            else
                int scenesBefore = activeSceneHandles.Length
                TryStartScene(eligible[idxA], eligible[idxB])
                ; Mark used even on failure — don't retry the same pair this tick
                usedThisTick.Add(eligible[idxA], 1)
                usedThisTick.Add(eligible[idxB], 1)
                if activeSceneHandles.Length > scenesBefore
                    startedThisTick += 1
                else
                    ; Pair-specific failure (distance/tags/furniture) — keep
                    ; looking; both actors are consumed so the pool shrinks
                    ; and a different pair may still be viable this tick
                    Log("Scene wave — pair failed all scene queries, trying others")
                endif
            endif
        endif
    endwhile

    if startedThisTick > 1
        Log("OnTimer — scene wave started " + startedThisTick + " scenes")
    endif

    ; Reschedule timer
    StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
EndEvent

; ===========================================================================
; Eligibility Filter
; ===========================================================================

bool Function IsActorEligible(Actor akActor)
    if akActor == None
        return false
    endif

    string actorName = "0x" + akActor.GetFormID()

    ; --- ABSOLUTE BLOCKERS ---

    ; Never select the player
    if akActor == Game.GetPlayer()
        Log("Rejected " + actorName + " — player")
        return false
    endif

    ; Children (Cora Coe and any child) — hardcoded, never bypassed
    if akActor.IsChild()
        Log("Rejected " + actorName + " — is child")
        return false
    endif

    ; Must be loaded and active in the world
    if !akActor.Is3DLoaded() || akActor.IsDisabled()
        Log("Rejected " + actorName + " — not 3D loaded or disabled")
        return false
    endif

    ; Hostile to player — never allow (covers unalerted enemies in dungeons)
    if akActor.IsHostileToActor(Game.GetPlayer())
        Log("Rejected " + actorName + " — hostile to player")
        return false
    endif

    ; Dead
    if akActor.IsDead()
        Log("Rejected " + actorName + " — dead")
        return false
    endif

    ; In combat
    if akActor.IsInCombat()
        Log("Rejected " + actorName + " — in combat")
        return false
    endif

    ; Already in an OSF scene
    if OSF.IsPlaying(akActor)
        Log("Rejected " + actorName + " — already in OSF scene")
        return false
    endif

    ; In dialogue with player
    if akActor.IsInDialogueWithPlayer()
        Log("Rejected " + actorName + " — in dialogue with player")
        return false
    endif

    ; Only standing actors are eligible — seated NPCs (desks, terminals, chairs) stay put
    int sitState = akActor.GetSitState()
    if sitState != 0
        Log("Rejected " + actorName + " — sitting or transitioning (sitState=" + sitState + ")")
        return false
    endif

    ; Sleeping actors — never yank them out of bed for a scene
    int sleepState = akActor.GetSleepState()
    if sleepState != 0
        Log("Rejected " + actorName + " — sleeping (sleepState=" + sleepState + ")")
        return false
    endif

    ; Movement guards — actors that are walking/running will desync from OSF animations
    ; OSF snaps actors to position, but if they're mid-stride the animation can slide/stutter
    if akActor.IsRunning()
        Log("Rejected " + actorName + " — running (moving)")
        return false
    endif

    ; Sneaking actors are in a different animation state — block to avoid skeleton conflicts
    if akActor.IsSneaking()
        Log("Rejected " + actorName + " — sneaking")
        return false
    endif

    ; Actor is talking (not just to player — any dialogue including sandbox barks)
    ; Starting an animation during dialogue causes voice+anim desync
    if akActor.IsTalking()
        Log("Rejected " + actorName + " — talking")
        return false
    endif

    ; Bleeding out, unconscious, or arrested
    if akActor.IsBleedingOut() || akActor.IsUnconscious() || akActor.IsArrested()
        Log("Rejected " + actorName + " — bleeding/unconscious/arrested")
        return false
    endif

    ; Robots (Vasco, Kaiser, security bots) — non-humanoid skeleton causes crashes
    ; Race fetched once — reused by the robot keyword check below and the
    ; crowd/mannequin skeleton guards further down.
    Race actorRace = akActor.GetRace()

    ; ActorTypeRobot keyword may be on the Race, not on the ActorBase.
    ; Check both Actor.HasKeyword and Race.HasKeyword for robustness.
    if kActorTypeRobot != None
        if akActor.HasKeyword(kActorTypeRobot)
            Log("Rejected " + actorName + " — robot (actor keyword)")
            return false
        endif
        if actorRace != None && actorRace.HasKeyword(kActorTypeRobot)
            Log("Rejected " + actorName + " — robot (race keyword)")
            return false
        endif
    endif

    ; Children (Cora Coe and any child) — never allow
    if kActorTypeChild != None && akActor.HasKeyword(kActorTypeChild)
        Log("Rejected " + actorName + " — child keyword")
        return false
    endif

    ; Crowd NPCs (HumanCrowdRace) — different skeleton, OSF animation crash risk
    if actorRace != None
        if actorRace == kHumanCrowdRace
            Log("Rejected " + actorName + " — crowd race (skeleton mismatch)")
            return false
        endif
        if actorRace == kMannequinRace
            Log("Rejected " + actorName + " — mannequin race (skeleton mismatch)")
            return false
        endif
    endif

    ; --- Conditional filters ---

    ; Named companions only (if MCM setting is enabled)
    if IsCompanionsOnly()
        if kCrewCompanion == None || !akActor.HasKeyword(kCrewCompanion)
            Log("Rejected " + actorName + " — not a companion (companionsOnly mode)")
            return false
        endif
    endif

    ; Cache relationship rank once — reused by crew guards and romance exclusivity below
    int relRank = akActor.GetRelationshipRank(Game.GetPlayer())

    ; Non-crew safety net — actors without crew keywords who are not a teammate
    ; and not in the crew faction are only eligible inside private player
    ; locations (own ship, outposts, homes). Blocks station guards and other
    ; public NPCs even if they reach the candidate list via the generic
    ; human scan (SF-TIK-008).
    bool hasCrewKeyword = (kCrewCompanion != None && akActor.HasKeyword(kCrewCompanion)) || (kCrewGeneric != None && akActor.HasKeyword(kCrewGeneric)) || (kCrewElite != None && akActor.HasKeyword(kCrewElite))
    if !hasCrewKeyword && !akActor.IsPlayerTeammate() && !(kCurrentCrewFaction != None && akActor.IsInFaction(kCurrentCrewFaction))
        if !IsInPrivatePlayerLocation()
            Log("Rejected " + actorName + " — non-crew NPC outside private player location")
            return false
        endif
    endif

    ; Crew Keyword Guard - Reject unrecruited/unassigned actors that carry crew keywords
    ; Use CurrentCrewFaction to precisely identify recruited crew (not just active teammates)
    if kCrewCompanion != None && akActor.HasKeyword(kCrewCompanion)
        bool inCrewFaction = (kCurrentCrewFaction != None && akActor.IsInFaction(kCurrentCrewFaction))
        bool isTeammate = akActor.IsPlayerTeammate()
        if inCrewFaction || isTeammate || relRank >= 1
            ; crew OK — accepted
        else
            Log("Rejected " + actorName + " — companion crew keyword but not recruited/teammate (inCrewFaction=" + inCrewFaction + " relRank=" + relRank + ")")
            return false
        endif
    endif
    if (kCrewGeneric != None && akActor.HasKeyword(kCrewGeneric)) || (kCrewElite != None && akActor.HasKeyword(kCrewElite))
        bool inCrewFaction = (kCurrentCrewFaction != None && akActor.IsInFaction(kCurrentCrewFaction))
        bool isTeammate = akActor.IsPlayerTeammate()
        if inCrewFaction || isTeammate || relRank >= 1
            ; crew OK — accepted
        else
            Log("Rejected " + actorName + " — generic/elite crew but not recruited (inCrewFaction=" + inCrewFaction + " relRank=" + relRank + ")")
            return false
        endif
    endif

    ; Romance Exclusivity Guard — block romanced companions from autonomous scenes
    ; Check rank >= 3 (Ally/Dating) — covers dismissed/unassigned companions too
    if IsRomanceExclusivity() && !IsPolyamoryBypass()
        if relRank >= 3
            Log("Rejected " + actorName + " — romanced companion (exclusivity guard)")
            return false
        endif
    endif

    ; Cooldown check
    if IsOnCooldown(akActor)
        Log("Rejected " + actorName + " — on cooldown")
        return false
    endif

    return true
EndFunction

; ===========================================================================
; Scene Start
; ===========================================================================

Function TryStartScene(Actor akActorA, Actor akActorB)
    if akActorA == None || akActorB == None
        return
    endif
    if akActorA == akActorB
        return
    endif

    ; Re-check scene occupancy — eligibility was computed during the scan and
    ; an external scene (OSF UI browser launch, another mod) may have claimed
    ; an actor since. Without this every candidate start below is refused.
    if OSF.IsPlaying(akActorA) || OSF.IsPlaying(akActorB)
        Log("Scene skipped — actor already in a scene (claimed since eligibility check)")
        return
    endif

    ; --- Player Proximity Shield — MAX distance always active, MIN only if shield enabled and > 0 ---
    float maxDist = GetMaxStartDistance()
    Actor player = Game.GetPlayer()
    float distA = akActorA.GetDistance(player as ObjectReference)
    float distB = akActorB.GetDistance(player as ObjectReference)
    if distA > maxDist || distB > maxDist
        Log("Scene skipped — actor too far from player (" + maxDist + " units)")
        return
    endif

    ; --- Inter-Scene Proximity Guard — don't start scenes next to already-running scenes ---
    EnsureArraysInitialized()
    if activeSceneHandles.Length > 0
        float minSpacing = GetMinSceneSpacing()
        int h = 0
        while h < activeSceneHandles.Length
            Actor[] activeParticipants = OSF.GetSceneParticipants(activeSceneHandles[h])
            if activeParticipants != None
                int p = 0
                while p < activeParticipants.Length
                    Actor other = activeParticipants[p]
                    if other != None
                        if akActorA.GetDistance(other as ObjectReference) < minSpacing || akActorB.GetDistance(other as ObjectReference) < minSpacing
                            Log("Scene skipped — too close to active scene " + activeSceneHandles[h] + " (< " + minSpacing + " units)")
                            return
                        endif
                    endif
                    p += 1
                endwhile
            endif
            h += 1
        endwhile
    endif

    ; --- Distance + Z-offset check between actors ---
    ; Prevent teleporting a partner from another deck or far away
    float maxZ = GetMaxZOffset()
    float actorDist = akActorA.GetDistance(akActorB as ObjectReference)
    float actorZDiff = Math.abs(akActorA.GetPositionZ() - akActorB.GetPositionZ())
    if actorDist > GetMaxPairDistance()
        Log("Scene skipped — actors too far apart (" + actorDist + " units)")
        return
    endif
    if maxZ > 0.0 && actorZDiff > maxZ
        Log("Scene skipped — actors on different decks (Z-delta=" + actorZDiff + ")")
        return
    endif

    ; --- Gender-based tag selection ---
    ; Get sex: 0 = male, 1 = female (ActorBase.GetSex)
    ; FF and MF are allowed. MM (two males) is blocked — no compatible animation packs.
    ; GetLeveledActorBase can return None for broken NPCs — guard before GetSex.
    ActorBase baseA = akActorA.GetLeveledActorBase()
    ActorBase baseB = akActorB.GetLeveledActorBase()
    if baseA == None || baseB == None
        Log("Scene skipped — could not resolve ActorBase (sex unknown)")
        return
    endif
    int sexA = baseA.GetSex()
    int sexB = baseB.GetSex()
    string genderTag = ""
    if sexA == 1 && sexB == 1
        genderTag = "ff"
    elseif (sexA == 0 && sexB == 1) || (sexA == 1 && sexB == 0)
        genderTag = "mf"
    elseif sexA == 0 && sexB == 0
        ; Two males — no compatible scenes, skip
        Log("Scene skipped — male/male pair not supported")
        return
    else
        ; At least one actor has undefined sex (-1) — skip to be safe
        Log("Scene skipped — undefined sex for actor (sexA=" + sexA + " sexB=" + sexB + ")")
        return
    endif

    ; Build actor arrays — MF packs have different role conventions:
    ;   GE (381 scenes):    roles=[m, f] → actors[0]=male,  actors[1]=female
    ;   SnuSnu (7 scenes):  roles=[f, m] → actors[0]=female, actors[1]=male (femdom)
    ; We prepare both orderings and use tag-based partitioning ('ge' vs 'snusnu')
    Actor[] standardOrder = new Actor[2]  ; [male, female]   — for GE
    Actor[] femdomOrder   = new Actor[2]  ; [female, male]   — for SnuSnu
    Actor[] actors        = new Actor[2]  ; default (same-sex or fallback)
    if genderTag == "mf"
        if sexA == 0
            standardOrder[0] = akActorA  ; male
            standardOrder[1] = akActorB  ; female
            femdomOrder[0]   = akActorB  ; female
            femdomOrder[1]   = akActorA  ; male
        else
            standardOrder[0] = akActorB  ; male
            standardOrder[1] = akActorA  ; female
            femdomOrder[0]   = akActorA  ; female
            femdomOrder[1]   = akActorB  ; male
        endif
        actors = standardOrder  ; default to GE convention
    else
        actors[0] = akActorA
        actors[1] = akActorB
    endif

    ; Determine action tag via rotation
    string actionTag = ""
    if IsTagRotation()
        actionTag = GetNextActionTag(genderTag)
    endif

    ; Find furniture anchor — check currently-used furniture first, then nearby candidates
    int sitA = akActorA.GetSitState()
    int sitB = akActorB.GetSitState()
    Log("TryStartScene — A=" + akActorA + " sitState=" + sitA + "  B=" + akActorB + " sitState=" + sitB + "  gender=" + genderTag + " action=" + actionTag)

    ObjectReference anchorRef = None
    ObjectReference[] furnitureCandidates = new ObjectReference[0]
    if sitA == 3
        ObjectReference usedFurniture = akActorA.GetFurnitureUsing()
        if usedFurniture != None
            anchorRef = usedFurniture
            Log("  Actor A sitting on: " + usedFurniture + " base=" + usedFurniture.GetBaseObject())
        else
            Log("  Actor A sitState=3 but GetFurnitureUsing() returned None")
        endif
    endif
    if anchorRef == None && sitB == 3
        ObjectReference usedFurniture = akActorB.GetFurnitureUsing()
        if usedFurniture != None
            anchorRef = usedFurniture
            Log("  Actor B sitting on: " + usedFurniture + " base=" + usedFurniture.GetBaseObject())
        else
            Log("  Actor B sitState=3 but GetFurnitureUsing() returned None")
        endif
    endif
    if anchorRef == None
        Log("  Neither actor sitting — searching nearby furniture (radius=400)")
        furnitureCandidates = FindNearbyFurniture(akActorA, 400.0)
        if furnitureCandidates.Length > 0
            anchorRef = furnitureCandidates[0]  ; closest first
            Log("  Nearest furniture: " + anchorRef + " base=" + anchorRef.GetBaseObject())
        else
            Log("  No nearby furniture found — will try standing scenes")
        endif
    endif

    ; Resolve OSF furniture tag from anchor
    string furnitureTag = GetOSFFurnitureTag(anchorRef)

    ; Common scene options
    OSFTypes:SceneOptions opts = new OSFTypes:SceneOptions
    opts.LockPlayerMode    = OSF.OFF()
    opts.PlayerControlMode = OSF.OFF()
    opts.Camera            = "none"
    opts.FadeMode          = OSF.OFF()
    opts.LoopScale         = GetLoopScale()

    ; Strip follows the scene actually started, not the intended action —
    ; action-matched queries below temporarily force OFF for foreplay
    ; (kissing), while action-agnostic fallback tiers (generic furniture /
    ; standing sex scenes) restore this configured value.
    opts.StripMode     = GetStripMode()

    int handle = 0

    ; ===== ANCHOR + STANDING FALLBACK CHAIN =====

    ; TIER 1: Anchor + Action (+ sequence if preferred) — iterate ALL furniture candidates
    if furnitureCandidates.Length > 0 || anchorRef != None
        ; Build candidate list — currently-used furniture first, then nearby
        ; Cap at 15 closest candidates to avoid performance issues in dense areas (87+ furniture in cities)
        ObjectReference[] allCandidates = new ObjectReference[0]
        if anchorRef != None
            allCandidates.Add(anchorRef, 1)
        endif
        int fc = 0
        while fc < furnitureCandidates.Length && allCandidates.Length < 15
            if furnitureCandidates[fc] != anchorRef && allCandidates.Find(furnitureCandidates[fc]) < 0
                allCandidates.Add(furnitureCandidates[fc], 1)
            endif
            fc += 1
        endwhile
        if allCandidates.Length < furnitureCandidates.Length
            Log("  Capped furniture candidates: " + allCandidates.Length + "/" + furnitureCandidates.Length + " (performance limit)")
        endif

        ; A participant sitting on anchorRef is the intended case — exempt it
        ; from the occupied check below (it always reports in-use by our actor)
        bool anchorIsParticipantFurniture = (anchorRef != None && ((sitA == 3 && akActorA.GetFurnitureUsing() == anchorRef) || (sitB == 3 && akActorB.GetFurnitureUsing() == anchorRef)))
        opts.InPlaceMode = OSF.OFF()  ; snap to anchor
        int ci = 0
        while ci < allCandidates.Length && handle <= 0
            ObjectReference candidate = allCandidates[ci]
            if candidate != None
                ; An actor claimed mid-loop makes every remaining candidate fail
                ; the same way — bail instead of grinding refused starts
                if OSF.IsPlaying(akActorA) || OSF.IsPlaying(akActorB)
                    Log("  -> aborting candidates: actor claimed by another scene")
                    return
                endif
                Log("Trying anchor candidate " + ci + "/" + allCandidates.Length + ": " + candidate + " base=" + candidate.GetBaseObject() + " baseID=0x" + (candidate.GetBaseObject() as Form).GetFormID())

                ; Re-check occupancy at use time — FindNearbyFurniture filtered at
                ; scan time, but between then and now another NPC may have sat
                ; down or reserved a marker. IsFurnitureInUse() counts marker
                ; reservations by default (abIgnoreReserved=false), so actors
                ; merely walking to the seat are caught too.
                bool candidateFree = !candidate.IsFurnitureInUse() || (anchorIsParticipantFurniture && candidate == anchorRef)
                if !candidateFree
                    Log("  -> skipped: furniture occupied or reserved by another actor")
                endif

                ; Action-matched queries — foreplay (kissing) keeps actors dressed
                if actionTag == "kissing"
                    opts.StripMode = OSF.OFF()
                endif
                ; TIER 1: Anchor + Action (+ sequence if preferred)
                ; Try original gender first, then FF→MF fallback, then pack-specific
                string[] genderVariants = new string[2]
                genderVariants[0] = genderTag
                if genderTag == "ff"
                    genderVariants[1] = "mf"  ; FF pairs can use MF furniture scenes
                else
                    genderVariants[1] = ""
                endif
                string[] packVariants = new string[3]
                packVariants[0] = ""
                packVariants[1] = "ge"
                packVariants[2] = "snusnu"
                
                int gi = 0
                while candidateFree && gi < genderVariants.Length && handle <= 0
                    if genderVariants[gi] != ""
                        int pi = 0
                        while pi < packVariants.Length && handle <= 0
                            if actionTag != ""
                                ; T1 with pack + sequence
                                if IsPreferSequences() && packVariants[pi] != ""
                                    string[] t1ps = BuildQueryTagsWithPack(genderVariants[gi], actionTag, packVariants[pi], "sequence")
                                    handle = OSF.StartSceneAtAnchor(actors, candidate, t1ps, opts)
                                endif
                                if handle <= 0 && IsPreferSequences()
                                    string[] t1seq = BuildQueryTags(genderVariants[gi], furnitureTag, actionTag, "sequence")
                                    handle = OSF.StartSceneAtAnchor(actors, candidate, t1seq, opts)
                                endif
                                if handle <= 0 && packVariants[pi] != ""
                                    string[] t1p = BuildQueryTagsWithPack(genderVariants[gi], actionTag, packVariants[pi], "")
                                    handle = OSF.StartSceneAtAnchor(actors, candidate, t1p, opts)
                                endif
                                if handle <= 0
                                    string[] t1 = BuildQueryTags(genderVariants[gi], furnitureTag, actionTag, "")
                                    handle = OSF.StartSceneAtAnchor(actors, candidate, t1, opts)
                                endif
                            endif
                            pi += 1
                        endwhile
                    endif
                    gi += 1
                endwhile
                
                ; TIER 2: Anchor + any action for this furniture type —
                ; action-agnostic queries can match a sex scene even when the
                ; intent was foreplay, so strip follows the scene type again
                opts.StripMode = GetStripMode()
                gi = 0
                while candidateFree && gi < genderVariants.Length && handle <= 0
                    if genderVariants[gi] != ""
                        int pi = 0
                        while pi < packVariants.Length && handle <= 0
                            if IsPreferSequences() && packVariants[pi] != ""
                                string[] t2ps = BuildQueryTagsWithPack(genderVariants[gi], "", packVariants[pi], "sequence")
                                handle = OSF.StartSceneAtAnchor(actors, candidate, t2ps, opts)
                            endif
                            if handle <= 0 && IsPreferSequences()
                                string[] t2seq = BuildQueryTags(genderVariants[gi], furnitureTag, "", "sequence")
                                handle = OSF.StartSceneAtAnchor(actors, candidate, t2seq, opts)
                            endif
                            if handle <= 0 && packVariants[pi] != ""
                                string[] t2p = BuildQueryTagsWithPack(genderVariants[gi], "", packVariants[pi], "")
                                handle = OSF.StartSceneAtAnchor(actors, candidate, t2p, opts)
                            endif
                            if handle <= 0
                                string[] t2 = BuildQueryTags(genderVariants[gi], furnitureTag, "", "")
                                handle = OSF.StartSceneAtAnchor(actors, candidate, t2, opts)
                            endif
                            pi += 1
                        endwhile
                    endif
                    gi += 1
                endwhile
                
                if handle > 0
                    Log("  -> MATCHED: " + candidate + " handle=" + handle)
                elseif candidateFree
                    Log("  -> rejected")
                endif
            endif
            ci += 1
        endwhile

        if handle > 0
            activeSceneHandles.Add(handle, 1)
            sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
            sceneActorA.Add(akActorA, 1)
            sceneActorB.Add(akActorB, 1)
            SetPairCooldown(akActorA, akActorB)
            StartSceneTimeoutTimer()
            Log("Scene started at anchor (T1/T2) — handle=" + handle + " furn=" + furnitureTag + " action=" + actionTag + " candidates=" + allCandidates.Length)
            return
        endif
        Log("All furniture candidates rejected — falling through to standing scenes")
    endif
    if !IsRequireFurniture()
        float dist = akActorA.GetDistance(akActorB as ObjectReference)
        if dist > 250.0
            Log("Standing scene skipped — actors too far apart (" + dist + " units, max 250)")
            return
        endif

        opts.InPlaceMode = OSF.OFF()  ; paired scenes always need alignment — InPlaceMode=ON causes instant abort

        ; Action-matched queries (T3/T3.5 carry actionTag) — foreplay stays dressed
        if actionTag == "kissing"
            opts.StripMode = OSF.OFF()
        endif

        ; TIER 3: Unanchored specific action — pack partitioning + catch-all for unknown packs.
        ; Every unanchored query carries a position tag so OSF can never pick a
        ; bed-anchored animation and float actors in mid-air. Packs use BOTH
        ; conventions: dedicated floor pack tags scenes "floor", furniture packs
        ; tag standing variants "standing" — so each query is tried twice
        ; (SF-TIK-007).
        int matchedTier = 0
        if actionTag != ""
            ; 3a: GE standard (male=role0) — 381 scenes
            if IsPreferSequences()
                string[] t3seq = BuildQueryTagsWithPack(genderTag, actionTag, "ge", "sequence", "standing")
                handle = OSF.StartSceneByTags(standardOrder, t3seq, opts)
                if handle <= 0
                    string[] t3seqf = BuildQueryTagsWithPack(genderTag, actionTag, "ge", "sequence", "floor")
                    handle = OSF.StartSceneByTags(standardOrder, t3seqf, opts)
                endif
            endif
            if handle <= 0
                string[] t3 = BuildQueryTagsWithPack(genderTag, actionTag, "ge", "", "standing")
                handle = OSF.StartSceneByTags(standardOrder, t3, opts)
            endif
            if handle <= 0
                string[] t3f = BuildQueryTagsWithPack(genderTag, actionTag, "ge", "", "floor")
                handle = OSF.StartSceneByTags(standardOrder, t3f, opts)
            endif
            if handle > 0
                matchedTier = 3
            endif
            ; 3b: SnuSnu femdom (female=role0) — 7 scenes
            if handle <= 0 && genderTag == "mf"
                if IsPreferSequences()
                    string[] t3sseq = BuildQueryTagsWithPack(genderTag, actionTag, "snusnu", "sequence", "standing")
                    handle = OSF.StartSceneByTags(femdomOrder, t3sseq, opts)
                    if handle <= 0
                        string[] t3sseqf = BuildQueryTagsWithPack(genderTag, actionTag, "snusnu", "sequence", "floor")
                        handle = OSF.StartSceneByTags(femdomOrder, t3sseqf, opts)
                    endif
                endif
                if handle <= 0
                    string[] t3s = BuildQueryTagsWithPack(genderTag, actionTag, "snusnu", "", "standing")
                    handle = OSF.StartSceneByTags(femdomOrder, t3s, opts)
                endif
                if handle <= 0
                    string[] t3sf = BuildQueryTagsWithPack(genderTag, actionTag, "snusnu", "", "floor")
                    handle = OSF.StartSceneByTags(femdomOrder, t3sf, opts)
                endif
                if handle > 0
                    matchedTier = 3
                    Log("SnuSnu femdom scene — female=role0 (handle=" + handle + ")")
                endif
            endif
            ; 3c: Catch-all for any other animation pack (standard [m,f] convention)
            if handle <= 0
                if IsPreferSequences()
                    string[] t3cseq = BuildQueryTags(genderTag, "", actionTag, "sequence", "standing")
                    handle = OSF.StartSceneByTags(standardOrder, t3cseq, opts)
                    if handle <= 0
                        string[] t3cseqf = BuildQueryTags(genderTag, "", actionTag, "sequence", "floor")
                        handle = OSF.StartSceneByTags(standardOrder, t3cseqf, opts)
                    endif
                endif
                if handle <= 0
                    string[] t3c = BuildQueryTags(genderTag, "", actionTag, "", "standing")
                    handle = OSF.StartSceneByTags(standardOrder, t3c, opts)
                endif
                if handle <= 0
                    string[] t3cf = BuildQueryTags(genderTag, "", actionTag, "", "floor")
                    handle = OSF.StartSceneByTags(standardOrder, t3cf, opts)
                endif
                if handle > 0
                    matchedTier = 3
                    Log("Scene from unknown animation pack — action='" + actionTag + "' (handle=" + handle + ")")
                endif
            endif
        endif
        ; TIER 3.5: FF fallback — try native FF (any pack), then MF GE, then MF catch-all
        if handle <= 0 && genderTag == "ff" && actionTag != ""
            ; 3.5a: Native FF from any pack
            if IsPreferSequences()
                string[] t35seq = BuildQueryTags("ff", "", actionTag, "sequence", "standing")
                handle = OSF.StartSceneByTags(actors, t35seq, opts)
                if handle <= 0
                    string[] t35seqf = BuildQueryTags("ff", "", actionTag, "sequence", "floor")
                    handle = OSF.StartSceneByTags(actors, t35seqf, opts)
                endif
            endif
            if handle <= 0
                string[] t35 = BuildQueryTags("ff", "", actionTag, "", "standing")
                handle = OSF.StartSceneByTags(actors, t35, opts)
            endif
            if handle <= 0
                string[] t35f = BuildQueryTags("ff", "", actionTag, "", "floor")
                handle = OSF.StartSceneByTags(actors, t35f, opts)
            endif
            if handle > 0
                matchedTier = 35
                Log("FF pair using native FF scene for action='" + actionTag + "'")
            endif
            ; 3.5b: FF fallback to MF GE pool
            if handle <= 0 && IsUseMFForFF()
                if IsPreferSequences()
                    string[] t35geseq = BuildQueryTagsWithPack("mf", actionTag, "ge", "sequence", "standing")
                    handle = OSF.StartSceneByTags(actors, t35geseq, opts)
                    if handle <= 0
                        string[] t35geseqf = BuildQueryTagsWithPack("mf", actionTag, "ge", "sequence", "floor")
                        handle = OSF.StartSceneByTags(actors, t35geseqf, opts)
                    endif
                endif
                if handle <= 0
                    string[] t35ge = BuildQueryTagsWithPack("mf", actionTag, "ge", "", "standing")
                    handle = OSF.StartSceneByTags(actors, t35ge, opts)
                endif
                if handle <= 0
                    string[] t35gef = BuildQueryTagsWithPack("mf", actionTag, "ge", "", "floor")
                    handle = OSF.StartSceneByTags(actors, t35gef, opts)
                endif
                if handle > 0
                    matchedTier = 35
                    Log("FF pair using GE MF pool for action='" + actionTag + "'")
                endif
            endif
            ; 3.5c: FF fallback to MF catch-all (any pack)
            if handle <= 0 && IsUseMFForFF()
                if IsPreferSequences()
                    string[] t35cseq = BuildQueryTags("mf", "", actionTag, "sequence", "standing")
                    handle = OSF.StartSceneByTags(actors, t35cseq, opts)
                    if handle <= 0
                        string[] t35cseqf = BuildQueryTags("mf", "", actionTag, "sequence", "floor")
                        handle = OSF.StartSceneByTags(actors, t35cseqf, opts)
                    endif
                endif
                if handle <= 0
                    string[] t35c = BuildQueryTags("mf", "", actionTag, "", "standing")
                    handle = OSF.StartSceneByTags(actors, t35c, opts)
                endif
                if handle <= 0
                    string[] t35cf = BuildQueryTags("mf", "", actionTag, "", "floor")
                    handle = OSF.StartSceneByTags(actors, t35cf, opts)
                endif
                if handle > 0
                    matchedTier = 35
                    Log("FF pair using unknown MF pack for action='" + actionTag + "'")
                endif
            endif
        endif
        ; TIER 4: Position-generic scenes — "standing" and "floor" variants.
        ; ge-floor.osf.json is the dedicated floor pack (13 scenes tagged
        ; "floor"), furniture packs expose "*.standing" variants (SF-TIK-007).
        if handle <= 0
            ; Generic queries drop actionTag — whatever matches is a standing
            ; sex scene, not the chosen foreplay. Re-arm the configured strip
            ; mode so a kissing intent can't produce a fully dressed sex scene.
            opts.StripMode = GetStripMode()
            ; 4a: GE standing
            if IsPreferSequences()
                string[] t4seq = BuildQueryTagsWithPack(genderTag, "standing", "ge", "sequence")
                handle = OSF.StartSceneByTags(standardOrder, t4seq, opts)
            endif
            if handle <= 0
                string[] t4 = BuildQueryTagsWithPack(genderTag, "standing", "ge", "")
                handle = OSF.StartSceneByTags(standardOrder, t4, opts)
            endif
            ; 4a2: GE floor pack
            if handle <= 0 && IsPreferSequences()
                string[] t4seqf = BuildQueryTagsWithPack(genderTag, "floor", "ge", "sequence")
                handle = OSF.StartSceneByTags(standardOrder, t4seqf, opts)
            endif
            if handle <= 0
                string[] t4f = BuildQueryTagsWithPack(genderTag, "floor", "ge", "")
                handle = OSF.StartSceneByTags(standardOrder, t4f, opts)
            endif
            if handle > 0
                matchedTier = 4
            endif
            ; 4b: SnuSnu standing (female=role0)
            if handle <= 0 && genderTag == "mf"
                string[] t4s = BuildQueryTagsWithPack(genderTag, "standing", "snusnu", "")
                handle = OSF.StartSceneByTags(femdomOrder, t4s, opts)
                if handle > 0
                    matchedTier = 4
                    Log("SnuSnu standing scene — female=role0")
                endif
            endif
            ; 4c: Catch-all standing/floor (any pack, standard order)
            if handle <= 0
                string[] t4c = BuildQueryTags(genderTag, "", "standing", "")
                handle = OSF.StartSceneByTags(standardOrder, t4c, opts)
                if handle <= 0
                    string[] t4cf = BuildQueryTags(genderTag, "", "floor", "")
                    handle = OSF.StartSceneByTags(standardOrder, t4cf, opts)
                endif
                if handle > 0
                    matchedTier = 4
                    Log("Standing/floor scene from unknown pack")
                endif
            endif
        endif
        ; TIER 4.5: FF standing fallback — native FF, then MF GE, then MF catch-all
        if handle <= 0 && genderTag == "ff" && IsUseMFForFF()
            ; 4.5a: Native FF standing/floor
            string[] t45ff = BuildQueryTags("ff", "", "standing", "")
            handle = OSF.StartSceneByTags(actors, t45ff, opts)
            if handle <= 0
                string[] t45fff = BuildQueryTags("ff", "", "floor", "")
                handle = OSF.StartSceneByTags(actors, t45fff, opts)
            endif
            ; 4.5b: MF GE standing/floor
            if handle <= 0
                string[] t45ge = BuildQueryTagsWithPack("mf", "standing", "ge", "")
                handle = OSF.StartSceneByTags(actors, t45ge, opts)
            endif
            if handle <= 0
                string[] t45gef = BuildQueryTagsWithPack("mf", "floor", "ge", "")
                handle = OSF.StartSceneByTags(actors, t45gef, opts)
            endif
            ; 4.5c: MF catch-all standing/floor
            if handle <= 0
                string[] t45c = BuildQueryTags("mf", "", "standing", "")
                handle = OSF.StartSceneByTags(actors, t45c, opts)
            endif
            if handle <= 0
                string[] t45cf = BuildQueryTags("mf", "", "floor", "")
                handle = OSF.StartSceneByTags(actors, t45cf, opts)
            endif
            if handle > 0
                matchedTier = 45
                Log("FF pair using MF standing scene")
            endif
        endif
        ; NOTE: the former TIER 5/5.5 baselines ("paired" + gender with no
        ; position tag) were removed — OSF could match a bed-anchored scene
        ; and play it on the floor, floating the actors in mid-air. With no
        ; dedicated standing scene available we now bail out safely instead
        ; (SF-TIK-007).
        if handle > 0
            activeSceneHandles.Add(handle, 1)
            sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
            sceneActorA.Add(akActorA, 1)
            sceneActorB.Add(akActorB, 1)
            SetPairCooldown(akActorA, akActorB)
            StartSceneTimeoutTimer()
            Log("Scene started (T" + matchedTier + ", " + genderTag + ", action=" + actionTag + ") — handle=" + handle)
            return
        endif
    endif

    Log("Scene start failed — no matching scene for this pair/furniture")
EndFunction

; ===========================================================================
; --- Solo Downtime — single NPC relaxation/self-pleasure animation ---
; ===========================================================================

Function TryStartSoloScene(Actor[] eligible)
    if eligible == None || eligible.Length == 0
        return
    endif
    if !IsSoloDowntime()
        return
    endif

    ; Solo chance check (separate from pair chance)
    int soloRoll = Utility.RandomInt(1, 100)
    if soloRoll > GetSoloChance()
        Log("Solo scene skipped — chance roll failed (" + soloRoll + " > " + GetSoloChance() + ")")
        return
    endif

    ; Pick a random eligible actor
    Actor soloActor = eligible[Utility.RandomInt(0, eligible.Length - 1)]
    if soloActor == None
        return
    endif

    ; Must be idle — not running, not talking, not sneaking (already checked in IsActorEligible but double-check)
    if soloActor.IsRunning() || soloActor.IsTalking() || soloActor.IsSneaking()
        Log("Solo scene skipped — actor not idle")
        return
    endif

    ; Private-only check — restrict to ship interiors or player-owned cells
    if IsSoloPrivateOnly()
        Cell c = soloActor.GetParentCell()
        if c == None || !c.IsInterior()
            Log("Solo scene skipped — not interior (privateOnly)")
            return
        endif
    endif

    ; Player proximity check — MAX always active, MIN only if shield enabled
    float soloDist = soloActor.GetDistance(Game.GetPlayer() as ObjectReference)
    if soloDist > GetMaxStartDistance()
        Log("Solo scene skipped — too far from player")
        return
    endif

    ; --- Solo proximity guard — only block if actor is already in an active scene ---
    ; IsActorEligible() checked OSF.IsPlaying() at scan time, but an external scene
    ; may have claimed the actor since — re-check now. No distance check needed —
    ; on small ship interiors all NPCs are within any reasonable proximity
    ; threshold of a paired scene.
    if OSF.IsPlaying(soloActor)
        Log("Solo scene skipped — actor already in a scene (claimed since eligibility check)")
        return
    endif
    EnsureArraysInitialized()

    ; Start solo scene via OSF tag query — full pipeline (stripActors, callbacks, handle)
    Actor[] soloArr = new Actor[1]
    soloArr[0] = soloActor

    ; Select tags by actor sex — female actors get self-pleasure scenes,
    ; male actors get neutral poses only (cover, surrender)
    ActorBase soloBase = soloActor.GetLeveledActorBase()
    if soloBase == None
        Log("Solo scene skipped — could not resolve ActorBase (sex unknown)")
        return
    endif
    int actorSex = soloBase.GetSex()
    string[] soloTags = new string[3]
    soloTags[0] = "solo"
    soloTags[1] = "osfautonomous"
    if actorSex == 1  ; Female
        soloTags[2] = "female"
        Log("Solo scene — female actor, using self-pleasure pool")
    else  ; Male (0) or undefined (-1) — use neutral poses only
        soloTags[2] = "neutral"
        Log("Solo scene — male/neutral actor, using neutral pose pool")
    endif

    OSFTypes:SceneOptions soloOpts = new OSFTypes:SceneOptions
    soloOpts.LockPlayerMode    = OSF.OFF()
    soloOpts.PlayerControlMode = OSF.OFF()
    soloOpts.Camera            = "none"
    soloOpts.FadeMode          = OSF.OFF()
    soloOpts.InPlaceMode       = OSF.OFF()  ; OSF semantics: InPlaceMode=ON disables pinning — OFF keeps the root/heading lock so the solo actor doesn't drift
    soloOpts.StripMode         = GetStripMode()
    soloOpts.LoopScale         = GetLoopScale()

    int handle = OSF.StartSceneByTags(soloArr, soloTags, soloOpts)
    if handle > 0
        activeSceneHandles.Add(handle, 1)
        sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
        sceneActorA.Add(soloActor, 1)
        sceneActorB.Add(None, 1)
        ; No self-pair cooldown: the actor is blocked by OSF.IsPlaying() while
        ; running and gets a real cooldown via ApplyCooldownToActor on END/ghost
        ; cleanup — a "id:id" pair key here would just be an orphan entry
        StartSceneTimeoutTimer()
        Log("Solo scene started — handle=" + handle + " actor=" + soloActor)
    else
        Log("Solo scene start failed — no matching solo scene")
    endif
EndFunction

ObjectReference[] Function FindNearbyFurniture(Actor akActor, float afRadius)
    ; Collect ALL furniture candidates within radius — not just beds.
    ; OSF's StartSceneAtAnchor matches by anchor.base FormID, so we return
    ; every furniture ref and let the caller iterate until one matches.
    ObjectReference[] candidates = new ObjectReference[0]
    float maxZ = GetMaxZOffset()
    float actorZ = akActor.GetPositionZ()

    ; Search each furniture keyword — merge unique refs.
    ; Restricted to furniture with real animation-pack coverage: beds
    ; (IsSleepFurniture), chairs and couches/benches. Bar stools, table
    ; chairs, stools and pilot seats produced dozens of rejected anchor
    ; queries in dense interiors like Astral Lounge (SF-TIK-007).
    Keyword[] keywords = new Keyword[3]
    keywords[0] = kIsSleepFurniture
    keywords[1] = kAnimFurnChair
    keywords[2] = kAnimFurnBench

    int ki = 0
    while ki < keywords.Length
        if keywords[ki] != None
            ObjectReference[] refs = akActor.FindAllReferencesWithKeyword(keywords[ki], afRadius)
            int i = 0
            while i < refs.Length
                ; Is3DLoaded filters refs found in adjacent (not loaded) cells —
                ; their GetDistance reports FLT_MAX and they can never serve as
                ; anchors, they only wasted probe budget (observed in logs).
                if refs[i] != None && refs[i].Is3DLoaded() && !refs[i].IsFurnitureInUse()
                    ; Z-offset filter — prevent teleporting between ship decks
                    if maxZ <= 0.0 || Math.abs(refs[i].GetPositionZ() - actorZ) <= maxZ
                        if candidates.Find(refs[i]) < 0
                            candidates.Add(refs[i], 1)
                        endif
                    endif
                endif
                i += 1
            endwhile
        endif
        ki += 1
    endwhile

    Log("FindNearbyFurniture: " + candidates.Length + " total candidates")

    ; Sort by distance (closest first)
    int n = candidates.Length
    if n > 1
        int i2 = 0
        while i2 < n - 1
            int j = 0
            while j < n - 1 - i2
                if candidates[j].GetDistance(akActor) > candidates[j + 1].GetDistance(akActor)
                    ObjectReference tmp = candidates[j]
                    candidates[j] = candidates[j + 1]
                    candidates[j + 1] = tmp
                endif
                j += 1
            endwhile
            i2 += 1
        endwhile
    endif

    return candidates
EndFunction

; ===========================================================================
; Emergency Stop & Audit
; ===========================================================================

Function EmergencyStopAll()
    if activeSceneHandles == None || activeSceneHandles.Length == 0
        return
    endif
    ; Snapshot handles AND tracked actors BEFORE clearing arrays
    int[] handlesToStop = activeSceneHandles
    Actor[] trackedA = sceneActorA
    Actor[] trackedB = sceneActorB
    activeSceneHandles = new int[0]
    sceneStartTimes = new float[0]
    finaleTriggeredHandles = new int[0]
    sceneActorA = new Actor[0]
    sceneActorB = new Actor[0]
    CancelTimer(TIMER_ID_SCENE_TIMEOUT)

    int i = 0
    while i < handlesToStop.Length
        if handlesToStop[i] > 0
            ; Tracked actors first (covers ghost scenes with empty participants);
            ; ApplyCooldownToActor is idempotent — also gives cooldown + anchor
            ; release + unequip so stopped pairs aren't instantly re-picked
            if i < trackedA.Length && trackedA[i] != None
                ApplyCooldownToActor(trackedA[i])
            endif
            if i < trackedB.Length && trackedB[i] != None
                ApplyCooldownToActor(trackedB[i])
            endif
            ; OSF participants for any actors tracking missed
            Actor[] parts = OSF.GetSceneParticipants(handlesToStop[i])
            if parts != None
                int pi = 0
                while pi < parts.Length
                    if parts[pi] != None
                        ApplyCooldownToActor(parts[pi])
                    endif
                    pi += 1
                endwhile
            endif
            OSF.StopScene(handlesToStop[i])
        endif
        i += 1
    endwhile
    Log("EmergencyStopAll — all scenes stopped")
EndFunction

Function AuditActiveScenes()
    if activeSceneHandles == None || activeSceneHandles.Length == 0
        return
    endif
    SyncSceneTracking()
    int i = 0
    while i < activeSceneHandles.Length
        int handle = activeSceneHandles[i]
        if handle <= 0
            ; Stale entry — remove directly (no OSF callback for invalid handles)
            activeSceneHandles.Remove(i)
            if i < sceneStartTimes.Length
                sceneStartTimes.Remove(i)
            endif
            if i < sceneActorA.Length
                sceneActorA.Remove(i)
            endif
            if i < sceneActorB.Length
                sceneActorB.Remove(i)
            endif
            int fIdx1 = finaleTriggeredHandles.Find(handle)
            if fIdx1 >= 0
                finaleTriggeredHandles.Remove(fIdx1)
            endif
            ; do not increment i — next element shifted into this slot
        else
            Actor[] participants = OSF.GetSceneParticipants(handle)
            if participants.Length == 0
                ; Scene no longer valid — remove directly (no callback will fire)
                float ghostDur = 0.0
                if i < sceneStartTimes.Length
                    ghostDur = Utility.GetCurrentRealTime() - sceneStartTimes[i]
                endif
                ; Tracked-actor cleanup — OSF.GetSceneParticipants returns empty
                ; for ghosts, so cooldown/anchor/gear teardown goes via tracking
                if i < sceneActorA.Length && sceneActorA[i] != None
                    ApplyCooldownToActor(sceneActorA[i])
                endif
                if i < sceneActorB.Length && sceneActorB[i] != None
                    ApplyCooldownToActor(sceneActorB[i])
                endif
                Log("Ghost scene removed — handle=" + handle + " duration=" + ghostDur + "s (no participants, no END callback)")
                activeSceneHandles.Remove(i)
                if i < sceneStartTimes.Length
                    sceneStartTimes.Remove(i)
                endif
                if i < sceneActorA.Length
                    sceneActorA.Remove(i)
                endif
                if i < sceneActorB.Length
                    sceneActorB.Remove(i)
                endif
                int fIdx2 = finaleTriggeredHandles.Find(handle)
                if fIdx2 >= 0
                    finaleTriggeredHandles.Remove(fIdx2)
                endif
            else
                ; Check participants for invalid states
                bool shouldStop = false
                int j = 0
                while j < participants.Length && !shouldStop
                    Actor p = participants[j]
                    if p != None
                        if p.IsDead() || p.IsInCombat() || p.IsInDialogueWithPlayer()
                            shouldStop = true
                        endif
                    else
                        shouldStop = true
                    endif
                    j += 1
                endwhile

                ; Desync detection: OSF says scene is active but actor has no animation
                if !shouldStop
                    j = 0
                    while j < participants.Length && !shouldStop
                        Actor p = participants[j]
                        if p != None && !OSF.IsPlaying(p)
                            shouldStop = true
                            Log("Desync detected — actor " + p + " not playing but scene " + handle + " still active")
                        endif
                        j += 1
                    endwhile
                endif

                ; Walk-in interrupt — stop scene if player approaches (optional, OFF by default)
                if !shouldStop && IsStopOnPlayerWalkIn()
                    float walkDist = GetWalkInDistance()
                    Actor player = Game.GetPlayer()
                    j = 0
                    while j < participants.Length && !shouldStop
                        Actor p = participants[j]
                        if p != None && p.GetDistance(player as ObjectReference) < walkDist
                            shouldStop = true
                            Log("Walk-in interrupt — player approached scene " + handle + " within " + walkDist + " units")
                        endif
                        j += 1
                    endwhile
                endif

                if shouldStop
                    ; Remove from tracking FIRST — OSF.StopScene may dispatch
                    ; EVENT_SCENE_END synchronously; if the handle were still in
                    ; the array, OnSceneEvent would remove index i and this path
                    ; would then remove it AGAIN, popping a different scene and
                    ; desyncing every parallel array (observed as bogus elapsed).
                    Actor tA = None
                    Actor tB = None
                    if i < sceneActorA.Length
                        tA = sceneActorA[i]
                    endif
                    if i < sceneActorB.Length
                        tB = sceneActorB[i]
                    endif
                    activeSceneHandles.Remove(i)
                    if i < sceneStartTimes.Length
                        sceneStartTimes.Remove(i)
                    endif
                    if i < sceneActorA.Length
                        sceneActorA.Remove(i)
                    endif
                    if i < sceneActorB.Length
                        sceneActorB.Remove(i)
                    endif
                    int fIdx3 = finaleTriggeredHandles.Find(handle)
                    if fIdx3 >= 0
                        finaleTriggeredHandles.Remove(fIdx3)
                    endif

                    ; Now safe to stop — a synchronous END callback finds nothing.
                    ; Reuse `participants` fetched pre-stop — a post-stop query
                    ; could return empty if OSF teardown ran synchronously.
                    bool stopped = OSF.StopScene(handle)
                    ; Apply cooldowns so the same pair isn't immediately re-selected
                    Actor[] stopParticipants = participants
                    int pi = 0
                    while pi < stopParticipants.Length
                        Actor p = stopParticipants[pi]
                        if p != None
                            ApplyCooldownToActor(p)
                        endif
                        pi += 1
                    endwhile
                    ; Tracked-actor fallback — covers ghost scenes where the
                    ; participants list came back empty
                    if tA != None && stopParticipants.Find(tA) < 0
                        ApplyCooldownToActor(tA)
                    endif
                    if tB != None && stopParticipants.Find(tB) < 0
                        ApplyCooldownToActor(tB)
                    endif
                    Log("Scene " + handle + " removed from tracking (stopped=" + stopped + ")")
                    ; do not increment i — next element shifted into this slot
                else
                    i += 1  ; scene still valid, move to next
                endif
            endif
        endif
    endwhile
EndFunction

; ===========================================================================
; Scene Timeout Enforcement
; ===========================================================================

Function StartSceneTimeoutTimer()
    ; Check every 30 seconds (real time) for expired scenes
    StartTimer(30.0, TIMER_ID_SCENE_TIMEOUT)
EndFunction

Function EnforceSceneTimeouts()
    if activeSceneHandles == None || activeSceneHandles.Length == 0
        return
    endif
    ; Realign scene-parallel arrays — also drops stale extras that would shift elapsed
    SyncSceneTracking()

    ; Use REAL time — animations play in real time, not game time
    float nowReal = Utility.GetCurrentRealTime()
    float timeoutSeconds = GetSceneTimeoutMinutes() * 60.0
    float finaleWindow = GetFinaleGracePeriod()

    ; Iterate BACKWARDS — safe removal during iteration
    int i = activeSceneHandles.Length - 1
    while i >= 0
        if i < sceneStartTimes.Length
            float elapsed = nowReal - sceneStartTimes[i]
            int handle = activeSceneHandles[i]
            if elapsed < 0.0
                ; Stored start time is in the future — stale value from a previous
                ; session (GetCurrentRealTime is process uptime). Reset, don't kill.
                Log("WARNING: stale start time for handle " + handle + " (elapsed=" + elapsed + ") — resetting timer")
                sceneStartTimes[i] = nowReal
                elapsed = 0.0
            endif

            ; Natural Finale — advance ONCE during Finale Window (not every tick)
            ; Use handle-based tracking to survive array shifts from AuditActiveScenes
            if IsNaturalFinale() && elapsed >= (timeoutSeconds - finaleWindow) && elapsed < timeoutSeconds
                bool alreadyTriggered = (finaleTriggeredHandles.Find(handle) >= 0)
                if !alreadyTriggered
                    int currentStage = OSF.GetSceneStage(handle)
                    if currentStage >= 0  ; -1 = non-linear or invalid, skip
                        OSF.AdvanceScene(handle)
                        Log("Natural finale — advanced stage for handle " + handle + " (stage=" + currentStage + ", elapsed=" + elapsed + "s)")
                    endif
                    ; Mark as triggered by handle — immune to array index shifts
                    finaleTriggeredHandles.Add(handle, 1)
                endif
            endif

            if elapsed >= timeoutSeconds
                Log("Scene timeout — stopping handle " + handle + " (elapsed=" + elapsed + " real seconds)")

                ; Remove from tracking FIRST — OSF.StopScene may dispatch
                ; EVENT_SCENE_END synchronously; if the handle were still in the
                ; array, OnSceneEvent would remove index i and this path would
                ; then remove it AGAIN, popping a different scene and desyncing
                ; every parallel array (observed as bogus elapsed).
                Actor tA = None
                Actor tB = None
                if i < sceneActorA.Length
                    tA = sceneActorA[i]
                endif
                if i < sceneActorB.Length
                    tB = sceneActorB[i]
                endif
                activeSceneHandles.Remove(i)
                sceneStartTimes.Remove(i)
                if i < sceneActorA.Length
                    sceneActorA.Remove(i)
                endif
                if i < sceneActorB.Length
                    sceneActorB.Remove(i)
                endif
                int fIdx4 = finaleTriggeredHandles.Find(handle)
                if fIdx4 >= 0
                    finaleTriggeredHandles.Remove(fIdx4)
                endif

                ; Fetch participants BEFORE stopping — if OSF teardown is
                ; synchronous, a post-stop query returns empty and misses them
                Actor[] participants = OSF.GetSceneParticipants(handle)

                ; Now safe to stop — a synchronous END callback finds nothing
                OSF.StopScene(handle)

                ; Apply cooldowns for real participants (ghost scenes return empty array)
                int pi = 0
                while pi < participants.Length
                    Actor p = participants[pi]
                    if p != None
                        ApplyCooldownToActor(p)
                    endif
                    pi += 1
                endwhile
                ; Tracked-actor fallback — ghost scenes return empty participants,
                ; so tA/tB still need cooldown + anchor release + gear cleanup
                if tA != None && participants.Find(tA) < 0
                    ApplyCooldownToActor(tA)
                endif
                if tB != None && participants.Find(tB) < 0
                    ApplyCooldownToActor(tB)
                endif
            endif
        endif
        i -= 1
    endwhile

    ; Reschedule timeout check if scenes still active
    if activeSceneHandles != None && activeSceneHandles.Length > 0
        StartTimer(30.0, TIMER_ID_SCENE_TIMEOUT)
    endif
EndFunction

; ===========================================================================
; Cooldown Management
; ===========================================================================

; Cooldown + anchor release + gear cleanup for one participant. Idempotent —
; safe to call for an actor already processed by a participants loop.
Function ApplyCooldownToActor(Actor p)
    float cooldownEnd = Utility.GetCurrentGameTime() + (GetCooldownMinutes() / 1440.0)
    int cIdx = cooldownActors.Find(p)
    if cIdx >= 0
        cooldownEndTimes[cIdx] = cooldownEnd
    else
        cooldownActors.Add(p, 1)
        cooldownEndTimes.Add(cooldownEnd, 1)
    endif
    ; Release OSF anchor so actor can walk off furniture instead of standing on it
    OSF.ClearAnchor(p)
    p.EvaluatePackage()
    UnequipStuckAttachments(p)
EndFunction

bool Function IsOnCooldown(Actor akActor)
    int idx = cooldownActors.Find(akActor)
    if idx < 0
        return false
    endif
    float now = Utility.GetCurrentGameTime()
    if now >= cooldownEndTimes[idx]
        ; Cooldown expired — clean up this entry
        cooldownActors.Remove(idx)
        cooldownEndTimes.Remove(idx)
        return false
    endif
    return true
EndFunction

Function CleanExpiredCooldowns()
    ; Clean actor cooldowns
    if cooldownActors != None && cooldownActors.Length > 0
        float now = Utility.GetCurrentGameTime()
        int i = 0
        while i < cooldownActors.Length
            if now >= cooldownEndTimes[i]
                cooldownActors.Remove(i)
                cooldownEndTimes.Remove(i)
                ; do not increment i
            else
                i += 1
            endif
        endwhile
    endif

    ; Clean pair cooldowns
    if pairCooldownKeys != None && pairCooldownKeys.Length > 0
        float nowPair = Utility.GetCurrentGameTime()
        int j = 0
        while j < pairCooldownKeys.Length
            if nowPair >= pairCooldownEndTimes[j]
                pairCooldownKeys.Remove(j)
                pairCooldownEndTimes.Remove(j)
                ; do not increment j
            else
                j += 1
            endif
        endwhile
    endif
EndFunction

; ===========================================================================
; MCM Settings Readers (OSFSettings — cheap, thread-safe, call per use)
; ===========================================================================

bool Function IsEnabled()
    return OSFSettings.GetBool(MOD_ID, "bEnabled", true)
EndFunction

; Restart the scan timer only while the mod is enabled — event-driven resumes
; shouldn't leave a stray pending tick (and a wasted OnTimer pass) after the
; user has disabled the mod via OSF UI.
Function ResumeScanTimer()
    if IsEnabled()
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
    endif
EndFunction

; Returns true only when the player is physically inside their OWN ship.
; Cell.GetParentRef() returns the SpaceshipReference that owns a ship/station
; interior cell — but Actor.GetCurrentShipRef() is just an alias for that
; same call (see ObjectReference.psc), so comparing them is a tautology that
; reports "own ship" inside ANY vessel: docked ships, stations, Deimos.
; Ownership must come from the engine's player-ship registry (SF-TIK-008).
bool Function IsPlayerInOwnShip()
    Actor player = Game.GetPlayer()
    Cell playerCell = player.GetParentCell()
    if playerCell == None
        return false
    endif
    SpaceshipReference ship = playerCell.GetParentRef() as SpaceshipReference
    if ship == None
        return false
    endif
    return Game.IsPlayerSpaceshipOwner(ship)
EndFunction

; Private locations owned by the player: own ship interior, player outposts
; (LocTypeOutpost) and purchasable player homes (LocTypePlayerHouse).
bool Function IsInPrivatePlayerLocation()
    if IsPlayerInOwnShip()
        return true
    endif
    Location loc = Game.GetPlayer().GetCurrentLocation()
    if loc == None
        return false
    endif
    if kLocTypePlayerOutpost != None && loc.HasKeyword(kLocTypePlayerOutpost)
        return true
    endif
    if kLocTypePlayerHouse != None && loc.HasKeyword(kLocTypePlayerHouse)
        return true
    endif
    return false
EndFunction

; Vacuum / suit-required environments: no NPC scenes on airless or non-
; breathable exteriors. Interiors are pressurized regardless of planet.
bool Function IsBreathableEnvironment()
    Actor player = Game.GetPlayer()
    Cell c = player.GetParentCell()
    if c != None && c.IsInterior()
        return true
    endif
    ; Space exterior: GetCurrentPlanet still resolves to the planet being
    ; orbited, so a pure atmosphere check would wrongly mark orbit as
    ; breathable. IsInSpace() is the definitive vacuum test.
    if player.IsInSpace()
        Log("Environment blocked — space exterior (vacuum)")
        return false
    endif
    ; Pressurized zones that aren't interior-flagged cells — outpost habs and
    ; seamless structures are exterior cells by engine design. The engine
    ; tracks "hide helmet in breathable zone" as an actor value; trust it.
    if kAvHideHelmetBreathable != None && player.GetValue(kAvHideHelmetBreathable) > 0.0
        return true
    endif
    Planet p = player.GetCurrentPlanet()
    if p == None
        Log("Environment blocked — exterior with no planet (deep space)")
        return false
    endif
    Keyword atmo = p.GetAtmosphereType()
    ; Oxygen-class atmospheres are breathable: O2, HighO2 and LowO2 (thin but
    ; suit-free — NPCs walk unsuited on Low O2 worlds). None/vacuum, CO2, N2,
    ; H2 and methane all require a suit.
    bool ok = atmo != None && (atmo == kPlanetAtmoO2 || atmo == kPlanetAtmoHighO2 || atmo == kPlanetAtmoLowO2)
    if !ok
        Log("Environment blocked — non-breathable exterior, planet=" + p + " atmosphere=" + atmo + " cell=" + c + " interior=" + (c != None && c.IsInterior()))
    endif
    return ok
EndFunction

bool Function IsLocationAllowed()
    if !IsEnabled()
        Log("Location denied — mod disabled (bEnabled=false)")
        return false
    endif
    if !IsBreathableEnvironment()
        return false  ; reason already logged inside
    endif
    string mode = GetLocationMode()
    if mode == "everywhere"
        return true
    endif
    ; Dynamic check, not the cached flag — enter/exit event ordering can leave
    ; bIsOnShip stale across station/docked transitions (SF-TIK-008).
    if IsPlayerInOwnShip()
        return true
    endif
    if mode == "interiors"
        ; "Ship + Outposts + Homes" — private player locations only, never
        ; public interiors like starstations, bars or clubs (SF-TIK-008).
        bool priv = IsInPrivatePlayerLocation()
        if !priv
            Log("Location denied — mode=" + mode + " but not a private location; bIsOnShip=" + bIsOnShip + " loc=" + Game.GetPlayer().GetCurrentLocation() + " cell=" + Game.GetPlayer().GetParentCell())
        endif
        return priv
    endif
    Log("Location denied — mode=" + mode + " bIsOnShip=" + bIsOnShip)
    return false
EndFunction

string Function GetLocationMode()
    return OSFSettings.GetEnum(MOD_ID, "sLocationMode", "ship")
EndFunction

bool Function IsCompanionsOnly()
    return OSFSettings.GetBool(MOD_ID, "bCompanionsOnly", false)
EndFunction

bool Function IsIncludeOutpostNPC()
    return OSFSettings.GetBool(MOD_ID, "bIncludeOutpostNPC", false)
EndFunction

bool Function IsRequireFurniture()
    return OSFSettings.GetBool(MOD_ID, "bRequireFurniture", true)
EndFunction

int Function GetMaxConcurrent()
    return OSFSettings.GetInt(MOD_ID, "iMaxConcurrentScenes", 2)
EndFunction

float Function GetCheckInterval()
    return OSFSettings.GetFloat(MOD_ID, "fCheckInterval", 45.0)
EndFunction

int Function GetChancePercent()
    return OSFSettings.GetInt(MOD_ID, "iChancePercent", 25)
EndFunction

float Function GetCooldownMinutes()
    return OSFSettings.GetFloat(MOD_ID, "fActorCooldownMinutes", 10.0)
EndFunction

int Function GetStripMode()
    ; Schema declares iStripMode as enum with numeric options — GetEnum then cast
    return OSFSettings.GetEnum(MOD_ID, "iStripMode", "-1") as int
EndFunction

float Function GetLoopScale()
    return OSFSettings.GetFloat(MOD_ID, "fLoopScale", 1.0)
EndFunction

float Function GetSceneTimeoutMinutes()
    return OSFSettings.GetFloat(MOD_ID, "fSceneTimeoutMinutes", 3.0)
EndFunction

bool Function IsAdvanceStages()
    return true
EndFunction

float Function GetMaxZOffset()
    return OSFSettings.GetFloat(MOD_ID, "fMaxZOffset", 200.0)
EndFunction

float Function GetMaxPairDistance()
    return 400.0
EndFunction

float Function GetPairCooldownMinutes()
    return OSFSettings.GetFloat(MOD_ID, "fPairCooldownMinutes", 30.0)
EndFunction

bool Function IsTagRotation()
    return true
EndFunction

bool Function IsPreferSequences()
    return true
EndFunction

bool Function IsAllowForeplay()
    return OSFSettings.GetBool(MOD_ID, "bAllowForeplay", true)
EndFunction

bool Function IsAllowClassic()
    return OSFSettings.GetBool(MOD_ID, "bAllowClassic", true)
EndFunction

bool Function IsAllowIntense()
    return OSFSettings.GetBool(MOD_ID, "bAllowIntense", true)
EndFunction

; --- Romance Exclusivity ---
bool Function IsRomanceExclusivity()
    return OSFSettings.GetBool(MOD_ID, "bRomanceExclusivity", true)
EndFunction

bool Function IsPolyamoryBypass()
    return false
EndFunction

; --- Max Distance Guard ---
float Function GetMaxStartDistance()
    return OSFSettings.GetFloat(MOD_ID, "fMaxStartDistance", 2000.0)
EndFunction

float Function GetMinSceneSpacing()
    return OSFSettings.GetFloat(MOD_ID, "fMinSceneSpacing", 500.0)
EndFunction

bool Function IsUseMFForFF()
    return OSFSettings.GetBool(MOD_ID, "bUseMFForFF", true)
EndFunction

bool Function IsStopOnPlayerWalkIn()
    return OSFSettings.GetBool(MOD_ID, "bStopOnPlayerWalkIn", false)
EndFunction

float Function GetWalkInDistance()
    return OSFSettings.GetFloat(MOD_ID, "fWalkInDistance", 150.0)
EndFunction

; --- Natural Finale ---
bool Function IsNaturalFinale()
    return true
EndFunction

float Function GetFinaleGracePeriod()
    return 10.0
EndFunction

; --- Solo Downtime ---
bool Function IsSoloDowntime()
    return OSFSettings.GetBool(MOD_ID, "bSoloDowntime", true)
EndFunction

bool Function IsSoloPrivateOnly()
    return OSFSettings.GetBool(MOD_ID, "bSoloPrivateOnly", true)
EndFunction

float Function GetSoloChance()
    return OSFSettings.GetFloat(MOD_ID, "fSoloChance", 20.0)
EndFunction

string Function GetSpeedMode()
    return OSFSettings.GetEnum(MOD_ID, "sSpeedMode", "static")
EndFunction

float Function GetBaseSceneSpeed()
    return 1.0
EndFunction

; ===========================================================================
; Pair Cooldown — prevents same two NPCs from pairing too frequently
; ===========================================================================

String Function GetPairKey(Actor akA, Actor akB)
    int idA = akA.GetFormID()
    int idB = akB.GetFormID()
    if idA < idB
        return idA + ":" + idB
    endif
    return idB + ":" + idA
EndFunction

bool Function IsPairOnCooldown(Actor akA, Actor akB)
    if pairCooldownKeys == None || pairCooldownKeys.Length == 0
        return false
    endif
    String pairKey = GetPairKey(akA, akB)
    int idx = pairCooldownKeys.Find(pairKey)
    if idx < 0
        return false
    endif
    if Utility.GetCurrentGameTime() >= pairCooldownEndTimes[idx]
        pairCooldownKeys.Remove(idx)
        pairCooldownEndTimes.Remove(idx)
        return false
    endif
    return true
EndFunction

Function SetPairCooldown(Actor akA, Actor akB)
    String pairKey = GetPairKey(akA, akB)
    float endTime = Utility.GetCurrentGameTime() + (GetPairCooldownMinutes() / 1440.0)
    int idx = pairCooldownKeys.Find(pairKey)
    if idx >= 0
        pairCooldownEndTimes[idx] = endTime
    else
        pairCooldownKeys.Add(pairKey, 1)
        pairCooldownEndTimes.Add(endTime, 1)
    endif
EndFunction

; ===========================================================================
; Tag Rotation — cycles action tags for scene variety (OSF-validated tags)
; ===========================================================================

String Function GetNextActionTag(String asGenderTag)
    String[] pool = GetActiveActionPool(asGenderTag)
    
    ; Count actual valid tags
    int validCount = 0
    while validCount < pool.Length && pool[validCount] != ""
        validCount += 1
    endwhile

    if validCount == 0
        return ""
    endif
    
    String tag = pool[iTagRotationIndex % validCount]
    iTagRotationIndex = (iTagRotationIndex + 1) % 1000  ; monotonic — avoids phase skipping between MF/FF pools
    return tag
EndFunction

String[] Function GetActiveActionPool(String asGenderTag)
    String[] pool = new String[16]
    int count = 0

    if asGenderTag == "ff"
        if IsAllowForeplay()
            pool[count] = "kissing"
            count += 1
            pool[count] = "oral"
            count += 1
        endif
        if IsAllowClassic()
            pool[count] = "scissors"
            count += 1
            pool[count] = "cowgirl"
            count += 1
            pool[count] = "facedown"
            count += 1
        endif
        if IsAllowIntense()
            pool[count] = "doggy"
            count += 1
            pool[count] = "reversecowgirl"
            count += 1
        endif
    else ; "mf"
        if IsAllowForeplay()
            pool[count] = "kissing"
            count += 1
            pool[count] = "blowjob"
            count += 1
            pool[count] = "oral"
            count += 1
        endif
        if IsAllowClassic()
            pool[count] = "missionary"
            count += 1
            pool[count] = "cowgirl"
            count += 1
            pool[count] = "spoon"
            count += 1
            pool[count] = "facedown"
            count += 1
        endif
        if IsAllowIntense()
            pool[count] = "doggy"
            count += 1
            pool[count] = "reversecowgirl"
            count += 1
            pool[count] = "riding"
            count += 1
        endif
    endif

    ; Pack into exact-sized array
    String[] result = new String[count]
    int i = 0
    while i < count
        result[i] = pool[i]
        i += 1
    endwhile
    return result
EndFunction

; --- Furniture keyword to OSF furniture tag mapping ---
; Starfield doesn't expose standard furniture type keywords (FurnitureBedDouble, etc).
; OSF's StartSceneAtAnchor receives the anchor reference directly and matches
; furniture type internally — no furniture tag needed in the query.
; This function is reserved for future use if keyword mapping becomes viable.

String Function GetOSFFurnitureTag(ObjectReference akAnchor)
    return ""  ; OSF handles furniture matching via anchor reference
EndFunction

; --- Query tag builder ---

String[] Function BuildQueryTags(String asGenderTag, String asFurnitureTag, String asActionTag, String asExtraTag, String asExtraTag2 = "")
    string[] temp = new string[6]
    int count = 0
    temp[count] = "paired"
    count += 1
    temp[count] = asGenderTag
    count += 1
    if asFurnitureTag != ""
        temp[count] = asFurnitureTag
        count += 1
    endif
    if asActionTag != ""
        temp[count] = asActionTag
        count += 1
    endif
    if asExtraTag != ""
        temp[count] = asExtraTag
        count += 1
    endif
    if asExtraTag2 != ""
        temp[count] = asExtraTag2
        count += 1
    endif
    string[] result = new string[count]
    int i = 0
    while i < count
        result[i] = temp[i]
        i += 1
    endwhile
    return result
EndFunction

; Build query tags with pack discriminator ('ge' or 'snusnu') for role-safe MF partitioning
String[] Function BuildQueryTagsWithPack(String asGenderTag, String asActionTag, String asPackTag, String asExtraTag, String asExtraTag2 = "")
    string[] temp = new string[7]
    int count = 0
    temp[count] = "paired"
    count += 1
    temp[count] = asGenderTag
    count += 1
    if asPackTag != ""
        temp[count] = asPackTag
        count += 1
    endif
    if asActionTag != ""
        temp[count] = asActionTag
        count += 1
    endif
    if asExtraTag != ""
        temp[count] = asExtraTag
        count += 1
    endif
    if asExtraTag2 != ""
        temp[count] = asExtraTag2
        count += 1
    endif
    string[] result = new string[count]
    int i = 0
    while i < count
        result[i] = temp[i]
        i += 1
    endwhile
    return result
EndFunction

; ===========================================================================
; Speed Control — calculates initial speed based on MCM mode
; ===========================================================================

float Function CalculateInitialSpeed()
    string mode = GetSpeedMode()
    if mode == "dynamic"
        return 0.85
    elseif mode == "random"
        return Utility.RandomFloat(0.8, 1.25)
    endif
    ; mode == "static"
    float speed = GetBaseSceneSpeed()
    if speed < 0.5
        return 0.5
    elseif speed > 2.0
        return 2.0
    endif
    return speed
EndFunction
