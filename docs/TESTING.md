# Testing — OSF Autonomous

Test suite: `tests/` (pytest). Runs against the **specification** of each
contract — a failing test means the current state violates intent, not that
the test needs updating.

`tests/` lives in the repo but outside `release/`. `build_zip.ps1` only
stages `release/`, so test files can never reach the release ZIP — and
`test_zip_has_no_dev_or_source_files` guards that guarantee.

## Run

```powershell
# from repo_upload/
powershell -ExecutionPolicy Bypass -File run_tests.ps1
# or directly
py -m pytest tests -v
```

**Release gate:** `build_zip.ps1` runs `py -m pytest tests -x -q` before
packaging and **aborts the build** if the suite is red. Bypass only for
emergencies: `-SkipTests` (must be flagged to the user).

Requirements: Python via `py` launcher + `pytest`
(`py -m pip install -r tests/requirements-dev.txt`).

Papyrus compile tests need the game toolchain at `G:\Starfield`
(override via env var `STARFIELD_ROOT`). They are skipped automatically
if `PapyrusCompiler.exe` or the flags file is missing.

## Coverage (minimum scope)

| File | What it guards |
|:---|:---|
| `test_papyrus_compile.py` | `.psc` compiles with zero errors via real `PapyrusCompiler.exe`; shipped `.pex` is newer than `.psc` (no stale artifacts) |
| `test_data_json.py` | OSF scene pack schema + clip `.glb` existence; sound `spec` resolves to a pool for every gender/intensity; sound pools have non-empty `clips` (SF-TIK-001) + `.wem` existence; MCM settings schema/defaults; every MCM key is referenced by the script |
| `test_papyrus_static.py` | MCM parity: script reads == declared keys, `OSFSettings.Get*` type matches json type, code fallback == declared default, enum fallback ∈ options, `MOD_ID` == file id, `OnOSFSettingChanged` handles only declared keys. OSFSettings migration: no removed `OSFUI.*` settings API, no callback token, fixed callback name, subscribe-before-read ordering. Timers: named `TIMER_ID_*` only, all handled in `OnTimer`. Events: registered names ↔ `Type.Name` handlers, string callbacks → Functions. Stable signatures. Hygiene: no debug spam, `GetFormFromFile` only in init. Tags: allow-flag gating consistent across mf/ff pools, no dupes, within array capacity, gender literals `mf`/`ff`, pack queries carry `solo`, female solo query covered by shipped scenes |
| `test_release_build.py` | Real `build_zip.ps1` run: zip == `release/` minus `.psc`, no dev files, no empty dirs (TODO-004), no `\`/`./` in entry names (SF-TIK-002/004) |

## Known toolchain quirk

`PapyrusCompiler.exe` is flaky when the target `.psc` sits under `G:\Starfield`
(bogus `filename does not match script name` errors and rare .NET crashes).
Compiling a copy under `%TEMP%` is reliable — the test suite and
`src/build_script_only.ps1` both do this and copy the resulting `.pex` into
place. If you compile manually, prefer the same approach.

## Tier 4 — in-game self-test harness

`tests/papyrus/OSF_SelfTests.psc` — dev-only, **never shipped** (guarded by
`test_selftest_harness_not_in_release` + the zip payload-equality test).

Deploy to the game:

```powershell
powershell -ExecutionPolicy Bypass -File tests/papyrus/deploy_selftest.ps1
```

Run in-game (console `~`):

```
cgf "OSF_SelfTests.RunAll"
; or
bat osfselftest
```

Results go to `Logs/Script/User/OSF_Autonomous.log` tagged `[SELFTEST]`
(PASS/FAIL per check + summary).

What it verifies **live**: OSF readiness, manager instance, every MCM getter
wired to the right key (`mgr.GetX() == OSFSettings.Get*(key)` for all 20 keys),
constant getters, MCM range bounds, deterministic eligibility (player/None
rejected), query-builder output shape, action-pool vocabulary + flag-driven
sizes, tag rotation, pair-key symmetry + cooldown round-trip (uses the fake
`player:player` pair — harmless), init idempotency, furniture-scan sanity.

Checks that mutate state deliberately use only the impossible
`player:player` pair, which scenes can never form.
