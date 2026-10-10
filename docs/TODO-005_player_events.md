# TODO-005 — Player-involved events ("Snu Snu Light" / SSLite)

Powiązane: [TODO.md](TODO.md) → TODO-005

## Źródło

Sugestia użytkownika (cytat):

> "I'd really like to see the Player involved in this. If player is generally
> idle, then a Snu Snu Light event may occur that includes the player and a
> fellow NPC (emphasis on SSLite for minimal impact on gameplay). Adjustable
> by the slider set from 0% chance of happening to 100% and level of affinity."

## Werdykt

**Wykonalne** w obrębie istniejących zależności (OSF + OSFUI + czysty Papyrus).
Szacunek: ~150–250 linii w `OSF_AutonomousManagerScript.psc` + 3 ustawienia
w `osf.autonomous.json`. Brak nowych twardych wymagań.

## Ograniczenia (bridge-framework)

- Mod to bridge na OSF: bez własnych DLL, bez hooków inputu, bez zależności
  od innych modów / konkretnych animation packów / questów z GlobalVariables.
- **Nie używać `OSFSeduce.*`** (`PlayTagPlayerTop`, `RandomPlayerTop` itd.) —
  te helpery wymagają działającego questa Seduce z wypełnionymi GlobalVariables
  = hard-requirement. `OSFSeduce` traktować wyłącznie jako *dowód konceptu*:
  gracz może być zwykłym elementem tablicy aktorów w `OSF.StartSceneByTags` /
  `OSF.StartSceneAtAnchor` (własne przykłady w `Data\Scripts\Source\OSFSeduce.psc`).
- Każda nowa ścieżka kończy się graceful skip (log + reschedule) — identycznie
  jak nieudane sceny NPC (`handle <= 0`).
- Wszystko opt-in: default 0% szansy = feature wyłączony dla istniejących
  użytkowników. Zero nowych Property → brak ryzyka dla save'ów.

## Mechanika obecna, którą feature wykorzysta

- Skaner `OnTimer` co 45 s — naturalne miejsce na roll player-event.
- `eligible[]` — gotowa lista przefiltrowanych NPC (child/robot/sit/combat/…).
- `activeSceneHandles` + `sceneActorA`/`sceneActorB` — tracking i cleanup
  działają też dla scen z graczem (pause menu, combat, location change
  już je zatrzymują).
- `GetRelationshipRank(player)` — już używane (Romance Exclusivity, rank ≥ 3).
- `GetPairKey`/`SetPairCooldown` — działa z FormID gracza.
- `UnequipStuckAttachments` — już ma guard `akActor == Game.GetPlayer()`.
- `SceneOptions.LockPlayerMode` / `PlayerControlMode` — pola dokładnie pod
  ten przypadek (lock inputu + prawo gracza do abort/advance).

## Synergia

Romance Exclusivity Guard wyklucza romansowane companiony (relRank ≥ 3)
ze scen NPC-NPC. Player event **naturalnie domyka tę lukę** — companion
z wysokim affinity nie bawi się z innymi, tylko podchodzi do gracza.
To chyba sens "level of affinity" z sugestii.

## Projekt

### 1. Wykrywanie idle gracza

Papyrus nie ma input events → proxy przez deltę pozycji między tickami
skanera (45 s) + twarde guardy stanu. False-positive kończy się sceną,
którą gracz przerywa jednym klawiszem (`PlayerControlMode=ON`).

Stan (session vars, NIE Property):

```papyrus
float fIdlePosX = 0.0
float fIdlePosY = 0.0
float fIdlePosZ = 0.0
int   iIdleTicks = 0
```

```papyrus
bool Function IsPlayerIdle()
    Actor player = Game.GetPlayer()
    if player == None
        iIdleTicks = 0
        return false
    endif

    ; Twarde guardy — nigdy w dialogu / scenie gry / menu / meblu / boostpacku
    if Game.IsPlayerInDialogue() || player.IsInScene() || Utility.IsGameMenuPaused()
        iIdleTicks = 0
        return false
    endif
    if player.IsWeaponDrawn() || player.IsFlying() || player.GetFurnitureUsing() != None
        iIdleTicks = 0
        return false
    endif
    if player.GetSitState() != 0 || player.GetSleepState() != 0
        iIdleTicks = 0
        return false
    endif
    if player.IsSneaking() || player.IsSprinting() || player.IsRunning()
        iIdleTicks = 0
        return false
    endif
    if OSF.IsPlaying(player)
        iIdleTicks = 0
        return false
    endif

    ; Delta pozycji między tickami (45 s)
    float px = player.GetPositionX()
    float py = player.GetPositionY()
    float pz = player.GetPositionZ()
    float d2 = (px - fIdlePosX) * (px - fIdlePosX) + (py - fIdlePosY) * (py - fIdlePosY) + (pz - fIdlePosZ) * (pz - fIdlePosZ)
    fIdlePosX = px
    fIdlePosY = py
    fIdlePosZ = pz
    if d2 > 22500.0   ; ~150 u — przesunął się, nie jest idle
        iIdleTicks = 0
        return false
    endif

    iIdleTicks += 1
    return iIdleTicks >= 2   ; ~90 s bezruchu (2 ticki × 45 s)
EndFunction
```

Resetować `iIdleTicks = 0` także w `OnLocationChange` i `OnPlayerLoadGame`
(pozycja po load/fast travel nie ma sensu jako baseline).

### 2. Punkt integracji w OnTimer

Po zbudowaniu `eligible[]` (po logu `"Eligible actors: ..."`), **przed**
checkiem `eligible.Length < 2` — player event potrzebuje tylko 1 NPC:

```papyrus
    Log("Eligible actors: " + eligible.Length + "/" + candidates.Length)

    ; --- TODO-005: player event roll (przed wymogiem 2 eligible) ---
    if GetPlayerChancePercent() > 0 && activeSceneHandles.Length < GetMaxConcurrent() && IsPlayerIdle()
        int proll = Utility.RandomInt(1, 100)
        if proll <= GetPlayerChancePercent()
            Actor partner = PickPlayerScenePartner(eligible)
            if partner != None
                TryStartPlayerScene(partner)
            endif
        else
            Log("Player event skipped — chance roll failed (" + proll + " > " + GetPlayerChancePercent() + ")")
        endif
    endif

    ; Fewer than 2 eligible actors → only solo scenes are possible
    if eligible.Length < 2
        ...
```

Decyzja: player event zajmuje slot `iMaxConcurrentScenes` (liczony do limitu,
roll **przed** falą par) — prosty i spójny z istniejącymi limitami.

### 3. Dobór partnera

```papyrus
Actor Function PickPlayerScenePartner(Actor[] eligible)
    ; ≤10 losowań jak w parowaniu; wymogi:
    ;   - relRank >= GetPlayerMinAffinityRank()  (0 = bez gate'u)
    ;   - dystans do gracza <= ~600 u (nie snapować partnera z drugiego końca statku)
    ;   - płeć: male player + male NPC = skip (brak MM packów — jak TryStartScene)
    ;   - !IsPairOnCooldown(player, npc)
    ; Zwraca pierwszego pasującego albo None.
EndFunction
```

Affinity gate: `partner.GetRelationshipRank(Game.GetPlayer()) >= threshold` —
zero form loading, już używane w kodzie. `COM_AffinityLevel` AV jest opcją
na przyszłość (base-game ActorValue z `Starfield.esm`, bezpieczny
`GetFormFromFile` + None-guard jak reszta w `InitKeywords()`), ale relRank
wystarcza. Uwaga: generic crew ma relRank 0 → gate ≥ 1 de facto ogranicza
feature do companionów/rekrutów (zgodne z intencją "level of affinity").

### 4. TryStartPlayerScene (zarys)

```papyrus
Function TryStartPlayerScene(Actor akNPC)
    Actor player = Game.GetPlayer()
    if akNPC == None || player == None
        return
    endif
    if akNPC.GetDistance(player as ObjectReference) > 600.0
        Log("Player scene skipped — NPC too far")
        return
    endif

    ActorBase baseP = player.GetLeveledActorBase()
    ActorBase baseN = akNPC.GetLeveledActorBase()
    if baseP == None || baseN == None
        return
    endif
    int sexP = baseP.GetSex()
    int sexN = baseN.GetSex()
    if sexP == 0 && sexN == 0
        Log("Player scene skipped — male/male not supported")
        return
    endif
    string genderTag = "ff"
    if sexP != sexN
        genderTag = "mf"
    endif

    ; Kolejność ról: GE [m,f], snusnu [f,m] — gracz wstawiany wg płci
    Actor[] standardOrder = new Actor[2]  ; [male, female]
    Actor[] femdomOrder   = new Actor[2]  ; [female, male]
    if genderTag == "mf"
        if sexP == 0
            standardOrder[0] = player
            standardOrder[1] = akNPC
            femdomOrder[0]   = akNPC
            femdomOrder[1]   = player
        else
            standardOrder[0] = akNPC
            standardOrder[1] = player
            femdomOrder[0]   = player
            femdomOrder[1]   = akNPC
        endif
    else
        standardOrder[0] = akNPC
        standardOrder[1] = player
        femdomOrder[0]   = akNPC
        femdomOrder[1]   = player
    endif

    OSFTypes:SceneOptions opts = new OSFTypes:SceneOptions
    opts.LockPlayerMode    = OSF.ON()    ; lock inputu na czas sceny
    opts.PlayerControlMode = OSF.ON()    ; KLUCZOWE: gracz może przerwać/advance (consent hatch)
    opts.Camera            = ""          ; inherit pack default (lub "thirdperson_hold")
    opts.FadeMode          = OSF.OFF()
    opts.InPlaceMode       = OSF.OFF()
    opts.StripMode         = OSF.OFF()   ; LITE: aktorzy zostają ubrani
    opts.LoopScale         = GetPlayerLoopScale()  ; np. 0.5 — krótsze sceny

    ; LITE pool: foreplay najpierw, fallback do pełnej puli GetActiveActionPool
    ; (pack-agnostic — brak tagu "kissing" w packu ≠ martwy feature).
    ; Tier chain jak w TryStartScene: pack-partitioned + catch-all,
    ; pozycje "standing"/"floor" (v1 bez anchorów mebli).
    int handle = OSF.StartSceneByTags(standardOrder, BuildQueryTagsWithPack(genderTag, "kissing", "ge", "", "standing"), opts)
    ; ... kolejne fallbacki (oral → pełna pula → snusnu femdomOrder → catch-all)

    if handle > 0
        activeSceneHandles.Add(handle, 1)
        sceneStartTimes.Add(Utility.GetCurrentRealTime(), 1)
        sceneActorA.Add(player, 1)
        sceneActorB.Add(akNPC, 1)
        SetPairCooldown(player, akNPC)
        StartSceneTimeoutTimer()
        Debug.Notification((akNPC as ObjectReference).GetDisplayName() + " approaches you...")
        Log("Player scene started — handle=" + handle + " npc=" + akNPC + " gender=" + genderTag)
    endif
EndFunction
```

### 5. Korekty istniejącego kodu (wymagane)

- `AuditActiveScenes()` — walk-in interrupt mierzy dystans uczestnik→gracz
  (~linia 2229): przy graczu jako uczestniku dystans = 0 i scena zawsze umrze,
  gdy `bStopOnPlayerWalkIn=true`. Dodać `p != Game.GetPlayer()` do warunku.
- `ApplyCooldownToActor()` (~linia 2418) — `p.EvaluatePackage()` tylko dla NPC
  (`if p != Game.GetPlayer()`); `OSF.ClearAnchor(p)` zostaje (unpin roota).
  `UnequipStuckAttachments` już ma guard gracza.
- Reszta lifecycle (PauseMenu, combat, ship events, location change)
  działa bez zmian — scena z graczem jest w tych samych tablicach.

### 6. Ustawienia OSFUI (`osf.autonomous.json`, grupa "romance" lub nowa "player")

```json
{
  "key": "iPlayerChancePercent",
  "label": "Player Event Chance (%)",
  "type": "int", "min": 0, "max": 100, "default": 0,
  "hint": "Chance per scan that a nearby NPC starts a light scene with an idle player. 0 = disabled."
},
{
  "key": "sPlayerMinAffinity",
  "label": "Player Event Min Relationship",
  "type": "enum",
  "options": ["any", "friend", "ally", "romanced"],
  "optionLabels": ["Any NPC", "Friend (rank 1+)", "Ally (rank 2+)", "Romanced (rank 3+)"],
  "default": "romanced",
  "hint": "Minimum relationship rank for NPCs initiating player scenes. Generic crew has rank 0."
},
{
  "key": "fPlayerLoopScale",
  "label": "Player Scene Duration Scale",
  "type": "float", "min": 0.25, "max": 1.0, "step": 0.25, "default": 0.5,
  "hint": "Player scenes run shorter (SSLite). 0.5 = half the loops."
}
```

Reader'y z fallbackami zgodnymi z defaultami — `test_papyrus_static.py`
pilnuje parity kluczy + fallbacków + typów `OSFSettings.Get*`. `sPlayerMinAffinity`
czytać przez `OSFSettings.GetEnum` i mapować na threshold (any=0, friend=1,
ally=2, romanced=3).

**Synchronizować obie kopie:** `src/osf.autonomous.json` i
`release/Data/SFSE/Plugins/OSFUI/settings/osf.autonomous.json`.

## Edge cases

- Męski gracz + męski NPC → skip (brak MM packów, jak w `TryStartScene`).
- Gracz siedzi / śpi / używa workbencha → guardy `GetSitState`,
  `GetSleepState`, `GetFurnitureUsing` blokują (pilot seat dodatkowo
  chroniony przez `GetSpaceship()` w OnTimer).
- Gracz wchodzi do walki w trakcie sceny → `OnCombatStateChanged` +
  `AuditActiveScenes` (participant `IsInCombat`) już zatrzymują.
- Save w trakcie sceny → PauseMenu handler zatrzymuje sceny przed dialogiem
  save (scena z graczem jest objęta).
- Ghost scene z graczem → cleanup przez `sceneActorA` (player) —
  `ApplyCooldownToActor` z guardem `EvaluatePackage`.
- Companion "wants to talk" (COM quest) może czekać, aż NPC zwolni się
  ze sceny — questy czekają na dostępność, opóźnienie nie konflikt.
- Idle = heurystyka (brak input API): gracz czytający in-game menu książkowe
  itp. — `Utility.IsGameMenuPaused()` + `Game.IsMenuControlsEnabled()`
  w guardach jako safety (StartTimer to game-time → w pauzie nie tyka).

## Otwarte pytania

1. Anchor-first dla scen z graczem (łóżko/kanapa obok idle gracza)?
   v1: standing/floor only — anchor w v2 po udowodnieniu stabilności.
2. Affinity reward po scenie (jak `OSFSeduceManager` → `AddAffinity` na cue
   "orgasm")? OPCJONALNE, v2 — czytanie COM globals; bez tego feature stoi sam.
3. Heads-up: `Debug.Notification` vs cichy start. Rekomendacja: notification
   (gracz wie, że to feature, a nie bug animacji).
4. `iPlayerIdleTicks` jako ustawienie (1–4 ticki)? v1: stała 2 (~90 s).

## Plan implementacji

1. Settings JSON (obie kopie) + reader'y + dopiąć klucze w `OSF_SelfTests.psc`
   (parity test czyta wszystkie zadeklarowane klucze).
2. `IsPlayerIdle()` + resety w `OnLocationChange`/`OnPlayerLoadGame`.
3. `PickPlayerScenePartner()` + `TryStartPlayerScene()` + roll w `OnTimer`.
4. Korekty walk-in / cooldown guardów (punkt 5).
5. Kompilacja przez `deploy_selftest.ps1` pattern + `run_tests.ps1`.
6. Test w grze: `iPlayerChancePercent=100`, stać bezczynnie ~90 s na statku
   obok companiona rank ≥ 3 → event; abort inputem; regresja scen NPC
   przy `iPlayerChancePercent=0`.

## Weryfikacja w grze

- Log `OSF_Autonomous.log`: `"Player event skipped — chance roll failed"`,
  `"Player scene started — handle=…"`, `"Player event — player not idle"`.
- Abort test: wyjść ze sceny inputem (`PlayerControlMode=ON`).
- Ghost test: quit w trakcie sceny z graczem → po load brak stuck gear/
  anchor na graczu (cleanup przez tracked actors).
