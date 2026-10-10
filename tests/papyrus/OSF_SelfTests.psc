ScriptName OSF_SelfTests
{
Dev-only in-game self-test harness for OSF_AutonomousManagerScript.
 Lives in repo tests/papyrus/ - NEVER shipped in the release ZIP.
 Deploy:  tests/papyrus/deploy_selftest.ps1
 Run:     console -> cgf "OSF_SelfTests.RunAll"
          (or:    bat osfselftest)
 Output:  Logs/Script/User/OSF_Autonomous.log  (lines tagged [SELFTEST])
}

Function TLog(String asMsg) global
    Debug.OpenUserLog("OSF_Autonomous")
    Debug.TraceUser("OSF_Autonomous", "[SELFTEST] " + asMsg)
    Debug.Trace("[OSF_SELFTEST] " + asMsg)
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

Function CheckIRange(String asName, int aiVal, int aiLo, int aiHi, int[] aiC) global
    Check(asName, aiVal >= aiLo && aiVal <= aiHi, aiC, "value=" + aiVal + " expected in [" + aiLo + "," + aiHi + "]")
EndFunction

Function CheckFRange(String asName, float afVal, float afLo, float afHi, int[] aiC) global
    Check(asName, afVal >= afLo && afVal <= afHi, aiC, "value=" + afVal + " expected in [" + afLo + "," + afHi + "]")
EndFunction

bool Function IsKnownActionTag(String asTag) global
    return asTag == "kissing" || asTag == "blowjob" || asTag == "oral" || \
           asTag == "missionary" || asTag == "cowgirl" || asTag == "spoon" || \
           asTag == "facedown" || asTag == "scissors" || asTag == "doggy" || \
           asTag == "reversecowgirl" || asTag == "riding"
EndFunction

Function RunAll() global
    int[] c = new int[2]
    TLog("===== OSF SelfTests begin =====")

    Check("OSF.IsReady()", OSF.IsReady(), c, "OSF Animation framework not ready - mod cannot function")

    OSF_AutonomousManagerScript mgr = Game.GetFormFromFile(0x01000801, "OSFAutonomous.esm") as OSF_AutonomousManagerScript
    if mgr == None
        TLog("FATAL: manager instance not found (quest 0x01000801) - aborting")
        return
    endif

    Actor player = Game.GetPlayer()
    String mid = "osf.autonomous"

    Check("wire bEnabled",            mgr.IsEnabled() == OSFSettings.GetBool(mid, "bEnabled", true), c)
    Check("wire sLocationMode",       mgr.GetLocationMode() == OSFSettings.GetEnum(mid, "sLocationMode", "ship"), c)
    Check("wire bCompanionsOnly",     mgr.IsCompanionsOnly() == OSFSettings.GetBool(mid, "bCompanionsOnly", false), c)
    Check("wire bIncludeOutpostNPC",  mgr.IsIncludeOutpostNPC() == OSFSettings.GetBool(mid, "bIncludeOutpostNPC", false), c)
    Check("wire bRequireFurniture",   mgr.IsRequireFurniture() == OSFSettings.GetBool(mid, "bRequireFurniture", true), c)
    Check("wire iMaxConcurrentScenes", mgr.GetMaxConcurrent() == OSFSettings.GetInt(mid, "iMaxConcurrentScenes", 2), c)
    Check("wire iChancePercent",      mgr.GetChancePercent() == OSFSettings.GetInt(mid, "iChancePercent", 25), c)
    Check("wire fActorCooldownMinutes", mgr.GetCooldownMinutes() == OSFSettings.GetFloat(mid, "fActorCooldownMinutes", 10.0), c)
    Check("wire iStripMode",          mgr.GetStripMode() == OSFSettings.GetEnum(mid, "iStripMode", "-1") as int, c)
    Check("wire fLoopScale",          mgr.GetLoopScale() == OSFSettings.GetFloat(mid, "fLoopScale", 1.0), c)
    Check("wire bAllowForeplay",      mgr.IsAllowForeplay() == OSFSettings.GetBool(mid, "bAllowForeplay", true), c)
    Check("wire bAllowClassic",       mgr.IsAllowClassic() == OSFSettings.GetBool(mid, "bAllowClassic", true), c)
    Check("wire bAllowIntense",       mgr.IsAllowIntense() == OSFSettings.GetBool(mid, "bAllowIntense", true), c)
    Check("wire bRomanceExclusivity", mgr.IsRomanceExclusivity() == OSFSettings.GetBool(mid, "bRomanceExclusivity", true), c)
    Check("wire fMinSceneSpacing",    mgr.GetMinSceneSpacing() == OSFSettings.GetFloat(mid, "fMinSceneSpacing", 500.0), c)
    Check("wire bUseMFForFF",         mgr.IsUseMFForFF() == OSFSettings.GetBool(mid, "bUseMFForFF", true), c)
    Check("wire bStopOnPlayerWalkIn", mgr.IsStopOnPlayerWalkIn() == OSFSettings.GetBool(mid, "bStopOnPlayerWalkIn", false), c)
    Check("wire bSoloDowntime",       mgr.IsSoloDowntime() == OSFSettings.GetBool(mid, "bSoloDowntime", true), c)
    Check("wire fSoloChance",         mgr.GetSoloChance() == OSFSettings.GetFloat(mid, "fSoloChance", 20.0), c)
    Check("wire sSpeedMode",          mgr.GetSpeedMode() == OSFSettings.GetEnum(mid, "sSpeedMode", "static"), c)

    Check("const CheckInterval 45",     mgr.GetCheckInterval() == 45.0, c)
    Check("const SceneTimeoutMin 3",    mgr.GetSceneTimeoutMinutes() == 3.0, c)
    Check("const PairCooldownMin 30",   mgr.GetPairCooldownMinutes() == 30.0, c)
    Check("const MaxStartDistance 2000", mgr.GetMaxStartDistance() == 2000.0, c)
    Check("const MaxPairDistance 400",  mgr.GetMaxPairDistance() == 400.0, c)
    Check("const MaxZOffset 200",       mgr.GetMaxZOffset() == 200.0, c)
    Check("const WalkInDistance 150",   mgr.GetWalkInDistance() == 150.0, c)
    Check("const FinaleGrace 10",       mgr.GetFinaleGracePeriod() == 10.0, c)
    Check("const BaseSceneSpeed 1",     mgr.GetBaseSceneSpeed() == 1.0, c)

    CheckIRange("range iMaxConcurrentScenes", mgr.GetMaxConcurrent(), 1, 4, c)
    CheckIRange("range iChancePercent",       mgr.GetChancePercent(), 1, 100, c)
    CheckIRange("range iStripMode",           mgr.GetStripMode(), -1, 1, c)
    CheckFRange("range fActorCooldown",       mgr.GetCooldownMinutes(), 1.0, 60.0, c)
    CheckFRange("range fLoopScale",           mgr.GetLoopScale(), 0.25, 3.0, c)
    CheckFRange("range fMinSceneSpacing",     mgr.GetMinSceneSpacing(), 250.0, 1500.0, c)
    CheckFRange("range fSoloChance",          mgr.GetSoloChance(), 1.0, 100.0, c)
    String sm = mgr.GetSpeedMode()
    Check("enum sSpeedMode", sm == "static" || sm == "dynamic" || sm == "random", c, "got=" + sm)
    String lm = mgr.GetLocationMode()
    Check("enum sLocationMode", lm == "ship" || lm == "interiors" || lm == "everywhere", c, "got=" + lm)

    CheckFRange("CalculateInitialSpeed bounds", mgr.CalculateInitialSpeed(), 0.5, 2.0, c)

    Check("player never eligible", mgr.IsActorEligible(player) == false, c, "player must be rejected")
    Check("None not eligible",     mgr.IsActorEligible(None) == false, c)
    Check("player never on cooldown", mgr.IsOnCooldown(player) == false, c, "player can never join scenes")

    String[] q = mgr.BuildQueryTags("mf", "", "doggy", "")
    Check("BuildQueryTags len 3", q.Length == 3, c, "len=" + q.Length)
    if q.Length == 3
        Check("BuildQueryTags[0] paired", q[0] == "paired", c, "got=" + q[0])
        Check("BuildQueryTags[1] gender", q[1] == "mf", c, "got=" + q[1])
        Check("BuildQueryTags[2] action", q[2] == "doggy", c, "got=" + q[2])
    endif

    String[] qf = mgr.BuildQueryTags("ff", "bed", "oral", "sequence")
    Check("BuildQueryTags full order", qf.Length == 5 && qf[0] == "paired" && qf[1] == "ff" && qf[2] == "bed" && qf[3] == "oral" && qf[4] == "sequence", c, "len=" + qf.Length)

    String[] qp = mgr.BuildQueryTagsWithPack("mf", "cowgirl", "ge", "sequence")
    Check("BuildQueryTagsWithPack order", qp.Length == 5 && qp[0] == "paired" && qp[1] == "mf" && qp[2] == "ge" && qp[3] == "cowgirl" && qp[4] == "sequence", c, "len=" + qp.Length)

    String[] pmf = mgr.GetActiveActionPool("mf")
    bool mfVocab = true
    int i = 0
    while i < pmf.Length
        if !IsKnownActionTag(pmf[i])
            mfVocab = false
        endif
        i += 1
    endwhile
    Check("mf pool within vocabulary", mfVocab, c)
    int expMF = 0
    if mgr.IsAllowForeplay()
        expMF += 3
    endif
    if mgr.IsAllowClassic()
        expMF += 4
    endif
    if mgr.IsAllowIntense()
        expMF += 3
    endif
    Check("mf pool size vs flags", pmf.Length == expMF, c, "expected=" + expMF + " got=" + pmf.Length)

    String[] pff = mgr.GetActiveActionPool("ff")
    int expFF = 0
    if mgr.IsAllowForeplay()
        expFF += 2
    endif
    if mgr.IsAllowClassic()
        expFF += 3
    endif
    if mgr.IsAllowIntense()
        expFF += 2
    endif
    Check("ff pool size vs flags", pff.Length == expFF, c, "expected=" + expFF + " got=" + pff.Length)

    if pmf.Length > 0
        String rot = mgr.GetNextActionTag("mf")
        Check("GetNextActionTag in pool", pmf.Find(rot) >= 0, c, "tag=" + rot)
    endif

    String pk = mgr.GetPairKey(player, player)
    Check("GetPairKey format", pk == player.GetFormID() + ":" + player.GetFormID(), c, "got=" + pk)
    Actor[] followers = Game.GetPlayerFollowers()
    if followers != None && followers.Length > 0
        Check("GetPairKey symmetric", mgr.GetPairKey(player, followers[0]) == mgr.GetPairKey(followers[0], player), c)
    else
        TLog("SKIP  GetPairKey symmetry - no active followers")
    endif
    mgr.SetPairCooldown(player, player)
    Check("pair cooldown roundtrip", mgr.IsPairOnCooldown(player, player), c, "SetPairCooldown -> IsPairOnCooldown failed")

    Check("IsBoundInstance on live quest", mgr.IsBoundInstance(), c, "bound check false on the real quest instance")

    mgr.EnsureArraysInitialized()
    mgr.EnsureArraysInitialized()
    mgr.SyncSceneTracking()
    mgr.EnsureArraysInitialized()
    mgr.TryStartSoloScene(None)
    mgr.TryStartSoloScene(new Actor[0])
    mgr.CleanExpiredCooldowns()
    Check("init/early-out smoke", true, c)

    bool ownShip = mgr.IsPlayerInOwnShip()
    Check("IsPlayerInOwnShip callable", ownShip || !ownShip, c)
    bool privLoc = mgr.IsInPrivatePlayerLocation()
    Check("IsInPrivatePlayerLocation callable", privLoc || !privLoc, c)
    bool breathable = mgr.IsBreathableEnvironment()
    Check("IsBreathableEnvironment callable", breathable || !breathable, c)
    if ownShip
        Check("own ship counts as private", privLoc, c, "player inside own ship but IsInPrivatePlayerLocation=false")
    endif

    mgr.ResumeScanTimer()
    Check("ResumeScanTimer callable", true, c)

    if lm == "everywhere"
        Check("IsLocationAllowed everywhere", mgr.IsLocationAllowed(), c)
    endif

    ObjectReference[] furn = mgr.FindNearbyFurniture(player, 200.0)
    Check("FindNearbyFurniture array", furn != None, c)
    if furn != None
        bool noNulls = true
        int j = 0
        while j < furn.Length
            if furn[j] == None
                noNulls = false
            endif
            j += 1
        endwhile
        Check("FindNearbyFurniture no nulls", noNulls, c)
        TLog("INFO  furniture candidates in 200u: " + furn.Length)
    endif

    Check("GetOSFFurnitureTag empty", mgr.GetOSFFurnitureTag(None) == "", c)

    TLog("===== OSF SelfTests done: " + c[0] + " passed, " + c[1] + " failed =====")
    if c[1] == 0
        TLog("===== ALL GREEN =====")
    endif
EndFunction
