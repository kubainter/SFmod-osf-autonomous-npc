ScriptName OSF_AutonomousManagerScript Extends Quest
{OSF Autonomous NPC Interactions — manager quest script.
 Scans for eligible NPC pairs during idle/sandbox situations and starts
 OSF Animation scenes. Pure Papyrus + OSF UI JSON settings. No C++ DLL required.}

; --- Timer IDs (constants) ---
int Property TIMER_ID_SCAN = 1 Auto Const
{Timer ID for the scan loop.}
int Property TIMER_ID_SCENE_TIMEOUT = 2 Auto Const
{Timer ID for scene timeout enforcement.}

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

; --- Internal state (not properties — not saved with the quest) ---
int iActiveScenes = 0
int[] activeSceneHandles
float[] sceneStartTimes        ; REAL-time when each scene started (parallel to activeSceneHandles)
bool[] sceneFinaleTriggered    ; tracks if natural finale advance was fired (parallel to activeSceneHandles)
int[] finaleTriggeredHandles   ; handle-based finale tracking — immune to array shifts
Actor[] cooldownActors
float[] cooldownEndTimes
String[] pairCooldownKeys      ; pair cooldown tracking (FormID_A:FormID_B)
float[] pairCooldownEndTimes
int iTagRotationIndex = 0      ; rotates through mood tags for scene variety

; --- Version migration (prevents save corruption on script updates) ---
int Property CURRENT_VERSION = 2 AutoReadOnly
int Property iInstalledVersion = 0 Auto
int iSceneCallbackToken = 0
int iSettingsCallbackToken = 0
bool bIsOnShip = false

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

    ; --- Register OSF UI settings change listener ---
    if OSFUI.GetVersion() > 0
        iSettingsCallbackToken = OSFUI.RegisterForSettingChanges(self, "OnSettingChanged", MOD_ID)
    endif

    ; --- Check initial ship state ---
    ; Do NOT use GetCurrentShipRef() — it returns home ship everywhere.
    ; Check if player is actually inside a ship interior cell.
    Cell playerCell = player.GetParentCell()
    if playerCell != None && playerCell.IsInterior()
        ; Heuristic: if GetCurrentShipRef returns a ship and player is in interior, likely in ship
        bIsOnShip = (ship != None)
    else
        bIsOnShip = false
    endif

    if IsLocationAllowed()
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        Log("OnQuestInit — scan timer started (" + GetCheckInterval() + "s)")
    else
        Log("OnQuestInit — location not allowed, scan timer NOT started")
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

    if kActorTypeRobot == None
        Log("WARNING: ActorTypeRobot keyword not loaded — robot filter inactive")
    endif
    if kIsSleepFurniture == None
        Log("WARNING: IsSleepFurniture keyword not loaded — furniture detection inactive")
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
EndFunction

Function UnequipStuckAttachments(Actor akActor)
    ; Some SOS/strapon mods (Dick.esm, Haters Body) leave their gear equipped after a scene
    ; when OSF's built-in strip/restore fails to remove it. Force-unequip known forms.
    ; This only touches these specific gear items, never the full inventory.
    if akActor == None
        return
    endif
    if kDickGear != None && akActor.IsEquipped(kDickGear)
        akActor.UnequipItem(kDickGear, false, true)
    endif
    if kDickFlaccidGear != None && akActor.IsEquipped(kDickFlaccidGear)
        akActor.UnequipItem(kDickFlaccidGear, false, true)
    endif
    if kDickErectGear != None && akActor.IsEquipped(kDickErectGear)
        akActor.UnequipItem(kDickErectGear, false, true)
    endif
    if kDickErect2Gear != None && akActor.IsEquipped(kDickErect2Gear)
        akActor.UnequipItem(kDickErect2Gear, false, true)
    endif
    if kHatersGear != None && akActor.IsEquipped(kHatersGear)
        akActor.UnequipItem(kHatersGear, false, true)
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
; OSF Scene Event Handler (called by OSF native relay)
; ===========================================================================

Function OnSceneEvent(OSFTypes:SceneEvent akEvent)
    if akEvent == None
        return
    endif

    if akEvent.eventType == OSF.EVENT_SCENE_BEGIN()
        ; Guard against duplicate BEGIN events (from double callback registration)
        if activeSceneHandles.Find(akEvent.sceneHandle) < 0
            return  ; handle not in our list — duplicate event, ignore
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
        int idx = activeSceneHandles.Find(handle)
        if idx < 0
            return  ; Not our scene — ignore
        endif

        if sceneFinaleTriggered == None
            sceneFinaleTriggered = new bool[0]
        endif
        if finaleTriggeredHandles == None
            finaleTriggeredHandles = new int[0]
        endif

        activeSceneHandles.Remove(idx)
        if idx < sceneStartTimes.Length
            float duration = Utility.GetCurrentRealTime() - sceneStartTimes[idx]
            if duration < 5.0
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
        if idx < sceneFinaleTriggered.Length
            sceneFinaleTriggered.Remove(idx)
        endif
        ; Handle-based finale tracking — remove by value
        int fIdx = finaleTriggeredHandles.Find(handle)
        if fIdx >= 0
            finaleTriggeredHandles.Remove(fIdx)
        endif
        iActiveScenes = activeSceneHandles.Length

        ; Set cooldowns for participants and return them to sandbox AI
        Actor[] participants = OSF.GetSceneParticipants(handle)
        float cooldownEnd = Utility.GetCurrentGameTime() + (GetCooldownMinutes() / 1440.0)
        int i = 0
        while i < participants.Length
            Actor p = participants[i]
            if p != None
                ; Update existing cooldown or add new (prevent duplicate entries)
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
            endif
            i += 1
        endwhile

        Log("Scene END — handle=" + handle + " cooldowns set for " + participants.Length + " actors")

    elseif akEvent.eventType == OSF.EVENT_CUE()
        ; Optional: log orgasm cue for future affinity integration
        if akEvent.cue == "orgasm"
            Log("Cue: orgasm (scene=" + akEvent.sceneHandle + ")")
        endif
    endif
EndFunction

; ===========================================================================
; OSF UI Settings Change Handler
; ===========================================================================

Function OnSettingChanged(String asModId, String asKey)
    if asModId != MOD_ID
        return
    endif

    if asKey == "bEnabled"
        if !IsEnabled()
            CancelTimer(TIMER_ID_SCAN)
            EmergencyStopAll()
            Log("Mod disabled via MCM")
        elseif IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("Mod re-enabled via MCM")
        endif
    elseif asKey == "sLocationMode"
        if !IsLocationAllowed()
            CancelTimer(TIMER_ID_SCAN)
            EmergencyStopAll()
            Log("Location mode changed — current location not allowed, scanning stopped")
        else
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("Location mode changed — scanning started")
        endif
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
    if sceneFinaleTriggered == None
        sceneFinaleTriggered = new bool[0]
    endif
    if finaleTriggeredHandles == None
        finaleTriggeredHandles = new int[0]
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

Event Actor.OnPlayerLoadGame(Actor akSender)
    if akSender != Game.GetPlayer()
        return
    endif

    ; Version migration — reset all state if script was updated
    if iInstalledVersion < CURRENT_VERSION
        Log("Migrating script data from v" + iInstalledVersion + " to v" + CURRENT_VERSION)
        activeSceneHandles = new int[0]
        sceneStartTimes = new float[0]
        sceneFinaleTriggered = new bool[0]
        finaleTriggeredHandles = new int[0]
        cooldownActors = new Actor[0]
        cooldownEndTimes = new float[0]
        pairCooldownKeys = new String[0]
        pairCooldownEndTimes = new float[0]
        iActiveScenes = 0
        iInstalledVersion = CURRENT_VERSION
    endif

    ; Safety: ensure all arrays are non-None
    EnsureArraysInitialized()

    ; DLL forgot all callback registrations — re-register
    RegisterOSFCallbacks()

    ; Re-initialize keywords (safeguard for existing saves)
    InitKeywords()
    InitGearForms()
    
    ; Ensure OnSit is registered for existing saves
    RegisterForRemoteEvent(Game.GetPlayer(), "OnSit")

    ; Re-register OSF UI settings listener (session-scoped)
    if iSettingsCallbackToken
        OSFUI.Unregister(iSettingsCallbackToken)
    endif
    if OSFUI.GetVersion() > 0
        iSettingsCallbackToken = OSFUI.RegisterForSettingChanges(self, "OnSettingChanged", MOD_ID)
    endif

    ; Audit active scenes — stop any that are no longer valid
    AuditActiveScenes()

    ; Re-evaluate timer state
    SpaceshipReference ship = Game.GetPlayer().GetCurrentShipRef()
    ; Fallback: if player is inside an interior cell and has a ship, likely on ship.
    ; OnEnterShipInterior won't fire on load if player was already inside.
    Cell playerCell = Game.GetPlayer().GetParentCell()
    if playerCell != None && playerCell.IsInterior()
        bIsOnShip = (ship != None)
    else
        bIsOnShip = false
    endif
    if ship != None
        RegisterForRemoteEvent(ship, "OnShipGravJump")
        RegisterForRemoteEvent(ship, "OnShipTakeOff")
        RegisterForRemoteEvent(ship, "OnShipDock")
        RegisterForRemoteEvent(ship, "OnShipLanding")
    endif
    if IsLocationAllowed()
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
    else
        CancelTimer(TIMER_ID_SCAN)
    endif

    ; Purge any scenes that exceeded timeout while cell was unloaded
    EnforceSceneTimeouts()
    AuditActiveScenes()

    Log("OnPlayerLoadGame — callbacks re-registered, active scenes=" + iActiveScenes)
EndEvent

; ===========================================================================
; OnQuestInit runs AFTER OnPlayerLoadGame on first load with a new mod.
; If OnPlayerLoadGame fired first and failed to start a timer (unbound script),
; OnQuestInit will handle it. This flag prevents duplicate timer starts.
; ===========================================================================

Event Actor.OnLocationChange(Actor akSender, Location akOldLoc, Location akNewLoc)
    if akSender != Game.GetPlayer()
        return
    endif

    ; Do NOT use GetCurrentShipRef() to set bIsOnShip — it returns the player's home ship
    ; everywhere in the galaxy. Rely on OnEnterShipInterior/OnExitShipInterior for ship state.
    ; Just re-evaluate timer based on current bIsOnShip (set by enter/exit events)

    ; On fast travel or grav jump to a new location, existing scenes may have unloaded actors
    Cell playerCell = Game.GetPlayer().GetParentCell()
    bool isInExterior = (playerCell == None || !playerCell.IsInterior())

    if IsLocationAllowed()
        ; Unconditionally purge if exterior, regardless of bIsOnShip
        if isInExterior
            EmergencyStopAll()
            Log("Location change — exterior, old scenes cleared, scanning started")
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        elseif !bIsOnShip
            ; Purge ghost scenes from previous location before starting fresh
            EnforceSceneTimeouts()
            AuditActiveScenes()
            Log("Location change — interior cell, scenes audited, scanning started")
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        endif
    else
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("Location change — location not allowed, scanning stopped")
    endif
EndEvent

Event Actor.OnSit(Actor akSender, ObjectReference akFurniture)
    if akSender != Game.GetPlayer()
        return
    endif
    ; If player takes the pilot seat, their spaceship reference becomes valid
    if Game.GetPlayer().GetSpaceship() != None
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("OnSit — player started piloting, all scenes stopped")
    endif
EndEvent

Event Actor.OnEnterShipInterior(Actor akSender, ObjectReference akShip)
    if akSender != Game.GetPlayer()
        return
    endif
    bIsOnShip = true
    ; Register ship lifecycle events on current ship (handles ship changes mid-session)
    SpaceshipReference currentShip = Game.GetPlayer().GetCurrentShipRef()
    if currentShip != None
        RegisterForRemoteEvent(currentShip, "OnShipGravJump")
        RegisterForRemoteEvent(currentShip, "OnShipTakeOff")
        RegisterForRemoteEvent(currentShip, "OnShipDock")
        RegisterForRemoteEvent(currentShip, "OnShipLanding")
    endif
    if IsLocationAllowed()
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        Log("OnEnterShipInterior — scanning started")
    endif
EndEvent

Event Actor.OnExitShipInterior(Actor akSender, ObjectReference akShip)
    if akSender != Game.GetPlayer()
        return
    endif
    bIsOnShip = false
    string mode = GetLocationMode()

    ; Check if player is now in an exterior (planet surface) or interior (outpost/station)
    Cell playerCell = Game.GetPlayer().GetParentCell()
    bool isInExterior = (playerCell == None || !playerCell.IsInterior())

    if mode == "ship"
        ; Ship-only mode — always stop when leaving ship
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("OnExitShipInterior — mode=ship, scanning stopped, scenes cleared")
    elseif isInExterior
        ; Player exited to a planet surface / exterior — ship actors will unload
        ; Stop all scenes regardless of mode to prevent ghost scenes
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("OnExitShipInterior — exterior exit, ship scenes cleared, scanning resumed")
        else
            Log("OnExitShipInterior — exterior exit, scenes cleared, location not allowed")
        endif
    else
        ; Player moved to another interior (outpost building, docked station)
        ; Keep scenes but purge any actors left behind in the old cell
        EnforceSceneTimeouts()
        AuditActiveScenes()
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("OnExitShipInterior — interior transition, scenes audited, scanning continued")
        else
            CancelTimer(TIMER_ID_SCAN)
            EmergencyStopAll()
            Log("OnExitShipInterior — interior transition, location not allowed, scenes cleared")
        endif
    endif
EndEvent

Event Actor.OnCombatStateChanged(Actor akSender, ObjectReference akTarget, int aeCombatState)
    if akSender != Game.GetPlayer()
        return
    endif
    if aeCombatState == 1
        ; Entering combat — stop everything immediately
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("Player entered combat — all scenes stopped")
    elseif aeCombatState == 0
        ; Leaving combat — resume if location allows
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("Player combat ended — scanning resumed")
        endif
    endif
EndEvent

; ===========================================================================
; Ship Lifecycle Events — stop scenes during transitions
; ===========================================================================

Event SpaceshipReference.OnShipGravJump(SpaceshipReference akSender, Location aDestination, int aState)
    ; Only process events from the player's current ship
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    ; aState: 0 = departure, 1 = arrival
    if aState == 0
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("OnShipGravJump — departure, all scenes stopped")
    elseif aState == 1
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("OnShipGravJump — arrival, scanning resumed")
        endif
    endif
EndEvent

Event SpaceshipReference.OnShipTakeOff(SpaceshipReference akSender, bool abComplete)
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if !abComplete
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("OnShipTakeOff — takeoff started, all scenes stopped")
    else
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("OnShipTakeOff — takeoff complete, scanning resumed")
        endif
    endif
EndEvent

Event SpaceshipReference.OnShipDock(SpaceshipReference akSender, bool abComplete, SpaceshipReference akDocking, SpaceshipReference akParent)
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if !abComplete
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("OnShipDock — docking started, all scenes stopped")
    else
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("OnShipDock — docking complete, scanning resumed")
        endif
    endif
EndEvent

Event SpaceshipReference.OnShipLanding(SpaceshipReference akSender, bool abComplete)
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if !abComplete
        CancelTimer(TIMER_ID_SCAN)
        EmergencyStopAll()
        Log("OnShipLanding — landing started, all scenes stopped")
    else
        if IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            Log("OnShipLanding — landing complete, scanning resumed")
        endif
    endif
EndEvent

; ===========================================================================
; Timer — Main Scan Loop
; ===========================================================================

Event OnTimer(int aiTimerID)
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
        ; Player piloting ship (prevents scenes starting while flying)
        if player.GetSpaceship() != None
            Log("OnTimer — player is piloting ship, rescheduling")
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
    if iActiveScenes >= GetMaxConcurrent()
        Log("OnTimer — max concurrent scenes reached (" + iActiveScenes + "/" + GetMaxConcurrent() + "), rescheduling")
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
            if a != None && candidates.Find(a) < 0
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
            if a != None && candidates.Find(a) < 0
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
            if a != None && candidates.Find(a) < 0
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
        ObjectReference[] nearbyNPCs = player.FindAllReferencesWithKeyword(kActorTypeHuman, scanRange)
        int k = 0
        while k < nearbyNPCs.Length
            Actor a = nearbyNPCs[k] as Actor
            if a != None && candidates.Find(a) < 0
                candidates.Add(a, 1)
                outpostCount += 1
            endif
            k += 1
        endwhile
    endif

    Log("Candidates — companions=" + companionCount + " generic=" + genericCount + " elite=" + eliteCount + " followers=" + followerCount + " outpost=" + outpostCount + " total=" + candidates.Length)
    Log("Settings — bIncludeOutpostNPC=" + IsIncludeOutpostNPC() + " kActorTypeHuman=" + (kActorTypeHuman != None) + " bCompanionsOnly=" + IsCompanionsOnly())

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

    ; Roll trigger chance
    int roll = Utility.RandomInt(1, 100)
    if roll > GetChancePercent()
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    ; Select a random pair — try to find one not on pair cooldown, within distance, and gender-compatible
    int idxA = -1
    int idxB = -1
    bool foundPair = false
    int attempts = 0
    int maxAttempts = 10
    float maxZ = GetMaxZOffset()

    while attempts < maxAttempts && !foundPair
        idxA = Utility.RandomInt(0, eligible.Length - 1)
        idxB = (idxA + Utility.RandomInt(1, eligible.Length - 1)) % eligible.Length
        Actor aA = eligible[idxA]
        Actor aB = eligible[idxB]
        if !IsPairOnCooldown(aA, aB)
            ; Check distance and Z-offset
            float dist = aA.GetDistance(aB as ObjectReference)
            float zDiff = Math.abs(aA.GetPositionZ() - aB.GetPositionZ())
            if dist <= GetMaxPairDistance() && (maxZ <= 0.0 || zDiff <= maxZ)
                ; Check gender compatibility (skip MM pairs)
                int sexA = aA.GetLeveledActorBase().GetSex()
                int sexB = aB.GetLeveledActorBase().GetSex()
                if !(sexA == 0 && sexB == 0)
                    foundPair = true
                endif
            endif
        endif
        attempts += 1
    endwhile

    ; If all pairs on cooldown, skip this scan cycle — don't bypass the cooldown
    if !foundPair
        ; Solo Downtime — try solo animation if no pair found
        if IsSoloDowntime()
            TryStartSoloScene(eligible)
        else
            Log("All pairs on cooldown — skipping scan cycle")
        endif
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    ; Try to start a scene
    TryStartScene(eligible[idxA], eligible[idxB])

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
    ; ActorTypeRobot keyword may be on the Race, not on the ActorBase.
    ; Check both Actor.HasKeyword and Race.HasKeyword for robustness.
    if kActorTypeRobot != None
        if akActor.HasKeyword(kActorTypeRobot)
            Log("Rejected " + actorName + " — robot (actor keyword)")
            return false
        endif
        Race actorRace = akActor.GetRace()
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
    Race actorRace = akActor.GetRace()
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

    ; Romance Exclusivity Guard — block romanced companions from autonomous scenes
    ; Check rank >= 3 (Ally/Dating) — covers dismissed/unassigned companions too
    if IsRomanceExclusivity() && !IsPolyamoryBypass()
        if akActor.GetRelationshipRank(Game.GetPlayer()) >= 3
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
    int sexA = akActorA.GetLeveledActorBase().GetSex()
    int sexB = akActorB.GetLeveledActorBase().GetSex()
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

    ; Find furniture anchor
    ObjectReference anchorRef = None
    if akActorA.GetSitState() == 3
        ObjectReference usedFurniture = akActorA.GetFurnitureUsing()
        if usedFurniture != None && kIsSleepFurniture != None && usedFurniture.HasKeyword(kIsSleepFurniture)
            anchorRef = usedFurniture
        endif
    endif
    if anchorRef == None && akActorB.GetSitState() == 3
        ObjectReference usedFurniture = akActorB.GetFurnitureUsing()
        if usedFurniture != None && kIsSleepFurniture != None && usedFurniture.HasKeyword(kIsSleepFurniture)
            anchorRef = usedFurniture
        endif
    endif
    if anchorRef == None
        anchorRef = FindNearbyFurniture(akActorA, 400.0)
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

    ; Keep actors dressed for non-sexual scenes (kissing doesn't need nudity)
    if actionTag == "kissing"
        opts.StripMode     = OSF.OFF()
    else
        opts.StripMode     = GetStripMode()
    endif

    int handle = 0

    ; ===== 5-TIER FALLBACK CHAIN =====

    ; TIER 1: Anchor + Action (+ sequence if preferred)
    if anchorRef != None && furnitureTag != ""
        opts.InPlaceMode = OSF.OFF()  ; snap to anchor
        if actionTag != ""
            if IsPreferSequences()
                string[] t1seq = BuildQueryTags(genderTag, furnitureTag, actionTag, "sequence")
                handle = OSF.StartSceneAtAnchor(actors, anchorRef, t1seq, opts)
            endif
            if handle <= 0
                string[] t1 = BuildQueryTags(genderTag, furnitureTag, actionTag, "")
                handle = OSF.StartSceneAtAnchor(actors, anchorRef, t1, opts)
            endif
        endif
        ; TIER 2: Anchor + any action for this furniture type
        if handle <= 0
            if IsPreferSequences()
                string[] t2seq = BuildQueryTags(genderTag, furnitureTag, "", "sequence")
                handle = OSF.StartSceneAtAnchor(actors, anchorRef, t2seq, opts)
            endif
            if handle <= 0
                string[] t2 = BuildQueryTags(genderTag, furnitureTag, "", "")
                handle = OSF.StartSceneAtAnchor(actors, anchorRef, t2, opts)
            endif
        endif
        if handle > 0
            activeSceneHandles.Add(handle, 1)
            sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
            if sceneFinaleTriggered == None
                sceneFinaleTriggered = new bool[0]
            endif
            sceneFinaleTriggered.Add(false, 1)
            iActiveScenes = activeSceneHandles.Length
            SetPairCooldown(akActorA, akActorB)
            StartSceneTimeoutTimer()
            Log("Scene started at anchor (T1/T2) " + anchorRef + " — handle=" + handle + " furn=" + furnitureTag + " action=" + actionTag)
            return
        endif
    endif

    ; TIER 3-5: Standing scenes (only if furniture not required)
    if !IsRequireFurniture()
        bool eitherSitting = (akActorA.GetSitState() == 3 || akActorB.GetSitState() == 3)
        float dist = akActorA.GetDistance(akActorB as ObjectReference)
        if dist > 250.0
            Log("Standing scene skipped — actors too far apart (" + dist + " units, max 250)")
            return
        endif

        if eitherSitting
            opts.InPlaceMode = OSF.OFF()
        else
            opts.InPlaceMode = OSF.OFF()  ; paired scenes always need alignment — InPlaceMode=ON causes instant abort
        endif

        ; TIER 3: Unanchored specific action — pack partitioning + catch-all for unknown packs
        int matchedTier = 0
        if actionTag != ""
            ; 3a: GE standard (male=role0) — 381 scenes
            if IsPreferSequences()
                string[] t3seq = BuildQueryTagsWithPack(genderTag, actionTag, "ge", "sequence")
                handle = OSF.StartSceneByTags(standardOrder, t3seq, opts)
            endif
            if handle <= 0
                string[] t3 = BuildQueryTagsWithPack(genderTag, actionTag, "ge", "")
                handle = OSF.StartSceneByTags(standardOrder, t3, opts)
            endif
            if handle > 0
                matchedTier = 3
            endif
            ; 3b: SnuSnu femdom (female=role0) — 7 scenes
            if handle <= 0 && genderTag == "mf"
                if IsPreferSequences()
                    string[] t3sseq = BuildQueryTagsWithPack(genderTag, actionTag, "snusnu", "sequence")
                    handle = OSF.StartSceneByTags(femdomOrder, t3sseq, opts)
                endif
                if handle <= 0
                    string[] t3s = BuildQueryTagsWithPack(genderTag, actionTag, "snusnu", "")
                    handle = OSF.StartSceneByTags(femdomOrder, t3s, opts)
                endif
                if handle > 0
                    matchedTier = 3
                    Log("SnuSnu femdom scene — female=role0 (handle=" + handle + ")")
                endif
            endif
            ; 3c: Catch-all for any other animation pack (standard [m,f] convention)
            if handle <= 0
                if IsPreferSequences()
                    string[] t3cseq = BuildQueryTags(genderTag, "", actionTag, "sequence")
                    handle = OSF.StartSceneByTags(standardOrder, t3cseq, opts)
                endif
                if handle <= 0
                    string[] t3c = BuildQueryTags(genderTag, "", actionTag, "")
                    handle = OSF.StartSceneByTags(standardOrder, t3c, opts)
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
                string[] t35seq = BuildQueryTags("ff", "", actionTag, "sequence")
                handle = OSF.StartSceneByTags(actors, t35seq, opts)
            endif
            if handle <= 0
                string[] t35 = BuildQueryTags("ff", "", actionTag, "")
                handle = OSF.StartSceneByTags(actors, t35, opts)
            endif
            if handle > 0
                matchedTier = 35
                Log("FF pair using native FF scene for action='" + actionTag + "'")
            endif
            ; 3.5b: FF fallback to MF GE pool
            if handle <= 0 && IsUseMFForFF()
                if IsPreferSequences()
                    string[] t35geseq = BuildQueryTagsWithPack("mf", actionTag, "ge", "sequence")
                    handle = OSF.StartSceneByTags(actors, t35geseq, opts)
                endif
                if handle <= 0
                    string[] t35ge = BuildQueryTagsWithPack("mf", actionTag, "ge", "")
                    handle = OSF.StartSceneByTags(actors, t35ge, opts)
                endif
                if handle > 0
                    matchedTier = 35
                    Log("FF pair using GE MF pool for action='" + actionTag + "'")
                endif
            endif
            ; 3.5c: FF fallback to MF catch-all (any pack)
            if handle <= 0 && IsUseMFForFF()
                if IsPreferSequences()
                    string[] t35cseq = BuildQueryTags("mf", "", actionTag, "sequence")
                    handle = OSF.StartSceneByTags(actors, t35cseq, opts)
                endif
                if handle <= 0
                    string[] t35c = BuildQueryTags("mf", "", actionTag, "")
                    handle = OSF.StartSceneByTags(actors, t35c, opts)
                endif
                if handle > 0
                    matchedTier = 35
                    Log("FF pair using unknown MF pack for action='" + actionTag + "'")
                endif
            endif
        endif
        ; TIER 4: Standing-specific scenes — GE, SnuSnu, catch-all
        if handle <= 0
            ; 4a: GE standing
            if IsPreferSequences()
                string[] t4seq = BuildQueryTagsWithPack(genderTag, "standing", "ge", "sequence")
                handle = OSF.StartSceneByTags(standardOrder, t4seq, opts)
            endif
            if handle <= 0
                string[] t4 = BuildQueryTagsWithPack(genderTag, "standing", "ge", "")
                handle = OSF.StartSceneByTags(standardOrder, t4, opts)
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
            ; 4c: Catch-all standing (any pack, standard order)
            if handle <= 0
                string[] t4c = BuildQueryTags(genderTag, "", "standing", "")
                handle = OSF.StartSceneByTags(standardOrder, t4c, opts)
                if handle > 0
                    matchedTier = 4
                    Log("Standing scene from unknown pack")
                endif
            endif
        endif
        ; TIER 4.5: FF standing fallback — native FF, then MF GE, then MF catch-all
        if handle <= 0 && genderTag == "ff" && IsUseMFForFF()
            ; 4.5a: Native FF standing
            string[] t45ff = BuildQueryTags("ff", "", "standing", "")
            handle = OSF.StartSceneByTags(actors, t45ff, opts)
            ; 4.5b: MF GE standing
            if handle <= 0
                string[] t45ge = BuildQueryTagsWithPack("mf", "standing", "ge", "")
                handle = OSF.StartSceneByTags(actors, t45ge, opts)
            endif
            ; 4.5c: MF catch-all standing
            if handle <= 0
                string[] t45c = BuildQueryTags("mf", "", "standing", "")
                handle = OSF.StartSceneByTags(actors, t45c, opts)
            endif
            if handle > 0
                matchedTier = 45
                Log("FF pair using MF standing scene")
            endif
        endif
        ; TIER 5: Absolute baseline — GE, SnuSnu, catch-all
        if handle <= 0
            ; 5a: GE baseline
            string[] t5ge = new string[3]
            t5ge[0] = "paired"
            t5ge[1] = genderTag
            t5ge[2] = "ge"
            handle = OSF.StartSceneByTags(standardOrder, t5ge, opts)
            if handle > 0
                matchedTier = 5
            endif
            ; 5b: SnuSnu baseline (female=role0)
            if handle <= 0 && genderTag == "mf"
                string[] t5snu = new string[3]
                t5snu[0] = "paired"
                t5snu[1] = genderTag
                t5snu[2] = "snusnu"
                handle = OSF.StartSceneByTags(femdomOrder, t5snu, opts)
                if handle > 0
                    matchedTier = 5
                    Log("SnuSnu baseline scene — female=role0")
                endif
            endif
            ; 5c: Catch-all baseline (any pack, standard order)
            if handle <= 0
                string[] t5c = new string[2]
                t5c[0] = "paired"
                t5c[1] = genderTag
                handle = OSF.StartSceneByTags(standardOrder, t5c, opts)
                if handle > 0
                    matchedTier = 5
                    Log("Baseline scene from unknown pack")
                endif
            endif
        endif
        ; TIER 5.5: FF baseline fallback — native FF, then MF GE, then MF catch-all
        if handle <= 0 && genderTag == "ff" && IsUseMFForFF()
            ; 5.5a: Native FF paired
            string[] t55ff = new string[2]
            t55ff[0] = "paired"
            t55ff[1] = "ff"
            handle = OSF.StartSceneByTags(actors, t55ff, opts)
            ; 5.5b: MF GE paired
            if handle <= 0
                string[] t55ge = new string[3]
                t55ge[0] = "paired"
                t55ge[1] = "mf"
                t55ge[2] = "ge"
                handle = OSF.StartSceneByTags(actors, t55ge, opts)
            endif
            ; 5.5c: MF catch-all paired
            if handle <= 0
                string[] t55c = new string[2]
                t55c[0] = "paired"
                t55c[1] = "mf"
                handle = OSF.StartSceneByTags(actors, t55c, opts)
            endif
            if handle > 0
                matchedTier = 55
                Log("FF pair using MF baseline scene")
            endif
        endif
        if handle > 0
            activeSceneHandles.Add(handle, 1)
            sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
            if sceneFinaleTriggered == None
                sceneFinaleTriggered = new bool[0]
            endif
            sceneFinaleTriggered.Add(false, 1)
            iActiveScenes = activeSceneHandles.Length
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
    ; IsActorEligible() already checks OSF.IsPlaying(), so the solo actor is guaranteed
    ; not to be a participant in any running scene. No distance check needed — on small
    ; ship interiors all NPCs are within any reasonable proximity threshold of a paired scene.
    EnsureArraysInitialized()

    ; Start solo scene via OSF tag query — full pipeline (stripActors, callbacks, handle)
    Actor[] soloArr = new Actor[1]
    soloArr[0] = soloActor

    ; Select tags by actor sex — female actors get self-pleasure scenes,
    ; male actors get neutral poses only (cover, surrender)
    int actorSex = soloActor.GetLeveledActorBase().GetSex()
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
    soloOpts.InPlaceMode       = OSF.OFF()  ; pin solo actor to starting position (no root motion drift)
    soloOpts.StripMode         = GetStripMode()
    soloOpts.LoopScale         = GetLoopScale()

    int handle = OSF.StartSceneByTags(soloArr, soloTags, soloOpts)
    if handle > 0
        activeSceneHandles.Add(handle, 1)
        sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
            if sceneFinaleTriggered == None
                sceneFinaleTriggered = new bool[0]
            endif
            sceneFinaleTriggered.Add(false, 1)
        iActiveScenes = activeSceneHandles.Length
        SetPairCooldown(soloActor, soloActor)  ; cooldown the actor
        StartSceneTimeoutTimer()
        Log("Solo scene started — handle=" + handle + " actor=" + soloActor)
    else
        Log("Solo scene start failed — no matching solo scene")
    endif
EndFunction

ObjectReference Function FindNearbyFurniture(Actor akActor, float afRadius)
    if kIsSleepFurniture == None
        return None
    endif
    float maxZ = GetMaxZOffset()
    float actorZ = akActor.GetPositionZ()
    ObjectReference[] refs = akActor.FindAllReferencesWithKeyword(kIsSleepFurniture, afRadius)
    int i = 0
    while i < refs.Length
        if refs[i] != None && !refs[i].IsFurnitureInUse()
            ; Z-offset filter — prevent teleporting between ship decks
            if maxZ <= 0.0 || Math.abs(refs[i].GetPositionZ() - actorZ) <= maxZ
                return refs[i]
            endif
        endif
        i += 1
    endwhile
    return None
EndFunction

; ===========================================================================
; Emergency Stop & Audit
; ===========================================================================

Function EmergencyStopAll()
    if activeSceneHandles == None || activeSceneHandles.Length == 0
        return
    endif
    ; Snapshot handles, clear arrays FIRST so OnSceneEvent callback finds nothing to remove
    int[] handlesToStop = activeSceneHandles
    activeSceneHandles = new int[0]
    sceneStartTimes = new float[0]
    sceneFinaleTriggered = new bool[0]
    finaleTriggeredHandles = new int[0]
    iActiveScenes = 0
    CancelTimer(TIMER_ID_SCENE_TIMEOUT)

    int i = 0
    while i < handlesToStop.Length
        if handlesToStop[i] > 0
            Actor[] parts = OSF.GetSceneParticipants(handlesToStop[i])
            int pi = 0
            if parts != None
                while pi < parts.Length
                    Actor p = parts[pi]
                    if p != None
                        OSF.ClearAnchor(p)
                        p.EvaluatePackage()
                        UnequipStuckAttachments(p)
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
    if sceneFinaleTriggered == None
        sceneFinaleTriggered = new bool[0]
    endif
    ; Sync sceneFinaleTriggered to activeSceneHandles — guard against infinite loop
    if sceneFinaleTriggered.Length < activeSceneHandles.Length
        int needed = activeSceneHandles.Length - sceneFinaleTriggered.Length
        sceneFinaleTriggered.Add(false, needed)
    endif
    int i = 0
    while i < activeSceneHandles.Length
        int handle = activeSceneHandles[i]
        if handle <= 0
            ; Stale entry — remove directly (no OSF callback for invalid handles)
            activeSceneHandles.Remove(i)
            if i < sceneStartTimes.Length
                sceneStartTimes.Remove(i)
            endif
            if i < sceneFinaleTriggered.Length
                sceneFinaleTriggered.Remove(i)
            endif
            int fIdx1 = finaleTriggeredHandles.Find(handle)
            if fIdx1 >= 0
                finaleTriggeredHandles.Remove(fIdx1)
            endif
            iActiveScenes = activeSceneHandles.Length
            ; do not increment i — next element shifted into this slot
        else
            Actor[] participants = OSF.GetSceneParticipants(handle)
            if participants.Length == 0
                ; Scene no longer valid — remove directly (no callback will fire)
                float ghostDur = 0.0
                if i < sceneStartTimes.Length
                    ghostDur = Utility.GetCurrentRealTime() - sceneStartTimes[i]
                endif
                Log("Ghost scene removed — handle=" + handle + " duration=" + ghostDur + "s (no participants, no END callback)")
                activeSceneHandles.Remove(i)
                if i < sceneStartTimes.Length
                    sceneStartTimes.Remove(i)
                endif
                if i < sceneFinaleTriggered.Length
                    sceneFinaleTriggered.Remove(i)
                endif
                int fIdx2 = finaleTriggeredHandles.Find(handle)
                if fIdx2 >= 0
                    finaleTriggeredHandles.Remove(fIdx2)
                endif
                iActiveScenes = activeSceneHandles.Length
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
                    ; Try to stop the scene via OSF
                    bool stopped = OSF.StopScene(handle)
                    ; Apply cooldowns so the same pair isn't immediately re-selected
                    Actor[] stopParticipants = OSF.GetSceneParticipants(handle)
                    if stopParticipants.Length > 0
                        float cooldownEnd = Utility.GetCurrentGameTime() + (GetCooldownMinutes() / 1440.0)
                        int pi = 0
                        while pi < stopParticipants.Length
                            Actor p = stopParticipants[pi]
                            if p != None
                                int cIdx = cooldownActors.Find(p)
                                if cIdx >= 0
                                    cooldownEndTimes[cIdx] = cooldownEnd
                                else
                                    cooldownActors.Add(p, 1)
                                    cooldownEndTimes.Add(cooldownEnd, 1)
                                endif
                                OSF.ClearAnchor(p)
                                p.EvaluatePackage()
                                UnequipStuckAttachments(p)
                            endif
                            pi += 1
                        endwhile
                    endif
                    ; Remove from arrays immediately — ghost scenes (stuck handles)
                    ; never fire EVENT_SCENE_END, so waiting for callback creates a permanent deadlock.
                    ; For valid scenes, EVENT_SCENE_END will fire but Find() will return -1 (already removed) — safe.
                    activeSceneHandles.Remove(i)
                    if i < sceneStartTimes.Length
                        sceneStartTimes.Remove(i)
                    endif
                    if i < sceneFinaleTriggered.Length
                        sceneFinaleTriggered.Remove(i)
                    endif
                    int fIdx3 = finaleTriggeredHandles.Find(handle)
                    if fIdx3 >= 0
                        finaleTriggeredHandles.Remove(fIdx3)
                    endif
                    iActiveScenes = activeSceneHandles.Length
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
    if sceneFinaleTriggered == None
        sceneFinaleTriggered = new bool[0]
    endif
    ; Sync sceneFinaleTriggered to activeSceneHandles — guard against infinite loop
    if sceneFinaleTriggered.Length < activeSceneHandles.Length
        int needed = activeSceneHandles.Length - sceneFinaleTriggered.Length
        sceneFinaleTriggered.Add(false, needed)
    endif

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

                ; Apply cooldowns for real participants (ghost scenes return empty array)
                Actor[] participants = OSF.GetSceneParticipants(handle)
                if participants.Length > 0
                    float cooldownEnd = Utility.GetCurrentGameTime() + (GetCooldownMinutes() / 1440.0)
                    int pi = 0
                    while pi < participants.Length
                        Actor p = participants[pi]
                        if p != None
                            int cIdx = cooldownActors.Find(p)
                            if cIdx >= 0
                                cooldownEndTimes[cIdx] = cooldownEnd
                            else
                                cooldownActors.Add(p, 1)
                                cooldownEndTimes.Add(cooldownEnd, 1)
                            endif
                            OSF.ClearAnchor(p)
                            p.EvaluatePackage()
                            UnequipStuckAttachments(p)
                        endif
                        pi += 1
                    endwhile
                endif

                ; Stop scene and remove from tracking immediately (ghost scenes never fire END callback)
                OSF.StopScene(handle)
                activeSceneHandles.Remove(i)
                sceneStartTimes.Remove(i)
                if i < sceneFinaleTriggered.Length
                    sceneFinaleTriggered.Remove(i)
                endif
                int fIdx4 = finaleTriggeredHandles.Find(handle)
                if fIdx4 >= 0
                    finaleTriggeredHandles.Remove(fIdx4)
                endif
                iActiveScenes = activeSceneHandles.Length
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
; MCM Settings Readers (OSF UI — cheap, thread-safe, call per use)
; ===========================================================================

bool Function IsEnabled()
    return OSFUI.GetBool(MOD_ID, "bEnabled", true)
EndFunction

bool Function IsLocationAllowed()
    if !IsEnabled()
        return false
    endif
    string mode = GetLocationMode()
    if mode == "everywhere"
        return true
    endif
    if bIsOnShip
        return true
    endif
    if mode == "interiors"
        Cell c = Game.GetPlayer().GetParentCell()
        return (c != None && c.IsInterior())
    endif
    ; mode == "ship" — only ship
    return false
EndFunction

string Function GetLocationMode()
    return OSFUI.GetString(MOD_ID, "sLocationMode", "ship")
EndFunction

bool Function IsCompanionsOnly()
    return OSFUI.GetBool(MOD_ID, "bCompanionsOnly", false)
EndFunction

bool Function IsIncludeOutpostNPC()
    return OSFUI.GetBool(MOD_ID, "bIncludeOutpostNPC", false)
EndFunction

bool Function IsRequireFurniture()
    return OSFUI.GetBool(MOD_ID, "bRequireFurniture", true)
EndFunction

int Function GetMaxConcurrent()
    return OSFUI.GetInt(MOD_ID, "iMaxConcurrentScenes", 1)
EndFunction

float Function GetCheckInterval()
    return 45.0
EndFunction

int Function GetChancePercent()
    return OSFUI.GetInt(MOD_ID, "iChancePercent", 25)
EndFunction

float Function GetCooldownMinutes()
    return OSFUI.GetFloat(MOD_ID, "fActorCooldownMinutes", 10.0)
EndFunction

int Function GetStripMode()
    ; OSF UI stores enum settings as strings — use GetString and cast to int
    return OSFUI.GetString(MOD_ID, "iStripMode", "-1") as int
EndFunction

float Function GetLoopScale()
    return OSFUI.GetFloat(MOD_ID, "fLoopScale", 1.0)
EndFunction

float Function GetSceneTimeoutMinutes()
    return 3.0
EndFunction

bool Function IsAdvanceStages()
    return true
EndFunction

float Function GetMaxZOffset()
    return 200.0
EndFunction

float Function GetMaxPairDistance()
    return 400.0
EndFunction

float Function GetPairCooldownMinutes()
    return 30.0
EndFunction

bool Function IsTagRotation()
    return true
EndFunction

bool Function IsPreferSequences()
    return true
EndFunction

bool Function IsAllowForeplay()
    return OSFUI.GetBool(MOD_ID, "bAllowForeplay", true)
EndFunction

bool Function IsAllowClassic()
    return OSFUI.GetBool(MOD_ID, "bAllowClassic", true)
EndFunction

bool Function IsAllowIntense()
    return OSFUI.GetBool(MOD_ID, "bAllowIntense", true)
EndFunction

; --- Romance Exclusivity ---
bool Function IsRomanceExclusivity()
    return OSFUI.GetBool(MOD_ID, "bRomanceExclusivity", true)
EndFunction

bool Function IsPolyamoryBypass()
    return false
EndFunction

; --- Max Distance Guard ---
float Function GetMaxStartDistance()
    return 2000.0
EndFunction

float Function GetMinSceneSpacing()
    return OSFUI.GetFloat(MOD_ID, "fMinSceneSpacing", 500.0)
EndFunction

bool Function IsUseMFForFF()
    return OSFUI.GetBool(MOD_ID, "bUseMFForFF", true)
EndFunction

bool Function IsStopOnPlayerWalkIn()
    return OSFUI.GetBool(MOD_ID, "bStopOnPlayerWalkIn", false)
EndFunction

float Function GetWalkInDistance()
    return 150.0
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
    return OSFUI.GetBool(MOD_ID, "bSoloDowntime", true)
EndFunction

bool Function IsSoloPrivateOnly()
    return true
EndFunction

float Function GetSoloChance()
    return OSFUI.GetFloat(MOD_ID, "fSoloChance", 20.0)
EndFunction

string Function GetSpeedMode()
    return OSFUI.GetString(MOD_ID, "sSpeedMode", "static")
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
    if pool.Length == 0
        return ""
    endif
    String tag = pool[iTagRotationIndex % pool.Length]
    iTagRotationIndex = (iTagRotationIndex + 1) % 1000  ; monotonic — avoids phase skipping between MF/FF pools
    return tag
EndFunction

String[] Function GetActiveActionPool(String asGenderTag)
    String[] pool = new String[16]
    int count = 0

    if asGenderTag == "ff"
        if IsAllowForeplay()
            pool[count] = "kissing"     ; count += 1
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

String[] Function BuildQueryTags(String asGenderTag, String asFurnitureTag, String asActionTag, String asExtraTag)
    string[] temp = new string[5]
    int count = 0
    temp[count] = "paired"   ; count += 1
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
    string[] result = new string[count]
    int i = 0
    while i < count
        result[i] = temp[i]
        i += 1
    endwhile
    return result
EndFunction

; Build query tags with pack discriminator ('ge' or 'snusnu') for role-safe MF partitioning
String[] Function BuildQueryTagsWithPack(String asGenderTag, String asActionTag, String asPackTag, String asExtraTag)
    string[] temp = new string[6]
    int count = 0
    temp[count] = "paired"
    count += 1
    temp[count] = asGenderTag
    count += 1
    temp[count] = asPackTag
    count += 1
    if asActionTag != ""
        temp[count] = asActionTag
        count += 1
    endif
    if asExtraTag != ""
        temp[count] = asExtraTag
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
