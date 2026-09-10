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
