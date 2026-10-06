ScriptName OSF_E2ETests

Function TLog(String asMsg) global
    Debug.OpenUserLog("OSF_Autonomous")
    Debug.TraceUser("OSF_Autonomous", "[E2E] " + asMsg)
    Debug.Trace("[OSF_E2E] " + asMsg)
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

Actor Function SarahRef() global
    return Game.GetFormFromFile(0x00005986, "Starfield.esm") as Actor
EndFunction

Actor Function AndrejaRef() global
    return Game.GetFormFromFile(0x000059A9, "Starfield.esm") as Actor
EndFunction

Keyword Function ActorTypeHumanKeyword() global
    return Game.GetFormFromFile(0x0025E194, "Starfield.esm") as Keyword
EndFunction

Actor[] Function CollectEligibleActors(OSF_AutonomousManagerScript mgr) global
    Actor player = Game.GetPlayer()
    Actor[] pool = new Actor[0]
    float scanRange = mgr.GetMaxStartDistance() + 200.0

    Actor sarah = SarahRef()
    Actor andreja = AndrejaRef()
    if sarah != None && pool.Find(sarah) < 0
        pool.Add(sarah, 1)
    endif
    if andreja != None && pool.Find(andreja) < 0
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

; Gear helpers (SF-TIK-010)

Form Function FormDick() global
    return Game.GetFormFromFile(0x00000800, "Dick.esm")
EndFunction

Form Function FormDickFlaccid() global
    return Game.GetFormFromFile(0x0000081B, "Dick.esm")
EndFunction

Form Function FormDickErect() global
    return Game.GetFormFromFile(0x0000081D, "Dick.esm")
EndFunction

Form Function FormDickErect2() global
    return Game.GetFormFromFile(0x00000820, "Dick.esm")
EndFunction

Form Function FormHatersErection() global
    return Game.GetFormFromFile(0x00000804, "Haters Body.esm")
EndFunction

String Function GearReport(Actor a) global
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

; E2E-1: FF scene -> role 'm' must get the strapon (SF-TIK-010)

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
        return
    endif

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

    OSF.StopSceneForActor(femA)
    OSF.StopSceneForActor(femB)
    Utility.Wait(6.0)
    mgr.UnequipStuckAttachments(femA)
    mgr.UnequipStuckAttachments(femB)

    bool stillEquipped = femA.IsEquipped(FormDickErect()) || femB.IsEquipped(FormDickErect())
    int leftover = femA.GetItemCount(FormDickErect()) + femB.GetItemCount(FormDickErect())
    Check("stuck-gear cleanup after scene", !stillEquipped && leftover == 0, c, "equipped=" + stillEquipped + " invCount=" + leftover + " - UnequipStuckAttachments should strip it")
EndFunction

; E2E-2: concurrency cap is pool-driven, not chance-driven (SF-TIK-011)

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
    Utility.Wait(6.0)

    if n < 4
        TLog("INFO  pool=" + n + " -> second pair impossible (need 4 eligible). This is the single-scene root cause from SF-TIK-011.")
        Check("pool cap documented (1 scene, pool<4)", OSF.IsPlaying(a1) || OSF.IsPlaying(b1), c)
        OSF.StopSceneForActor(a1)
        OSF.StopSceneForActor(b1)
        return
    endif

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

Function RunAll() global
    int[] c = new int[2]
    TLog("===== OSF E2E begin =====")
    TLog("NOTE: tests start/stop REAL scenes; NPC cooldowns are applied for real.")
    TestSettingsEcho(c)
    TestStraponFF(c)
    TestConcurrency(c)
    TLog("===== OSF E2E done: " + c[0] + " passed, " + c[1] + " failed =====")
    if c[1] == 0
        TLog("===== ALL GREEN =====")
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
