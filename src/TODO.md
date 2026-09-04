# OSF Autonomous — TODO / Known Issues

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
