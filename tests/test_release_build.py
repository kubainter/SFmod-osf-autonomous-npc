"""Tier 3 - release package spec.

Runs the real build_zip.ps1 with a throwaway version, then checks the ZIP
against the package spec:

  * content == every file under release/ minus never-shipped sources (.psc)
  * no dev/test files can leak in (tests/, src/, *.py, *.ps1, staging/, .git)
  * no empty directory entries (SF-TIK-TODO-004: empty Scripts/Source/ dir)
  * no backslashes or './' prefixes in entry names (SF-TIK-002/004 MO2 bugs)
"""

import subprocess
import zipfile
from pathlib import Path

import pytest

from conftest import RELEASE_DIR, REPO_ROOT

TEST_VERSION = "0.0.0-test"
NEVER_SHIPPED_SUFFIXES = {".psc"}  # script sources are stripped by the builder
FORBIDDEN_SUFFIXES = {".psc", ".py", ".ps1", ".bak", ".pyc"}
FORBIDDEN_PARTS = {"tests", "src", "staging", ".git", "__pycache__"}


@pytest.fixture(scope="module")
def built_zip():
    zip_path = REPO_ROOT / "zips" / f"OSFAutonomous_v{TEST_VERSION}.zip"
    proc = subprocess.run(
        [
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(REPO_ROOT / "build_zip.ps1"),
            "-Version", TEST_VERSION,
            "-SkipTests",  # avoid recursion: the suite IS the gate
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=300,
    )
    assert proc.returncode == 0, (
        f"build_zip.ps1 failed:\n{proc.stdout}\n{proc.stderr}"
    )
    assert zip_path.exists(), "builder did not produce the expected zip"
    yield zip_path
    zip_path.unlink(missing_ok=True)


def _expected_files() -> set:
    """Spec: the archive must contain exactly the release/ payload, minus
    file types that are never shipped (Papyrus source)."""
    expected = set()
    for f in RELEASE_DIR.rglob("*"):
        if f.is_file() and f.suffix.lower() not in NEVER_SHIPPED_SUFFIXES:
            expected.add(f.relative_to(RELEASE_DIR).as_posix())
    return expected


def test_zip_entry_names_are_clean(built_zip):
    with zipfile.ZipFile(built_zip) as z:
        names = z.namelist()
    for name in names:
        assert not name.startswith("./"), f"'./' prefixed entry: {name}"
        assert "\\" not in name, f"backslash in entry name: {name}"


def test_zip_contains_exact_release_payload(built_zip):
    with zipfile.ZipFile(built_zip) as z:
        file_entries = {n for n in z.namelist() if not n.endswith("/")}
    expected = _expected_files()
    missing = expected - file_entries
    extra = file_entries - expected
    assert not missing, f"files missing from zip: {sorted(missing)}"
    assert not extra, f"unexpected files in zip: {sorted(extra)}"


def test_zip_has_no_dev_or_source_files(built_zip):
    with zipfile.ZipFile(built_zip) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
    for name in names:
        p = Path(name)
        assert p.suffix.lower() not in FORBIDDEN_SUFFIXES, (
            f"forbidden file type shipped: {name}"
        )
        assert not (FORBIDDEN_PARTS & set(p.parts)), (
            f"dev directory leaked into zip: {name}"
        )


def test_selftest_harness_not_in_release():
    """The in-game self-test script is dev-only: it must never exist under
    release/ (and therefore can never reach the zip)."""
    leaked = list(RELEASE_DIR.rglob("OSF_SelfTests*"))
    assert not leaked, f"self-test files leaked into release/: {leaked}"


def test_zip_has_no_empty_directories(built_zip):
    """Every explicit dir entry in the zip must contain at least one file
    (regression: empty Data/Scripts/Source/ ships today - TODO-004)."""
    with zipfile.ZipFile(built_zip) as z:
        names = z.namelist()
    files = {n for n in names if not n.endswith("/")}
    empty = [
        d for d in names if d.endswith("/") and not any(f.startswith(d) for f in files)
    ]
    assert not empty, f"empty directories shipped in zip: {empty}"
