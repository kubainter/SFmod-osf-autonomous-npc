# Starfield Workspace — Directory Map

Szybka orientacja, gdzie znajdują się pliki gry, mody, źródła i logi. Traktuj to jako mapę bezpiecznych i niebezpiecznych obszarów.

## Kategorie bezpieczeństwa

- **Bezpieczne do edycji** — pliki modów / własne źródła / logi.
- **Tylko do odczytu / kopie** — podstawowa gra; zmiany wyłącznie przez patch albo zachowawczo.
- **Wynikowe / generowane** — pliki powstałe po kompilacji lub uruchomieniu gry; nie edytuj ręcznie.

---

## Główny katalog gry

`G:\Starfield\`

- `Starfield.exe` — plik wykonywalny gry. **Nie modyfikuj.**
- `sfse_1_*.dll`, `sfse_loader.exe` — SFSE. **Nie modyfikuj.**
- `CreationKit.exe` — edytor gry.
- `.agents\` — reguły agenta (w tym `AGENTS.md`).
- `.devin\` — pliki meta projektu: `directory_map.md`, `anti_patterns.md`, `lessons_learned.md`, `config.local.json`.
- `Bethini Pie*`, `Config\`, `D3D12\`, `Documents\` — konfiguracje i nakładki graficzne.
- `vortex.deployment.json` — stan wdrożenia Vortex; **nie edytuj ręcznie**.
- `Starfield.ini`, `High.ini`, `Medium.ini`, `Low.ini` — predefiniowane presety. Nie nadpisuj bez kopii.
- `materials\`, `meshes\`, `textures\`, `SAF\`, `Scripts\` — **Vortex-managed** (hardlinki). Nie ruszaj ręcznie.
- `temp-dodi\` — temp z instalatora Dodi. Nie ruszaj.

## Modów i danych gry

`G:\Starfield\Data\`

- `*.esm`, `*.esp` — ładowane pluginy (głównie mody, część bazowa). Sprawdź w `plugins.txt`, zanim coś dotkniesz.
- `*.ba2` — zarchiwizowane assety (tekstury, meshe, dźwięki). Do tworzenia użyj `Tools\Archive2`.
- `Scripts\` — skompilowane skrypty Papyrusa (`.pex`). **Wynikowe.** Źródła są w `Scripts\Source\` lub folderze moda.
- `Scripts\Source\` — źródła `.psc` (jeśli istnieją). Bezpieczne do edycji, jeśli należą do modu.
- `Data\Docs\` — dokumentacje modów (`Ship Vendor Framework`, patche).
- `Data\SFSE\Plugins\` — logi i konfigi pluginów SFSE (np. `sfse_plugin_console.log`).

## Źródła własnych pluginów SFSE / C++

`G:\Starfield\StarfieldDev\src\`

- `HighlightQuestGivers\` — przykładowy projekt SFSE (`main.cpp`, `build*.ps1`, `template.esm`).
- `sfse-0.2.21\` — rozpakowane źródła SFSE. Traktuj jako SDK; nie modyfikuj, chyba że celowo testujesz build.
- `OSFAutonomous\` — źródła moda OSF Autonomous (`.psc`, `.py`, `.json`, `build.ps1`).
- `find_shaders.cpp` — drobne narzędzie lokalne.

## Narzędzia deweloperskie

`G:\Starfield\Tools\`

- `Papyrus Compiler\PapyrusCompiler.exe` — kompilator Papyrusa.
- `Champollion\Champollion.exe` — deasembler `.pex` -> `.psc`.
- `Archive2\Archive2.exe` — pakowanie `*.ba2`.
- `AssetWatcher\` — obserwator assetów do edycji mesha/tekstur.
- `VSCodePapyrusAddon\` — rozszerzenie Papyrus do VS Code.

## Logi i konfiguracja użytkownika

- `C:\Users\kubai\AppData\Local\Starfield\plugins.txt` — aktywna lista modów/ESL/ESM. Odczytaj przed debugowaniem.
- `C:\Users\kubai\Documents\My Games\Starfield\Logs\Script\` — logi Papyrusa (np. `Papyrus.0.log`).
- `C:\Users\kubai\Documents\My Games\Starfield\Logs\Script\User\` — logi modów (np. `SFF_Distributor.0.log`).
- `C:\Users\kubai\Documents\My Games\Starfield\StarfieldCustom.ini` — ustawienia użytkownika (Papyrus logging, itp.).
- `C:\Users\kubai\Documents\My Games\Starfield\StarfieldPrefs.ini` — preferencje graficzne.

## Inne ważne katalogi

- `Plugins\` — alternatywna ścieżka dla niektórych narzędzi; sprawdź zawartość w razie potrzeby.
- `SFSE\` — instalacja / narzędzia SFSE (np. `sfse_loader.exe` kopia); zachowaj ostrożność.

---

## Workspace deweloperski

`G:\Starfield\StarfieldDev\`

Katalog roboczy dla developmentu — oddzielony od plików gry. Wszystkie skrypty Python, źródła, release i backupy są tutaj.

### Struktura

```
StarfieldDev\
├── src\                          — źródła pluginów (OSFAutonomous, HighlightQuestGivers, sfse-0.2.21)
├── animation_references\         — referencyjne animacje .af + GLB z Blender
│   ├── blender_edit\             — edytowane GLB (solo_standing_touch.glb)
│   └── preview\                  — podgląd .af
├── extracted_vanilla\            — ekstrakcja vanilla animacji (.af/.afx) z $outDir
├── release\                      — release ZIPy i build output
│   ├── OSFAutonomous\            — staging release (Data, fomod, README, CHANGELOG)
│   └── archive\                  — archiwalne wersje (v1.0.0.zip)
├── backups\                      — backupy plików gry i modów
│   ├── bsarch\                   — backupy BA2 (backup_bsarch_versions)
│   ├── morph\                    — backup morph.dat (backup_haters_head_morph)
│   ├── dlls_2026_08_20\          — backup DLL (backup_replaced_dlls_2026-08-20)
│   └── v1_16_242\                — backup gier v1.16.242 (backups_DLL)
├── temp\                         — pliki tymczasowe z ekstrakcji
│   ├── temp_animations_extract\  — ekstrakcja BA2 animacji
│   ├── temp_facemesh\            — ekstrakcja FaceMeshes
│   └── temp_facegeom\            — temp NIF face geometry
└── archive\
    └── trash\                    — śmieci/testy (dawne ŚMIECI JAKIEŚ)
```

### Kluczowe pliki w `StarfieldDev\src\OSFAutonomous\`

- `OSF_AutonomousManagerScript.psc` — główny skrypt Papyrus moda
- `osfautonomous-solo.osf.json` — manifest sceny solo
- `osfautonomous-solo.sounds.json` — manifest dźwięków
- `modify_standself01.py` — skrypt Blender modyfikujący animację
- `generate_osf_solo_animations.py` — generator animacji proceduralnych
- `build.ps1` — skrypt budujący release
- `osf.autonomous.json` — ustawienia OSFUI

### Kluczowe pliki w `StarfieldDev\release\OSFAutonomous\`

- `fomod\ModuleConfig.xml` — konfiguracja FOMOD installera
- `fomod\info.xml` — metadane FOMOD (wersja)
- `Data\` — pliki dystrybucyjne (esm, json, glb, pex, wem)
- `README.txt`, `CHANGELOG.txt`, `nexus_description.md` — dokumentacja
- `dev_source\` — artefakty deweloperskie (nie w ZIP)

### Reguły budowania ZIP

- **Whitelist only** — pakuj tylko pliki dystrybucyjne, nigdy rekursywnie cały `Data\`
- **Zabronione w ZIP**: `Data\Scripts\Source\` (`.psc`), `dev_source\`, `nexus_description.md`, `CHANGELOG.txt`, skrypty Python, narzędzia build
- **Wymagane w ZIP**: `README.txt`, `Data\` (tylko `.esm`, `.json`, `.glb`, `.pex`, `.wem`), `fomod\info.xml`, `fomod\ModuleConfig.xml`
- **Po każdej zmianie**: aktualizuj `CHANGELOG.txt` z opisem co dodano/zmieniono/naprawiono
- **Archiwizuj** poprzednie ZIP do `StarfieldDev\release\archive\` przed nadpisaniem
