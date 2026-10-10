# OSF Autonomous — TODO / Known Issues

## v1.0.4 — Spaceflight / Piloting scene trigger & floating crew bug (CRITICAL BUGFIX)

**Priorytet:** KRYTYCZNY — powoduje wypadanie załogi w przestrzeń kosmiczną ("outside ship in space") i soft-lock animacji.

**Objawy zgłoszone przez graczy:**
"So far this mod has caused NPCs to spawn and get stuck in an animation outside the ship every time I've gone into space. Doesn't rectify when I land. Super bogged at least on my instance."

**Przyczyna (Root Cause):**
1. `OnTimer` (linia ~744) blokuje sceny sprawdzając jedynie `player.GetSitState() != 0`.
   - W locie kosmicznym w widoku 3. osoby (kamera zewnętrzna statku), w trakcie sekwencji przelotów lub po wstaniu gracza na orbicie silnik potrafi zwrócić `GetSitState() == 0`.
   - Prawidłowe sprawdzenie aktywnego pilotowania to `player.GetSpaceship() != None` (tak jak w Bethesda `MQ101PlayerAliasScript`).
2. Skaner odpalał sceny OSF dla załogi w trakcie gdy statek poruszał się z prędkością w przestrzeni kosmicznej (`Space Cell`).
   - OSF (`InPlaceMode = OFF`) pinuje transformację aktora do koordynatów świata. Statek odlatuje w przód, a NPC zostaje "wyrwany" z wnętrza statku w próżnię na zewnątrz kadłuba.
3. W `OnLocationChange` (linia ~549) warunek `if !bIsOnShip` pomijał czyszczenie scen (`EmergencyStopAll()`) przy bezpośrednim Fast Travelu / skoku na orbitę z pokładu statku.
4. Przy lądowaniu na planecie komórka kosmiczna się wyładowuje, a zawieszeni w animacji OSF NPC nie są poprawnie przenoszeni, co generuje stały spam błędów silnika ("Super bogged").

**Do zrobienia:**
1. W `OnTimer`:
   - Zablokować start scen, gdy gracz aktywnie pilotuje: `if player.GetSpaceship() != None`.
   - Zablokować, gdy statek jest w walce: `if currentShip != None && currentShip.IsInCombat()`.
   - Zezwalać na sceny na orbicie TYLKO wtedy, gdy gracz wstał z fotela (`player.GetSpaceship() == None`) i spaceruje pieszo po wnętrzu statku (`player.GetParentCell().IsInterior()`).
2. Wycofanie/zakończenie scen w chwili powrotu za stery:
   - Zarejestrować zdarzenie zajęcia fotela pilota lub sprawdzać w timerze i wywołać `EmergencyStopAll()` zanim statek ruszy.
3. W `OnLocationChange`:
   - Bezwarunkowo wywoływać `EmergencyStopAll()`, jeśli następuje przejście do przestrzeni kosmicznej (`player.IsInSpace()` / zmiana komórki na zewnętrzną).

## v1.0.2 — Crew recruitment filter (BLOCKER for "Everywhere" mode)

**Priorytet:** WYSOKI — blokuje bezpieczne użycie trybu "Everywhere"

**Problem:**
Skan kandydatów (linie ~800-840 w OSF_AutonomousManagerScript.psc) używa
`FindAllReferencesWithKeyword` z crew keywords (Crew_CrewTypeCompanion,
Crew_CrewTypeGeneric, Crew_CrewTypeElite). To znajduje WSZYSTKICH NPC
z tymi keywordami w zasięgu — niezależnie czy są zrekrutowani czy nie.

W trybie "Everywhere" (lub w "Interiors" w lokacjach z niezrekrutowanymi
crew NPC) sceny parowane mogą startować między zrekrutowanym companionem
a niezrekrutowanym NPC z crew keyword (np. Mickey w barze Akila City).

**IsActorEligible() NIE sprawdza:**
- Czy actor jest przypisany do statku gracza
- Czy actor jest w CurrentCompanionFaction (0x00023C01)
- Czy actor jest teammate gracza (IsPlayerTeammate)
- Czy actor został zrekrutowany

**Do zbadania:**
- Papyrus API do sprawdzania czy Crew jest zrekrutowany
  (gra wie kto jest przypisany do statku/outpostu — musi być metoda)
- Możliwe metody: IsPlayerTeammate(), CurrentCompanionFaction,
  sprawdzanie przypisania do HomeShip, ew. faction z rekrutacji
- `Game.GetPlayerFollowers()` zwraca tylko aktywnych followers (OK),
  ale crew keywords szukają wszystkich

**Sugerowane rozwiązanie:**
Dodać filtr w IsActorEligible() — gdy nie jesteśmy na statku (bIsOnShip == false),
sprawdź czy actor z crew keyword jest faktycznie zrekrutowany/aktywny.
Na statku nie ma niezrekrutowanych crew NPC, więc filtr nie jest potrzebny tam.

**Plik:** StarfieldDev\src\OSFAutonomous\OSF_AutonomousManagerScript.psc
**Funkcja:** IsActorEligible() (~linia 958) + skan kandydatów (~linia 786)

---

## v1.1.x+ — Future improvements / in-game verification backlog

### TODO-001 — Cache `GetRelationshipRank` in `IsActorEligible()` ✅ DONE

**Priorytet:** LOW — kosmetyczna optymalizacja

**Rozwiązanie (2026-09-29):**
`int relRank` jest teraz liczone raz na początku sekcji filtrów warunkowych i używane
przez oba crew guardy (companion + generic/elite) oraz romance exclusivity guard —
3 wywołania `GetRelationshipRank` zredukowane do 1. Bonus: usunęło to podwójne
deklaracje zmiennej w blokach `if`.

**Plik:** `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
**Funkcja:** `IsActorEligible()`

---

### TODO-002 — Verify ghost-scene cleanup after save+quit mid-scene

**Priorytet:** MEDIUM — poprawność cleanupu sprzętu

**Problem:**
W v1.1.0 dodano śledzenie uczestników sceny w tablicach `sceneActorA`/`sceneActorB`, żeby `UnequipStuckAttachments()` mogło działać nawet gdy `OSF.GetSceneParticipants()` zwraca pustą tablicę po load save ("ghost scene").

**Do zweryfikowania w grze:**
1. Poczekaj aż scena się rozpocznie (sprawdź log `Scene started`).
2. Zrób hard-quit do pulpitu (Alt+F4) lub zapisz i wyjdź w trakcie sceny.
3. Wczytaj save.
4. Sprawdź `OSF_Autonomous.0.log` — powinien pojawić się wpis `Ghost scene removed` i aktorzy powinni mieć zdjęty sprzęt (`Dick.esm` / `Haters Body`).
5. Sprawdź wizualnie czy NPC nie jest nagi / bez zbędnych attachmentów.

**Plik:** `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
**Funkcje:** `OnPlayerLoadGame()`, `AuditActiveScenes()`, `EnforceSceneTimeouts()`

---

### TODO-003 — Verify furniture scenes in dense cells after 15-candidate cap

**Priorytet:** MEDIUM — wydajność + poprawność w gęstych komórkach

**Problem:**
W v1.1.0 dodano limit 15 najbliższych mebli w `TryStartScene()`, żeby uniknąć zawieszania w gęstych lokacjach (np. Cydonia miała 87+ mebli).

**Do zweryfikowania w grze:**
1. Polec do Cydonii / New Atlantis / innej gęstej lokacji.
2. Upewnij się, że `ReloadScript "OSF_AutonomousManagerScript"` zostało wykonane.
3. Poczekaj na timer scan (45s).
4. Sprawdź log:
   - `Capped furniture candidates: 15/... (performance limit)`
   - Scena powinna spróbować tylko 15 najbliższych mebli i nie zawieszać skryptu.
   - Jeśli żaden z 15 mebli nie pasuje, powinien nastąpić fallback do standing scenes.
5. Sprawdź czy w mniej gęstych lokacjach (statek, outpost) sceny meblowe nadal działają.

**Plik:** `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
**Funkcja:** `TryStartScene()` -> `FindNearbyFurniture()`

---

### TODO-004 — Clean up empty `Data\Scripts\Source\` folder in release ZIP ✅ DONE

**Priorytet:** LOW — kosmetyka paczki

**Problem:**
`build_zip.ps1` usuwa `.psc` z staging, ale zostawia pusty folder `Data\Scripts\Source\` w końcowym ZIP-ie.

**Rozwiązanie (2026-09-29):**
`build_zip.ps1` po wycięciu `.psc` usuwa teraz wszystkie puste katalogi ze staging (sortowane wg głębokości, deepest-first). Regresję pilnuje test `tests/test_release_build.py::test_zip_has_no_empty_directories` — wyłapał defekt przy pierwszym uruchomieniu suity.

**Plik:** `repo_upload/build_zip.ps1`

---

### TODO-005 — Player-involved events ("Snu Snu Light" / SSLite)

**Priorytet:** FEATURE — sugestia użytkownika (nowa funkcjonalność, nie bug)

**Źródło (sugestia):**
"I'd really like to see the Player involved in this. If player is generally idle, then a Snu Snu Light event may occur that includes the player and a fellow NPC (emphasis on SSLite for minimal impact on gameplay). Adjustable by the slider set from 0% chance of happening to 100% and level of affinity."

**Opis:**
Gdy gracz jest bezczynny (idle — brak ruchu przez ≥2 ticki skanera, ~90 s), pobliski NPC może zainicjować krótką ("lite": foreplay, ubrani aktorzy, krótsza pętla) scenę OSF z udziałem gracza. Szansa sterowana suwakiem 0–100% (default **0 = opt-in**), gate po relationship rank NPC (default: romanced = rank ≥ 3 — naturalnie domyka lukę po Romance Exclusivity Guard).

**Wykonalność:** WYSOKA — OSF wspiera gracza jako uczestnika sceny (dowód: `OSFSeduce.psc`), cała infrastruktura skanowania/trackingu już jest. Bridge-framework respektowany: bez OSFSeduce quest/globals, bez DLL, bez hooków inputu — tylko `OSF.*` + base Papyrus. ~150–250 linii + 3 ustawienia JSON (`iPlayerChancePercent`, `sPlayerMinAffinity`, `fPlayerLoopScale`).

**Szczegóły + zarys prototypu:** [TODO-005_player_events.md](TODO-005_player_events.md)

**Plik:** `release/Data/Scripts/Source/OSF_AutonomousManagerScript.psc`
**Funkcje:** `OnTimer` (roll + idle sampling), nowe `IsPlayerIdle()`, `PickPlayerScenePartner()`, `TryStartPlayerScene()`; poprawki w `AuditActiveScenes()` (walk-in vs player) i `ApplyCooldownToActor()` (EvaluatePackage guard dla gracza).

