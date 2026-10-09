ScriptName OSF_E2ETests
{Dev-only in-game E2E tests for OSF_AutonomousManagerScript.
 Lives in repo tests/papyrus/ - NEVER shipped in the release ZIP.
 Deploy:  tests/papyrus/deploy_e2e.ps1
 Run:     console -> cgf "OSF_E2ETests.RunAll"
          (or:    bat osfe2e)
 Output:  Logs/Script/User/OSF_Autonomous.N.log  (lines tagged [E2E])

 SIDE EFFECTS: starts and stops REAL scenes through the production
 code path (TryStartScene). NPCs get real cooldowns, strip/equip gear,
 and furniture is used. Run at a private location (ship / outpost /
 home) with the mod enabled. Covers SF-TIK-010 (strapon equip on FF
 scenes) and SF-TIK-011 (concurrency pool cap demonstration).}

; ---------------------------------------------------------------------------
; Plumbing (all global - cgf can only invoke globals)
; ---------------------------------------------------------------------------

Function TLog(String asMsg) global
    Debug.OpenUserLog("OSF_Autonomous")
    Debug.TraceUser("OSF_Autonomous", "[E2E] " + asMsg)
    Debug.Trace("[OSF_E2E] " + asMsg)
EndFunction

; Same as TLog plus an on-screen notification - use for ABORT/result lines so
; the user sees the outcome without opening the log.
Function TNote(String asMsg) global
    TLog(asMsg)
    Debug.Notification("OSF E2E: " + asMsg)
EndFunction

Function Check(String asName, bool abCond, int[] aiC, String asDetail = "") global
    if abCond
        aiC[0] += 1
        TLog("PASS  " + asName)
    else
        aiC[1] += 1
        TLog("FAIL  " + asName + "   " + asDetail)
    endif
EndFunction

Function Skip(String asName, String asWhy) global
    TLog("SKIP  " + asName + "   " + asWhy)
EndFunction

OSF_AutonomousManagerScript Function GetManager() global
    OSF_AutonomousManagerScript mgr = Game.GetFormFromFile(0x01000801, "OSFAutonomous.esm") as OSF_AutonomousManagerScript
    if mgr == None
        TLog("FATAL: manager instance not found (quest 0x01000801 in OSFAutonomous.esm)")
    endif
    return mgr
EndFunction

; ---------------------------------------------------------------------------
; Actor pool helpers
; ---------------------------------------------------------------------------

Actor Function SarahRef() global
    return Game.GetFormFromFile(0x00005986, "Starfield.esm") as Actor  ; SarahMorganREF
EndFunction

Actor Function AndrejaRef() global
    return Game.GetFormFromFile(0x000059A9, "Starfield.esm") as Actor  ; andrejaRef
EndFunction

Keyword Function ActorTypeHumanKeyword() global
    return Game.GetFormFromFile(0x0025E194, "Starfield.esm") as Keyword  ; ActorTypeNPC
EndFunction

; Collects actors the autonomous scanner would see and runs them through the
; REAL eligibility filter (IsActorEligible logs a reject reason per failure -
; that output is part of the diagnostic). Mirrors the OnTimer candidate build:
; companions + followers + generic humans (outpost scan) within scan range.
Actor[] Function CollectEligibleActors(OSF_AutonomousManagerScript mgr) global
    Actor player = Game.GetPlayer()
    Actor[] pool = new Actor[0]
    float scanRange = mgr.GetMaxStartDistance() + 200.0

    ; Named companions - always tried, logged for diagnostics
    Actor sarah = SarahRef()
    Actor andreja = AndrejaRef()
    if sarah != None && pool.Find(sarah) < 0
        pool.Add(sarah, 1)
    endif
    if andreja != None && pool.Find(andreja) < 0
        pool.Add(andreja, 1)
    endif

    ; Active followers (multi-follower mods)
    Actor[] followers = Game.GetPlayerFollowers()
    if followers != None
        int i = 0
        while i < followers.Length
            if followers[i] != None && followers[i] != player && pool.Find(followers[i]) < 0
                pool.Add(followers[i], 1)
            endif
            i += 1
        endwhile
    endif

    ; Generic humans in scan range (outpost settlers, lodge residents)
    Keyword kHuman = ActorTypeHumanKeyword()
    if kHuman != None
        ObjectReference[] npcs = player.FindAllReferencesWithKeyword(kHuman, scanRange)
        if npcs != None
            int k = 0
            while k < npcs.Length
                Actor a = npcs[k] as Actor
                if a != None && a != player && pool.Find(a) < 0
                    pool.Add(a, 1)
                endif
                k += 1
            endwhile
        endif
    endif

    TLog("Candidate pool gathered: " + pool.Length + " actor(s) - running IsActorEligible on each")
    Actor[] eligible = new Actor[0]
    int e = 0
    while e < pool.Length
        if mgr.IsActorEligible(pool[e])
            eligible.Add(pool[e], 1)
        endif
        e += 1
    endwhile
    TLog("Eligible pool: " + eligible.Length + "/" + pool.Length)
    return eligible
EndFunction

int Function GetSexOf(Actor a) global
    ActorBase b = a.GetLeveledActorBase()
    if b == None
        return -1
    endif
    return b.GetSex()
EndFunction

String Function ActorTag(Actor a) global
    if a == None
        return "None"
    endif
    string sexStr = "?"
    int s = GetSexOf(a)
    if s == 0
        sexStr = "m"
    elseif s == 1
        sexStr = "f"
    endif
    return "0x" + a.GetFormID() + "(" + sexStr + ")"
EndFunction

; ---------------------------------------------------------------------------
; Gear helpers (SF-TIK-010)
; ---------------------------------------------------------------------------

Form Function FormDick() global
    return Game.GetFormFromFile(0x00000800, "Dick.esm")
EndFunction

Form Function FormDickFlaccid() global
    return Game.GetFormFromFile(0x0000081B, "Dick.esm")
EndFunction

Form Function FormDickErect() global
    return Game.GetFormFromFile(0x0000081D, "Dick.esm")  ; the strapon used by equip strings
EndFunction

Form Function FormDickErect2() global
    return Game.GetFormFromFile(0x00000820, "Dick.esm")
EndFunction

Form Function FormHatersErection() global
    return Game.GetFormFromFile(0x00000804, "Haters Body.esm")
EndFunction

String Function GearReport(Actor a) global
    ; Which known gear forms are equipped on this actor right now
    string found = ""
    if FormDick() != None && a.IsEquipped(FormDick())
        found += " Dick.esm|0x800"
    endif
    if FormDickFlaccid() != None && a.IsEquipped(FormDickFlaccid())
        found += " Dick.esm|0x81B(flaccid)"
    endif
    if FormDickErect() != None && a.IsEquipped(FormDickErect())
        found += " Dick.esm|0x81D(ERECT-STRAPON)"
    endif
    if FormDickErect2() != None && a.IsEquipped(FormDickErect2())
        found += " Dick.esm|0x820"
    endif
    if FormHatersErection() != None && a.IsEquipped(FormHatersErection())
        found += " HatersBody.esm|0x804"
    endif
    if found == ""
        found = " none"
    endif
    return found
EndFunction

bool Function WaitForPlaying(Actor a, float afTimeout) global
    float waited = 0.0
    while waited < afTimeout
        if a != None && OSF.IsPlaying(a)
            return true
        endif
        Utility.Wait(2.0)
        waited += 2.0
    endwhile
    return false
EndFunction

; ---------------------------------------------------------------------------
; E2E-1: FF scene -> role 'm' must get the strapon (SF-TIK-010)
; ---------------------------------------------------------------------------

Function TestStraponFF(int[] c) global
    TLog("--- E2E-1: strapon equip on FF scene (SF-TIK-010) ---")
    OSF_AutonomousManagerScript mgr = GetManager()
    if mgr == None || !OSF.IsReady()
        Skip("strapon-ff", "manager/OSF not ready")
        return
    endif

    if !Game.IsPluginInstalled("Dick.esm") && !Game.IsPluginInstalled("Haters Body.esm")
        Skip("strapon-ff", "no gear plugin installed (Dick.esm / Haters Body.esm) - equip string cannot resolve")
        return
    endif

    Actor[] eligible = CollectEligibleActors(mgr)

    ; Pick two females - role 'm' in an FF pair receives equip.female = Dick.esm|0x81D
    Actor femA = None
    Actor femB = None
    int i = 0
    while i < eligible.Length
        if GetSexOf(eligible[i]) == 1
            if femA == None
                femA = eligible[i]
            elseif femB == None
                femB = eligible[i]
            endif
        endif
        i += 1
    endwhile

    if femA == None || femB == None
        Skip("strapon-ff", "need 2 eligible females - found A=" + ActorTag(femA) + " B=" + ActorTag(femB))
        return
    endif
    TLog("FF pair: A=" + ActorTag(femA) + " (role m - strapon expected)  B=" + ActorTag(femB))

    mgr.TryStartScene(femA, femB)
    Check("strapon-ff scene started", WaitForPlaying(femA, 30.0), c, "IsPlaying(A) false after 30s - check TryStartScene log above for the skip reason")

    if !OSF.IsPlaying(femA)
        return  ; no scene - nothing more to check
    endif

    ; Wait for the equip to land (actors walk to furniture + undress first)
    float waited = 0.0
    bool straponOn = false
    while waited < 45.0 && !straponOn
        if femA.IsEquipped(FormDickErect())
            straponOn = true
        endif
        if !straponOn
            Utility.Wait(3.0)
            waited += 3.0
        endif
    endwhile

    TLog("gear on A(role m): " + GearReport(femA))
    TLog("gear on B(role f): " + GearReport(femB))
    Check("strapon equipped (Dick.esm|0x81D on role m)", straponOn, c, "no DickErect on " + ActorTag(femA) + " after 45s - if OSF Animation.log shows no [E] equip error, the scene json may lack roles.m.equip.female")

    ; Cleanup path: stop our scene, then verify stuck-gear removal works
    OSF.StopSceneForActor(femA)
    OSF.StopSceneForActor(femB)
    Utility.Wait(6.0)  ; let OSF run its own restore first
    mgr.UnequipStuckAttachments(femA)
    mgr.UnequipStuckAttachments(femB)

    bool stillEquipped = femA.IsEquipped(FormDickErect()) || femB.IsEquipped(FormDickErect())
    int leftover = femA.GetItemCount(FormDickErect()) + femB.GetItemCount(FormDickErect())
    Check("stuck-gear cleanup after scene", !stillEquipped && leftover == 0, c, "equipped=" + stillEquipped + " invCount=" + leftover + " - UnequipStuckAttachments should strip it")
EndFunction

; ---------------------------------------------------------------------------
; E2E-2: concurrency cap is pool-driven, not chance-driven (SF-TIK-011)
; ---------------------------------------------------------------------------

Function TestConcurrency(int[] c) global
    TLog("--- E2E-2: concurrent scenes vs eligibility pool (SF-TIK-011) ---")
    OSF_AutonomousManagerScript mgr = GetManager()
    if mgr == None || !OSF.IsReady()
        Skip("concurrency", "manager/OSF not ready")
        return
    endif

    Actor[] eligible = CollectEligibleActors(mgr)
    int n = eligible.Length
    int maxPairs = n / 2
    TLog("eligible=" + n + " -> max concurrent pairs = " + maxPairs + " (pool cap is BY_DESIGN per SF-TIK-011; iMaxConcurrentScenes=" + mgr.GetMaxConcurrent() + " is a ceiling, not a target)")

    if n < 2
        Skip("concurrency", "fewer than 2 eligible actors nearby - move to an outpost/ship with standing NPCs")
        return
    endif

    ; Pair 1: pick the two closest-to-each-other eligible actors (must be <=400u)
    Actor a1 = None
    Actor b1 = None
    float best = 99999.0
    int i = 0
    while i < n
        int j = i + 1
        while j < n
            float d = eligible[i].GetDistance(eligible[j] as ObjectReference)
            if d < best
                best = d
                a1 = eligible[i]
                b1 = eligible[j]
            endif
            j += 1
        endwhile
        i += 1
    endwhile
    TLog("pair 1: " + ActorTag(a1) + " + " + ActorTag(b1) + " dist=" + best)

    mgr.TryStartScene(a1, b1)
    bool s1 = WaitForPlaying(a1, 30.0)
    Check("scene 1 started", s1, c, "IsPlaying(pair1) false after 30s")

    if !s1
        return
    endif
    Utility.Wait(6.0)  ; let scene 1 register before pair 2 hits the spacing guard

    if n < 4
        ; Pool can't host a second pair - document the cap instead of failing
        TLog("INFO  pool=" + n + " -> second pair impossible (need 4 eligible). This is the single-scene root cause from SF-TIK-011.")
        Check("pool cap documented (1 scene, pool<4)", OSF.IsPlaying(a1) || OSF.IsPlaying(b1), c)
        OSF.StopSceneForActor(a1)
        OSF.StopSceneForActor(b1)
        return
    endif

    ; Pair 2: first disjoint pair that is NOT within spacing of scene 1 actors
    Actor a2 = None
    Actor b2 = None
    float minSpacing = mgr.GetMinSceneSpacing()
    i = 0
    while i < n && a2 == None
        if eligible[i] != a1 && eligible[i] != b1
            int j = i + 1
            while j < n
                Actor candB = eligible[j]
                if candB != a1 && candB != b1 && candB != eligible[i]
                    float dPair = eligible[i].GetDistance(candB as ObjectReference)
                    float dScene = eligible[i].GetDistance(a1 as ObjectReference)
                    if dPair <= mgr.GetMaxPairDistance() && dScene >= minSpacing
                        a2 = eligible[i]
                        b2 = candB
                    endif
                endif
                j += 1
            endwhile
        endif
        i += 1
    endwhile

    if a2 == None
        TLog("INFO  no second pair satisfies pair-distance<=400 AND scene-spacing>=" + minSpacing + " - geometry cap, BY_DESIGN per SF-TIK-011")
        Skip("second concurrent scene", "eligible=" + n + " but all remaining pairs fail distance/spacing - geometry cap, not a bug")
        OSF.StopSceneForActor(a1)
        OSF.StopSceneForActor(b1)
        return
    endif
    TLog("pair 2: " + ActorTag(a2) + " + " + ActorTag(b2))

    mgr.TryStartScene(a2, b2)
    bool s2 = WaitForPlaying(a2, 30.0)
    Check("scene 2 runs concurrently", s2 && (OSF.IsPlaying(a1) || OSF.IsPlaying(b1)), c, "pair2 never played or scene1 died")

    OSF.StopSceneForActor(a1)
    OSF.StopSceneForActor(b1)
    OSF.StopSceneForActor(a2)
    OSF.StopSceneForActor(b2)
EndFunction

; ---------------------------------------------------------------------------
; E2E-3: settings echo + wiring (proves OSFSettings values reach the getters)
; ---------------------------------------------------------------------------

Function TestSettingsEcho(int[] c) global
    TLog("--- E2E-3: settings echo ---")
    OSF_AutonomousManagerScript mgr = GetManager()
    if mgr == None
        return
    endif
    string mid = "osf.autonomous"
    Check("wire iChancePercent", mgr.GetChancePercent() == OSFSettings.GetInt(mid, "iChancePercent", 25), c, "getter=" + mgr.GetChancePercent())
    Check("wire iMaxConcurrentScenes", mgr.GetMaxConcurrent() == OSFSettings.GetInt(mid, "iMaxConcurrentScenes", 2), c, "getter=" + mgr.GetMaxConcurrent())
    Check("wire fMinSceneSpacing", mgr.GetMinSceneSpacing() == OSFSettings.GetFloat(mid, "fMinSceneSpacing", 500.0), c, "getter=" + mgr.GetMinSceneSpacing())
    Check("wire fCheckInterval", mgr.GetCheckInterval() == OSFSettings.GetFloat(mid, "fCheckInterval", 45.0), c, "getter=" + mgr.GetCheckInterval())
    Check("wire fPairCooldownMinutes", mgr.GetPairCooldownMinutes() == OSFSettings.GetFloat(mid, "fPairCooldownMinutes", 30.0), c, "getter=" + mgr.GetPairCooldownMinutes())
    Check("wire fMaxZOffset", mgr.GetMaxZOffset() == OSFSettings.GetFloat(mid, "fMaxZOffset", 200.0), c, "getter=" + mgr.GetMaxZOffset())
    Check("wire fMaxStartDistance", mgr.GetMaxStartDistance() == OSFSettings.GetFloat(mid, "fMaxStartDistance", 2000.0), c, "getter=" + mgr.GetMaxStartDistance())
    TLog("settings now: chance=" + mgr.GetChancePercent() + "% maxScenes=" + mgr.GetMaxConcurrent() + " spacing=" + mgr.GetMinSceneSpacing() + "u interval=" + mgr.GetCheckInterval() + "s pairCooldown=" + mgr.GetPairCooldownMinutes() + "min")
EndFunction

; ---------------------------------------------------------------------------
; Entry points
; ---------------------------------------------------------------------------

Function RunAll() global
    int[] c = new int[2]
    TLog("===== OSF E2E begin =====")
    TLog("NOTE: tests start/stop REAL scenes; NPC cooldowns are applied for real.")
    TestSettingsEcho(c)
    TestStraponFF(c)
    TestConcurrency(c)
    TLog("===== OSF E2E done: " + c[0] + " passed, " + c[1] + " failed =====")
    if c[1] == 0
        TNote("===== ALL GREEN =====")
    endif
EndFunction

Function GearOnly() global
    int[] c = new int[2]
    TLog("===== OSF E2E (strapon only) =====")
    TestStraponFF(c)
    TLog("===== done: " + c[0] + " passed, " + c[1] + " failed =====")
EndFunction

Function ConcurrencyOnly() global
    int[] c = new int[2]
    TLog("===== OSF E2E (concurrency only) =====")
    TestConcurrency(c)
    TLog("===== done: " + c[0] + " passed, " + c[1] + " failed =====")
EndFunction

Function DumpPool() global
    OSF_AutonomousManagerScript mgr = GetManager()
    if mgr != None
        CollectEligibleActors(mgr)
    endif
EndFunction

; ---------------------------------------------------------------------------
; Staged demo: force TWO concurrent scenes (SF-TIK-011 visual proof)
; ---------------------------------------------------------------------------
; The organic wave can only run floor(eligible/2) scenes and the eligibility
; pool at a small outpost is typically 2-3 -> one scene. This demo bypasses
; the scanner (deliberately - it is a demo, not the organic path): it gathers
; any usable nearby actors (cooldown/sitting allowed - TryStartScene does not
; check those), teleports two pairs into two spots in front of the player
; separated by more than MinSceneSpacing, and starts both scenes.
; Scenes are LEFT RUNNING so you can look at them; stop with
;   cgf "OSF_E2ETests.StopDemo"

bool Function DemoFilter(OSF_AutonomousManagerScript mgr, Actor a) global
    ; Looser than IsActorEligible - cooldown and sitting are fine for a demo.
    ; Only hard requirements (skeleton/sex sanity, not busy, not player).
    if a == None || a == Game.GetPlayer()
        return false
    endif
    if !a.Is3DLoaded() || a.IsDisabled() || a.IsDead() || a.IsChild()
        return false
    endif
    if a.IsInCombat() || OSF.IsPlaying(a)
        return false
    endif
    Keyword kRobot = Game.GetFormFromFile(0x002702C9, "Starfield.esm") as Keyword
    if kRobot != None
        if a.HasKeyword(kRobot)
            return false
        endif
        Race r = a.GetRace()
        if r != None && r.HasKeyword(kRobot)
            return false
        endif
    endif
    return a.GetLeveledActorBase() != None
EndFunction

Actor[] Function CollectDemoActors(OSF_AutonomousManagerScript mgr) global
    Actor player = Game.GetPlayer()
    Actor[] pool = new Actor[0]
    float scanRange = mgr.GetMaxStartDistance() + 200.0

    Actor sarah = SarahRef()
    Actor andreja = AndrejaRef()
    if sarah != None
        pool.Add(sarah, 1)
    endif
    if andreja != None
        pool.Add(andreja, 1)
    endif

    Actor[] followers = Game.GetPlayerFollowers()
    if followers != None
        int i = 0
        while i < followers.Length
            if followers[i] != None && followers[i] != player && pool.Find(followers[i]) < 0
                pool.Add(followers[i], 1)
            endif
            i += 1
        endwhile
    endif

    Keyword kHuman = ActorTypeHumanKeyword()
    if kHuman != None
        ObjectReference[] npcs = player.FindAllReferencesWithKeyword(kHuman, scanRange)
        if npcs != None
            int k = 0
            while k < npcs.Length
                Actor a = npcs[k] as Actor
                if a != None && a != player && pool.Find(a) < 0
                    pool.Add(a, 1)
                endif
                k += 1
            endwhile
        endif
    endif

    ; Keep only demo-usable actors
    Actor[] usable = new Actor[0]
    int u = 0
    while u < pool.Length
        if DemoFilter(mgr, pool[u])
            usable.Add(pool[u], 1)
        endif
        u += 1
    endwhile
    TLog("Demo pool: " + usable.Length + "/" + pool.Length + " usable actor(s)")
    return usable
EndFunction

Function DemoTwoScenes() global
    int[] c = new int[2]
    TLog("===== OSF E2E: staged 2-scene demo =====")
    OSF_AutonomousManagerScript mgr = GetManager()
    if mgr == None || !OSF.IsReady()
        TNote("ABORT: manager/OSF not ready")
        return
    endif

    Actor[] pool = CollectDemoActors(mgr)
    if pool.Length < 4
        TNote("ABORT: need 4 usable actors, found " + pool.Length + " - move somewhere with more NPCs")
        return
    endif

    ; Build two pairs - each must contain at least one female (mm is blocked).
    ; Greedy: take the first female, pair her with the next actor of any sex.
    Actor[] females = new Actor[0]
    Actor[] males = new Actor[0]
    int i = 0
    while i < pool.Length
        if GetSexOf(pool[i]) == 1
            females.Add(pool[i], 1)
        else
            males.Add(pool[i], 1)
        endif
        i += 1
    endwhile
    if females.Length < 2
        TNote("ABORT: need 2 females for two valid pairs (mm pairs are blocked by design), found " + females.Length)
        return
    endif

    Actor a1 = females[0]
    Actor b1 = None
    Actor a2 = females[1]
    Actor b2 = None
    if males.Length >= 2
        b1 = males[0]
        b2 = males[1]
    elseif females.Length >= 4
        b1 = females[2]
        b2 = females[3]
    elseif males.Length == 1 && females.Length >= 3
        b1 = males[0]
        b2 = females[2]
    else
        TNote("ABORT: cannot compose two valid pairs from " + females.Length + "F + " + males.Length + "M")
        return
    endif
    TLog("pair 1: " + ActorTag(a1) + " + " + ActorTag(b1))
    TLog("pair 2: " + ActorTag(a2) + " + " + ActorTag(b2))

    ; v5 staging - maxDist override only. OSFSettings enforces schema bounds:
    ; fMinSceneSpacing is clamped to schema min=250, so spacing cannot be
    ; overridden away - and it should not be (the guard stays real). Instead
    ; we widen fMaxStartDistance (schema max 10000) so pair 2 can be staged
    ; far enough from scene 1's ANCHOR position while spacing stays intact.
    ; TryStartScene anchors to furniture and RELOCATES actors, so pair 2 is
    ; placed relative to scene 1's actual post-anchor position, on the ray
    ; anchor->player extended past the player.
    Actor player = Game.GetPlayer()
    if player == None
        TNote("ABORT: player ref unavailable (cell transition?) - retry in a second")
        return
    endif
    string mid = "osf.autonomous"
    float spacing = mgr.GetMinSceneSpacing()
    float origMaxDist = OSFSettings.GetFloat(mid, "fMaxStartDistance", mgr.GetMaxStartDistance())
    bool okOverride = OSFSettings.SetFloat(mid, "fMaxStartDistance", 2000.0)
    TLog("settings override for demo: maxDist " + origMaxDist + "->2000u (SetFloat=" + okOverride + "), spacing left at " + spacing + "u")

    mgr.EmergencyStopAll()  ; idempotent - no-op when nothing is playing
    Utility.Wait(2.0)

    a1.MoveTo(player, 0.0, 150.0, 0.0, false, false)
    b1.MoveTo(player, 30.0, 160.0, 0.0, false, false)
    Utility.Wait(1.0)
    a1.MoveToNearestNavmeshLocation()
    b1.MoveToNearestNavmeshLocation()
    TLog("pair 1 staged ~150u from player; starting scene 1")
    Utility.Wait(2.0)

    mgr.TryStartScene(a1, b1)
    bool s1 = WaitForPlaying(a1, 25.0)
    Check("demo scene 1 playing", s1, c, "see TryStartScene skip reason above")
    if !s1
        OSFSettings.SetFloat(mid, "fMaxStartDistance", origMaxDist)
        TNote("===== demo aborted: scene 1 did not start =====")
        return
    endif

    Utility.Wait(4.0)  ; let OSF finish relocating actors to the anchor

    ; Pair 2: past the player on the ray anchor->player, s units out, where
    ; dist(pair2, anchor) = distAP + s must exceed spacing + margin.
    float ax = a1.GetPositionX()
    float ay = a1.GetPositionY()
    float dx = player.GetPositionX() - ax
    float dy = player.GetPositionY() - ay
    float distAP = Math.sqrt(dx * dx + dy * dy)
    if distAP < 1.0
        dx = 1.0
        dy = 0.0
        distAP = 1.0
    endif
    float ux = dx / distAP
    float uy = dy / distAP

    float s = spacing + 80.0 - distAP
    if s < 150.0
        s = 150.0
    endif
    if s > 1900.0
        OSFSettings.SetFloat(mid, "fMaxStartDistance", origMaxDist)
        TNote("ABORT: spacing=" + spacing + "u + anchor at " + distAP + "u needs pair 2 at " + s + "u - beyond maxDist. Lower fMinSceneSpacing.")
        return
    endif

    ; Keep pair 2 tight: 10u apart (not 30) so OSF Animation can pull both
    ; to the same furniture anchor. Navmesh snap can separate them further.
    a2.MoveTo(player, ux * s, uy * s, 0.0, false, false)
    b2.MoveTo(player, ux * s + uy * 10.0, uy * s - ux * 10.0, 0.0, false, false)
    Utility.Wait(1.0)
    a2.MoveToNearestNavmeshLocation()
    b2.MoveToNearestNavmeshLocation()
    TLog("pair 2 staged +" + s + "u past player on anchor->player ray (anchor->player " + distAP + "u, pair2->scene1 ~" + (distAP + s) + "u > spacing " + spacing + "u)")
    Utility.Wait(2.0)

    ; Navmesh snap can pull actors back toward scene 1, and the guard checks
    ; BOTH scene-1 participants - nudge pair 2 further out until clear of a1
    ; AND b1 (safety counter: max 5 retries, 100u steps).
    int nudge = 0
    while nudge < 5 && s <= 1900.0 && (a2.GetDistance(a1) <= spacing + 20.0 || a2.GetDistance(b1) <= spacing + 20.0 || b2.GetDistance(a1) <= spacing + 20.0 || b2.GetDistance(b1) <= spacing + 20.0)
        s += 100.0
        a2.MoveTo(player, ux * s, uy * s, 0.0, false, false)
        b2.MoveTo(player, ux * s + uy * 10.0, uy * s - ux * 10.0, 0.0, false, false)
        Utility.Wait(0.5)
        a2.MoveToNearestNavmeshLocation()
        b2.MoveToNearestNavmeshLocation()
        nudge += 1
    endwhile
    if nudge > 0
        TLog("pair 2 nudged out to +" + s + "u after " + nudge + " retry/retries")
    endif
    if a2.GetDistance(a1) <= spacing || a2.GetDistance(b1) <= spacing || b2.GetDistance(a1) <= spacing || b2.GetDistance(b1) <= spacing
        OSFSettings.SetFloat(mid, "fMaxStartDistance", origMaxDist)
        TNote("ABORT: pair 2 still inside spacing of scene 1 after " + nudge + " nudges - run in a more open spot")
        return
    endif

    Utility.Wait(1.0)  ; final settle before scene start

    mgr.TryStartScene(a2, b2)
    bool s2 = WaitForPlaying(a2, 25.0)
    Check("demo scene 2 playing", s2, c, "see TryStartScene skip reason above")

    ; Per-actor diagnostic: OSF can start a scene formally but only one
    ; actor actually plays (pathing/furniture AI failure). Log each so the
    ; "1 NPC visible" case is detectable in the log.
    bool a2Play = OSF.IsPlaying(a2)
    bool b2Play = OSF.IsPlaying(b2)
    TLog("scene 2 actors: a2=" + (a2Play as string) + "  b2=" + (b2Play as string) + "  dist(a2,b2)=" + a2.GetDistance(b2) + "u")
    if a2Play && !b2Play
        TLog("WARN: b2 not playing - OSF may have failed to pull b2 to the anchor. b2 dist from a2=" + a2.GetDistance(b2) + "u")
    elseif b2Play && !a2Play
        TLog("WARN: a2 not playing - same. a2 dist from b2=" + a2.GetDistance(b2) + "u")
    elseif !a2Play && !b2Play
        TLog("WARN: neither a2 nor b2 is playing")
    endif

    bool bothPairsConcurrent = (OSF.IsPlaying(a1) || OSF.IsPlaying(b1)) && a2Play && b2Play
    Check("TWO scenes concurrent (both actors in each)", bothPairsConcurrent, c)
    if !bothPairsConcurrent && s2
        TLog("NOTE: scene 2 started formally but one actor missing - this is an OSF Animation framework issue (pathing/furniture), not our mod")
    endif
    if bothPairsConcurrent
        TNote("DONE - look around; stop with: cgf \"OSF_E2ETests.StopDemo\"")
    endif
    TNote("===== demo done: " + c[0] + " passed, " + c[1] + " failed =====")

    OSFSettings.SetFloat(mid, "fMaxStartDistance", origMaxDist)
    TLog("settings restored: maxDist=" + origMaxDist)
EndFunction

Function StopDemo() global
    OSF_AutonomousManagerScript mgr = GetManager()
    if mgr == None
        return
    endif
    mgr.EmergencyStopAll()
    TLog("StopDemo: EmergencyStopAll issued (all scenes stopped, cooldowns applied)")
EndFunction

; ---------------------------------------------------------------------------
; Recovery: pull every nearby NPC back to the player
; ---------------------------------------------------------------------------
; DemoTwoScenes once scattered actors via SetPosition which could land them
; outside cell geometry. This pulls the full pool (named companions,
; followers, scanned humans) back to the player's position via MoveTo, then
; snaps each onto navmesh. Safe to run anytime.
Function RecallNPCs() global
    TLog("===== OSF E2E: recall NPCs =====")
    Actor player = Game.GetPlayer()
    if player == None
        TNote("ABORT: player ref unavailable - retry in a second")
        return
    endif
    OSF_AutonomousManagerScript mgr = GetManager()
    float scanRange = 3000.0
    if mgr != None
        scanRange = mgr.GetMaxStartDistance() + 200.0
        if scanRange < 3000.0
            scanRange = 3000.0
        endif
    endif

    Actor[] pool = new Actor[0]
    Actor sarah = SarahRef()
    Actor andreja = AndrejaRef()
    if sarah != None
        pool.Add(sarah, 1)
    endif
    if andreja != None
        pool.Add(andreja, 1)
    endif
    Actor andromeda = Game.GetFormFromFile(0x0016B3D0, "Starfield.esm") as Actor
    if andromeda != None && pool.Find(andromeda) < 0
        pool.Add(andromeda, 1)
    endif

    Actor[] followers = Game.GetPlayerFollowers()
    if followers != None
        int i = 0
        while i < followers.Length
            if followers[i] != None && followers[i] != player && pool.Find(followers[i]) < 0
                pool.Add(followers[i], 1)
            endif
            i += 1
        endwhile
    endif

    Keyword kHuman = ActorTypeHumanKeyword()
    if kHuman != None
        ObjectReference[] npcs = player.FindAllReferencesWithKeyword(kHuman, scanRange)
        if npcs != None
            int k = 0
            while k < npcs.Length
                Actor a = npcs[k] as Actor
                if a != None && a != player && pool.Find(a) < 0
                    pool.Add(a, 1)
                endif
                k += 1
            endwhile
        endif
    endif

    int moved = 0
    int skipped = 0
    int n = 0
    while n < pool.Length
        Actor a = pool[n]
        if a != None && !a.IsDead() && !a.IsChild() && !OSF.IsPlaying(a)
            a.MoveTo(player)
            moved += 1
        else
            skipped += 1
            TLog("skip " + ActorTag(a) + " (dead/child/in-scene/none)")
        endif
        n += 1
    endwhile

    Utility.Wait(1.0)
    n = 0
    while n < pool.Length
        if pool[n] != None
            pool[n].MoveToNearestNavmeshLocation()
        endif
        n += 1
    endwhile
    TNote("recall done: " + moved + " moved to player, " + skipped + " skipped of " + pool.Length)
    TLog("===== recall done =====")
EndFunction
