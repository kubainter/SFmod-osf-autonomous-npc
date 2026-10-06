ScriptName OSF_AutonomousManagerScript Extends Quest

int Property TIMER_ID_SCAN = 1 Auto Const

int Property TIMER_ID_SCENE_TIMEOUT = 2 Auto Const

int Property TIMER_ID_SETTINGS_RETRY = 3 Auto Const

String Property MOD_ID = "osf.autonomous" Auto Const

String Property LOG_NAME = "OSF_Autonomous" Auto Const

Function Log(String asMessage, int aiSeverity = 0)
    Debug.OpenUserLog(LOG_NAME)
    Debug.TraceUser(LOG_NAME, asMessage, aiSeverity)
EndFunction

int[] activeSceneHandles
float[] sceneStartTimes
int[] finaleTriggeredHandles
Actor[] sceneActorA             ; tracked participants (parallel to activeSceneHandles) — for ghost scene cleanup
Actor[] sceneActorB
Actor[] cooldownActors
float[] cooldownEndTimes
String[] pairCooldownKeys
float[] pairCooldownEndTimes
int iTagRotationIndex = 0

int Property MANAGER_QUEST_FORMID = 0x01000801 Auto Const

OSF_AutonomousManagerScript managerQuestCache = None
bool managerQuestLookedUp = false

int Property CURRENT_VERSION = 4 AutoReadOnly
int Property iInstalledVersion = 0 Auto
int iSceneCallbackToken = 0
bool bIsOnShip = false
bool bSettingsWarned = false
bool bDependencyNotified = false
int iSettingsRetryCount = 0

Keyword kActorTypeRobot
Keyword kIsSleepFurniture
Keyword kCrewCompanion
Keyword kCrewGeneric
Keyword kCrewElite
Keyword kActorTypeHuman
Keyword kActorTypeChild
Race kHumanCrowdRace
Race kMannequinRace
Faction kCurrentCompanionFaction
Faction kCurrentCrewFaction
Keyword kLocTypePlayerOutpost
Keyword kLocTypePlayerHouse

Keyword kAnimFurnChair
Keyword kAnimFurnBench
; Removed (SF-TIK-007): AnimFurnSitTable / AnimFurnStool / AnimFurnBarStool /

Keyword kPlanetAtmoO2
Keyword kPlanetAtmoHighO2
Keyword kPlanetAtmoLowO2
ActorValue kAvHideHelmetBreathable ; ActorShouldHideSpacesuitHelmetCosmeticBreathable_AV — engine's own "breathable zone" signal

Form kDickGear
Form kDickFlaccidGear
Form kDickErectGear
Form kDickErect2Gear
Form kHatersGear

Event OnQuestInit()
    InitKeywords()
    InitGearForms()

    EnsureArraysInitialized()
    iInstalledVersion = CURRENT_VERSION

    Actor player = Game.GetPlayer()
    RegisterForRemoteEvent(player, "OnPlayerLoadGame")
    RegisterForRemoteEvent(player, "OnLocationChange")
    RegisterForRemoteEvent(player, "OnCombatStateChanged")
    RegisterForRemoteEvent(player, "OnEnterShipInterior")
    RegisterForRemoteEvent(player, "OnExitShipInterior")
    RegisterForRemoteEvent(player, "OnSit")

    RegisterForMenuOpenCloseEvent("PauseMenu")

    SpaceshipReference ship = player.GetCurrentShipRef()
    if ship != None
        RegisterForRemoteEvent(ship, "OnShipGravJump")
        RegisterForRemoteEvent(ship, "OnShipTakeOff")
        RegisterForRemoteEvent(ship, "OnShipDock")
        RegisterForRemoteEvent(ship, "OnShipLanding")
    endif

    RegisterOSFCallbacks()

    RegisterSettingsListener()

    bIsOnShip = IsPlayerInOwnShip()

    ResumeScanTimer()
    if IsEnabled()
        Log("OnQuestInit — scan timer started (" + GetCheckInterval() + "s)")
    else
        Log("OnQuestInit — mod disabled (or OSFSettings unavailable), scan timer idle")
    endif

    Log("OnQuestInit — robotKW=" + kActorTypeRobot + " sleepKW=" + kIsSleepFurniture + " humanKW=" + kActorTypeHuman + " childKW=" + kActorTypeChild + " onShip=" + bIsOnShip)
EndEvent

Function InitKeywords()
    if kActorTypeRobot == None
        kActorTypeRobot    = Game.GetFormFromFile(0x002702C9, "Starfield.esm") as Keyword
    endif
    if kIsSleepFurniture == None
        kIsSleepFurniture  = Game.GetFormFromFile(0x00021B18, "Starfield.esm") as Keyword
    endif
    if kCrewCompanion == None
        kCrewCompanion     = Game.GetFormFromFile(0x002705E4, "Starfield.esm") as Keyword
    endif
    if kCrewGeneric == None
        kCrewGeneric       = Game.GetFormFromFile(0x00270728, "Starfield.esm") as Keyword
    endif
    if kCrewElite == None
        kCrewElite         = Game.GetFormFromFile(0x00270729, "Starfield.esm") as Keyword
    endif
    if kActorTypeHuman == None
        kActorTypeHuman    = Game.GetFormFromFile(0x0025E194, "Starfield.esm") as Keyword
    endif
    if kActorTypeChild == None
        kActorTypeChild    = Game.GetFormFromFile(0x001157E8, "Starfield.esm") as Keyword
    endif
    if kHumanCrowdRace == None
        kHumanCrowdRace    = Game.GetFormFromFile(0x002BBC09, "Starfield.esm") as Race
    endif
    if kMannequinRace == None
        kMannequinRace     = Game.GetFormFromFile(0x001EE4DA, "Starfield.esm") as Race
    endif
    if kCurrentCompanionFaction == None
        kCurrentCompanionFaction = Game.GetFormFromFile(0x00023C01, "Starfield.esm") as Faction
    endif
    if kCurrentCrewFaction == None
        kCurrentCrewFaction = Game.GetFormFromFile(0x00014312, "Starfield.esm") as Faction
    endif
    if kLocTypePlayerOutpost == None
        kLocTypePlayerOutpost = Game.GetFormFromFile(0x000234F1, "Starfield.esm") as Keyword
    endif
    if kLocTypePlayerHouse == None
        kLocTypePlayerHouse = Game.GetFormFromFile(0x002EF272, "Starfield.esm") as Keyword
    endif
    if kAnimFurnChair == None
        kAnimFurnChair    = Game.GetFormFromFile(0x00021BF1, "Starfield.esm") as Keyword
    endif
    if kAnimFurnBench == None
        kAnimFurnBench    = Game.GetFormFromFile(0x003A2DF2, "Starfield.esm") as Keyword
    endif
    if kPlanetAtmoO2 == None
        kPlanetAtmoO2     = Game.GetFormFromFile(0x00295EA4, "Starfield.esm") as Keyword
    endif
    if kPlanetAtmoHighO2 == None
        kPlanetAtmoHighO2 = Game.GetFormFromFile(0x00295EA3, "Starfield.esm") as Keyword
    endif
    if kPlanetAtmoLowO2 == None
        kPlanetAtmoLowO2 = Game.GetFormFromFile(0x00295EA2, "Starfield.esm") as Keyword
    endif
    if kAvHideHelmetBreathable == None
        kAvHideHelmetBreathable = Game.GetFormFromFile(0x000B120B, "Starfield.esm") as ActorValue
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
    if Game.IsPluginInstalled("Dick.esm")
        if kDickGear == None
            kDickGear = Game.GetFormFromFile(0x00000800, "Dick.esm")
        endif
        if kDickFlaccidGear == None
            kDickFlaccidGear = Game.GetFormFromFile(0x0000081B, "Dick.esm")
        endif
        if kDickErectGear == None
            kDickErectGear = Game.GetFormFromFile(0x0000081D, "Dick.esm")
        endif
        if kDickErect2Gear == None
            kDickErect2Gear = Game.GetFormFromFile(0x00000820, "Dick.esm")
        endif
    endif
    if Game.IsPluginInstalled("Haters Body.esm")
        if kHatersGear == None
            kHatersGear = Game.GetFormFromFile(0x00000804, "Haters Body.esm")
        endif
    endif

    if kDickErectGear == None && kHatersGear == None
        OSFSettings.ReportIssue(MOD_ID, "gear", "No strap-on/erection gear plugins found", false, "Paired scenes play without auto-equipped gear (FF pairs get no strap-on)", "Install Dick.esm / Haters Body.esm, or edit 'equip' strings in Data/OSF/*.osf.json to point at gear you have")
    else
        OSFSettings.ClearIssue(MOD_ID, "gear")
    endif
EndFunction

Function UnequipStuckAttachments(Actor akActor)
    if akActor == None || akActor == Game.GetPlayer()
        return
    endif
    RemoveStuckGear(akActor, kDickGear)
    RemoveStuckGear(akActor, kDickErectGear)
    RemoveStuckGear(akActor, kDickErect2Gear)
    RemoveStuckGear(akActor, kHatersGear)
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

Function RegisterOSFCallbacks()
    if !OSF.IsReady()
        Log("RegisterOSFCallbacks — OSF not ready, skipping")
        return
    endif
    if iSceneCallbackToken
        OSF.UnregisterSceneCallback(iSceneCallbackToken)
        iSceneCallbackToken = 0
    endif
    int eventMask = OSF.EVENT_SCENE_BEGIN() + OSF.EVENT_SCENE_END() + OSF.EVENT_CUE() + OSF.EVENT_NODE_EXIT()
    iSceneCallbackToken = OSF.RegisterSceneCallback(self, "OnSceneEvent", 0, eventMask)
    if iSceneCallbackToken == 0
        Log("WARNING: RegisterSceneCallback failed — scene events will not fire")
    endif
EndFunction

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
    if !bSettingsWarned
        Log("WARNING: OSFSettings.RegisterForChanges failed — retrying")
        bSettingsWarned = true
    endif
    iSettingsRetryCount += 1
    if iSettingsRetryCount <= 3
        StartTimer(5.0, TIMER_ID_SETTINGS_RETRY)
        return
    endif
    String reason = "OSF Settings plugin unavailable — install OSF Settings (ships with OSF UI 2.0+)"
    int uiVersion = OSFUI.GetVersion()
    if uiVersion > 0 && uiVersion < 20000
        reason = "OSF UI " + OSFUI.GetVersionString() + " too old — OSF UI 2.0+ required"
    endif
    NotifyDependencyProblem(reason)
EndFunction

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
; remote events serialized in the save, but every engine-facing call on it
;    a ghost has no bound game object. Needs no FormID or plugin name, so a
;    would ghost the foreign instance). When it doesn't resolve — variant
bool Function IsBoundInstance()
    if !IsBoundGameObjectAvailable()
        return false  ; save-carried ghost — detached from any game object
    endif
    if !managerQuestLookedUp
        managerQuestLookedUp = true
        managerQuestCache = Game.GetFormFromFile(MANAGER_QUEST_FORMID, "OSFAutonomous.esm") as OSF_AutonomousManagerScript
    endif
    if managerQuestCache == None
        return true
    endif
    return managerQuestCache == self
EndFunction

Function OnSceneEvent(OSFTypes:SceneEvent akEvent)
    if !IsBoundInstance()
        return
    endif
    if akEvent == None
        return
    endif

    if akEvent.eventType == OSF.EVENT_SCENE_BEGIN()
        if activeSceneHandles.Find(akEvent.sceneHandle) < 0
            return
        endif
        Log("Scene BEGIN — handle=" + akEvent.sceneHandle)

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
        if IsAdvanceStages()
            int handle = akEvent.sceneHandle
            if handle > 0 && activeSceneHandles.Find(handle) >= 0
                int edgeCount = OSF.GetSceneEdgeCount(handle)
                if edgeCount > 0
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
                        advanced = OSF.AdvanceScene(handle)
                        if advanced
                            Log("Scene advanced — handle=" + handle + " edges=" + edgeCount)
                        else
                            Log("Scene advance failed — handle=" + handle + " (scene may be ending)")
                        endif
                    endif

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

        SyncSceneTracking()
        int idx = activeSceneHandles.Find(handle)
        if idx < 0
            return
        endif

        if finaleTriggeredHandles == None
            finaleTriggeredHandles = new int[0]
        endif

        ; Capture tracked actors BEFORE removal — abort/ghost END events can
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
                Log("Scene " + handle + " duration unknown — stale start time (" + duration + "s)")
            elseif duration < 5.0
                Log("WARNING: Scene " + handle + " ended abnormally fast (" + duration + "s) — likely InPlace alignment or collision failure")
            elseif duration < 30.0
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
        int fIdx = finaleTriggeredHandles.Find(handle)
        if fIdx >= 0
            finaleTriggeredHandles.Remove(fIdx)
        endif
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
        if akEvent.cue == "orgasm"
            Log("Cue: orgasm (scene=" + akEvent.sceneHandle + ")")
        endif
    endif
EndFunction

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
        EmergencyStopAll()
        ResumeScanTimer()
        Log("Location denied after settings change — scenes stopped, scan idles")
        return
    endif
    ResumeScanTimer()
    if asKey == "bEnabled"
        Log("Mod re-enabled via OSF Settings")
    elseif asKey == "sLocationMode"
        Log("Location mode changed — scanning active")
    endif
EndFunction

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
    ; a healthy scene, while ghost scenes are reaped by AuditActiveScenes via
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
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif

    ; clearing sceneActorA/B would orphan ghost cleanup: AuditActiveScenes
    if iInstalledVersion < CURRENT_VERSION
        Log("Script updated from v" + iInstalledVersion + " to v" + CURRENT_VERSION)
        iInstalledVersion = CURRENT_VERSION
    endif

    iSettingsRetryCount = 0
    bSettingsWarned = false
    bDependencyNotified = false

    EnsureArraysInitialized()
    SyncSceneTracking()

    RegisterOSFCallbacks()

    InitKeywords()
    InitGearForms()

    RegisterForRemoteEvent(Game.GetPlayer(), "OnSit")

    RegisterForMenuOpenCloseEvent("PauseMenu")

    RegisterSettingsListener()

    ; player's own ship (SF-TIK-008).
    SpaceshipReference ship = Game.GetPlayer().GetCurrentShipRef()
    bIsOnShip = IsPlayerInOwnShip()
    if ship != None
        RegisterForRemoteEvent(ship, "OnShipGravJump")
        RegisterForRemoteEvent(ship, "OnShipTakeOff")
        RegisterForRemoteEvent(ship, "OnShipDock")
        RegisterForRemoteEvent(ship, "OnShipLanding")
    endif
    ResumeScanTimer()
    IsLocationAllowed()

    EnforceSceneTimeouts()
    AuditActiveScenes()

    Log("OnPlayerLoadGame — callbacks re-registered, active scenes=" + activeSceneHandles.Length)
EndEvent

Event Actor.OnLocationChange(Actor akSender, Location akOldLoc, Location akNewLoc)
    if !IsBoundInstance()
        return
    endif
    if akSender != Game.GetPlayer()
        return
    endif

    ; is fragile. Cell-derived check is self-healing (SF-TIK-008).
    bIsOnShip = IsPlayerInOwnShip()

    Cell playerCell = Game.GetPlayer().GetParentCell()
    bool isInExterior = (playerCell == None || !playerCell.IsInterior())

    if IsLocationAllowed()
        if isInExterior && !IsInPrivatePlayerLocation()
            EmergencyStopAll()
            Log("Location change — exterior, old scenes cleared")
        else
            ; wrongly stopped; the per-tick audit purges real ghosts anyway.
            Log("Location change — allowed interior, scanning continues")
        endif
    else
        EmergencyStopAll()
        Log("Location change — location not allowed, scenes stopped, scan idles")
    endif
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
    ; vessels — only flag when entering the player's own ship (SF-TIK-008).
    ; engine's player-ship registry.
    SpaceshipReference enteredShip = akShip as SpaceshipReference
    bIsOnShip = (enteredShip != None && Game.IsPlayerSpaceshipOwner(enteredShip))
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
    ; ownership must be checked against the engine registry (SF-TIK-008).
    SpaceshipReference exitedShip = akShip as SpaceshipReference
    if exitedShip != None && !Game.IsPlayerSpaceshipOwner(exitedShip)
        return
    endif
    bIsOnShip = IsPlayerInOwnShip()
    string mode = GetLocationMode()

    Cell playerCell = Game.GetPlayer().GetParentCell()
    bool isInExterior = (playerCell == None || !playerCell.IsInterior())

    if mode == "ship"
        EmergencyStopAll()
        Log("OnExitShipInterior — mode=ship, scenes cleared, scan idles")
    elseif isInExterior
        ; Stop all scenes regardless of mode to prevent ghost scenes
        EmergencyStopAll()
        Log("OnExitShipInterior — exterior exit, ship scenes cleared")
    else
        ; mid-load and would be wrongly stopped); per-tick audit purges ghosts.
        if !IsLocationAllowed()
            EmergencyStopAll()
            Log("OnExitShipInterior — interior transition, location not allowed, scenes cleared")
        else
            Log("OnExitShipInterior — interior transition, scenes kept")
        endif
    endif
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
        EmergencyStopAll()
        Log("Player entered combat — all scenes stopped")
    elseif aeCombatState == 0
        ResumeScanTimer()
        Log("Player combat ended — scanning resumed")
    endif
EndEvent

Event SpaceshipReference.OnShipGravJump(SpaceshipReference akSender, Location aDestination, int aState)
    if !IsBoundInstance()
        return
    endif
    if Game.GetPlayer().GetCurrentShipRef() != akSender
        return
    endif
    if aState == 0
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

Event OnTimer(int aiTimerID)
    if !IsBoundInstance()
        return
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

    Actor player = Game.GetPlayer()
    if player != None
        bIsOnShip = IsPlayerInOwnShip()

        if player.GetSpaceship() != None
            Log("OnTimer — player is piloting ship, rescheduling")
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        if player.GetCombatState() != 0
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        if !IsLocationAllowed()
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        Cell playerCell = player.GetParentCell()
        if bIsOnShip && (playerCell == None || !playerCell.IsInterior())
            Log("OnTimer — ship in space exterior, rescheduling")
            StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
            return
        endif

        SpaceshipReference currentShip = player.GetCurrentShipRef()
        if currentShip != None
            if currentShip.IsInCombat()
                Log("OnTimer — ship in combat, rescheduling")
                StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
                return
            endif
        endif
    endif

    CleanExpiredCooldowns()

    AuditActiveScenes()

    EnforceSceneTimeouts()

    if activeSceneHandles.Length >= GetMaxConcurrent()
        Log("OnTimer — max concurrent scenes reached (" + activeSceneHandles.Length + "/" + GetMaxConcurrent() + "), rescheduling")
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    Actor[] candidates = new Actor[0]
    int companionCount = 0
    int genericCount = 0
    int eliteCount = 0
    int followerCount = 0
    int outpostCount = 0

    float scanRange = GetMaxStartDistance() + 200.0

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

    Actor[] followers = Game.GetPlayerFollowers()
    int j = 0
    while j < followers.Length
        if followers[j] != None && candidates.Find(followers[j]) < 0
            candidates.Add(followers[j], 1)
            followerCount += 1
        endif
        j += 1
    endwhile

    if IsIncludeOutpostNPC() && kActorTypeHuman != None
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

    if candidates.Length == 0
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

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

    if eligible.Length < 2
        if eligible.Length == 1 && IsSoloDowntime()
            TryStartSoloScene(eligible)
        endif
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
        return
    endif

    Actor[] usedThisTick = new Actor[0]
    int startedThisTick = 0
    bool waveDone = false
    while !waveDone && activeSceneHandles.Length < GetMaxConcurrent() && (eligible.Length - usedThisTick.Length) >= 2
        int roll = Utility.RandomInt(1, 100)
        if roll > GetChancePercent()
            Log("OnTimer — scene wave ended: chance roll failed (" + roll + " > " + GetChancePercent() + ")")
            waveDone = true
        else
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
                    float dist = aA.GetDistance(aB as ObjectReference)
                    float zDiff = Math.abs(aA.GetPositionZ() - aB.GetPositionZ())
                    if dist <= GetMaxPairDistance() && (maxZ <= 0.0 || zDiff <= maxZ)
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
                usedThisTick.Add(eligible[idxA], 1)
                usedThisTick.Add(eligible[idxB], 1)
                if activeSceneHandles.Length > scenesBefore
                    startedThisTick += 1
                else
                    Log("Scene wave — pair failed all scene queries, trying others")
                endif
            endif
        endif
    endwhile

    if startedThisTick > 1
        Log("OnTimer — scene wave started " + startedThisTick + " scenes")
    endif

    StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
EndEvent

bool Function IsActorEligible(Actor akActor)
    if akActor == None
        return false
    endif

    string actorName = "0x" + akActor.GetFormID()

    if akActor == Game.GetPlayer()
        Log("Rejected " + actorName + " — player")
        return false
    endif

    if akActor.IsChild()
        Log("Rejected " + actorName + " — is child")
        return false
    endif

    if !akActor.Is3DLoaded() || akActor.IsDisabled()
        Log("Rejected " + actorName + " — not 3D loaded or disabled")
        return false
    endif

    if akActor.IsHostileToActor(Game.GetPlayer())
        Log("Rejected " + actorName + " — hostile to player")
        return false
    endif

    if akActor.IsDead()
        Log("Rejected " + actorName + " — dead")
        return false
    endif

    if akActor.IsInCombat()
        Log("Rejected " + actorName + " — in combat")
        return false
    endif

    if OSF.IsPlaying(akActor)
        Log("Rejected " + actorName + " — already in OSF scene")
        return false
    endif

    if akActor.IsInDialogueWithPlayer()
        Log("Rejected " + actorName + " — in dialogue with player")
        return false
    endif

    int sitState = akActor.GetSitState()
    if sitState != 0
        Log("Rejected " + actorName + " — sitting or transitioning (sitState=" + sitState + ")")
        return false
    endif

    int sleepState = akActor.GetSleepState()
    if sleepState != 0
        Log("Rejected " + actorName + " — sleeping (sleepState=" + sleepState + ")")
        return false
    endif

    if akActor.IsRunning()
        Log("Rejected " + actorName + " — running (moving)")
        return false
    endif

    if akActor.IsSneaking()
        Log("Rejected " + actorName + " — sneaking")
        return false
    endif

    if akActor.IsTalking()
        Log("Rejected " + actorName + " — talking")
        return false
    endif

    if akActor.IsBleedingOut() || akActor.IsUnconscious() || akActor.IsArrested()
        Log("Rejected " + actorName + " — bleeding/unconscious/arrested")
        return false
    endif

    Race actorRace = akActor.GetRace()

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

    if kActorTypeChild != None && akActor.HasKeyword(kActorTypeChild)
        Log("Rejected " + actorName + " — child keyword")
        return false
    endif

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

    if IsCompanionsOnly()
        if kCrewCompanion == None || !akActor.HasKeyword(kCrewCompanion)
            Log("Rejected " + actorName + " — not a companion (companionsOnly mode)")
            return false
        endif
    endif

    int relRank = akActor.GetRelationshipRank(Game.GetPlayer())

    ; human scan (SF-TIK-008).
    bool hasCrewKeyword = (kCrewCompanion != None && akActor.HasKeyword(kCrewCompanion)) || (kCrewGeneric != None && akActor.HasKeyword(kCrewGeneric)) || (kCrewElite != None && akActor.HasKeyword(kCrewElite))
    if !hasCrewKeyword && !akActor.IsPlayerTeammate() && !(kCurrentCrewFaction != None && akActor.IsInFaction(kCurrentCrewFaction))
        if !IsInPrivatePlayerLocation()
            Log("Rejected " + actorName + " — non-crew NPC outside private player location")
            return false
        endif
    endif

    if kCrewCompanion != None && akActor.HasKeyword(kCrewCompanion)
        bool inCrewFaction = (kCurrentCrewFaction != None && akActor.IsInFaction(kCurrentCrewFaction))
        bool isTeammate = akActor.IsPlayerTeammate()
        if !(inCrewFaction || isTeammate || relRank >= 1)
            Log("Rejected " + actorName + " — companion crew keyword but not recruited/teammate (inCrewFaction=" + inCrewFaction + " relRank=" + relRank + ")")
            return false
        endif
    endif
    if (kCrewGeneric != None && akActor.HasKeyword(kCrewGeneric)) || (kCrewElite != None && akActor.HasKeyword(kCrewElite))
        bool inCrewFaction = (kCurrentCrewFaction != None && akActor.IsInFaction(kCurrentCrewFaction))
        bool isTeammate = akActor.IsPlayerTeammate()
        if !(inCrewFaction || isTeammate || relRank >= 1)
            Log("Rejected " + actorName + " — generic/elite crew but not recruited (inCrewFaction=" + inCrewFaction + " relRank=" + relRank + ")")
            return false
        endif
    endif

    if IsRomanceExclusivity() && !IsPolyamoryBypass()
        if relRank >= 3
            Log("Rejected " + actorName + " — romanced companion (exclusivity guard)")
            return false
        endif
    endif

    if IsOnCooldown(akActor)
        Log("Rejected " + actorName + " — on cooldown")
        return false
    endif

    return true
EndFunction

Function TryStartScene(Actor akActorA, Actor akActorB)
    if akActorA == None || akActorB == None
        return
    endif
    if akActorA == akActorB
        return
    endif

    if OSF.IsPlaying(akActorA) || OSF.IsPlaying(akActorB)
        Log("Scene skipped — actor already in a scene (claimed since eligibility check)")
        return
    endif

    float maxDist = GetMaxStartDistance()
    Actor player = Game.GetPlayer()
    float distA = akActorA.GetDistance(player as ObjectReference)
    float distB = akActorB.GetDistance(player as ObjectReference)
    if distA > maxDist || distB > maxDist
        Log("Scene skipped — actor too far from player (" + maxDist + " units)")
        return
    endif

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
        Log("Scene skipped — male/male pair not supported")
        return
    else
        Log("Scene skipped — undefined sex for actor (sexA=" + sexA + " sexB=" + sexB + ")")
        return
    endif

    Actor[] standardOrder = new Actor[2]
    Actor[] femdomOrder   = new Actor[2]
    Actor[] actors        = new Actor[2]
    if genderTag == "mf"
        if sexA == 0
            standardOrder[0] = akActorA
            standardOrder[1] = akActorB
            femdomOrder[0]   = akActorB
            femdomOrder[1]   = akActorA
        else
            standardOrder[0] = akActorB
            standardOrder[1] = akActorA
            femdomOrder[0]   = akActorA
            femdomOrder[1]   = akActorB
        endif
        actors = standardOrder
    else
        actors[0] = akActorA
        actors[1] = akActorB
    endif

    string actionTag = ""
    if IsTagRotation()
        actionTag = GetNextActionTag(genderTag)
    endif

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
            anchorRef = furnitureCandidates[0]
            Log("  Nearest furniture: " + anchorRef + " base=" + anchorRef.GetBaseObject())
        else
            Log("  No nearby furniture found — will try standing scenes")
        endif
    endif

    string furnitureTag = GetOSFFurnitureTag(anchorRef)

    OSFTypes:SceneOptions opts = new OSFTypes:SceneOptions
    opts.LockPlayerMode    = OSF.OFF()
    opts.PlayerControlMode = OSF.OFF()
    opts.Camera            = "none"
    opts.FadeMode          = OSF.OFF()
    opts.LoopScale         = GetLoopScale()

    opts.StripMode     = GetStripMode()

    int handle = 0

    if furnitureCandidates.Length > 0 || anchorRef != None
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

        bool anchorIsParticipantFurniture = (anchorRef != None && ((sitA == 3 && akActorA.GetFurnitureUsing() == anchorRef) || (sitB == 3 && akActorB.GetFurnitureUsing() == anchorRef)))
        opts.InPlaceMode = OSF.OFF()
        int ci = 0
        while ci < allCandidates.Length && handle <= 0
            ObjectReference candidate = allCandidates[ci]
            if candidate != None
                if OSF.IsPlaying(akActorA) || OSF.IsPlaying(akActorB)
                    Log("  -> aborting candidates: actor claimed by another scene")
                    return
                endif
                Log("Trying anchor candidate " + ci + "/" + allCandidates.Length + ": " + candidate + " base=" + candidate.GetBaseObject() + " baseID=0x" + (candidate.GetBaseObject() as Form).GetFormID())

                bool candidateFree = !candidate.IsFurnitureInUse() || (anchorIsParticipantFurniture && candidate == anchorRef)
                if !candidateFree
                    Log("  -> skipped: furniture occupied or reserved by another actor")
                endif

                if actionTag == "kissing"
                    opts.StripMode = OSF.OFF()
                endif
                string[] genderVariants = new string[2]
                genderVariants[0] = genderTag
                if genderTag == "ff"
                    genderVariants[1] = "mf"
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

        opts.InPlaceMode = OSF.OFF()

        if actionTag == "kissing"
            opts.StripMode = OSF.OFF()
        endif

        ; (SF-TIK-007).
        int matchedTier = 0
        if actionTag != ""
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
        if handle <= 0 && genderTag == "ff" && actionTag != ""
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
        ; "floor"), furniture packs expose "*.standing" variants (SF-TIK-007).
        if handle <= 0
            opts.StripMode = GetStripMode()
            if IsPreferSequences()
                string[] t4seq = BuildQueryTagsWithPack(genderTag, "standing", "ge", "sequence")
                handle = OSF.StartSceneByTags(standardOrder, t4seq, opts)
            endif
            if handle <= 0
                string[] t4 = BuildQueryTagsWithPack(genderTag, "standing", "ge", "")
                handle = OSF.StartSceneByTags(standardOrder, t4, opts)
            endif
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
            if handle <= 0 && genderTag == "mf"
                string[] t4s = BuildQueryTagsWithPack(genderTag, "standing", "snusnu", "")
                handle = OSF.StartSceneByTags(femdomOrder, t4s, opts)
                if handle > 0
                    matchedTier = 4
                    Log("SnuSnu standing scene — female=role0")
                endif
            endif
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
        if handle <= 0 && genderTag == "ff" && IsUseMFForFF()
            string[] t45ff = BuildQueryTags("ff", "", "standing", "")
            handle = OSF.StartSceneByTags(actors, t45ff, opts)
            if handle <= 0
                string[] t45fff = BuildQueryTags("ff", "", "floor", "")
                handle = OSF.StartSceneByTags(actors, t45fff, opts)
            endif
            if handle <= 0
                string[] t45ge = BuildQueryTagsWithPack("mf", "standing", "ge", "")
                handle = OSF.StartSceneByTags(actors, t45ge, opts)
            endif
            if handle <= 0
                string[] t45gef = BuildQueryTagsWithPack("mf", "floor", "ge", "")
                handle = OSF.StartSceneByTags(actors, t45gef, opts)
            endif
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

Function TryStartSoloScene(Actor[] eligible)
    if eligible == None || eligible.Length == 0
        return
    endif
    if !IsSoloDowntime()
        return
    endif

    int soloRoll = Utility.RandomInt(1, 100)
    if soloRoll > GetSoloChance()
        Log("Solo scene skipped — chance roll failed (" + soloRoll + " > " + GetSoloChance() + ")")
        return
    endif

    Actor soloActor = eligible[Utility.RandomInt(0, eligible.Length - 1)]
    if soloActor == None
        return
    endif

    if soloActor.IsRunning() || soloActor.IsTalking() || soloActor.IsSneaking()
        Log("Solo scene skipped — actor not idle")
        return
    endif

    if IsSoloPrivateOnly()
        Cell c = soloActor.GetParentCell()
        if c == None || !c.IsInterior()
            Log("Solo scene skipped — not interior (privateOnly)")
            return
        endif
    endif

    float soloDist = soloActor.GetDistance(Game.GetPlayer() as ObjectReference)
    if soloDist > GetMaxStartDistance()
        Log("Solo scene skipped — too far from player")
        return
    endif

    if OSF.IsPlaying(soloActor)
        Log("Solo scene skipped — actor already in a scene (claimed since eligibility check)")
        return
    endif
    EnsureArraysInitialized()

    Actor[] soloArr = new Actor[1]
    soloArr[0] = soloActor

    ActorBase soloBase = soloActor.GetLeveledActorBase()
    if soloBase == None
        Log("Solo scene skipped — could not resolve ActorBase (sex unknown)")
        return
    endif
    int actorSex = soloBase.GetSex()
    string[] soloTags = new string[3]
    soloTags[0] = "solo"
    soloTags[1] = "osfautonomous"
    if actorSex == 1
        soloTags[2] = "female"
        Log("Solo scene — female actor, using self-pleasure pool")
    else
        soloTags[2] = "neutral"
        Log("Solo scene — male/neutral actor, using neutral pose pool")
    endif

    OSFTypes:SceneOptions soloOpts = new OSFTypes:SceneOptions
    soloOpts.LockPlayerMode    = OSF.OFF()
    soloOpts.PlayerControlMode = OSF.OFF()
    soloOpts.Camera            = "none"
    soloOpts.FadeMode          = OSF.OFF()
    soloOpts.InPlaceMode       = OSF.OFF()
    soloOpts.StripMode         = GetStripMode()
    soloOpts.LoopScale         = GetLoopScale()

    int handle = OSF.StartSceneByTags(soloArr, soloTags, soloOpts)
    if handle > 0
        activeSceneHandles.Add(handle, 1)
        sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
        sceneActorA.Add(soloActor, 1)
        sceneActorB.Add(None, 1)
        ; running and gets a real cooldown via ApplyCooldownToActor on END/ghost
        StartSceneTimeoutTimer()
        Log("Solo scene started — handle=" + handle + " actor=" + soloActor)
    else
        Log("Solo scene start failed — no matching solo scene")
    endif
EndFunction

ObjectReference[] Function FindNearbyFurniture(Actor akActor, float afRadius)
    ObjectReference[] candidates = new ObjectReference[0]
    float maxZ = GetMaxZOffset()
    float actorZ = akActor.GetPositionZ()

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
                if refs[i] != None && refs[i].Is3DLoaded() && !refs[i].IsFurnitureInUse()
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

Function EmergencyStopAll()
    if activeSceneHandles == None || activeSceneHandles.Length == 0
        return
    endif
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
            if i < trackedA.Length && trackedA[i] != None
                ApplyCooldownToActor(trackedA[i])
            endif
            if i < trackedB.Length && trackedB[i] != None
                ApplyCooldownToActor(trackedB[i])
            endif
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
        else
            Actor[] participants = OSF.GetSceneParticipants(handle)
            if participants.Length == 0
                float ghostDur = 0.0
                if i < sceneStartTimes.Length
                    ghostDur = Utility.GetCurrentRealTime() - sceneStartTimes[i]
                endif
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

                    bool stopped = OSF.StopScene(handle)
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
                    if tA != None && stopParticipants.Find(tA) < 0
                        ApplyCooldownToActor(tA)
                    endif
                    if tB != None && stopParticipants.Find(tB) < 0
                        ApplyCooldownToActor(tB)
                    endif
                    Log("Scene " + handle + " removed from tracking (stopped=" + stopped + ")")
                else
                    i += 1
                endif
            endif
        endif
    endwhile
EndFunction

Function StartSceneTimeoutTimer()
    StartTimer(30.0, TIMER_ID_SCENE_TIMEOUT)
EndFunction

Function EnforceSceneTimeouts()
    if activeSceneHandles == None || activeSceneHandles.Length == 0
        return
    endif
    SyncSceneTracking()

    float nowReal = Utility.GetCurrentRealTime()
    float timeoutSeconds = GetSceneTimeoutMinutes() * 60.0
    float finaleWindow = GetFinaleGracePeriod()

    int i = activeSceneHandles.Length - 1
    while i >= 0
        if i < sceneStartTimes.Length
            float elapsed = nowReal - sceneStartTimes[i]
            int handle = activeSceneHandles[i]
            if elapsed < 0.0
                Log("WARNING: stale start time for handle " + handle + " (elapsed=" + elapsed + ") — resetting timer")
                sceneStartTimes[i] = nowReal
                elapsed = 0.0
            endif

            if IsNaturalFinale() && elapsed >= (timeoutSeconds - finaleWindow) && elapsed < timeoutSeconds
                bool alreadyTriggered = (finaleTriggeredHandles.Find(handle) >= 0)
                if !alreadyTriggered
                    int currentStage = OSF.GetSceneStage(handle)
                    if currentStage >= 0
                        OSF.AdvanceScene(handle)
                        Log("Natural finale — advanced stage for handle " + handle + " (stage=" + currentStage + ", elapsed=" + elapsed + "s)")
                    endif
                    finaleTriggeredHandles.Add(handle, 1)
                endif
            endif

            if elapsed >= timeoutSeconds
                Log("Scene timeout — stopping handle " + handle + " (elapsed=" + elapsed + " real seconds)")

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

                Actor[] participants = OSF.GetSceneParticipants(handle)

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

    if activeSceneHandles != None && activeSceneHandles.Length > 0
        StartTimer(30.0, TIMER_ID_SCENE_TIMEOUT)
    endif
EndFunction

Function ApplyCooldownToActor(Actor p)
    float cooldownEnd = Utility.GetCurrentGameTime() + (GetCooldownMinutes() / 1440.0)
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
EndFunction

bool Function IsOnCooldown(Actor akActor)
    int idx = cooldownActors.Find(akActor)
    if idx < 0
        return false
    endif
    float now = Utility.GetCurrentGameTime()
    if now >= cooldownEndTimes[idx]
        cooldownActors.Remove(idx)
        cooldownEndTimes.Remove(idx)
        return false
    endif
    return true
EndFunction

Function CleanExpiredCooldowns()
    if cooldownActors != None && cooldownActors.Length > 0
        float now = Utility.GetCurrentGameTime()
        int i = 0
        while i < cooldownActors.Length
            if now >= cooldownEndTimes[i]
                cooldownActors.Remove(i)
                cooldownEndTimes.Remove(i)
            else
                i += 1
            endif
        endwhile
    endif

    if pairCooldownKeys != None && pairCooldownKeys.Length > 0
        float nowPair = Utility.GetCurrentGameTime()
        int j = 0
        while j < pairCooldownKeys.Length
            if nowPair >= pairCooldownEndTimes[j]
                pairCooldownKeys.Remove(j)
                pairCooldownEndTimes.Remove(j)
            else
                j += 1
            endif
        endwhile
    endif
EndFunction

bool Function IsEnabled()
    return OSFSettings.GetBool(MOD_ID, "bEnabled", true)
EndFunction

Function ResumeScanTimer()
    if IsEnabled()
        StartTimer(GetCheckInterval(), TIMER_ID_SCAN)
    endif
EndFunction

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

bool Function IsBreathableEnvironment()
    Actor player = Game.GetPlayer()
    Cell c = player.GetParentCell()
    if c != None && c.IsInterior()
        return true
    endif
    if player.IsInSpace()
        Log("Environment blocked — space exterior (vacuum)")
        return false
    endif
    ; seamless structures are exterior cells by engine design. The engine
    if kAvHideHelmetBreathable != None && player.GetValue(kAvHideHelmetBreathable) > 0.0
        return true
    endif
    Planet p = player.GetCurrentPlanet()
    if p == None
        Log("Environment blocked — exterior with no planet (deep space)")
        return false
    endif
    Keyword atmo = p.GetAtmosphereType()
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
        return false
    endif
    string mode = GetLocationMode()
    if mode == "everywhere"
        return true
    endif
    ; bIsOnShip stale across station/docked transitions (SF-TIK-008).
    if IsPlayerInOwnShip()
        return true
    endif
    if mode == "interiors"
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

bool Function IsRomanceExclusivity()
    return OSFSettings.GetBool(MOD_ID, "bRomanceExclusivity", true)
EndFunction

bool Function IsPolyamoryBypass()
    return false
EndFunction

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

bool Function IsNaturalFinale()
    return true
EndFunction

float Function GetFinaleGracePeriod()
    return 10.0
EndFunction

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

String Function GetNextActionTag(String asGenderTag)
    String[] pool = GetActiveActionPool(asGenderTag)

    int validCount = 0
    while validCount < pool.Length && pool[validCount] != ""
        validCount += 1
    endwhile

    if validCount == 0
        return ""
    endif

    String tag = pool[iTagRotationIndex % validCount]
    iTagRotationIndex = (iTagRotationIndex + 1) % 1000
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
    else
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

    String[] result = new String[count]
    int i = 0
    while i < count
        result[i] = pool[i]
        i += 1
    endwhile
    return result
EndFunction

String Function GetOSFFurnitureTag(ObjectReference akAnchor)
    return ""
EndFunction

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

float Function CalculateInitialSpeed()
    string mode = GetSpeedMode()
    if mode == "dynamic"
        return 0.85
    elseif mode == "random"
        return Utility.RandomFloat(0.8, 1.25)
    endif
    float speed = GetBaseSceneSpeed()
    if speed < 0.5
        return 0.5
    elseif speed > 2.0
        return 2.0
    endif
    return speed
EndFunction
