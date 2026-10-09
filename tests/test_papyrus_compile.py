"""Tier 0 - Papyrus compile gate.

The .psc is compiled by the real PapyrusCompiler in a temp directory with the
game's Base sources on the include path. Spec: the shipped script must compile
with zero errors and produce a non-empty .pex.

Also guards artifact freshness: the shipped .pex must not be older than the
shipped .psc (i.e. source was edited but the binary was never rebuilt).
"""

import re
import shutil
import subprocess

import pytest

from conftest import (
    PAPYRUS_COMPILER,
    PAPYRUS_FLAGS,
    PAPYRUS_SOURCE_DIR,
    PEX_PATH,
    PSC_PATH,
    REPO_ROOT,
    SCRIPT_STEM,
)

SELFTEST_PSC = REPO_ROOT / "tests" / "papyrus" / "OSF_SelfTests.psc"
E2E_PSC = REPO_ROOT / "tests" / "papyrus" / "OSF_E2ETests.psc"
COMPILE_TARGETS = [
    pytest.param(PSC_PATH, id=PSC_PATH.name),
    pytest.param(SELFTEST_PSC, id=SELFTEST_PSC.name),
    pytest.param(E2E_PSC, id=E2E_PSC.name),
]

needs_toolchain = pytest.mark.skipif(
    not PAPYRUS_COMPILER.exists() or not PAPYRUS_FLAGS.exists(),
    reason="PapyrusCompiler or Starfield flags file not found (set STARFIELD_ROOT)",
)

_ERROR_LINE = re.compile(r"(?i)\berror\b")
_OK_SUMMARY = re.compile(r"(?i)\b0 errors?\b|\bno errors?\b")


@needs_toolchain
@pytest.mark.parametrize("psc_path", COMPILE_TARGETS)
def test_psc_compiles_without_errors(tmp_path, psc_path):
    assert psc_path.exists(), f"missing script source: {psc_path}"

    work = tmp_path / "src"
    work.mkdir()
    src = work / psc_path.name
    shutil.copy2(psc_path, src)
    out_dir = tmp_path / "out"
    out_dir.mkdir()

    includes = f"{PAPYRUS_SOURCE_DIR};{PAPYRUS_SOURCE_DIR / 'Base'}"
    proc = subprocess.run(
        [
            str(PAPYRUS_COMPILER),
            str(src),
            f"-f={PAPYRUS_FLAGS}",
            f"-o={out_dir}",
            f"-i={includes}",
        ],
        capture_output=True,
        timeout=300,
    )
    # Compiler emits non-locale bytes in some messages - decode leniently
    output = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")

    error_lines = [
        line
        for line in output.splitlines()
        if _ERROR_LINE.search(line) and not _OK_SUMMARY.search(line)
    ]
    assert not error_lines, "Papyrus compilation reported errors:\n" + "\n".join(
        error_lines
    ) + "\n\nfull output:\n" + output

    pex = out_dir / f"{psc_path.stem}.pex"
    assert pex.exists(), f"compiler produced no .pex. output:\n{output}"
    assert pex.stat().st_size > 0


def test_release_pex_is_fresh():
    """The shipped .pex must have been built from the current shipped .psc."""
    assert PSC_PATH.exists(), f"missing script source: {PSC_PATH}"
    assert PEX_PATH.exists(), f"missing compiled script: {PEX_PATH}"
    assert PEX_PATH.stat().st_mtime >= PSC_PATH.stat().st_mtime, (
        f"{PEX_PATH.name} is older than {PSC_PATH.name} - "
        "the script was edited but never recompiled into release/"
    )
