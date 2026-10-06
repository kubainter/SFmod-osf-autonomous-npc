"""Shared fixtures and path constants for the OSF Autonomous test suite.

Tests are written against the *specification* of each file format / contract,
not against the current state of the code. If the current implementation
violates the spec, the test is expected to fail - that is the signal.

Layout note: this directory lives in the repo but outside release/.
build_zip.ps1 only stages release/, so nothing here can ship in the ZIP.
"""

import os
from pathlib import Path

import pytest

# --- Repository layout -------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[1]
RELEASE_DIR = REPO_ROOT / "release"
RELEASE_DATA = RELEASE_DIR / "Data"
OSF_DIR = RELEASE_DATA / "OSF"
MCM_SETTINGS_PATH = (
    RELEASE_DATA / "SFSE" / "Plugins" / "OSFUI" / "settings" / "osf.autonomous.json"
)

# --- Papyrus toolchain (game install, overridable via env) --------------------
GAME_ROOT = Path(os.environ.get("STARFIELD_ROOT", r"G:\Starfield"))
PAPYRUS_COMPILER = GAME_ROOT / "Tools" / "Papyrus Compiler" / "PapyrusCompiler.exe"
PAPYRUS_SOURCE_DIR = GAME_ROOT / "Data" / "Scripts" / "Source"
PAPYRUS_FLAGS = PAPYRUS_SOURCE_DIR / "Base" / "Starfield_Papyrus_Flags.flg"

# --- The mod's script ---------------------------------------------------------
SCRIPT_STEM = "OSF_AutonomousManagerScript"
PSC_PATH = RELEASE_DATA / "Scripts" / "Source" / f"{SCRIPT_STEM}.psc"
PEX_PATH = RELEASE_DATA / "Scripts" / f"{SCRIPT_STEM}.pex"


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def release_dir() -> Path:
    return RELEASE_DIR


@pytest.fixture(scope="session")
def release_data() -> Path:
    return RELEASE_DATA
