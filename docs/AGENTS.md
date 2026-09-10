# Starfield Workspace Agent Rules

Skrócona instrukcja i twardy zestaw zasad dla wszystkich operacji na tym workspace Starfield.

## Spis treści

1. [Mapa katalogów](#mapa-katalogów)
2. [Bezwzględne podstawy](#bezwzględne-podstawy)
3. [Instrukcje warunkowe / drzewo decyzyjne](#instrukcje-warunkowe--drzewo-decyzyjne)
4. [Silnik i narzędzia](#silnik-i-narzędzia)
5. [Wydajność](#wydajność)
6. [Antywzorce i lekcje](#antywzorce-i-lekcje)
7. [Współpraca z agy (MCP)](#współpraca-z-agy-mcp)

---

## Mapa katalogów (względem repo root)

- `release/` — pliki dystrybucyjne, 1:1 z katalogiem gry `Data/`
  - `release/Data/` — ESM, skrypty (.pex + .psc), manifesty OSF, animacje, dźwięki
  - `release/fomod/` — konfiguracja FOMOD installera
  - `release/README.txt`, `release/CHANGELOG.txt` — dokumentacja dystrybucyjna
- `src/` — narzędzia build, skrypty Python, manifesty źródłowe
- `docs/` — dokumentacja projektu
- `build_zip.ps1` — buduje ZIP z `release/` (wyklucza `.psc`)
- `sync_to_game.ps1` — kopiuje `release/Data/` do katalogu gry

---

## Bezwzględne podstawy

Te zasady obowiązują zawsze, bez wyjątków.

1. **Brak domniemań**: Nigdy nie opieraj się na domysłach ani domniemaniach. Zawsze sprawdzaj stan faktyczny, pliki źródłowe, logi i dokumentację.
2. **Analiza logów jako priorytet**: Pierwszym źródłem wiedzy o błędach i zachowaniu gry są logi SFSE, logi Papyrusa oraz logi powiązanych modów. Zawsze sprawdzaj pliki logów przed podjęciem decyzji.
3. **Bezpieczeństwo modyfikacji**: Każda zmiana musi być dokładnie zweryfikowana pod kątem stabilności i wpływu na zapisy gry (save'y). Zmiany nie mogą powodować błędów typu CTD (Crash to Desktop) ani uszkadzać save'ów.
4. **Modyfikacja wyłącznie modów**: Modyfikujemy tylko skrypty i pliki należące do modów. Pliki bazowe gry (*Starfield.esm*, bazowe skrypty itp.) pozostawiamy nienaruszone. W razie konieczności modyfikacji bazy tworzymy dedykowane patche.
5. **Optymalizacja i wydajność**: Zawsze dbamy o wydajność silnika gry (Creation Engine/Papyrus) — unikamy kosztownych pętli, nadmiarowych wywołań w krótkich odstępach czasu i operacji obciążających silnik gry w tle.
6. **Kontekst modów**: Starfield działa w najnowszej wersji z wieloma modami. Przy analizie problemów bierzemy pod uwagę listę aktywnych modów z pliku *plugins.txt*.
7. **Przenoszenie logiki z Papyrusa do xEdit (CTDA)**: Zamiast obciążać skrypty (Papyrus) skomplikowanym filtrowaniem i odrzucaniem aktorów (np. za pomocą `GetFormFromFile`, pętli czy sprawdzania słów kluczowych), przenosimy logikę wykluczającą (np. wykluczenie gracza, towarzyszy i już przetworzonych obiektów) bezpośrednio do warunków (Conditions) w Aliasach i Questach w pliku `.esm`. Pozwala to uniknąć zjawiska "Papyrus spam" i ogromnie poprawia wydajność.

---

## Instrukcje warunkowe / drzewo decyzyjne

Jeśli użytkownik prosi o:

### Naprawę/zmianę skryptu Papyrusa

1. Odczytaj odpowiednie logi: `Papyrus.0.log`, inne logi modów w `Logs\Script\User\`, `sfse_plugin_console.log`.
2. Sprawdź `plugins.txt` i potwierdź, które wtyczki i moduły są aktywne.
3. Zlokalizuj źródło `.psc` (najpierw `Data\Scripts\Source\`, potem foldery modów).
4. Zanim coś zmienisz, sprawdź:
   - czy timer jest uruchamiany w więcej niż jednym miejscu (`OnInit` i `OnQuestInit` razem jest błędem);
   - czy `GetFormFromFile` wykonuje się często (pętla/timer);
   - czy filtry aktorów da się przenieść do warunków aliasu (CTDA).
5. Po zmianie skryptu pamiętaj o `StopQuest <FormID>` + `StartQuest <FormID>` lub `sqv` po wczytaniu save'a.
6. Wystaw testowego save'a zamiast nadpisywać głównego, jeśli zmiana dotyczy działającego questa.

### Debugowanie wydajności / lagów

1. Otwórz `Papyrus.0.log` i poszukaj powtarzających się, częstych wpisów.
2. Szukaj timerów poniżej 1s, funkcji `GetFormFromFile` w pętlach, `Debug.Trace` w gorących ścieżkach.
3. Przenieś logikę do warunków CTDA w `.esm` zanim zaczniesz optymalizować Papyrus.

### Zmianę pliku `.esm` / questa

1. Sprawdź, czy jest to mod (nazwa zawiera nazwę moda) czy gra bazowa.
2. Dla gry bazowej twórz patch `.esp` / `.esm`.
3. Zapisz kopię (`*.BACK` / `*.bak`) przed edycją w xEdit.
4. Po zmianie, jeśli quest jest już uruchomiony w save, użyj `StopQuest` + `StartQuest` lub załaduj czysty zapis.

### Tworzenie / kompilację pluginu SFSE/C++

1. Źródła build skryptów znajdują się w `src/`.
2. Build wykonaj z poziomu repo root, nie bezpośrednio w katalogu gry.

### Budowanie release (ZIP)

1. `release/` jest 1:1 z katalogiem gry — edytuj pliki tam.
2. **Sync do gry**: `powershell -File sync_to_game.ps1` — kopiuje `release/Data/` do katalogu gry.
3. **Build ZIP**: `powershell -File build_zip.ps1 -Version X.Y.Z` — pakuje `release/` do ZIP (bez `.psc`).
4. **Zabronione w ZIP**: `.psc` (skrypt automatycznie usuwa ze staging), narzędzia Python, skrypty build.
5. Po każdej zmianie **aktualizuj `release/CHANGELOG.txt`**. Format:
   ```
   vX.Y.Z — YYYY-MM-DD — krótki tytuł
   ------------------------------------------------------
   ADDED: co dodano
   CHANGED: co zmieniono
   BUGFIX: co naprawiono (bez przyczyny)
   ```
6. Po zbudowaniu ZIP, zweryfikuj zawartość wypakowując go i sprawdzając listę plików oraz wersję w `fomod/info.xml`.

### Analizę crasha / CTD

1. Przeczytaj ostatni log SFSE w `<game>/Data/SFSE/Plugins/*.log`.
2. Sprawdź ostatnie wpisy `Papyrus.0.log` przed czasem crasha.
3. Nie usuwaj ani nie nadpisuj `Starfield.exe`, `bink2w64.dll` ani innych podstawowych DLL.

---

## Silnik i narzędzia

- **Silnik**: Creation Engine / Starfield (`Starfield.exe` i `sfse_1_*.dll`).
- **Skrypty**: Papyrus (kompilator: `PapyrusCompiler.exe`). Szczegółowa instrukcja: `docs/papyrus_build.md`.
- **Edytor danych**: xEdit / SF1Edit, Archive2 dla `*.ba2`.
- **SFSE**: `sfse_loader.exe`, `sfse_1_*.dll`, pluginy w `Data/SFSE/Plugins/`.
- **Deasembler skryptów**: Champollion (`Champollion.exe`).
- **Konfiguracja gry**: `StarfieldCustom.ini`, `StarfieldPrefs.ini` w `Documents/My Games/Starfield/`.
- **Lista modów**: `AppData/Local/Starfield/plugins.txt`.

Ograniczenia, o których zawsze trzeba pamiętać:

- Papyrus jest jednowątkowy; długie/blokujące operacje zabijają płynność gry.
- `Game.GetFormFromFile` szuka formy w tabeli — nigdy w gorących pętlach ani timerach.
- Alias Conditions (CTDA) w `.esm` są filtrowane przez silnik, nie obciążają Papyrusa.
- Save Game Caching: zmiany w skryptach/questach często wymagają pełnego `StopQuest`/`StartQuest` albo czystego zapisu, bo silnik cache'uje stan skryptu w save.
- Logi Papyrus zapisywane są w UTC; porównuj czas z czasem lokalnym.

---

## Wydajność

- Unikaj `GetFormFromFile` w timerach / pętlach.
- Używaj `Faction` / `Keyword` `Properties` zamiast odpytywania `Game.GetFormFromFile`.
- Nie uruchamiaj `StartTimer` więcej niż raz dla tego samego ID (np. nie w `OnInit` i `OnQuestInit` jednocześnie).
- Nie używaj `Debug.Trace` w gorących pętlach na długo.
- Filtrowanie aktorów (gracz, towarzysze, keyword `SFF_ProcessedKeyword` itp.) zachodzi najpierw w CTDA w `.esm`; Papyrus dostaje już przefiltrowany zbiór.

---

## Antywzorce i lekcje

Pełna lista: `docs/anti_patterns.md` i `docs/lessons_learned.md`.
Najważniejsze zagrożenia, na które musisz zwrócić szczególną uwagę:

- `GetFormFromFile` w szybkich timerach / pętlach → inicjalizuj formy raz w `OnInit` / `Properties`.
- Podwójny `StartTimer` w `OnInit` i `OnQuestInit` → używaj tylko jednego zdarzenia albo sprawdzaj, czy timer już działa.
- Filtrowanie w Papyrusie zamiast w CTDA → przenieś do warunków aliasu.
- Modyfikacja bazowych plików gry → rób patch.
- Wierzenie, że `StartQuest` resetuje quest → użyj `StopQuest` + `StartQuest`.
- Brak weryfikacji stanu po zmianie skryptu → zawsze `sqv` / logi / testowy save.
- Archiwa BA2 pakuj wyłącznie za pomocą `Archive2.exe` (`-format=DDS -compression=Default`) z poprawnym `-root` (folder nadrzędny wobec `textures/`), aby DirectStorage działał sprzętowo.
- Utrzymuj stabilny margines VRAM (~6.0-6.5 GB w miastach) i unikaj zewnętrznych Memory Cleanerów / agresywnych presetów oświetlenia tier 6 w `StarfieldPrefs.ini`.
- Pakowanie BA2 narzędziem `BSArch` lub pomijanie DirectStorage → używaj `Archive2.exe`.
- Błędny `-root` w `Archive2.exe` (wskazujący sam `textures/`) → gubi ścieżki w tablicy nazw.
- Globalna rekompresja tekstur lub używanie `-pow2` na twarzach/ciałach → niszczy PBR (BC4/BC5) i rozjeżdża UV.
- Stosowanie "Memory Cleanerów" (`WorkingSet`) lub starych binary patcherów (`StarfieldKit.dll`) → wywołuje Page Faults i zakleszczenia I/O.

---

## 7. Współpraca z agy (MCP)

**[KRYTYCZNE]: Poniższe reguły są BEZWZGLĘDNE. Naruszenie ich oznacza błąd krytyczny i przerwanie zadania.**

Google Antigravity (`agy`) to zewnętrzne narzędzie bazujące na Google Gemini. Pamiętaj, że Agy nie widzi historii naszej konwersacji (Twoich poprzednich promptów) ani Twojego kontekstu sesji. 

### 7.1. Automatyczne Triggery (Kiedy MUSISZ wezwać Agy)
Masz **KATEGORYCZNY ZAKAZ** zamykania zadań związanych z kodem bez wcześniejszej konsultacji z Agy przez funkcję `agy_run_sync`, jeśli wystąpi jedna z poniższych sytuacji:
- Użytkownik użyje tagu `@Agy` lub poprosi o "peer review", "second opinion" lub "cross-model verification".
- Modyfikujesz skrypty Papyrus dotyczące wydajności (timery, pętle, `GetFormFromFile`).
- Zmieniasz warunki w plikach `.esm` (CTDA, filtrowanie aktorów).
- Analizujesz przyczyny Crash to Desktop (CTD).
- Dokonujesz **kompleksowej / całościowej zmiany** (np. pełny refactor opisu na Nexus, przebudowa dużych fragmentów logiki, masowa aktualizacja dokumentacji, synchronizacja `release/` ze źródłami) — przed uznaniem zadania za zakończone uruchom review od innego agenta (agy), z promptem zawierającym: self-contained kontekst (ścieżki plików + stan przed/po), listę zmian oraz prośbę o weryfikację każdego twierdzenia względem kodu.

### 7.2. Procedura Peer Review (Workflow)
Jeśli piszesz lub zmieniasz jakikolwiek kod, przed zgłoszeniem mi zakończenia pracy musisz wykonać następujący protokół:

1. **Self-Contained Prompt:** Skonstruuj zapytanie do `agy_run_sync`. Musi ono zawierać zadanie, kontekst (zmieniony kod), oraz twarde ograniczenia z tego pliku (np. Papyrus jest jednowątkowy, GetFormFromFile nie w timerach, używaj Archive2.exe do BA2).
2. **Pobranie ID:** Zawsze zapamiętaj zwrócony `conversation_id` z pierwszego wywołania – to Twój klucz do utrzymania kontekstu dla kolejnych zapytań. 
3. **Serializacja:** Nigdy nie wywołuj dwóch zapytań równolegle na tym samym `conversation_id`.
4. **Zasada Zerowa (WERYFIKACJA):** Agy potrafi halucynować FormID oraz strukturę ESM. Masz obowiązek zweryfikować każde twierdzenie Agy za pomocą własnych narzędzi (np. `read`, `grep`, skryptów weryfikacyjnych w `src/`) ZANIM zastosujesz te porady w kodzie.

### 7.3. AGY jako Sub-Agent Kinematyczny (protokół pre-implementation)

Oprócz peer-review po implementacji, AGY MUSI być używane **PRZED** zmianą parametrów animacji (pozycje kości, amplitudy, częstotliwości, offsety kwaternionów). Protokół:

1. **Zderzenie założeń**: Zanim wygenerujesz nowy kandydat GLB, wyślij do AGY (kontynuując istniejący `conversation_id` jeśli dostępny):
   - Aktualne wartości parametrów z `modify_standself01.py`
   - Definition of Done użytkownika (pozycja dłoni, prędkość, brak penetracji)
   - Historię iteracji (jakie wartości były testowane, co użytkownik powiedział)
   - Rig referencyjny: `sf_animation_io_src/sf_animation_io-master/API/Assets/Rigs/human_female.rig`
2. **Samodzielne obliczenia AGY**: AGY ma wykonać FK (Forward Kinematics) z riga i obliczyć rzeczywistą pozycję końcówki łańcucha kostnego (np. dłoni/palców) dla proponowanych wartości.
3. **Rekomendacje**: AGY zasugeruje konkretne wartości liczbowe z uzasadnieniem kinematycznym (cm przesunięcia, stopnie obrotu, ryzyko penetracji).
4. **Zderzenie z moimi założeniami**: Porównaj rekomendacje AGY ze swoimi. Jeśli się różnią — zaufaj obliczeniom FK AGY (mają bazę w rigu), ale zweryfikuj logiczność.
5. **Pre-emptive tuning**: Jeśli użytkownik prosił o "więcej" 3+ razy z rzędu, AGY ma zasugerować wartość wystarczająco dużą by uniknąć kolejnego round-trip.
6. **Weryfikacja**: Po wygenerowaniu kandydata, zweryfikuj strukturalnie (normy kwaternionów, szew pętli, nieoczekiwane zmiany kanałów) lokalnymi skryptami.

### 7.4. Format Obowiązkowej Odpowiedzi (Exit Ticket)
Aby udowodnić mi, że wykonałeś obowiązkowy audyt, każda Twoja końcowa odpowiedź zamykająca zadanie opisane w punkcie 7.1 MUSI kończyć się następującym blokiem:

```text
---
[AGY-AUDIT-STATUS: PRZEPROWADZONO]
[CONVERSATION_ID: <tutaj wklej dokładne ID zwrócone przez agy_run_sync>]
[WYNIK WERYFIKACJI: <potwierdź jednym zdaniem, że użyłeś skryptu/read do weryfikacji twierdzeń Agy>]
---