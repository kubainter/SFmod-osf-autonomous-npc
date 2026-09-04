# Lessons Learned — Starfield Modding

Konkretne ustalenia z tego projektu. Nie są to ogólne porady z Internetu, a sprawdzone fakty dotyczące tego workspace.

---

## 1. SFF Body Distributor — restart questa jest niezbędny

**Co odkryliśmy:**
- Skrypt `SFF_BodyDistributorScript` może przestać generować logi po rekompilacji, mimo że quest jest "Running".
- Przyczyną jest `Save Game Caching` — silnik trzyma stary stan skryptu/aliasów w save.

**Rozwiązanie:**
```
StopQuest 08000808
StartQuest 08000808
```
- Wykonaj **po** wczytaniu zapisu, a nie w menu głównym.
- Warto potwierdzić `sqv 08000808`, żeby zobaczyć podpięte skrypty i `Properties`.

**Powiązany anti-pattern:**
[5. Wierzenie, że `StartQuest` resetuje quest](anti_patterns.md#5-wierzenie-ze-startquest-resetuje-quest)

---

## 2. `Game.GetFormFromFile` w timerze zabija wydajność

**Co odkryliśmy:**
- `SFF_BodyDistributorScript` wywoływał `Game.GetFormFromFile` wewnątrz funkcji sprawdzającej frakcje towarzyszy/załogi, wywoływanej co 0.5s.
- Przy wielu NPC w pobliżu generuje znaczący narzut (`script lag`).

**Rozwiązanie:**
- Przenieść formy do `Faction Property ... Auto` i przypisać w `.esm` / `.esp`.
- Alternatywnie pobrać formy raz w `OnInit` / `OnQuestInit` do zmiennych skryptu.

**Powiązany anti-pattern:**
[1. `Game.GetFormFromFile` w gorącym kodzie](anti_patterns.md#1-gamegetformfromfile-w-gorącym-kodzie)

---

## 3. Logi Papyrusa są w UTC

**Co odkryliśmy:**
- Wpisy w `Papyrus.0.log` i `SFF_Distributor.0.log` są datowane UTC.
- Użytkownik lokalnie widzi inny czas. Bez przesunięcia można uznać świeży log za stary.

**Rozwiązanie:**
- Porównuj `LastWriteTimeUtc` plików, nie lokalny.
- Dodaj przesunięcie `+2h` (CEST) lub odpowiednie dla lokalnej strefy.

**Powiązany anti-pattern:**
[7. Pomijanie różnicy UTC vs czas lokalny w logach](anti_patterns.md#7-pomijanie-różnicy-utc-vs-czas-lokalny-w-logach)

---

## 4. Filtruj aktorów w `Reference Alias Conditions`, nie w Papyrusie

**Co odkryliśmy:**
- SFF Body Replacer/Distributor używał Papyrusa do wykluczania gracza, towarzyszy, załogi i już przetworzonych NPC.
- Da się to przenieść do `Reference Alias Conditions` (CTDA) w `.esm`.
- Dzięki temu silnik wrzuca do aliasu już przefiltrowanych kandydatów, a Papyrus dostaje mniejszy zbiór.

**Rozwiązanie:**
- Otwórz `.esm` moda w xEdit/SF1Edit.
- W Quest -> Alias Conditions ustaw warunki wykluczające: `IsPlayer`, `IsPlayerTeammate`, `HasKeyword(SFF_ProcessedKeyword)` itp.
- Następnie uprość Papyrus do minimum.

**Powiązany anti-pattern:**
[3. Filtrowanie aktorów w Papyrusie zamiast w `Reference Alias Conditions`](anti_patterns.md#3-filtrowanie-aktorów-w-papyrusie-zamiast-w-reference-alias-conditions)

---

## 5. `StartTimer` w `OnInit` i `OnQuestInit` jednocześnie

**Co odkryliśmy:**
- `SFF_BodyDistributorScript` uruchamiał `StartTimer(0.5, ScanTimerID)` w obu zdarzeniach.
- W Creation Engine to ryzyko podwójnego timera.

**Rozwiązanie:**
- Uruchamiaj timer tylko w jednym z tych zdarzeń.
- Jeśli logika wymaga obu, sprawdź wewnętrzny stan, czy timer już biegnie.

**Powiązany anti-pattern:**
[2. Podwójny `StartTimer` w `OnInit` i `OnQuestInit`](anti_patterns.md#2-podwójny-starttimer-w-oninit-i-onquestinit)

---

## 6. `plugins.txt` w `AppData\Local\Starfield`

**Co odkryliśmy:**
- Aktywna lista ładowanych modów to `C:\Users\kubai\AppData\Local\Starfield\plugins.txt`.
- Zawiera ESM, ESP i ESL, w tym `SFF Body Replacer.esm`, `SFF Body Distributor.esm` i patche.

**Zastosowanie:**
- Przed debugowaniem zawsze sprawdź kolejność i aktywność modów.
- Przy problemach z ładowaniem plików może być konieczne wyciszenie lub zmiana kolejności.

**Powiązany anti-pattern:**
[10. Korzystanie z „popularnych” rozwiązań internetowych bez weryfikacji](anti_patterns.md#10-korzystanie-z-popularnych-rozwiązań-internetowych-bez-weryfikacji)

---

## 7. Logi modów lądują w `Logs\Script\User\`

**Co odkryliśmy:**
- `SFF_Distributor.0.log` itp. są w `C:\Users\kubai\Documents\My Games\Starfield\Logs\Script\User\`.
- Główny log Papyrusa to `Papyrus.0.log` w `Logs\Script\`.
- SFSE log konsoli to `G:\Starfield\Data\SFSE\Plugins\sfse_plugin_console.log`.

**Zastosowanie:**
- Debug zawsze zaczynaj od tych trzech lokalizacji.
- Sprawdzaj czas modyfikacji (UTC) i rozmiar pliku.

**Powiązany anti-pattern:**
[6. Brak weryfikacji po zmianie skryptu](anti_patterns.md#6-brak-weryfikacji-po-zmianie-skryptu)

---

## 8. Modyfikujemy tylko pliki modów, bazę gry zostawiamy

**Co odkryliśmy:**
- `Starfield.esm` i bazowe skrypty są poza zasięgiem edycji.
- Jeśli potrzebna jest zmiana, tworzymy dedykowany patch `.esp`/`.esm`.

**Zastosowanie:**
- Zawsze sprawdź właściciela pliku: czy to `Starfield.esm`, `SFF_*.esm`, czy twój własny `src\*`.

**Powiązany anti-pattern:**
[4. Modyfikacja bazowych plików gry bez patcha](anti_patterns.md#4-modyfikacja-bazowych-plików-gry-bez-patcha)

---

## 9. Kompilacja Papyrusa wymaga poprawnych ścieżek

**Co odkryliśmy:**
- Kompilator znajduje się w `Tools\Papyrus Compiler\PapyrusCompiler.exe`.
- Użytkownik ma uprawnienia do jego uruchamiania przez `.devin\config.local.json`.
- Ścieżki w Papyrus Project muszą wskazywać `Data\Scripts\Source` i `Data\Scripts`.

**Zastosowanie:**
- Przed kompilacją upewnij się, że `.ppj` ma właściwe importy i output.
- Sprawdź, czy wygenerowany `.pex` trafia do odpowiedniego katalogu modu, a nie nadpisuje bazowy `*.pex`.
- Pełna instrukcja z gotowymi poleceniami: `.devin/papyrus_build.md`.

**Powiązany anti-pattern:**
[9. Kompilowanie bez sprawdzenia ścieżek i zależności](anti_patterns.md#9-kompilowanie-bez-sprawdzenia-ścieżek-i-zależności)

---

## 10. Format archiwum BA2 jest ważniejszy niż rozmiar tekstur (DirectStorage)

**Co odkryliśmy:**
- Pakowanie tekstur do Starfielda narzędziem `BSArch` z Fallouta 4 tworzy archiwa BA2v2 (DX10), które wyłączają sprzętowy streaming DirectStorage i wymuszają powolne dekodowanie przez CPU (spadek z 35 do 12 FPS).
- Zawsze należy używać oficjalnego `Archive2.exe` z flagami `-format=DDS -compression=Default`.

**Powiązany anti-pattern:**
[10. Korzystanie z „popularnych” rozwiązań internetowych bez weryfikacji](anti_patterns.md#10-korzystanie-z-popularnych-rozwiązań-internetowych-bez-weryfikacji)

---

## 11. Kluczowe znaczenie flagi `-root` w `Archive2.exe`

**Co odkryliśmy:**
- Wskazanie w `-root` samego folderu `textures/` powoduje obcięcie tego członu w tablicy nazw archiwum, przez co silnik szuka plików pod `actors/...` zamiast `textures/actors/...` i gubi przypisanie materiałów do siatek 3D (brak tekstur / fioletowe siatki).
- Flaga `-root` musi zawsze wskazywać folder **nadrzędny** wobec `textures/` (np. `-root="G:\Starfield\.tmp\sfm01"`).

---

## 12. Selektywna kompresja modów na ciała (Body Replacers)

**Co odkryliśmy:**
- Bezpiecznej konwersji do `BC7_UNORM_SRGB` z pełnym łańcuchem mipmap (`-m 0`) podlegają **wyłącznie mapy koloru skóry** (`_skX_color.dds`).
- Mapy `normal`, `ao`, `rough`, `mask`, `transmissive` muszą pozostać nienaruszone w swoich oryginalnych formatach (DX9/BC4/BC5), aby nie uszkodzić warstw PBR i kanałów danych.

**Powiązany anti-pattern:**
[13. Globalna kompresja wszystkich typów map jednym formatem](anti_patterns.md#13-globalna-kompresja-wszystkich-typów-map-jednym-formatem--f-bc7_unorm-dla-wszystkiego)

---

## 13. Mechanizm VRAM Overcommit / PCIe Thrashing po wyjściu z menu

**Co odkryliśmy:**
- Chwilowy spadek klatkażu do ~7–10 FPS po wyjściu z menu, który po kilku sekundach samoistnie wraca do 30+ FPS, to podręcznikowy objaw przepełnienia 8 GB VRAM w momencie alokacji buforów interfejsu/podglądu 3D i awaryjnej ewizji zasobów do pamięci RAM komputera przez szynę PCIe.
- Rozwiązaniem jest odzyskanie bazowego marginesu VRAM (zejście do ~6.0–6.5 GB w gęstych lokacjach miejskich jak Neon), co zapobiega dobijaniu do 100% alokacji przy pauzie.

**Powiązany anti-pattern:**
[11. Stosowanie automatycznych "Memory Cleanerów"](anti_patterns.md#11-stosowanie-automatycznych-memory-cleanerów-memoryfixesdll--setprocessworkingsetsize)

---

## 14. Weryfikacja spójności presetów w `StarfieldPrefs.ini`

**Co odkryliśmy:**
- Uszkodzone lub wymuszone wartości parametrów (np. tier `6` w `uVolumetricLighting`, `uReflections`, `uShadows`) potrafią zignorować globalny profil jakości i drastycznie przeciążyć bufory oświetlenia w lokacjach takich jak Neon.
- Wartości muszą być utrzymywane na stabilnym poziomie `1` (Medium) lub `2` (High).
---
## 15. Patch REFR-owy na obcym CELL nie wymaga rekordow CELL ani XOWN w patchu
**Co odkrylismy (2026-08-24, StroudPremiumCompanionPatch.esp):**
- Patch usuwajacy tylko `XOWN` (ownership) z 28 REFR-ow lozek w Stroud Premium Edition dziala jako same REFR-y z prefiksem FD, bez rekordow CELL - silnik sam laczy je po FormID z rekordem CELL z mastera.
- Struktura GRUP (typy 0/2/3/6/9) zostala skopiowana 1:1 ze zrodlowego ESM i jest poprawna; etykiety grup typu `68560002` to wewn��trzny format CK, nie referencja mastera.
- Walidacja: wszystkie 28 REFR identyczne ze zrodlem oprocz usunietego XOWN; ONAM pokrywa sie 1:1 ze zbiorem REFR.
**Zastrzezenia do sprawdzenia przed wlaczeniem:**
- `HEDR` ma 8 B zamiast 12 B u wszystkich dzialajacych pluginow porownawczych (brak pola nextObjectID) - do potwierdzenia w grze/xEdit.
- Flaga ESM (0x001) jest ustawiona; kombinacja 0x481 (ESM+Localized+0x400) + rozszerzenie .esp = wzorzec medium plugin, identyczny jak w masterze stroudpremiumedition.esm (tez 0x481) - POPRAWNE.
**Powiazane narzedzie:** `.devin/analyze_stroud_companion_patch.py` (walidacja patch vs zrodlo).

---

## 16. Nowe zmienne instancyjne w quest script = None na istniejącym save'ie (KRYTYCZNE)

**Co odkryliśmy (2026-08-26, OSF_AutonomousManagerScript):**
- Dodanie nowej zmiennej instancyjnej (np. `bool[] sceneFinaleTriggered`) do skryptu questa, który już działa na save'ie użytkownika, powoduje że Papyrus ładuje tę zmienną jako `None` (nie jako pustą tablicę).
- Każda operacja `.Length`, `.Add()`, `.Remove()` na `None` generuje błąd "Cannot call Length() on a None variable" lub "Cannot add elements to a None array".
- Jeśli błąd występuje w pętli `while`, pętla się **nie przerywa** — Papyrus loguje błąd i kontynuuje iterację. Warunek `0 < N` pozostaje true forever → **nieskończona pętla błędów** → log rośnie o 100+ MB w minuty.

**Przyczyna:**
- Papyrus nie inicjalizuje nowych zmiennych instancyjnych przy ładowaniu starego save'a.
- `new bool[0]` w deklaracji zmiennej działa tylko przy `OnQuestInit` (nowy quest), nie przy `OnPlayerLoadGame` (istniejący save).

**Rozwiązanie — Version Migration Pattern (Agy):**
```papyrus
int Property CURRENT_VERSION = 2 AutoReadOnly
int Property iInstalledVersion = 0 Auto

Event Actor.OnPlayerLoadGame(Actor akSender)
    ; Migration — reset all state if script was updated
    if iInstalledVersion < CURRENT_VERSION
        activeSceneHandles = new int[0]
        sceneFinaleTriggered = new bool[0]
        ; ... wszystkie array
        iInstalledVersion = CURRENT_VERSION
    endif
    EnsureArraysInitialized()  ; centralna funkcja None-check
    ...
EndEvent

Function EnsureArraysInitialized()
    if activeSceneHandles == None
        activeSceneHandles = new int[0]
    endif
    ; ... wszystkie array
EndFunction
```

**Każda nowa zmienna instancyjna = bump CURRENT_VERSION + dodaj do migracji.**

---

## 17. Pętla `while` na None array = stuck thread baked w save (KRYTYCZNE)

**Co odkryliśmy (2026-08-26, OSF_AutonomousManagerScript):**
- Jeśli pętla `while arrA.Length < arrB.Length` zapętli się na `None` array, Papyrus **nie przerywa pętli** — loguje błąd i skacze na początek pętli.
- Jeśli save zostanie zapisany (auto-save, quicksave) podczas tej pętli, **zserializowany wątek zostaje wbaked w save**.
- Przy każdym kolejnym ładowaniu tego save'a, Papyrus **wznawia stuck thread** ze starego bytecode'u, ignorując nowy .pex na dysku.
- `StopQuest`/`StartQuest` **NIE zabija** działających wątków VM — zatrzymuje tylko quest stages/aliases.
- Nie istnieje żadne API Papyrus do killowania wątków (`Thread.Abort()` nie istnieje).
- **Save jest nie do naprawienia** — jedynym rozwiązaniem jest załadowanie save'a sprzed buga.

**Rozwiązanie — ZAWSZE używaj safety counter w pętlach while:**
```papyrus
; ZŁE — może się zapętlić na None:
while arrA.Length < arrB.Length
    arrA.Add(false, 1)
endwhile

; DOBRE — safety counter + None check:
int safety = 0
while arrA != None && arrB != None && arrA.Length < arrB.Length && safety < 50
    arrA.Add(false, 1)
    safety += 1
endwhile

; LEPSZE — pojedyncze Add zamiast pętli:
if arrA != None && arrB != None && arrA.Length < arrB.Length
    int needed = arrB.Length - arrA.Length
    arrA.Add(false, needed)
endif
```

**Zasada: NIGDY nie pisz nieograniczonej pętli `while` na dynamicznych właściwościach. Zawsze dodaj safety counter.**

---

## 18. Save Game Caching — nowy .pex nie zastępuje starego bytecode'u w save

**Co odkryliśmy (2026-08-26):**
- Papyrus VM czyta .pex z dysku, ALE zserializowane wątki w save'ie używają **cache'owanych referencji z ich stack frame**.
- Aktualizacja zmiennej instancyjnej (`sceneFinaleTriggered = new bool[0]`) w `OnPlayerLoadGame` **nie wpływa** na stuck thread — on używa swojej lokalnej, cache'owanej referencji `None`.
- `StopQuest` + `StartQuest` tworzy nową instancję questa, ale **nie zabiva starych wątków** które już działają w VM task queue.
- Jedynym sposobem na pozbycie się stuck thread jest **załadowanie save'a sprzed buga** (save bez zserializowanego stuck threada).

**Procedura aktualizacji skryptu questa na istniejącym save'ie:**
1. Zbuduj nowy .pex z fixem
2. Załaduj save sprzed buga (nie ten z stuck thread)
3. `OnPlayerLoadGame` odpali migration pattern → zresetuje array
4. Zapisz nowy save (`save CleanState01`)
5. Ten save jest czysty — można go używać

**NIGDY nie testuj bugged skryptu na głównym save'ie. Zawsze używaj kopii/save'a testowego.**

---

## 19. Kolejność inicjalizacji w OnPlayerLoadGame ma znaczenie

**Co odkryliśmy (2026-08-26):**
- Array None-checki muszą być **PRZED** wywołaniem jakichkolwiek funkcji które używają tych array (`AuditActiveScenes`, `EnforceSceneTimeouts`, sync loops).
- Timery zapisane w save'ie mogą odpalić się **przed lub równolegle z `OnPlayerLoadGame`** — jeśli timer wywoła `AuditActiveScenes()` zanim array zostanie zinit, crash.
- `RegisterOSFCallbacks()` może wywołać callback który używa array — musi być po init.

**Właściwa kolejność:**
```papyrus
Event Actor.OnPlayerLoadGame(Actor akSender)
    ; 1. Version migration (reset arrays)
    ; 2. EnsureArraysInitialized() (None checks)
    ; 3. RegisterOSFCallbacks() (rejestracja callbacków)
    ; 4. InitKeywords() (ładowanie form)
    ; 5. AuditActiveScenes() (używa array)
    ; 6. StartTimer() (odpala timery)
EndEvent
```

---

## 20. Papyrus VM nie przerywa pętli przy błędzie — tylko loguje i kontynuuje

**Co odkryliśmy (2026-08-26):**
- W przeciwieństwie do większości języków, Papyrus VM **nie rzuca wyjątku** przy błędzie typu "Cannot add elements to a None array".
- Zamiast tego: loguje błąd do `Papyrus.0.log` i **przechodzi do następnej instrukcji** (w pętli = skok na początek).
- To oznacza że błędna pętla `while` może wygenerować **setki tysięcy błędów** w sekundy, zapychając log (206 MB w kilka minut).
- Papyrus nie ma limitu iteracji pętli — pętla działa aż do przepełnienia stosu lub timeout'u klatki.

**Wniosek: KAŻDA pętla `while` w Papyrus musi mieć safety counter. Nie ma wyjątków.**

---

## 21. InPlaceMode=ON na paired scenach = natychmiastowy abort (OSF)

**Co odkryliśmy (2026-08-26, OSF_Autonomous):**
- `InPlaceMode = OSF.ON()` na paired scenach (2 aktorów) powoduje że OSF pomija wyrównanie pozycji aktorów.
- Aktorzy pozostają w swoich oryginalnych pozycjach → odległość między root bones przekracza threshold → OSF natychmiast kończy scenę (2 sekundy).
- `InPlaceMode = ON` jest przeznaczone **tylko dla solo scen** (1 aktor, brak potrzeby wyrównania).

**Rozwiązanie:**
- Paired sceny: zawsze `InPlaceMode = OSF.OFF()` (zarówno standing jak i sitting).
- Solo sceny: `InPlaceMode = OSF.ON()` (aktor zostaje w miejscu).

---

## 22. Skaner NPC — zasięg 4000 units = 20 sekund lag (OSF Autonomous)

**Co odkryliśmy (2026-08-26):**
- `FindAllReferencesWithKeyword(keyword, 4000.0)` na 267 NPC generuje 267 iteracji `IsActorEligible()` w Papyrus VM.
- Papyrus VM ma per-frame instruction budget → pętla rozciąga się na ~20 sekund.
- 20 sekund blokuje inne skrypty (quest AI, dialogue, combat) → thread starvation.

**Rozwiązanie — dynamiczny scan range:**
```papyrus
float scanRange = GetMaxStartDistance() + 200.0  ; np. 2000 + 200 = 2200
; C++ filtruje NPC przed utworzeniem tablicy Papyrus → -70% iteracji
ObjectReference[] nearby = player.FindAllReferencesWithKeyword(kw, scanRange)
```
- 4000u → 267 NPC → 20s | 2200u → ~60 NPC → <1.5s

---

## 23. Companion follow AI = 30-100 units od gracza (OSF Autonomous)

**Co odkryliśmy (2026-08-26):**
- Starfield companion follow AI trzyma NPC w promieniu 30-100 units (~0.5-1.4m) od gracza.
- MIN distance guard (nawet 50 units) blokuje 100% scen na statku/w budynku — companions są ZAWSZE blisko.
- MIN guard jest kontrproduktywny dla głównego use case (obserwowanie companions).

**Rozwiązanie:**
- Usunąć MIN distance guard całkowicie.
- Zachować tylko MAX distance (2000 units ~28m) — chroni przed scenami których gracz nie widzi.
- OSF ustawia `SetGhost(true)` na aktorach → zero ryzyka kolizji z graczem.

---

## 24. OSF pack role conventions — GE vs SnuSnu (OSF Autonomous)

**Co odkryliśmy (2026-08-26):**
- GE (381 scen): `roles = ['m', 'f']` → actors[0]=male, actors[1]=female (standard).
- SnuSnu (7 scen): `roles = ['f', 'm']` → actors[0]=female, actors[1]=male (femdom — female z strapon).
- OSF przypisuje role **ściśle po indeksie tablicy** — actors[0] → roles[0].
- Przekazanie [male, female] do SnuSnu → male w roli female → OSF zakłada strapon na mężczyźnie!

**Rozwiązanie — tag-based pack partitioning:**
- Query z tagiem `ge`: `['paired','mf','ge','cowgirl']` → tylko GE sceny → `standardOrder [m, f]`.
- Query z tagiem `snusnu`: `['paired','mf','snusnu','cowgirl']` → tylko SnuSnu → `femdomOrder [f, m]`.
- OSF używa conjunctive subset matching — SnuSnu nie ma tagu `ge`, więc nie matchuje query z `ge`.

**NIGDY nie modyfikuj plików innych autorów** (snusnufield.osf.json). Rozwiązuj w swoim skrypcie.

---

## 25. Nexus release — catch-all tiery dla nieznanych packów (OSF Autonomous)

**Co odkryliśmy (2026-08-26):**
- Hardkodowanie tagów `ge`/`snusnu` tworzy hard dependency — jeśli użytkownik ma inny pack, mod nie znajdzie scen.
- Dla release na Nexus: GE i SnuSnu to **soft dependencies** — mod działa bez nich.

**Rozwiązanie — 3-tier per query:**
1. Pack-specific (GE z `ge` tag, SnuSnu z `snusnu` tag) — poprawne role.
2. Catch-all (bez pack tagu, `standardOrder`) — dla dowolnego innego packa.
3. Standard convention: 99%+ packów używa `Role 0 = Male`.

**Struktura zależności dla Nexus:**
- Hard: `Starfield.esm`, `OSF Core`, SFSE.
- Optional/Recommended: GE Animation Pack, SnuSnu, OSFUI.
- Zero vanilla record overrides.
