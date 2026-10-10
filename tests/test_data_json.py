"""Tier 2 - data file spec tests.

Validates the three JSON contracts the mod ships:

  Data/OSF/*.osf.json          - OSF scene-pack definition
  Data/OSF/*.sounds.json       - OSF sound pools
  Data/SFSE/Plugins/OSFUI/...  - OSFUI (MCM) settings

These encode the *specification* of each format plus the cross-file
referential integrity the game loader relies on (e.g. every referenced
.glb/.wem must exist, every sound `spec` must resolve to a pool, no pool may
declare an empty `clips` map - the SF-TIK-001 pack-load crash).
"""

import json
import re
from pathlib import Path

import pytest

from conftest import MCM_SETTINGS_PATH, OSF_DIR, PSC_PATH, RELEASE_DATA

KNOWN_GENDERS = {"female", "male"}
SETTING_TYPES = {"bool", "int", "float", "enum", "string"}


def _load(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _data_rel(path_str: str) -> Path:
    """A path inside a pack file is relative to Data/."""
    return RELEASE_DATA / Path(path_str.replace("/", "\\"))


# ---------------------------------------------------------------------------
# OSF scene packs (Data/OSF/*.osf.json)
# ---------------------------------------------------------------------------

OSF_PACKS = sorted(OSF_DIR.glob("*.osf.json"))
SOUND_PACKS = sorted(OSF_DIR.glob("*.sounds.json"))

assert OSF_PACKS, f"no .osf.json packs found in {OSF_DIR}"


def _pools_by_tags():
    """All shipped sound pools as (file, pool_name, frozenset(tags), pool)."""
    out = []
    for path in SOUND_PACKS:
        for pool in _load(path).get("pools", []):
            out.append(
                (path.name, pool.get("name", ""), frozenset(pool.get("tags", [])), pool)
            )
    return out


@pytest.mark.parametrize("pack_path", OSF_PACKS, ids=[p.name for p in OSF_PACKS])
class TestOsfScenePack:
    def test_root_shape(self, pack_path):
        data = _load(pack_path)
        assert isinstance(data.get("schema"), int)
        assert data.get("name"), "pack must have a name"
        assert data.get("pack"), "pack must have a pack tag"
        scenes = data.get("scenes")
        assert isinstance(scenes, list) and scenes, "scenes must be non-empty"

    def test_scenes_have_unique_ids_and_required_fields(self, pack_path):
        scenes = _load(pack_path)["scenes"]
        ids = [s.get("id") for s in scenes]
        assert all(ids), "every scene needs an id"
        assert len(ids) == len(set(ids)), f"duplicate scene ids: {ids}"
        for scene in scenes:
            sid = scene["id"]
            assert scene.get("name"), f"{sid}: missing name"
            assert scene.get("tags"), f"{sid}: tags must be non-empty"
            roles = [r.get("name") for r in scene.get("roles", [])]
            assert roles, f"{sid}: roles must be non-empty"
            assert len(roles) == len(set(roles)), f"{sid}: duplicate role names"
            assert scene.get("stages"), f"{sid}: stages must be non-empty"

    def test_stage_clips_exist(self, pack_path):
        """Every clip referenced by a stage must be a .glb that exists in Data/."""
        for scene in _load(pack_path)["scenes"]:
            for stage in scene["stages"]:
                label = f"{scene['id']}::{stage.get('name', '?')}"
                clips = stage.get("clips")
                assert clips, f"{label}: clips must be a non-empty list"
                for clip in clips:
                    assert clip.lower().endswith(".glb"), f"{label}: not a .glb: {clip}"
                    assert _data_rel(clip).exists(), (
                        f"{label}: clip not found in release Data/: {clip}"
                    )
                if "loops" in stage:
                    assert isinstance(stage["loops"], int) and stage["loops"] >= 0

    def test_sound_specs_resolve_to_pools(self, pack_path):
        """Each stage sound spec like '$pack,{gender},moan' must, for every
        gender the scene targets and every 'at' intensity key, resolve to a
        pool whose tags cover {pack, gender, action..., intensity}."""
        data = _load(pack_path)
        pools = _pools_by_tags()
        assert pools, "no sound pools shipped to resolve spec against"

        for scene in data["scenes"]:
            role_names = {r["name"] for r in scene["roles"]}
            scene_genders = KNOWN_GENDERS & set(scene["tags"])
            for stage in scene["stages"]:
                label = f"{scene['id']}::{stage.get('name', '?')}"
                for sound in stage.get("sound", []):
                    assert sound.get("role") in role_names, (
                        f"{label}: sound role {sound.get('role')!r} not in scene roles"
                    )
                    spec = sound.get("spec", "")
                    assert spec.startswith("$"), f"{label}: bad spec {spec!r}"
                    parts = [p.strip().lower() for p in spec[1:].split(",")]
                    assert all(parts), f"{label}: empty component in spec {spec!r}"

                    if "{gender}" in parts:
                        genders = scene_genders or KNOWN_GENDERS
                    else:
                        genders = {None}
                    at_keys = list(sound.get("at", {}).keys())
                    assert at_keys, f"{label}: sound spec has no 'at' intensities"

                    for gender in genders:
                        resolved = {
                            gender if p == "{gender}" else p for p in parts
                        }
                        for at_key in at_keys:
                            required = resolved | {at_key.lower()}
                            match = any(required <= tags for _, _, tags, _ in pools)
                            assert match, (
                                f"{label}: no sound pool covers tags "
                                f"{sorted(required)} (spec {spec!r}, at='{at_key}')"
                            )


# ---------------------------------------------------------------------------
# OSF sound packs (Data/OSF/*.sounds.json)
# ---------------------------------------------------------------------------

assert SOUND_PACKS, f"no .sounds.json packs found in {OSF_DIR}"


@pytest.mark.parametrize("pack_path", SOUND_PACKS, ids=[p.name for p in SOUND_PACKS])
class TestOsfSoundPack:
    def test_root_shape(self, pack_path):
        data = _load(pack_path)
        assert isinstance(data.get("schema"), int)
        pools = data.get("pools")
        assert isinstance(pools, list) and pools, "pools must be non-empty"

    def test_pools_have_unique_names_tags_and_nonempty_clips(self, pack_path):
        """SF-TIK-001 regression: an empty clips map crashes the OSF loader."""
        pools = _load(pack_path)["pools"]
        names = [p.get("name") for p in pools]
        assert all(names), "every pool needs a name"
        assert len(names) == len(set(names)), f"duplicate pool names: {names}"
        for pool in pools:
            pname = pool["name"]
            assert pool.get("tags"), f"{pname}: tags must be non-empty"
            clips = pool.get("clips")
            assert isinstance(clips, dict) and clips, (
                f"{pname}: clips must be a non-empty map (SF-TIK-001)"
            )
            for clip_path, caption in clips.items():
                assert clip_path.lower().endswith(".wem"), (
                    f"{pname}: not a .wem: {clip_path}"
                )
                assert _data_rel(clip_path).exists(), (
                    f"{pname}: clip not found in release Data/: {clip_path}"
                )
                assert isinstance(caption, str) and caption.strip(), (
                    f"{pname}: empty caption for {clip_path}"
                )


# ---------------------------------------------------------------------------
# OSFUI / MCM settings (osf.autonomous.json)
# ---------------------------------------------------------------------------


class TestMcmSettings:
    def test_root_shape(self):
        data = _load(MCM_SETTINGS_PATH)
        assert data.get("id") == "osf.autonomous"
        assert data.get("title"), "settings need a title"
        assert isinstance(data.get("version"), int)
        groups = data.get("groups")
        assert isinstance(groups, list) and groups, "groups must be non-empty"

    def _settings(self):
        return [
            (group["id"], setting)
            for group in _load(MCM_SETTINGS_PATH)["groups"]
            for setting in group.get("settings", [])
        ]

    def test_groups_have_settings(self):
        for group in _load(MCM_SETTINGS_PATH)["groups"]:
            assert group.get("id") and group.get("label"), f"group missing id/label: {group}"
            assert group.get("settings"), f"group {group.get('id')}: no settings"

    def test_setting_keys_unique(self):
        keys = [s.get("key") for _, s in self._settings()]
        assert all(keys), "every setting needs a key"
        dupes = {k for k in keys if keys.count(k) > 1}
        assert not dupes, f"duplicate setting keys: {dupes}"

    def test_setting_types_and_defaults(self):
        for gid, s in self._settings():
            key, stype = s.get("key"), s.get("type")
            label = f"{gid}.{key}"
            assert s.get("label"), f"{label}: missing label"
            assert stype in SETTING_TYPES, f"{label}: unknown type {stype!r}"
            assert "default" in s, f"{label}: no default"
            default = s["default"]

            if stype == "bool":
                assert isinstance(default, bool), f"{label}: default not bool"
            elif stype == "int":
                assert isinstance(default, int) and not isinstance(default, bool), (
                    f"{label}: default not int"
                )
            elif stype == "float":
                assert isinstance(default, (int, float)) and not isinstance(
                    default, bool
                ), f"{label}: default not numeric"
            elif stype == "enum":
                options = s.get("options")
                assert isinstance(options, list) and options, (
                    f"{label}: enum needs non-empty options"
                )
                assert str(default) in [str(o) for o in options], (
                    f"{label}: default {default!r} not in options"
                )
                if "optionLabels" in s:
                    assert len(s["optionLabels"]) == len(options), (
                        f"{label}: optionLabels length != options length"
                    )

            if "min" in s or "max" in s:
                lo, hi = s.get("min", default), s.get("max", default)
                assert lo <= hi, f"{label}: min > max"
                assert lo <= default <= hi, f"{label}: default out of range"
            if "step" in s:
                assert s["step"] > 0, f"{label}: step must be positive"

    def test_every_setting_key_is_read_by_the_script(self):
        """A setting the Papyrus script never reads is dead config."""
        psc = PSC_PATH.read_text(encoding="utf-8", errors="replace")
        missing = [s["key"] for _, s in self._settings() if s["key"] not in psc]
        assert not missing, (
            f"MCM keys not referenced in {PSC_PATH.name}: {missing}"
        )
