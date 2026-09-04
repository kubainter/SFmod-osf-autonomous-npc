# Wytyczne współpracy Devin ↔ Agy (MCP)

Zasady delegowania zadań do Google Antigravity (`agy`) przez MCP server `tphakala/agy-mcp`.
Obowiązują przy każdym wywołaniu narzędzi `agy_run`, `agy_run_sync`, `agy_wait`, `agy_status`, `agy_cancel`, `list_sessions`.

---

## 1. Architektura

```
Devin (ta sesja)
  → MCP client
  → tphakala/agy-mcp (stdio JSON-RPC)
  → agy CLI
  → Google Gemini backend
```

- Agy używa modeli Google Gemini — nie widzi modeli Devina ani OpenRoutera.
- Agy działa w tym samym workspace (`G:\Starfield`), ale **nie widzi historii czatu Devina**.
- Kontekst agy jest trwały pod `conversation_id` — przeżywa restart MCP, restart Devina, nowe procesy agy.

---

## 2. Kiedy delegować do agy

**Tak:**
- Peer review kodu — niezależna ocena zmian przed commit.
- Second opinion architektoniczne — alternatywne podejście do problemu.
- Independent analysis — analiza ESM/ESP, struktury plików, logów, gdy chcemy cross-check.
- Research — przeszukanie dokumentacji, web search z perspektywy Gemini.
- Brainstorm — wygenerowanie pomysłów które potem weryfikuję narzędziami Devina.
- Cross-model verification — potwierdzenie hipotezy przez inny model (Gemini vs GLM/Claude).

**Nie:**
- Proste zmiany kodu — wykonam szybciej sam.
- Kompilacja Papyrusa — to operacja lokalna, agy nie ma do niej dostępu.
- Edycja plików gdy potrzebuję precyzyjnej kontroli — agy ma wyłączone sprawdzanie uprawnień.
- Zadania wymagające kontekstu całej sesji Devina — agy go nie widzi.
- Cokolwiek co wymaga natychmiastowej odpowiedzi bezpośrednio użytkownikowi.

---

## 3. Konstrukcja promptu

Każdy prompt do agy musi być **self-contained** — agy nie widzi tej rozmowy.

### Wymagane elementy

1. **Zadanie** — co dokładnie agy ma zrobić.
2. **Kontekst** — relevantne pliki, ścieżki, fragmenty kodu, logi.
3. **Ograniczenia** — czy agy może edytować pliki, czy analysis-only.
4. **Format odpowiedzi** — jak agy ma zwrócić wynik (lista, JSON, markdown).
5. **Workspace** — `cwd` ustawione na `G:\Starfield` chyba że inne.

### Szablon promptu analysis-only

```text
Zadanie: <opis>
Workspace: G:\Starfield

Pliki do przeanalizowania:
- <ścieżka 1>
- <ścieżka 2>

Kontekst:
<fragmenty kodu, logi, lub inne dane>

Ograniczenia:
- NIE edytuj plików. To jest analiza read-only.
- Uwzględnij zasady z .devin/AGENTS.md (Papyrus jednowątkowy, GetFormFromFile w gorących pętlach, CTDA zamiast filtrowania w Papyrusie).

Format odpowiedzi:
- Lista znalezisk z ścieżkami plików i numerami linii.
- Dla każdego znaleziska: priorytet (krytyczny/wysoki/średni/niski), opis, rekomendacja.
```

### Szablon promptu implementation

```text
Zadanie: <opis>
Workspace: G:\Starfield

Pliki do zmiany:
- <ścieżka 1>

Kontekst:
<fragmenty kodu>

Ograniczenia:
- Modyfikuj tylko pliki modów, nie Starfield.esm.
- Nie używaj GetFormFromFile w timerach/pętlach.
- Po zmianie skryptu Papyrus — zachowaj strukturę Properties.
- Używaj Archive2.exe dla BA2, nie BSArch.

Format odpowiedzi:
- Diff zmian.
- Krótkie uzasadnienie każdej zmiany.
```

---

## 4. Zarządzanie conversation_id

### Nowa konwersacja

```
agy_run_sync({ "prompt": "...", "cwd": "G:\\Starfield" })
→ zwraca conversation_id
```

Zawsze **zapamiętaj zwrócony `conversation_id`** — to jest klucz do kontekstu.

### Kontynuacja konwersacji

```
agy_run_sync({
  "prompt": "Biorąc pod uwagę poprzednią analizę, teraz...",
  "conversation_id": "<ID z poprzedniego wywołania>",
  "cwd": "G:\\Starfield"
})
```

### Zasady

- **Jedna konwersacja = jeden logiczny wątek zadania.**
- Nie mieszaj różnych zadań w jednej konwersacji.
- Jeśli zmieniasz temat — zacznij nową konwersację (nowy prompt bez `conversation_id`).
- **Nigdy nie wywołuj dwóch turnów równolegle na tym samym `conversation_id`** — agy-mcp serializuje dostęp, ale równoległe wywołania mogą wisieć.
- Jeśli `conversation_id` zostało zgubione — użyj `list_sessions` żeby znaleźć poprzednie konwersacje.

---

## 5. Tryby wywołania

### `agy_run_sync` — synchroniczny (preferowany)

Używaj gdy:
- Potrzebuję odpowiedzi przed następnym krokiem.
- Zadanie jest krótkie (peer review, quick question, cross-check).
- Czas oczekiwania < 120s.

```text
agy_run_sync({
  "prompt": "...",
  "cwd": "G:\\Starfield",
  "wait": "90s"
})
```

Jeśli `state` = `running` po przekroczeniu `wait` — job nadal działa w tle. Użyj `agy_wait` z `job_id` żeby doczekać.

### `agy_run` — asynchroniczny (długie zadania)

Używaj gdy:
- Zadanie może trwać > 2 minuty (pełny review, research, duża analiza).
- Chcę pracować dalej podczas gdy agy myśli.

```text
agy_run({ "prompt": "...", "cwd": "G:\\Starfield" })
→ zwraca job_id + conversation_id

# później:
agy_status({ "job_id": "..." })   # sprawdź status
agy_wait({ "job_id": "...", "wait": "120s" })  # zaczekaj na wynik
```

### `agy_cancel` — anulowanie

Tylko gdy:
- Zadanie poszło w złym kierunku.
- Użytkownik anulował żądanie.
- Job wisi i nie odpowiada.

---

## 6. Weryfikacja twierdzeń agy

**Agy potrafi się mylić.** To jest model Gemini, nie ekspert Starfield.

### Zasada zerowa

Każde twierdzenie agy o plikach, FormID, strukturze ESM, logach — **weryfikuj narzędziami Devina** przed użyciem.

### Co zawsze weryfikować

- **FormID i słowa kluczowe** — sprawdź w pliku ESM/ESP przez `read` lub skrypt Python.
- **Struktura GRUP/CELL/REFR** — użyj skryptów z `.devin/` (np. `verify_agy_claims.py`).
- **Twierdzenia o Papyrus API** — sprawdź w `Data\Scripts\Source\` lub dokumentacji SFSE.
- **Twierdzenia o logach** — odczytaj logi samodzielnie.
- **Twierdzenia o wydajności** — sprawdź logi Papyrus pod kątem spam.

### Przykład

```
agy_run_sync: "Przeanalizuj strukturę CELL w sfbgs004.esm"
→ agy: "CELL 0x02005668 to SamRoom_Aft_A_Int"

Devin weryfikuje:
→ read/skrypt Python na sfbgs004.esm
→ potwierdza lub obala twierdzenie
→ jeśli obala — kontynuacja z conversation_id + korekta
```

### Narzędzie: `verify_agy_claims.py`

W `.devin/` istnieje skrypt `verify_agy_claims.py` — precedent weryfikacji twierdzeń agy o strukturze ESM. Używaj jako wzorca dla nowych weryfikacji.

---

## 7. Kontekst workspace Starfield

Agy działa w `G:\Starfield` ale **nie zna reguł projektu**. Każdy prompt powinien zawierać relevantne ograniczenia z `AGENTS.md`:

### Minimum dla promptów o Papyrus

```text
Ograniczenia Papyrus (z .devin/AGENTS.md):
- Papyrus jest jednowątkowy — unikaj blokujących operacji.
- GetFormFromFile NIE w timerach/pętlach — używaj Properties.
- Filtrowanie aktorów w CTDA (warunki aliasu), nie w Papyrusie.
- StartTimer tylko w jednym zdarzeniu (OnInit ALBO OnQuestInit).
- Po zmianie skryptu: StopQuest + StartQuest, nie samo StartQuest.
- Modyfikuj tylko pliki modów, nie Starfield.esm.
```

### Minimum dla promptów o BA2/tekstury

```text
Ograniczenia BA2 (z .devin/AGENTS.md):
- Używaj Archive2.exe, nie BSArch.
- Flaga -root wskazuje folder nadrzędny wobec textures/.
- Kompresja: tylko _skX_color.dds do BC7_UNORM_SRGB.
- Mapy normal/ao/rough/mask zostaw w oryginalnych formatach.
- Nie używaj -pow2 na teksturach postaci.
```

---

## 8. Antywzorce współpracy z agy

### 1. Ślepe zaufanie do twierdzeń agy

**Źle:** agy mówi "FormID 0x00013794 to ActorTypeNPC" → wpisuję do skryptu bez weryfikacji.

**Dlaczego źle:** agy (Gemini) może halucynować FormID. `verify_agy_claims.py` powstał właśnie dlatego, że agy się myliło.

**Poprawnie:** weryfikuj każde twierdzenie o plikach/FormID/strukturze narzędziami Devina.

### 2. Brak kontekstu w prompcie

**Źle:** `agy_run_sync({ "prompt": "napraw skrypt" })`

**Dlaczego źle:** agy nie wie który skrypt, nie zna reguł projektu, nie widzi logów.

**Poprawnie:** pełny kontekst: ścieżka, fragment kodu, logi, ograniczenia z AGENTS.md.

### 3. Równoległe wywołania na tym samym conversation_id

**Źle:** dwa `agy_run_sync` z tym samym `conversation_id` w jednej wiadomości.

**Dlaczego źle:** agy-mcp serializuje dostęp, ale równoległe wywołania mogą blokować.

**Poprawnie:** sekwencyjnie — zaczekaj na wynik pierwszego przed drugim.

### 4. Edycja plików bez wyraźnej zgody

**Źle:** agy z implementacyjnym promptem edytuje pliki bez weryfikacji.

**Dlaczego źle:** agy ma wyłączone sprawdzanie uprawnień. Może nadpisać bazowe pliki gry.

**Poprawnie:** domyślnie analysis-only. Edycja tylko z wyraźnym "możesz edytować pliki" + ograniczenia z AGENTS.md.

### 5. Mieszanie zadań w jednej konwersacji

**Źle:** jedna konwersacja agy do review Papyrus + analiza tekstur + research web.

**Dlaczogo źle:** kontekst się rozmywa, agy gubi wątek.

**Poprawnie:** jedna konwersacja = jeden logiczny wątek. Nowe zadanie = nowa konwersacja.

### 6. Zgubienie conversation_id

**Źle:** zapomnij `conversation_id` po pierwszym wywołaniu, zacznij nową konwersację dla follow-up.

**Dlaczego źle:** tracisz cały kontekst agy. Follow-up musi powtarzać wszystko.

**Poprawnie:** zachowaj `conversation_id` i przekaż w kolejnym wywołaniu. Jeśli zgubione — `list_sessions`.

---

## 9. Workflow: peer review kodu

Typowy scenariusz — agy review zmian w skrypcie Papyrus.

```text
# 1. Devin kończy zmianę w skrypcie
# 2. Devin czyta zmieniony plik
# 3. Devin deleguje do agy:

agy_run_sync({
  "prompt": "Peer review zmian w skrypcie Papyrus.
    Plik: Data/Scripts/Source/OSF_AutonomousManagerScript.psc
    <wklej zmieniony fragment>
    
    Sprawdź:
    - czy nie ma GetFormFromFile w timerach/pętlach
    - czy timer nie jest uruchamiany w OnInit i OnQuestInit jednocześnie
    - czy filtrowanie aktorów nie powinno być w CTDA
    - czy Properties są poprawne
    - czy nie ma memory leak / script lag
    
    NIE edytuj plików. Zwróć listę znalezisk z priorytetami.",
  "cwd": "G:\\Starfield",
  "wait": "90s"
})

# 4. Agy zwraca znaleziska + conversation_id
# 5. Devin weryfikuje krytyczne twierdzenia narzędziami (read, grep, skrypty)
# 6. Jeśli potrzebny follow-up:
agy_run_sync({
  "prompt": "Dla znaleziska #2 — czy to faktycznie problem? Sprawdź...",
  "conversation_id": "<ID z kroku 4>",
  "cwd": "G:\\Starfield"
})
# 7. Devin implementuje poprawki samodzielnie
```

---

## 10. Workflow: cross-model verification

Scenariusz — potwierdzenie hipotezy przez drugi model.

```text
# 1. Devin formułuje hipotezę (np. "CTDA warunek X powinien wykluczyć towarzyszy")
# 2. Devin deleguje do agy:

agy_run_sync({
  "prompt": "Hipoteza do weryfikacji:
    W pliku SFF_BodyDistributor.esm, warunek CTDA na aliasie używa:
    <fragment warunku>
    
    Czy ten warunek poprawnie wyklucza:
    - gracza (IsPlayer)
    - towarzyszy (IsPlayerTeammate)
    - już przetworzonych NPC (HasKeyword SFF_ProcessedKeyword)
    
    Uwzględnij: Creation Engine Starfield, nie Skyrim/FO4.
    NIE edytuj plików.",
  "cwd": "G:\\Starfield",
  "wait": "60s"
})

# 3. Agy potwierdza lub obala
# 4. Devin weryfikuje w xEdit / skryptem Python niezależnie
# 5. Jeśli zgodne — wysoka pewność. Jeśli rozbieżne — głębsza analiza.
```
