"""Tier 1 - static Papyrus contract tests.

Verifies the contracts OSF_AutonomousManagerScript.psc must honor, without
running the game:

  * MCM parity    - every OSFSettings.Get*(MOD_ID, key, fallback) reads a key that
                    exists in osf.autonomous.json, with matching type, a
                    fallback equal to the declared default, and (for enums)
                    a fallback that is itself a declared option. No MCM key
                    may be dead config, no read key may be undeclared.
  * Timers        - every StartTimer/CancelTimer uses a named TIMER_ID_*
                    constant; every declared timer is handled in OnTimer.
  * Events        - every RegisterForRemoteEvent name has an Event handler;
                    every remote (Type.Name) handler is registered; every
                    string-callback registration resolves to a Function.
  * Signatures    - the stable API surface (events, callbacks, pipeline).
  * Hygiene       - no Debug.Notification/MessageBox/main-log Trace;
                    GetFormFromFile only inside init functions.
  * Tag logic     - action pool tags are guarded by allow-flags, consistent
                    across gender branches, within array capacity; gender
                    literals are only 'mf'/'ff'; queries carrying our pack
                    tag are coverable by shipped scenes.
"""

import json
import re
from pathlib import Path

import pytest

from conftest import MCM_SETTINGS_PATH, OSF_DIR, PSC_PATH

PSC_TEXT = PSC_PATH.read_text(encoding="utf-8", errors="replace")
PSC_LINES = PSC_TEXT.splitlines()

GETTER_TYPE = {
    "GetBool": {"bool"},
    "GetInt": {"int"},
    "GetFloat": {"float"},
    "GetEnum": {"enum"},
    "GetString": {"string"},
}

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------


def _code_lines():
    """(lineno, code) pairs with ';' comments stripped."""
    out = []
    for i, line in enumerate(PSC_LINES, start=1):
        code = line.split(";", 1)[0].rstrip()
        if code.strip():
            out.append((i, code))
    return out


CODE_LINES = _code_lines()
CODE_TEXT = "\n".join(code for _, code in CODE_LINES)


def _blocks():
    """All Function/Event blocks: (kind, name, start, end, body_lines)."""
    blocks = []
    kind = name = start = None
    body = []
    for lineno, code in CODE_LINES:
        if kind is None:
            m = re.match(r"\s*(?:[\w:\[\]]+\s+)?Function\s+(\w+)\s*\(", code)
            if m:
                kind, name, start, body = "Function", m.group(1), lineno, []
                continue
            m = re.match(r"\s*Event\s+([\w.]+)\s*\(", code)
            if m:
                kind, name, start, body = "Event", m.group(1), lineno, []
                continue
        else:
            body.append((lineno, code))
            if re.match(r"\s*End(Function|Event)\b", code):
                blocks.append((kind, name, start, lineno, body))
                kind = name = start = None
                body = []
    return blocks


BLOCKS = _blocks()


def _body_of(name):
    for kind, bname, start, end, body in BLOCKS:
        if bname == name:
            return kind, start, end, body
    raise AssertionError(f"block not found: {name}")


def _mcm_settings():
    data = json.loads(MCM_SETTINGS_PATH.read_text(encoding="utf-8"))
    return {
        s["key"]: s
        for g in data["groups"]
        for s in g["settings"]
    }


MCM = _mcm_settings()

# OSFSettings.Get*(MOD_ID, "key", fallback) -> (api, key, raw_fallback)
_GET_RE = re.compile(
    r"OSFSettings\.(GetBool|GetInt|GetFloat|GetEnum|GetString)\(\s*MOD_ID\s*,\s*"
    r'"([^"]+)"\s*,\s*([^,\)]+)'
)
SETTINGS_READS = _GET_RE.findall(CODE_TEXT)


def _literal(raw: str):
    """Parse a Papyrus literal argument to a Python value."""
    raw = raw.strip()
    if raw.startswith('"') and raw.endswith('"'):
        return raw[1:-1]
    if raw.lower() == "true":
        return True
    if raw.lower() == "false":
        return False
    try:
        return int(raw)
    except ValueError:
        return float(raw)


# ---------------------------------------------------------------------------
# MCM parity
# ---------------------------------------------------------------------------


class TestMcmParity:
    def test_read_keys_equal_declared_keys(self):
        read_keys = {key for _, key, _ in SETTINGS_READS}
        declared = set(MCM)
        assert not (read_keys - declared), (
            f"script reads undeclared MCM keys: {sorted(read_keys - declared)}"
        )
        assert not (declared - read_keys), (
            f"MCM keys never read by script (dead config): "
            f"{sorted(declared - read_keys)}"
        )

    def test_reader_api_matches_declared_type(self):
        for api, key, _ in SETTINGS_READS:
            declared = MCM.get(key)
            assert declared is not None, f"{key}: not declared in MCM json"
            assert declared["type"] in GETTER_TYPE[api], (
                f"{key}: OSFSettings.{api} used for setting of type "
                f"{declared['type']!r}"
            )

    def test_fallback_defaults_match_declared_defaults(self):
        """If OSFSettings is unavailable the script falls back to a literal - that
        literal must equal the declared default, else behavior silently
        diverges depending on whether settings loaded."""
        for api, key, raw in SETTINGS_READS:
            declared = MCM.get(key)
            if declared is None or declared["type"] == "enum":
                continue  # enum fallback checked separately (options subset)
            fallback = _literal(raw)
            assert fallback == declared["default"], (
                f"{key}: script fallback {fallback!r} != MCM default "
                f"{declared['default']!r} - behavior diverges when OSFSettings "
                "is unavailable"
            )

    def test_enum_fallbacks_are_declared_options(self):
        for api, key, raw in SETTINGS_READS:
            declared = MCM.get(key)
            if declared is None or declared["type"] != "enum":
                continue
            fallback = _literal(raw)
            options = [str(o) for o in declared["options"]]
            assert str(fallback) in options, (
                f"{key}: fallback {fallback!r} is not a declared option "
                f"{options}"
            )

    def test_mod_id_constant_matches_settings_file(self):
        m = re.search(r'Property\s+MOD_ID\s*=\s*"([^"]+)"', CODE_TEXT)
        assert m, "MOD_ID const not found"
        declared_id = json.loads(MCM_SETTINGS_PATH.read_text(encoding="utf-8"))["id"]
        assert m.group(1) == declared_id, (
            f"MOD_ID {m.group(1)!r} != settings file id {declared_id!r}"
        )

    def test_setting_changed_handler_keys_are_declared(self):
        _, _, _, body = _body_of("OnOSFSettingChanged")
        handled = {
            m.group(1)
            for _, code in body
            for m in [re.search(r'asKey\s*==\s*"([^"]+)"', code)]
            if m
        }
        unknown = handled - set(MCM)
        assert not unknown, (
            f"OnOSFSettingChanged handles undeclared keys: {unknown}"
        )


# ---------------------------------------------------------------------------
# Timers
# ---------------------------------------------------------------------------

_DECLARED_TIMERS = dict(
    (m.group(1), int(m.group(2)))
    for m in re.finditer(
        r"Property\s+(TIMER_ID_\w+)\s*=\s*(\d+)", CODE_TEXT
    )
)


class TestTimers:
    def test_timer_constants_declared_and_unique(self):
        assert _DECLARED_TIMERS, "no TIMER_ID_* constants declared"
        assert len(set(_DECLARED_TIMERS.values())) == len(_DECLARED_TIMERS), (
            f"duplicate timer id values: {_DECLARED_TIMERS}"
        )

    def test_start_cancel_timer_use_named_constants(self):
        offenders = []
        for lineno, code in CODE_LINES:
            for m in re.finditer(r"StartTimer\s*\([^,\)]+,\s*(\w+)", code):
                if m.group(1) not in _DECLARED_TIMERS:
                    offenders.append(f"line {lineno}: StartTimer id {m.group(1)}")
            for m in re.finditer(r"CancelTimer\s*\(\s*(\w+)", code):
                if m.group(1) not in _DECLARED_TIMERS:
                    offenders.append(f"line {lineno}: CancelTimer id {m.group(1)}")
        assert not offenders, (
            "timers must use declared TIMER_ID_* constants:\n"
            + "\n".join(offenders)
        )

    def test_every_declared_timer_is_handled_in_ontimer(self):
        _, _, _, body = _body_of("OnTimer")
        body_text = "\n".join(code for _, code in body)
        unhandled = [t for t in _DECLARED_TIMERS if t not in body_text]
        assert not unhandled, f"timers declared but not handled in OnTimer: {unhandled}"


# ---------------------------------------------------------------------------
# Events & string callbacks
# ---------------------------------------------------------------------------

_REGISTERED = set(
    re.findall(r'RegisterForRemoteEvent\s*\([^,\)]+,\s*"([^"]+)"', CODE_TEXT)
)
_REMOTE_HANDLERS = set(
    re.findall(r"^\s*Event\s+\w+\.(\w+)\s*\(", CODE_TEXT, re.MULTILINE)
)


class TestEvents:
    def test_registered_events_have_handlers(self):
        missing = _REGISTERED - _REMOTE_HANDLERS
        assert not missing, (
            f"registered remote events without handlers: {sorted(missing)}"
        )

    def test_remote_handlers_are_registered(self):
        orphans = _REMOTE_HANDLERS - _REGISTERED
        assert not orphans, (
            f"remote event handlers never registered: {sorted(orphans)}"
        )

    def test_string_callbacks_resolve_to_functions(self):
        callbacks = re.findall(
            r'RegisterSceneCallback\s*\(\s*self\s*,\s*"([^"]+)"',
            CODE_TEXT,
        )
        assert callbacks, "no string callbacks registered"
        functions = {name for kind, name, *_ in BLOCKS if kind == "Function"}
        missing = [cb for cb in callbacks if cb not in functions]
        assert not missing, f"callback functions not found: {missing}"

    def test_settings_callback_scoped_to_mod_id(self):
        calls = re.findall(
            r"OSFSettings\.RegisterForChanges\s*\(([^\)]*)\)", CODE_TEXT
        )
        assert calls, "OSFSettings.RegisterForChanges not found"
        for call in calls:
            assert "MOD_ID" in call, (
                f"settings callback not scoped to MOD_ID: {call!r}"
            )


class TestSettingsMigration:
    """SF-TIK-009: OSF UI 2.0 removed OSFUI.Get*/RegisterForSettingChanges and
    moved settings to the OSFSettings plugin. A stale call fails at runtime
    with 'Static function not found', returns None and silently disables the
    mod (IsEnabled() -> false) — the old surface must stay gone."""

    _REMOVED_API = re.compile(
        r"OSFUI\.(GetBool|GetInt|GetFloat|GetString|"
        r"RegisterForSettingChanges|Unregister)\b"
    )

    def test_no_removed_osfui_settings_api(self):
        bad = [
            f"line {lineno}: {code.strip()}"
            for lineno, code in CODE_LINES
            if self._REMOVED_API.search(code)
        ]
        assert not bad, (
            "removed OSFUI settings API still called:\n" + "\n".join(bad)
        )

    def test_no_settings_callback_token(self):
        """RegisterForChanges is session-scoped with no token/unregister —
        iSettingsCallbackToken must stay deleted."""
        assert "iSettingsCallbackToken" not in CODE_TEXT

    def test_fixed_callback_name_present(self):
        """OSFSettings invokes a hard-coded callback name — the handler must
        be spelled exactly OnOSFSettingChanged, the old name must be gone."""
        functions = {name for kind, name, *_ in BLOCKS if kind == "Function"}
        assert "OnOSFSettingChanged" in functions
        assert "OnSettingChanged" not in functions

    def test_handler_handles_empty_key_reread_all(self):
        """Empty asKey = 'reread all' (incl. the notification sent right after
        RegisterForChanges) — the handler must special-case it, not ignore."""
        _, _, _, body = _body_of("OnOSFSettingChanged")
        assert any(
            'asKey == ""' in c or 'asKey != ""' in c for _, c in body
        ), "OnOSFSettingChanged never inspects the empty key"

    def test_listener_registered_in_helper(self):
        """Both lifecycle events subscribe via RegisterSettingsListener, which
        must contain the actual OSFSettings.RegisterForChanges call."""
        _, _, _, body = _body_of("RegisterSettingsListener")
        assert any(
            "OSFSettings.RegisterForChanges" in c for _, c in body
        ), "RegisterSettingsListener never calls OSFSettings.RegisterForChanges"

    def test_registration_retry_is_bounded(self):
        """A failed RegisterForChanges (plugin not ready at VM thaw) must retry
        via TIMER_ID_SETTINGS_RETRY — but bounded, so a permanently missing
        plugin doesn't spam StartTimer forever."""
        _, _, _, body = _body_of("RegisterSettingsListener")
        body_text = "\n".join(c for _, c in body)
        assert "TIMER_ID_SETTINGS_RETRY" in body_text, (
            "RegisterSettingsListener never schedules a retry"
        )
        assert re.search(r"iSettingsRetryCount\s*<=\s*\d", body_text), (
            "retry chain is unbounded"
        )
        _, _, _, timer_body = _body_of("OnTimer")
        gated = _if_block_lines(
            timer_body, r"aiTimerID\s*==\s*TIMER_ID_SETTINGS_RETRY"
        )
        assert any("RegisterSettingsListener()" in c for _, c in gated), (
            "OnTimer does not retry RegisterSettingsListener on "
            "TIMER_ID_SETTINGS_RETRY"
        )

    def test_permanent_vs_transient_failure_distinguished(self):
        """OSFUI.GetVersion exists on both OSF UI generations — after retries
        are exhausted it picks the user-facing message ('old OSF UI' vs
        'OSFSettings unavailable'). It must NOT gate retry eligibility: OSF
        Settings is a standalone plugin that works without OSF UI, so an
        OSFSettings-only install would otherwise get zero retries."""
        _, _, _, body = _body_of("RegisterSettingsListener")
        assert any("OSFUI.GetVersion" in c for _, c in body), (
            "RegisterSettingsListener never probes OSFUI.GetVersion to "
            "classify the failure"
        )
        body_text = "\n".join(c for _, c in body)
        ver_ln = next(
            ln for ln, c in body
            if re.search(r"OSFUI\.GetVersion\s*\(", c)
        )
        retry_ln = next(
            ln for ln, c in body
            if re.search(r"StartTimer\s*\(\s*5\.0\s*,\s*TIMER_ID_SETTINGS_RETRY", c)
        )
        assert retry_ln < ver_ln, (
            "OSFUI.GetVersion probed before retry scheduling — version must "
            "only pick the post-retry message, not gate retries"
        )
        assert "iSettingsRetryCount" in body_text, "no retry counter"

    def test_dependency_failure_notifies_once(self):
        """A broken hard dependency must surface to the player exactly once:
        user log + in-game notification + OSF Settings Mod Issues entry."""
        _, _, _, body = _body_of("NotifyDependencyProblem")
        body_text = "\n".join(c for _, c in body)
        assert "Debug.Notification" in body_text, (
            "no in-game notification for a missing dependency"
        )
        assert "bDependencyNotified" in body_text, (
            "notification is not one-shot gated"
        )
        assert "OSFSettings.ReportIssue" in body_text, (
            "dependency problem not reported to OSF Settings Mod Issues"
        )

    def test_subscribe_before_first_read(self):
        """OSFSettings contract: subscribe before reading. In both lifecycle
        blocks RegisterSettingsListener() must precede ResumeScanTimer() —
        the first settings read (IsEnabled inside it)."""
        for name in ("OnQuestInit", "Actor.OnPlayerLoadGame"):
            _, _, _, body = _body_of(name)
            sub = next(
                (ln for ln, c in body if "RegisterSettingsListener()" in c),
                None,
            )
            read = next(
                (ln for ln, c in body if re.search(r"ResumeScanTimer\s*\(", c)),
                None,
            )
            assert sub is not None, f"{name}: no RegisterSettingsListener call"
            assert read is not None, f"{name}: no ResumeScanTimer call"
            assert sub < read, (
                f"{name}: settings listener registered at line {sub} after "
                f"first settings read at line {read}"
            )


# ---------------------------------------------------------------------------
# Stable signatures
# ---------------------------------------------------------------------------

REQUIRED_SIGNATURES = [
    r"Event\s+OnQuestInit\s*\(\s*\)",
    r"Event\s+OnTimer\s*\(\s*int\s+aiTimerID\s*\)",
    r"Function\s+OnSceneEvent\s*\(\s*OSFTypes:SceneEvent\s+",
    r"Function\s+OnOSFSettingChanged\s*\(\s*String\s+asModId\s*,\s*String\s+asKey\s*\)",
    r"Function\s+ResumeScanTimer\s*\(\s*\)",
    r"Function\s+ApplyCooldownToActor\s*\(\s*Actor\s+",
    r"Function\s+SyncSceneTracking\s*\(\s*\)",
    r"Function\s+EnsureArraysInitialized\s*\(\s*\)",
    r"bool\s+Function\s+IsBreathableEnvironment\s*\(\s*\)",
    r"bool\s+Function\s+IsPlayerInOwnShip\s*\(\s*\)",
    r"bool\s+Function\s+IsInPrivatePlayerLocation\s*\(\s*\)",
    r"Function\s+EmergencyStopAll\s*\(\s*\)",
    r"Function\s+AuditActiveScenes\s*\(\s*\)",
    r"Function\s+EnforceSceneTimeouts\s*\(\s*\)",
    r"bool\s+Function\s+IsActorEligible\s*\(\s*Actor\s+",
    r"Function\s+TryStartScene\s*\(\s*Actor\s+\w+\s*,\s*Actor\s+",
    r"Function\s+TryStartSoloScene\s*\(\s*Actor\[\]\s+",
    r"String\[\]\s+Function\s+BuildQueryTags\s*\(",
    r"String\[\]\s+Function\s+BuildQueryTagsWithPack\s*\(",
    r"String\[\]\s+Function\s+GetActiveActionPool\s*\(\s*String\s+",
    r"String\s+Function\s+GetNextActionTag\s*\(\s*String\s+",
    r"String\s+Function\s+GetPairKey\s*\(\s*Actor\s+",
    r"bool\s+Function\s+IsPairOnCooldown\s*\(\s*Actor\s+",
    r"Function\s+CleanExpiredCooldowns\s*\(\s*\)",
    r"bool\s+Function\s+IsOnCooldown\s*\(\s*Actor\s+",
    r"ObjectReference\[\]\s+Function\s+FindNearbyFurniture\s*\(",
    r"bool\s+Function\s+IsBoundInstance\s*\(\s*\)",
]


class TestSignatures:
    @pytest.mark.parametrize("sig", REQUIRED_SIGNATURES)
    def test_required_signature_present(self, sig):
        assert re.search(sig, CODE_TEXT), f"required signature missing: {sig}"


# ---------------------------------------------------------------------------
# Hygiene
# ---------------------------------------------------------------------------


class TestHygiene:
    def test_no_debug_spam_in_release_script(self):
        bad = []
        for lineno, code in CODE_LINES:
            for pat in (
                r"Debug\.MessageBox",
                r"Debug\.Trace\s*\(",  # main log spam - Log() uses TraceUser
            ):
                if re.search(pat, code):
                    bad.append(f"line {lineno}: {code.strip()}")
            # Debug.Notification is debug spam EXCEPT the one-shot dependency
            # alert in NotifyDependencyProblem (SF-TIK-009, user-approved).
            if "Debug.Notification" in code and (
                _block_of_lineno(lineno) != "NotifyDependencyProblem"
            ):
                bad.append(f"line {lineno}: {code.strip()}")
        assert not bad, "debug calls that bypass Log():\n" + "\n".join(bad)

    def test_getformfromfile_only_in_init_functions(self):
        """Spec: form lookup happens once at init, never in hot loops.
        Exception: IsBoundInstance does a single quest-form probe per remote
        event to reject stale unbound (ghost) script instances."""
        allowed = {
            "OnQuestInit", "InitKeywords", "InitGearForms", "IsBoundInstance",
        }
        offenders = []
        for kind, name, start, end, body in BLOCKS:
            for lineno, code in body:
                if "GetFormFromFile" in code and name not in allowed:
                    offenders.append(f"line {lineno} in {name}: {code.strip()}")
        assert not offenders, (
            "GetFormFromFile outside init functions:\n" + "\n".join(offenders)
        )


# ---------------------------------------------------------------------------
# Tag logic (action pool, query builders, solo coverage)
# ---------------------------------------------------------------------------


def _action_pool_assignments():
    """Parse GetActiveActionPool: list of (branch, frozenset(guards), tag)."""
    _, _, _, body = _body_of("GetActiveActionPool")
    records = []
    stack = []  # frames: {"cond": str, "else": bool}
    for lineno, code in body:
        m_if = re.match(r"\s*if\s+(.+)", code)
        m_elseif = re.match(r"\s*elseif\s+(.+)", code)
        if m_if:
            stack.append({"cond": m_if.group(1).strip(), "else": False})
            continue
        if m_elseif and stack:
            stack[-1]["cond"] = m_elseif.group(1).strip()
            continue
        if re.match(r"\s*else\b", code) and stack:
            stack[-1]["else"] = True
            continue
        if re.match(r"\s*endif\b", code) and stack:
            stack.pop()
            continue
        m = re.match(r'\s*pool\[count\]\s*=\s*"([^"]+)"', code)
        if m:
            branch = "mf"
            guards = set()
            for frame in stack:
                if 'asGenderTag == "ff"' in frame["cond"]:
                    branch = "mf" if frame["else"] else "ff"
                gm = re.match(r"(IsAllow\w+)\s*\(\s*\)", frame["cond"])
                if gm:
                    guards.add(gm.group(1))
            records.append((branch, frozenset(guards), m.group(1)))
    return records


class TestTagLogic:
    def test_action_pool_tags_are_guarded(self):
        allowed = {"IsAllowForeplay", "IsAllowClassic", "IsAllowIntense"}
        bad = [
            f"{tag} (branch {branch}, guards {sorted(guards)})"
            for branch, guards, tag in _action_pool_assignments()
            if not guards or not guards <= allowed
        ]
        assert not bad, "action tags not gated by an allow-flag:\n" + "\n".join(bad)

    def test_action_pool_no_duplicate_tags_per_branch(self):
        for branch in ("mf", "ff"):
            tags = [t for b, _, t in _action_pool_assignments() if b == branch]
            dupes = {t for t in tags if tags.count(t) > 1}
            assert not dupes, f"{branch} pool duplicate tags: {sorted(dupes)}"

    def test_action_pool_within_array_capacity(self):
        _, _, _, body = _body_of("GetActiveActionPool")
        m = re.search(r"new\s+String\[(\d+)\]", "\n".join(c for _, c in body))
        capacity = int(m.group(1)) if m else 0
        for branch in ("mf", "ff"):
            count = len(
                [t for b, _, t in _action_pool_assignments() if b == branch]
            )
            assert count <= capacity, (
                f"{branch} pool can emit {count} tags but scratch array is "
                f"only String[{capacity}] - overflow risk"
            )

    def test_shared_tags_have_same_guard_in_both_branches(self):
        """A tag gated as 'foreplay' for MF must not slip into 'intense' for
        FF - else the MCM toggles stop meaning what they say."""
        per_tag = {}
        for branch, guards, tag in _action_pool_assignments():
            per_tag.setdefault(tag, set()).add(guards)
        inconsistent = {
            tag: guards for tag, guards in per_tag.items() if len(guards) > 1
        }
        assert not inconsistent, (
            f"tags with inconsistent allow-flag gating: {inconsistent}"
        )

    def test_every_allow_flag_contributes_tags_per_branch(self):
        """Each category toggle must affect both pools - a flag gating zero
        tags in a branch is a no-op the user can't see."""
        expected = {"IsAllowForeplay", "IsAllowClassic", "IsAllowIntense"}
        for branch in ("mf", "ff"):
            used = {
                g for b, guards, _ in _action_pool_assignments()
                if b == branch for g in guards
            }
            assert used == expected, (
                f"{branch} pool: flags gating tags {sorted(used)} != "
                f"{sorted(expected)}"
            )

    def test_gender_literals_are_valid(self):
        """Only 'mf'/'ff' gender tags may be passed to query builders."""
        bad = []
        for m in re.finditer(
            r'BuildQueryTags\w*\s*\(\s*"([^"]+)"', CODE_TEXT
        ):
            if m.group(1) not in ("mf", "ff"):
                bad.append(m.group(1))
        assert not bad, f"invalid gender tag literals: {bad}"

    def test_our_pack_queries_are_solo(self):
        """Our pack only ships 'solo' scenes - any query array carrying the
        'osfautonomous' pack tag must include 'solo' or it can never match."""
        arrays = {}
        _, start, end, _ = _body_of("TryStartSoloScene")
        for lineno, code in CODE_LINES:
            m = re.match(r'\s*(\w+)\[(\d+)\]\s*=\s*"([^"]+)"', code)
            if m:
                arrays.setdefault(m.group(1), []).append((lineno, m.group(3)))
        offenders = []
        for var, items in arrays.items():
            tags = {t for _, t in items}
            if "osfautonomous" in tags and "solo" not in tags:
                offenders.append(f"{var}: tags {sorted(tags)}")
        assert not offenders, (
            "queries with our pack tag but no 'solo' tag can never match:\n"
            + "\n".join(offenders)
        )

    def test_female_solo_query_is_covered_by_shipped_pack(self):
        """The pack's core feature: a female solo query {solo, osfautonomous,
        female} must be satisfiable by at least one shipped scene."""
        required = {"solo", "osfautonomous", "female"}
        covered = False
        for pack_path in OSF_DIR.glob("*.osf.json"):
            data = json.loads(pack_path.read_text(encoding="utf-8"))
            for scene in data.get("scenes", []):
                if required <= set(scene.get("tags", [])):
                    covered = True
        assert covered, (
            f"no shipped scene covers the female solo query {sorted(required)}"
        )


# ---------------------------------------------------------------------------
# Scene lifecycle regressions
#
# Static guards for bugs that contracts alone cannot see: timer-resume gating,
# non-destructive version migration, participant ordering vs StopScene, and
# parallel-array alignment. Every check here maps to a previously observed
# failure mode.
# ---------------------------------------------------------------------------

TRACKING_ARRAYS = (
    "activeSceneHandles",
    "sceneStartTimes",
    "sceneActorA",
    "sceneActorB",
    "finaleTriggeredHandles",
    "cooldownActors",
    "cooldownEndTimes",
    "pairCooldownKeys",
    "pairCooldownEndTimes",
)

SCENE_PARALLEL_ARRAYS = ("sceneStartTimes", "sceneActorA", "sceneActorB")


def _block_of_lineno(lineno):
    """Name of the Function/Event block containing a source line."""
    for kind, name, start, end, _ in BLOCKS:
        if start <= lineno <= end:
            return name
    return None


def _if_block_lines(body, cond_regex):
    """Code lines inside `if <cond_regex> ... endif` within a block body.

    Handles nested if/endif depth; elseif/else stay part of the same block.
    Papyrus keywords are case-insensitive. Returns [] when not found.
    """
    inside = False
    depth = 0
    out = []
    for lineno, code in body:
        stripped = code.strip()
        if not inside:
            if re.match(r"(?:if|elseif)\s+" + cond_regex, stripped, re.IGNORECASE):
                inside, depth = True, 1
            continue
        if re.match(r"if\b", stripped, re.IGNORECASE):
            depth += 1
        elif re.match(r"endif\b", stripped, re.IGNORECASE):
            depth -= 1
            if depth == 0:
                return out
        out.append((lineno, code))
    return out


class TestSceneLifecycle:
    # --- removed dead state must stay removed -----------------------------

    def test_no_shadow_active_count(self):
        """iActiveScenes mirrored activeSceneHandles.Length and could drift -
        the variable must stay deleted; use the array length directly."""
        assert "iActiveScenes" not in CODE_TEXT

    def test_no_dead_finale_bool_array(self):
        """sceneFinaleTriggered desynced via parallel-array shifts; finale
        state lives in finaleTriggeredHandles (value-keyed, shift-safe)."""
        assert "sceneFinaleTriggered" not in CODE_TEXT
        assert "finaleTriggeredHandles" in CODE_TEXT

    def test_no_self_pair_cooldown(self):
        """SetPairCooldown(x, x) writes an orphan 'id:id' key that
        IsPairOnCooldown can never match - solo cooldown comes from
        ApplyCooldownToActor on END/cleanup."""
        bad = []
        for lineno, code in CODE_LINES:
            m = re.search(r"SetPairCooldown\(\s*(\w+)\s*,\s*(\w+)\s*\)", code)
            if m and m.group(1) == m.group(2):
                bad.append(f"line {lineno}: {code.strip()}")
        assert not bad, "self-pair cooldown (orphan key):\n" + "\n".join(bad)

    def test_no_dead_either_sitting(self):
        """Both branches of `if eitherSitting` assigned OSF.OFF() - dead
        branch and its variable were removed."""
        assert "eitherSitting" not in CODE_TEXT

    def test_no_stale_count_comments(self):
        """'; count += 1' after a statement looks like the increment happens
        twice - cosmetic but misleading, must stay removed."""
        bad = [
            f"line {i}: {line.strip()}"
            for i, line in enumerate(PSC_LINES, start=1)
            if re.search(r";[^\"]*count\s*\+=", line)
        ]
        assert not bad, "stale count comments:\n" + "\n".join(bad)

    # --- eligibility & queries ------------------------------------------------

    def test_leveled_actor_base_guarded_before_use(self):
        """GetLeveledActorBase() returns None for broken NPCs (deleted base
        forms). Chaining .GetSex() onto it derefs None: error spam plus a
        default 0 (male) that silently misclassifies the pair. The base must
        be stored in a variable and None-checked before use."""
        bad = [
            f"line {lineno}: {code.strip()}"
            for lineno, code in CODE_LINES
            if re.search(r"GetLeveledActorBase\(\s*\)\s*\.", code)
        ]
        assert not bad, (
            "method chained onto GetLeveledActorBase() without None guard:\n"
            + "\n".join(bad)
        )

    def test_actor_race_fetched_once(self):
        """IsActorEligible must not call GetRace() twice (F-04)."""
        _, _, _, body = _body_of("IsActorEligible")
        calls = [ln for ln, c in body if "GetRace()" in c]
        assert len(calls) == 1, (
            f"GetRace() called {len(calls)}x in IsActorEligible: {calls}"
        )

    def test_pack_tag_empty_guarded(self):
        """BuildQueryTagsWithPack must skip an empty asPackTag like every
        other optional tag in the builders - an '' element can never match."""
        _, _, _, body = _body_of("BuildQueryTagsWithPack")
        gated = _if_block_lines(body, r'asPackTag\s*!=\s*""')
        assert gated, "missing 'if asPackTag != \"\"' guard"
        assert any(
            re.search(r"temp\[count\]\s*=\s*asPackTag\b", c)
            for _, c in gated
        ), "asPackTag appended outside its non-empty guard"

    # --- ship ownership (SF-TIK-008 regression) -------------------------------

    def test_own_ship_uses_engine_ownership_api(self):
        """Actor.GetCurrentShipRef() is literally GetParentCell().GetParentRef()
        (ObjectReference.psc) - the ship the actor is INSIDE, not owned.
        Comparing cell parent ref to it is a tautology that reported 'own
        ship' aboard a Deimos vessel and let a companion pair with a civilian
        client NPC. Ownership must come from Game.IsPlayerSpaceshipOwner."""
        _, _, _, body = _body_of("IsPlayerInOwnShip")
        body_text = "\n".join(c for _, c in body)
        assert "GetCurrentShipRef" not in body_text, (
            "IsPlayerInOwnShip uses GetCurrentShipRef - ownership tautology"
        )
        assert "IsPlayerSpaceshipOwner" in body_text, (
            "IsPlayerInOwnShip must call Game.IsPlayerSpaceshipOwner"
        )

    def test_ship_enter_exit_events_use_ownership_api(self):
        """OnEnter/OnExitShipInterior must flag own-ship state via
        IsPlayerSpaceshipOwner - the event fires for foreign vessels too."""
        for name in ("Actor.OnEnterShipInterior", "Actor.OnExitShipInterior"):
            _, _, _, body = _body_of(name)
            body_text = "\n".join(c for _, c in body)
            assert "IsPlayerSpaceshipOwner" in body_text, (
                f"{name}: own-ship determination without ownership check"
            )
            assert "== Game.GetPlayer().GetCurrentShipRef()" not in body_text, (
                f"{name}: compares event ship to GetCurrentShipRef - tautology"
            )

    def test_generic_npc_scan_gated_on_private_location(self):
        """The generic human scan (bIncludeOutpostNPC) must stay behind the
        private-location gate - otherwise station/city NPCs get collected."""
        _, _, _, body = _body_of("OnTimer")
        gated = _if_block_lines(body, r"allowGenericScan")
        assert gated, "no 'if allowGenericScan' gate around generic scan"
        assert any(
            "FindAllReferencesWithKeyword(kActorTypeHuman" in c
            for _, c in gated
        ), "generic human scan outside the private-location gate"

    # --- timer resume gating ----------------------------------------------

    def test_resume_scan_timer_gates_on_enabled(self):
        """StartTimer(TIMER_ID_SCAN) must sit INSIDE the IsEnabled() gate -
        a substring presence check would pass even with an inverted or
        misplaced guard."""
        _, _, _, body = _body_of("ResumeScanTimer")
        gated = _if_block_lines(body, r"IsEnabled\(\s*\)")
        assert gated, "ResumeScanTimer has no 'if IsEnabled()' gate"
        assert any("TIMER_ID_SCAN" in c for _, c in gated), (
            "TIMER_ID_SCAN scheduled outside the IsEnabled() gate"
        )

    def test_scan_timer_restart_only_via_helper(self):
        """StartTimer(..., TIMER_ID_SCAN) may only appear inside OnTimer
        (already gated on IsEnabled) and ResumeScanTimer (gates internally).
        Any other site would schedule a scan tick while the mod is
        disabled."""
        allowed = {"OnTimer", "ResumeScanTimer"}
        offenders = []
        for lineno, code in CODE_LINES:
            if re.search(r"StartTimer\s*\([^)]*TIMER_ID_SCAN", code):
                owner = _block_of_lineno(lineno)
                if owner not in allowed:
                    offenders.append(
                        f"line {lineno} in {owner}: {code.strip()}"
                    )
        assert not offenders, (
            "scan timer restarted outside OnTimer/ResumeScanTimer:\n"
            + "\n".join(offenders)
        )

    def test_event_handlers_resume_via_helper(self):
        """Handlers that used to restart the scan timer inline must go
        through ResumeScanTimer() so a disabled mod leaves no stray tick."""
        handlers = [
            "OnQuestInit", "Actor.OnPlayerLoadGame", "Actor.OnLocationChange",
            "OnMenuOpenCloseEvent", "Actor.OnCombatStateChanged",
            "Actor.OnEnterShipInterior", "Actor.OnExitShipInterior",
            "SpaceshipReference.OnShipGravJump", "SpaceshipReference.OnShipTakeOff",
            "SpaceshipReference.OnShipDock", "SpaceshipReference.OnShipLanding",
            "OnOSFSettingChanged",
        ]
        missing = [
            name for name in handlers
            if "ResumeScanTimer()"
            not in "\n".join(c for _, c in _body_of(name)[3])
        ]
        assert not missing, f"handlers not using ResumeScanTimer: {missing}"

    # --- migration ----------------------------------------------------------

    def test_migration_is_non_destructive(self):
        """The version-bump block must only update iInstalledVersion.
        Clearing tracking arrays orphans sceneActorA/B before
        AuditActiveScenes can run ghost cleanup (cooldown/anchor/gear) on
        them; EnsureArraysInitialized + SyncSceneTracking heal skew."""
        _, _, _, body = _body_of("Actor.OnPlayerLoadGame")
        lines = _if_block_lines(
            body, r"iInstalledVersion\s*<\s*CURRENT_VERSION"
        )
        assert lines, "migration block 'if iInstalledVersion < CURRENT_VERSION' not found"
        names = "|".join(TRACKING_ARRAYS)
        destructive = (
            r"(?:" + names + r")\s*=\s*new\b"      # re-init
            r"|(?:" + names + r")\s*=\s*None\b"   # drop reference
            r"|(?:" + names + r")\.Clear\b"       # native clear
        )
        bad = [
            f"line {lineno}: {code.strip()}"
            for lineno, code in lines
            if re.search(destructive, code)
        ]
        assert not bad, "migration clears tracking state:\n" + "\n".join(bad)

    def test_load_audits_scenes_once(self):
        """OnPlayerLoadGame must call AuditActiveScenes exactly once - the
        earlier pre-timeout duplicate was redundant work."""
        _, _, _, body = _body_of("Actor.OnPlayerLoadGame")
        calls = [ln for ln, c in body if re.search(r"\bAuditActiveScenes\s*\(", c)]
        assert len(calls) == 1, f"AuditActiveScenes called {len(calls)}x on load"

    # --- stop ordering & array alignment ------------------------------------

    def test_participants_queried_before_stopscene(self):
        """OSF.StopScene tears down synchronously - a participant query
        issued afterwards returns an empty list and silently skips cooldown
        and gear cleanup. Every block calling StopScene must query
        GetSceneParticipants earlier."""
        for kind, name, start, end, body in BLOCKS:
            stop_lines = [ln for ln, c in body if "OSF.StopScene(" in c]
            if not stop_lines:
                continue
            part_lines = [
                ln for ln, c in body if "OSF.GetSceneParticipants(" in c
            ]
            if not (part_lines and min(part_lines) < min(stop_lines)):
                # A helper taking pre-fetched participants as an Actor[]
                # param is exempt - the caller owns the ordering contract.
                sig = PSC_LINES[start - 1] if 0 < start <= len(PSC_LINES) else ""
                assert re.search(r"Actor\[\]", sig), (
                    f"{name}: OSF.StopScene at {stop_lines} without an "
                    "earlier GetSceneParticipants in the same block "
                    "(or a pre-fetched Actor[] parameter)"
                )

    def test_handle_removal_aligns_parallel_arrays(self):
        """Removing a handle without removing the same index from the
        scene-parallel arrays desyncs every later lookup."""
        for kind, name, start, end, body in BLOCKS:
            body_text = "\n".join(c for _, c in body)
            n_handles = body_text.count("activeSceneHandles.Remove(")
            if n_handles == 0:
                continue
            for arr in SCENE_PARALLEL_ARRAYS:
                n_arr = body_text.count(f"{arr}.Remove(")
                assert n_arr == n_handles, (
                    f"{name}: {n_handles}x activeSceneHandles.Remove but "
                    f"{n_arr}x {arr}.Remove - a removal branch is missing "
                    "a parallel-array remove and desyncs every later lookup"
                )

    def test_emergency_stop_snapshots_before_clearing(self):
        """EmergencyStopAll must copy handles AND tracked actors into locals
        before zeroing the arrays, or cleanup loses every actor."""
        _, _, _, body = _body_of("EmergencyStopAll")
        body_lines = [c for _, c in body]
        for arr in ("activeSceneHandles", "sceneActorA", "sceneActorB"):
            snap = next(
                (i for i, c in enumerate(body_lines)
                 if re.search(r"\w+\s*=\s*" + arr + r"\b", c)
                 and not re.search(arr + r"\s*=", c)),
                None,
            )
            clear = next(
                (i for i, c in enumerate(body_lines)
                 if re.search(arr + r"\s*=\s*(?:new\b|None\b)", c)),
                None,
            )
            assert snap is not None, f"no snapshot of {arr} found"
            assert clear is not None, f"no reset of {arr} found"
            assert snap < clear, f"{arr} cleared before it was snapshotted"

    def test_tracking_removed_before_stopscene(self):
        """Tracking entries must leave the arrays BEFORE OSF.StopScene runs -
        a synchronous EVENT_SCENE_END finding the handle still tracked would
        double-remove and desync every parallel array. Acceptable forms:
        per-index .Remove() or a bulk `= new` reset after snapshotting."""
        for kind, name, start, end, body in BLOCKS:
            stop_lines = [ln for ln, c in body if "OSF.StopScene(" in c]
            if not stop_lines:
                continue
            first_stop = min(stop_lines)
            prior = [c for ln, c in body if ln < first_stop]
            assert any(
                re.search(
                    r"activeSceneHandles\.Remove\(|activeSceneHandles\s*=\s*new\b",
                    c,
                )
                for c in prior
            ), (
                f"{name}: OSF.StopScene at line {first_stop} without prior "
                "activeSceneHandles removal/reset"
            )

    def test_sync_scene_tracking_at_resync_points(self):
        """SyncSceneTracking heals parallel-array skew - it must run at every
        resync point: load, END handling, audit, and timeout enforcement."""
        for name in (
            "Actor.OnPlayerLoadGame", "OnSceneEvent",
            "AuditActiveScenes", "EnforceSceneTimeouts",
        ):
            _, _, _, body = _body_of(name)
            assert any(
                re.search(r"\bSyncSceneTracking\s*\(\s*\)", c)
                for _, c in body
            ), f"{name}: missing SyncSceneTracking() resync call"

    # --- event guards --------------------------------------------------------

    def test_ghost_instance_guard_everywhere(self):
        """Saves can carry a stale unbound copy of this quest script that still
        receives serialized remote/menu/timer/native-relay events — every
        engine-facing call on it then fails and spams Papyrus.0.log. Each
        event entry point must early-out via IsBoundInstance()."""
        guarded = [
            "Actor.OnPlayerLoadGame", "Actor.OnLocationChange",
            "OnMenuOpenCloseEvent", "Actor.OnSit",
            "Actor.OnEnterShipInterior", "Actor.OnExitShipInterior",
            "Actor.OnCombatStateChanged", "OnTimer", "OnSceneEvent",
            "OnOSFSettingChanged",
            "SpaceshipReference.OnShipGravJump",
            "SpaceshipReference.OnShipTakeOff",
            "SpaceshipReference.OnShipDock",
            "SpaceshipReference.OnShipLanding",
        ]
        missing = [
            name for name in guarded
            if "IsBoundInstance()" not in "\n".join(c for _, c in _body_of(name)[3])
        ]
        assert not missing, (
            "event handlers missing the unbound-instance guard: " + str(missing)
        )

    def test_bound_check_compares_live_quest_instance(self):
        """IsBoundInstance: IsBoundGameObjectAvailable() catches save-carried
        ghosts without any FormID (survives quest refID changes in mod
        variants); when the canonical quest resolves, self must equal the
        live instance — a ghost never does; when it doesn't (e.g. LIGHT
        build), boundness alone must suffice instead of bricking the mod."""
        _, _, _, body = _body_of("IsBoundInstance")
        body_text = "\n".join(c for _, c in body)
        assert "IsBoundGameObjectAvailable" in body_text, (
            "no native boundness check in IsBoundInstance"
        )
        bound_ln = next(
            ln for ln, c in body if "IsBoundGameObjectAvailable" in c
        )
        probe_ln = next(
            ln for ln, c in body if "GetFormFromFile" in c
        )
        assert bound_ln < probe_ln, (
            "native boundness check must run before the FormID probe — "
            "it is the only layer immune to quest refID changes"
        )
        assert "GetFormFromFile" in body_text, (
            "no quest-form probe in IsBoundInstance"
        )
        assert "MANAGER_QUEST_FORMID" in body_text, (
            "quest FormID not named constant"
        )
        assert re.search(r"==\s*self", body_text), (
            "IsBoundInstance does not compare the live instance to self"
        )
        assert re.search(
            r"\w+\s*==\s*None[\s\S]*?return\s+true", body_text, re.IGNORECASE
        ), (
            "missing 'unresolved quest -> True' fallback — a variant with a "
            "different quest FormID would brick its own bound instance"
        )
        assert "managerQuestLookedUp" in body_text, (
            "GetFormFromFile probe must be cached — IsBoundInstance runs "
            "inside OnTimer and event handlers (no GetFormFromFile in hot loops)"
        )

    def test_dependency_state_reset_on_load(self):
        """iSettingsRetryCount/bSettingsWarned/bDependencyNotified persist in
        saves (non-Property vars serialize). Without a per-load reset an
        exhausted retry count grants zero retries forever and a fired
        notify flag swallows the alert on every later load."""
        _, _, _, body = _body_of("Actor.OnPlayerLoadGame")
        reg_ln = next(
            ln for ln, c in body if "RegisterSettingsListener()" in c
        )
        for var in ("iSettingsRetryCount", "bSettingsWarned",
                    "bDependencyNotified"):
            reset = next(
                (ln for ln, c in body
                 if re.search(var + r"\s*=\s*(0|false)", c)),
                None,
            )
            assert reset is not None, (
                f"OnPlayerLoadGame never resets {var}"
            )
            assert reset < reg_ln, (
                f"{var} reset at line {reset} after RegisterSettingsListener "
                f"at {reg_ln}"
            )

    def test_begin_event_ignores_untracked_handles(self):
        """EVENT_SCENE_BEGIN must early-out on handles not in
        activeSceneHandles - foreign/manual scenes never get our speed
        override."""
        _, _, _, body = _body_of("OnSceneEvent")
        assert re.search(
            r"activeSceneHandles\.Find\(akEvent\.sceneHandle\)\s*<\s*0",
            "\n".join(c for _, c in body),
        ), "BEGIN guard for untracked handles missing"

    def test_end_log_counts_actual_cooldowns(self):
        """The END log must count actors actually processed (participants +
        tracked fallbacks tA/tB), not just participants.Length - ghost ENDs
        would otherwise log a count of 0 while cleaning two actors."""
        _, _, _, body = _body_of("OnSceneEvent")
        body_text = "\n".join(c for _, c in body)
        assert 'cooldowns set for " + participants.Length' not in body_text
        increments = len(re.findall(r"cooldownCount\s*\+=\s*1", body_text))
        assert increments >= 3, (
            f"cooldownCount incremented {increments}x - expected >= 3 "
            "(participants loop + tA fallback + tB fallback)"
        )
        assert re.search(
            r'Log\([^)]*cooldowns set for\s*"\s*\+\s*cooldownCount', body_text
        ), "END log does not report the counted cooldowns"
