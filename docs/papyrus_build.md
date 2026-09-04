# Kompilacja skryptów Papyrus — Starfield

Przewodnik krok po kroku dla tego workspace. Parametry pochodzą z istniejącego pliku `Data\Scripts\Source\PapyrusCompileRelease.cmd` i sprawdzonych kompilacji w poprzednich sesjach.

---

## Ścieżki kluczowe

- **Kompilator:** `G:\Starfield\Tools\Papyrus Compiler\PapyrusCompiler.exe`
- **Źródła użytkownika / modów:** `G:\Starfield\Data\Scripts\Source`
- **Źródła bazowe (Base):** `G:\Starfield\Data\Scripts\Source\Base`
- **Wyjście (`.pex`):** `G:\Starfield\Data\Scripts`
- **Flagi kompilatora:** `G:\Starfield\Data\Scripts\Source\Base\Starfield_Papyrus_Flags.flg`

---

## Kompilacja jednego pliku

### Pełna opcja RELEASE

```powershell
& "G:\Starfield\Tools\Papyrus Compiler\PapyrusCompiler.exe" `
  "G:\Starfield\Data\Scripts\Source\NazwaMojegoSkryptu.psc" `
  -import="G:\Starfield\Data\Scripts\Source;G:\Starfield\Data\Scripts\Source\Base" `
  -output="G:\Starfield\Data\Scripts" `
  -flags="G:\Starfield\Data\Scripts\Source\Base\Starfield_Papyrus_Flags.flg" `
  -release -final -optimize
```

### Opcja DEBUG (zachowuje logi / mniej agresywna optymalizacja)

```powershell
& "G:\Starfield\Tools\Papyrus Compiler\PapyrusCompiler.exe" `
  "G:\Starfield\Data\Scripts\Source\NazwaMojegoSkryptu.psc" `
  -import="G:\Starfield\Data\Scripts\Source;G:\Starfield\Data\Scripts\Source\Base" `
  -output="G:\Starfield\Data\Scripts" `
  -flags="G:\Starfield\Data\Scripts\Source\Base\Starfield_Papyrus_Flags.flg" `
  -optimize
```

### Skrócony, jeśli aktualny katalog to `Tools\Papyrus Compiler`

```cmd
PapyrusCompiler.exe "..\..\Data\Scripts\Source\NazwaMojegoSkryptu.psc" -import="..\..\Data\Scripts\Source;..\..\Data\Scripts\Source\Base" -output="..\..\Data\Scripts" -flags="..\..\Data\Scripts\Source\Base\Starfield_Papyrus_Flags.flg" -optimize
```

---

## Kompilacja za pomocą istniejącego pliku `.cmd`

W katalogu `G:\Starfield\Data\Scripts\Source` leży `PapyrusCompileRelease.cmd`:

```cmd
cd "G:\Starfield\Data\Scripts\Source"
PapyrusCompileRelease.cmd NazwaMojegoSkryptu.psc
```

Plik ten ustawia wszystkie ścieżki automatycznie i używa flag `-release -final -optimize`.

---

## Co znaczą parametry

| Parametr | Znaczenie |
|----------|-----------|
| `PapyrusCompiler.exe "ścieżka\do\pliku.psc"` | Plik źródłowy do skompilowania. Jeśli podasz katalog, kompiluje wszystkie `.psc` w nim. |
| `-import=PATH1;PATH2` | Gdzie kompilator szuka importowanych skryptów (bazowych i twoich). **Zawsze podawaj obie ścieżki** — swoją i `Base`. |
| `-output=PATH` | Gdzie wyląduje `.pex`. Standardowo `Data\Scripts`. |
| `-flags=PATH\*.flg` | Plik flag kompilatora (wymagany). Dla Starfield to `Starfield_Papyrus_Flags.flg`. |
| `-optimize` | Włącza optymalizację kodu. |
| `-release -final` | Dodatkowe opcje produkcyjne używane w `PapyrusCompileRelease.cmd`. |

---

## Najczęstsze błędy

1. **Brakujący `-import=...\Base`**
   - Objaw: `Script 'XYZ' not found on import path` albo brak rozpoznawanych funkcji silnika.
   - Rozwiązanie: zawsze dodaj `G:\Starfield\Data\Scripts\Source\Base` po średniku.

2. **Błędna ścieżka do `.flg`**
   - Objaw: `Could not open flags file` lub kompilacja zachodzi bez odpowiednich stałych silnika.
   - Rozwiązanie: wskaż `G:\Starfield\Data\Scripts\Source\Base\Starfield_Papyrus_Flags.flg`.

3. **`-output` wskazuje na niewłaściwy katalog**
   - Objaw: `.pex` ląduje w `Source` zamiast w `Data\Scripts` lub jest niewidoczny dla gry.
   - Rozwiązanie: `-output="G:\Starfield\Data\Scripts"`.

4. **Nadpisanie bazowego `.pex`**
   - Nie kompiluj do `Data\Scripts` plików o nazwach bazowych gry, chyba że celowo tworzysz patch.
   - Dla modów używaj unikalnych prefiksów, np. `MyMod_*.psc`.

5. **Brak flagi `-optimize` w kodzie debugowym**
   - W fazie testowania lepiej użyć samego `-optimize` bez `-release -final`, żeby łatwiej było śledzić błędy w logach.

---

## Po kompilacji

1. Sprawdź, czy `.pex` powstał w `G:\Starfield\Data\Scripts\NazwaMojegoSkryptu.pex`.
2. Jeśli quest był już uruchomiony, w grze po wczytaniu save wykonaj:
   ```
   StopQuest <FormID>
   StartQuest <FormID>
   ```
3. Sprawdź logi:
   - `C:\Users\kubai\Documents\My Games\Starfield\Logs\Script\Papyrus.0.log`
   - `C:\Users\kubai\Documents\My Games\Starfield\Logs\Script\User\NazwaModu.0.log`
   - `G:\Starfield\Data\SFSE\Plugins\sfse_plugin_console.log`
