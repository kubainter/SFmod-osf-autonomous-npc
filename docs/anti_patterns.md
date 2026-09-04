# Antywzorce — Starfield / Papyrus / SFSE

Niepoprawne, ale często spotykane w Internecie podejścia do modowania Bethesdy. W tym projekcie ich unikamy.

---

## 1. `Game.GetFormFromFile` w gorącym kodzie

**Źle:**
```papyrus
Function IsCompanionOrCrew(Actor akTarget)
    Faction CurrentCompanionFaction = Game.GetFormFromFile(0x00023C01, "Starfield.esm") as Faction
    if akTarget.IsInFaction(CurrentCompanionFaction)
        ; ...
    endIf
EndFunction
```

**Dlaczego źle:**
`GetFormFromFile` wymusza wyszukiwanie w tabeli form przy każdym wywołaniu. Jeśli funkcja leci co 0.5s w timerze, produkuje `script lag`.

**Poprawnie:**
- Zdefiniuj `Faction Property CurrentCompanionFaction Auto` i przypisz w `.esm` / `.esp`.
- Albo pobierz formy raz w `OnInit()` / `OnQuestInit()` do zmiennych skryptu.

---

## 2. Podwójny `StartTimer` w `OnInit` i `OnQuestInit`

**Źle:**
```papyrus
Event OnInit()
    StartTimer(0.5, ScanTimerID)
EndEvent

Event OnQuestInit()
    StartTimer(0.5, ScanTimerID)
EndEvent
```

**Dlaczego źle:**
Silnik Bethesdy może odpalić oba zdarzenia i zarejestrować dwa równoległe timery. Skrypt wykonuje się podwójnie.

**Poprawnie:**
- Uruchamiaj timer w jednym zdarzeniu.
- Albo sprawdź, czy timer już działa, zanim ponownie wywołasz `StartTimer`.

---

## 3. Filtrowanie aktorów w Papyrusie zamiast w `Reference Alias Conditions`

**Źle:**
W Papyrusie co pół sekundy sprawdzać `akActor != Player`, `!akActor.IsPlayerTeammate()`, `!akActor.HasKeyword(SFF_ProcessedKeyword)` itp.

**Dlaczego źle:**
Papyrus robi to dla każdego aktora w pobliżu. Przy dużej liczbie NPC generuje się `Papyrus spam`.

**Poprawnie:**
- Przenieś te warunki do `Reference Alias Conditions` (CTDA) w Quest / Alias w pliku `.esm`.
- Silnik filtruje kandydatów **zanim** wrzuci ich do aliasu i zanim Papyrus to zobaczy.

---

## 4. Modyfikacja bazowych plików gry bez patcha

**Źle:**
Bezpośrednia edycja `Starfield.esm`, bazowych skryptów, stockowych `.ini` gry.

**Dlaczego źle:**
- Utrata zmian przy aktualizacji gry.
- Ryzyko niestabilności i uszkodzenia save'ów.
- Trudność w cofnięciu.

**Poprawnie:**
- Twórz nowy plik `.esp` / `.esm` (patch) z overwrite / record injections.
- Dla skryptów — twórz nowy `.psc` modu, nie podmieniaj bazowych `*.pex`.

---

## 5. Wierzenie, że `StartQuest` resetuje quest

**Źle:**
Po zmianie skryptu wpisujesz `StartQuest 08000808` w konsoli, oczekując świeżej instancji.

**Dlaczego źle:**
Jeśli quest jest już w stanie `Running`, `StartQuest` jest ignorowane. Stare timery/aliasy zostają.

**Poprawnie:**
```
StopQuest 08000808
StartQuest 08000808
```
Lub wykonaj `sqv 08000808`, aby sprawdzić podpięty skrypt i jego właściwości.

---

## 6. Brak weryfikacji po zmianie skryptu

**Źle:**
Skompilowałeś `.psc`, wrzuciłeś do gry i założyłeś, że działa, bez patrzenia w logi.

**Dlaczego źle:**
Papyrus często nie wyrzuca błędów na ekran. Błąd objawia się brakiem logów, a nie crash.

**Poprawnie:**
- Zawsze sprawdź `Papyrus.0.log` i dedykowany log modu po wejściu do gry.
- Upewnij się, że quest jest faktycznie uruchomiony i skrypt ma przypisane `Properties` (`sqv`).
- Testuj na osobnym save'u, a nie głównym.

---

## 7. Pomijanie różnicy UTC vs czas lokalny w logach

**Źle:**
Szukanie wpisu z godziny lokalnej bez przesunięcia UTC.

**Dlaczego źle:**
Papyrus zapisuje czas UTC. Możesz pomyśleć, że log jest stary, choć właśnie powstał.

**Poprawnie:**
- Porównuj `LastWriteTimeUtc` plików logów.
- Dodaj odpowiednie przesunięcie strefy czasowej przed analizą.

---

## 8. `Debug.Trace` w gorących pętlach

**Źle:**
```papyrus
Event OnTimer(int aiTimerID)
    int i = 0
    while i < 100
        Debug.Trace("Iteracja " + i)
        i += 1
    endWhile
EndEvent
```

**Dlaczego źle:**
Pisanie do logu w szybkiej pętli spowalnia Papyrus i zalewa log.

**Poprawnie:**
- Ogranicz `Debug.Trace` do raz na cykl / warunkowo (`bDebugEnabled`).
- Do masowej diagnostyki użyj jednorazowego batcha lub narzędzi zewnętrznych (log SFSE).

---

## 9. Kompilowanie bez sprawdzenia ścieżek i zależności

**Źle:**
Wywołanie `PapyrusCompiler.exe` z domyślnymi ścieżkami, bez sprawdzenia, gdzie leży `Starfield.ppj` i czy importuje odpowiednie skrypty bazowe.

**Dlaczego źle:**
Brakujące importy albo niewłaściwa wersja kompilatora dają niespodziewane błędy lub brakujące funkcje.

**Poprawnie:**
- Zobacz `.devin/papyrus_build.md` dla poprawnych parametrów tego workspace.
- Upewnij się, że ścieżki w `.ppj` wskazują `Data\Scripts\Source` i `Data\Scripts`.
- Sprawdź flagi `--import` / `--output`.
- Porównaj wygenerowany `.pex` z oczekiwanym rozmiarem i nazwą.

---

## 10. Korzystanie z „popularnych” rozwiązań internetowych bez weryfikacji

**Źle:**
Zastosowanie skryptu / .ini / tweaku znalezionego na forum, który działa dla FO4/Skyrim, bez sprawdzenia, czy dotyczy Starfield.

**Dlaczego źle:**
Creation Engine ewoluuje. FormID, silnik Papyrus, alias conditions, SFSE API i ścieżki logów różnią się między grami.

**Poprawnie:**
- Zawsze weryfikuj w tym konkretnym workspace (pliki, logi, wersja gry).
- Szukaj w dokumentacji Starfield / SFSE, a nie ogólnej wiki Bethesdy.
- Jeśli nie masz pewności — zapytaj użytkownika i nie wdrażaj na ślepo.

---

## 11. Stosowanie automatycznych "Memory Cleanerów" (`MemoryFixes.dll` / `SetProcessWorkingSetSize`)

**Źle:**
Wywoływanie funkcji zrzucania pamięci roboczej (`WorkingSet`) podczas otwierania menu/UI gry.

**Dlaczego źle:**
W silnikach 64-bit DirectX 12 zrzucenie zaalokowanych stron pamięci do pliku wymiany (Pagefile) wywołuje kaskadę *Hard Page Faults* przy powrocie do renderowania świata 3D, powodując natychmiastowe zamrożenie klatek (stuttering / freeze).

**Poprawnie:**
- Pozwól menedżerowi pamięci Windows i sterownikom GPU zarządzać alokacją stron.
- Usuń skrypty/pluginy zrzucające pamięć roboczą w pętli.

---

## 12. Używanie przestarzałych binary patcherów (`StarfieldKit.dll` / Disk Cache Enabler)

**Źle:**
Nadpisywanie instrukcji assemblera w pamięci RAM gry za pomocą sztywnych sygnatur bajtowych (`memcpy`, `VirtualProtect`).

**Dlaczego źle:**
W nowszych wersjach silnika Creation Engine (v1.16+ / DirectStorage) sztywne patche powodują zakleszczenia wątków I/O (deadlocks) i zawieszenia pętli renderującej przy pauzie/wznawianiu gry.

**Poprawnie:**
- Korzystaj wyłącznie z aktualnych, natywnych pluginów SFSE kompilowanych pod aktualną wersję gry (`Starfield.exe`).
- Wszelkie operacje cache'owania i streamingu powierzaj zoptymalizowanemu podsystemowi DirectStorage w archiwach BA2.

---

## 13. Globalna kompresja wszystkich typów map jednym formatem (`-f BC7_UNORM` dla wszystkiego)

**Źle:**
Przepuszczanie całego archiwum modów na postacie przez uniwersalną kompresję koloru (np. `texconv -f BC7_UNORM *`).

**Dlaczego źle:**
Niszczy mapy wektorów normalnych (wymagające dedykowanego formatu dwukanałowego BC5), maski jednokanałowe (BC4) oraz formaty legacy, prowadząc do drastycznych zniekształceń cieniowania i materiałów skóry.

**Poprawnie:**
- Rekompresuj selektywnie: wyłącznie mapy koloru (`_skX_color.dds`) do `BC7_UNORM_SRGB` z pełnym łańcuchem mipmap (`-m 0`).
- Mapy `normal`, `ao`, `rough`, `mask`, `transmissive` pozostaw w ich oryginalnych formatach (DX9/BC4/BC5).

---

## 14. Używanie flagi `-pow2` (Power of Two resize) na teksturach postaci

**Źle:**
Wymuszanie proporcji kwadratowych na teksturach twarzy i ciał (np. `texconv -pow2`).

**Dlaczego źle:**
Zmiana proporcji obrazu (aspect ratio) bezpowrotnie rozjeżdża koordynaty siatki UV modelu 3D (nosy, usta i oczy lądują w przypadkowych miejscach na siatce).

**Poprawnie:**
- Proporcje wolno zmieniać wyłącznie na statycznych plakatach, bilbordach i architekturze otoczenia.
- Tekstury postaci (Face/Body/Clothes) muszą zachować oryginalne proporcje i układ UV.

---

## 14. Dodawanie nowych zmiennych instancyjnych do quest script bez version migration

**Źle:**
```papyrus
; Nowa zmienna dodana do skryptu questa
bool[] sceneFinaleTriggered    ; Na istniejącym save = None!
```

**Dlaczego źle:**
- Papyrus ładuje nowe zmienne instancyjne jako `None` na istniejącym save'ie.
- Każda operacja na `None` generuje błąd.
- Jeśli w pętli `while` → infinite loop → stuck thread baked w save → save nie do naprawienia.

**Poprawnie:**
```papyrus
int Property CURRENT_VERSION = 2 AutoReadOnly
int Property iInstalledVersion = 0 Auto

; W OnPlayerLoadGame:
if iInstalledVersion < CURRENT_VERSION
    ; Reset wszystkich nowych zmiennych
    sceneFinaleTriggered = new bool[0]
    iInstalledVersion = CURRENT_VERSION
endif
```
- Każda nowa zmienna = bump CURRENT_VERSION + dodaj do migracji.
- Zawsze używaj `EnsureArraysInitialized()` z None checkami.

---

## 15. Nieograniczone pętle `while` na dynamicznych właściwościach

**Źle:**
```papyrus
while arrA.Length < arrB.Length
    arrA.Add(false, 1)
endwhile
```

**Dlaczego źle:**
- Jeśli `.Add()` failuje (None array), `.Length` nie rośnie, warunek pozostaje true forever.
- Papyrus **nie przerywa pętli** przy błędzie — loguje i kontynuuje.
- Setki tysięcy iteracji w sekundy → log rośnie o 100+ MB w minuty.
- Jeśli save zostanie zapisany podczas pętli → stuck thread baked w save → nie do naprawienia.

**Poprawnie:**
```papyrus
; Safety counter + None check:
int safety = 0
while arrA != None && arrB != None && arrA.Length < arrB.Length && safety < 50
    arrA.Add(false, 1)
    safety += 1
endwhile

; Lub lepiej — pojedyncze Add zamiast pętli:
if arrA != None && arrB != None && arrA.Length < arrB.Length
    int needed = arrB.Length - arrA.Length
    arrA.Add(false, needed)
endif
```

**Zasada: KAŻDA pętla `while` w Papyrus musi mieć safety counter. Nie ma wyjątków.**

---

## 16. Testowanie bugged skryptu na głównym save'ie

**Źle:**
- Ładowanie głównego save'a po każdej zmianie skryptu questa.
- Auto-save i quick-save nadpisują się podczas testów.

**Dlaczego źle:**
- Jeśli skrypt ma bug który powoduje stuck thread, save zostaje corrupted.
- Auto-save może zapisać stan w środku stuck threada.
- Tracisz główny save — trzeba wracać do backupa.

**Poprawnie:**
- Zawsze testuj na **kopii save'a** lub osobnym save'ie testowym.
- Wyłącz auto-save podczas testów (`bAutoSaveOnTravel=0`, `bAutoSaveOnWait=0`).
- Zrób `save TestBeforeChanges` przed załadowaniem nowego skryptu.
- Jeśli coś pójdzie nie tak, masz czysty save do powrotu.

---

## 17. Wierzenie że `StopQuest`/`StartQuest` zabije stuck thread

**Źle:**
```text
StopQuest 08000801
StartQuest 08000801
; Zakładanie że stuck thread został zabity
```

**Dlaczego źle:**
- `StopQuest` zatrzymuje quest stages, aliases i future events, ale **nie zabiva działających wątków VM**.
- Stuck thread (infinite loop) kontynuuje działanie w VM task queue niezależnie od stanu questa.
- `StartQuest` tworzy nową instancję, ale stary wątek nadal działa w tle.

**Poprawnie:**
- Nie polegaj na `StopQuest`/`StartQuest` dla killowania stuck threadów.
- Jedynym rozwiązaniem jest **załadowanie save'a sprzed buga**.
- Zapobiegaj stuck threadom używając safety counterów w pętlach (patrz #15).


---

## 18. `InPlaceMode=ON` na paired scenach OSF

**Źle:**
```papyrus
opts.InPlaceMode = OSF.ON()  ; dla paired scen (2 aktorów)
```

**Dlaczego źle:**
- OSF pomija wyrównanie pozycji aktorów → aktorzy za daleko od siebie → natychmiastowy abort (2s).
- `InPlaceMode=ON` jest tylko dla solo scen (1 aktor).

**Poprawnie:**
```papyrus
; Paired sceny — zawsze OFF (wyrównanie pozycji)
opts.InPlaceMode = OSF.OFF()
; Solo sceny — ON (aktor zostaje w miejscu)
soloOpts.InPlaceMode = OSF.ON()
```

---

## 19. MIN distance guard blokujący wszystkie sceny (OSF Autonomous)

**Źle:**
```papyrus
if actor.GetDistance(player) < 250.0  ; companion follow AI = 30-100 units
    return  ; blokuje 100% scen na statku
endif
```

**Dlaczego źle:**
- Companion follow AI trzyma NPC w promieniu 30-100 units od gracza.
- MIN guard nawet przy 50 units blokuje wszystkie sceny we wnętrzach.
- Mod staje się całkowicie bezużyteczny.

**Poprawnie:**
```papyrus
; Tylko MAX distance — chroni przed niewidocznymi scenami
if actor.GetDistance(player) > maxDist
    return
endif
; Brak MIN guard — companions mogą startować sceny tuż obok gracza
```

---

## 20. Modyfikowanie plików innych autorów dla naprawy ról (OSF)

**Źle:**
```python
# Edycja snusnufield.osf.json — zamiana ról [f,m] → [m,f]
roles[0], roles[1] = roles[1], roles[0]
```

**Dlaczego źle:**
- Mod wydawany na Nexus nie może modyfikować plików innych autorów.
- Aktualizacja oryginalnego moda nadpisze nasze zmiany → bug powraca.
- Kwestie licencyjne i kompatybilności.

**Poprawnie:**
```papyrus
; W swoim skrypcie — tag-based pack partitioning
; Query z 'ge' tag → tylko GE sceny → standardOrder [male, female]
; Query z 'snusnu' tag → tylko SnuSnu → femdomOrder [female, male]
; Catch-all bez pack tagu → standardOrder (99% convention)
```

---

## 21. Hardkodowanie pack tagów bez catch-all (OSF Autonomous)

**Źle:**
```papyrus
; Tylko GE i SnuSnu — brak obsługi innych packów
handle = OSF.StartSceneByTags(actors, ["paired","mf","ge","cowgirl"], opts)
; Jeśli użytkownik ma inny pack → 0 scen → mod nie działa
```

**Dlaczego źle:**
- Hard dependency na konkretne pakiety animacji.
- Użytkownik z innym packiem (np. Community Animations) nie znajdzie żadnych scen.

**Poprawnie:**
```papyrus
; 1. Pack-specific (GE, SnuSnu) — poprawne role
; 2. Catch-all (bez pack tagu) — standardOrder dla dowolnego packa
; GE i SnuSnu = soft dependencies, nie hard
```
