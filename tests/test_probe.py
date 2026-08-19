#!/usr/bin/env python3
"""Tests for the probe's parsing and aggregation."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import tempfile
import time
import unittest
import unittest.mock
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

PROBE_PATH = Path(__file__).resolve().parent.parent / "plasmoid" / "contents" / "bin" / "claude-usage-probe"

_spec = importlib.util.spec_from_loader(
    "claude_usage_probe",
    importlib.machinery.SourceFileLoader("claude_usage_probe", str(PROBE_PATH)),
)
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)

REYKJAVIK = ZoneInfo("Atlantic/Reykjavik")

# Verbatim `claude -p /usage` output, including the U+00B7 separators.
USAGE_SAMPLE = """You are currently using your subscription to power your Claude Code usage

Current session: 63% used · resets Aug 17, 12:20am (Atlantic/Reykjavik)
Current week (all models): 79% used · resets Aug 17, 11am (Atlantic/Reykjavik)
Current week (Fable): 72% used · resets Aug 17, 11am (Atlantic/Reykjavik)

What's contributing to your limits usage?
Last 24h · 148 requests · 3 sessions
  99% of your usage came from subagent-heavy sessions
"""


def weekly_only():
    """USAGE_SAMPLE as printed while no session is open."""
    return "\n".join(
        line for line in USAGE_SAMPLE.splitlines()
        if not line.startswith("Current session")
    )


class ParseResetTest(unittest.TestCase):
    def test_parses_stamp_with_minutes(self):
        now = datetime(2026, 8, 16, 23, 55, tzinfo=REYKJAVIK)
        got = probe.parse_reset("Aug 17, 12:20am", "Atlantic/Reykjavik", now)
        self.assertEqual(
            datetime.fromtimestamp(got, REYKJAVIK),
            datetime(2026, 8, 17, 0, 20, tzinfo=REYKJAVIK),
        )

    def test_parses_stamp_without_minutes(self):
        now = datetime(2026, 8, 16, 23, 55, tzinfo=REYKJAVIK)
        got = probe.parse_reset("Aug 17, 11am", "Atlantic/Reykjavik", now)
        self.assertEqual(
            datetime.fromtimestamp(got, REYKJAVIK),
            datetime(2026, 8, 17, 11, 0, tzinfo=REYKJAVIK),
        )

    def test_rolls_year_forward_across_new_year(self):
        now = datetime(2026, 12, 31, 22, 0, tzinfo=REYKJAVIK)
        got = probe.parse_reset("Jan 2, 9am", "Atlantic/Reykjavik", now)
        self.assertEqual(
            datetime.fromtimestamp(got, REYKJAVIK),
            datetime(2027, 1, 2, 9, 0, tzinfo=REYKJAVIK),
        )

    def test_keeps_current_year_for_imminent_reset(self):
        now = datetime(2026, 1, 2, 8, 0, tzinfo=REYKJAVIK)
        got = probe.parse_reset("Jan 2, 9am", "Atlantic/Reykjavik", now)
        self.assertEqual(
            datetime.fromtimestamp(got, REYKJAVIK),
            datetime(2026, 1, 2, 9, 0, tzinfo=REYKJAVIK),
        )

    def test_handles_leap_day(self):
        now = datetime(2028, 2, 28, 12, 0, tzinfo=REYKJAVIK)
        got = probe.parse_reset("Feb 29, 11am", "Atlantic/Reykjavik", now)
        self.assertEqual(
            datetime.fromtimestamp(got, REYKJAVIK),
            datetime(2028, 2, 29, 11, 0, tzinfo=REYKJAVIK),
        )

    def test_rejects_unparsable_stamp(self):
        now = datetime(2026, 8, 16, 23, 55, tzinfo=REYKJAVIK)
        with self.assertRaises(ValueError):
            probe.parse_reset("sometime next Tuesday", "Atlantic/Reykjavik", now)

    def test_rejects_unusable_timezone(self):
        now = datetime(2026, 8, 16, 23, 55, tzinfo=REYKJAVIK)
        with self.assertRaises(ValueError):
            probe.parse_reset("Aug 17, 11am", "Not/AZone", now)

    def test_accepts_a_naive_now(self):
        got = probe.parse_reset("Aug 17, 11am", "Atlantic/Reykjavik",
                                datetime(2026, 8, 16, 23, 55))
        self.assertEqual(
            datetime.fromtimestamp(got, REYKJAVIK),
            datetime(2026, 8, 17, 11, 0, tzinfo=REYKJAVIK),
        )


class GaugeKeyTest(unittest.TestCase):
    def test_session_ignores_qualifier(self):
        self.assertEqual(probe.gauge_key("session", ""), "session")

    def test_all_models_week_collapses_to_week(self):
        self.assertEqual(probe.gauge_key("week", "all models"), "week")

    def test_bare_week_collapses_to_week(self):
        self.assertEqual(probe.gauge_key("week", ""), "week")

    def test_named_model_week_uses_model_name(self):
        self.assertEqual(probe.gauge_key("week", "Fable"), "fable")


class ParseUsageTest(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 8, 16, 23, 55, tzinfo=REYKJAVIK)

    def test_extracts_all_three_gauges_in_order(self):
        gauges = probe.parse_usage(USAGE_SAMPLE, self.now)
        self.assertEqual([g["key"] for g in gauges], ["session", "week", "fable"])
        self.assertEqual([g["pct"] for g in gauges], [63, 79, 72])

    def test_records_the_reporting_timezone(self):
        for gauge in probe.parse_usage(USAGE_SAMPLE, self.now):
            self.assertEqual(gauge["tz"], "Atlantic/Reykjavik")

    def test_assigns_window_length_per_kind(self):
        gauges = probe.parse_usage(USAGE_SAMPLE, self.now)
        by_key = {g["key"]: g for g in gauges}
        self.assertEqual(by_key["session"]["windowSeconds"], 5 * 3600)
        self.assertEqual(by_key["week"]["windowSeconds"], 7 * 86400)
        self.assertEqual(by_key["fable"]["windowSeconds"], 7 * 86400)

    def test_ignores_the_contributing_usage_section(self):
        """'Last 24h - 148 requests' must not be mistaken for a gauge line."""
        self.assertEqual(len(probe.parse_usage(USAGE_SAMPLE, self.now)), 3)

    def test_raises_when_no_gauges_present(self):
        with self.assertRaises(ValueError):
            probe.parse_usage("Claude Code is not authenticated.", self.now)

    def test_substitutes_an_inactive_session_when_its_line_is_missing(self):
        gauges = probe.parse_usage(weekly_only(), self.now)
        self.assertEqual([g["key"] for g in gauges], ["session", "week", "fable"])
        session = gauges[0]
        self.assertTrue(session["inactive"])
        self.assertEqual(session["pct"], 0)
        self.assertIsNone(session["resetsAt"])
        self.assertEqual(session["tz"], "Atlantic/Reykjavik")

    def test_keeps_the_weekly_gauges_without_a_session_line(self):
        by_key = {g["key"]: g for g in probe.parse_usage(weekly_only(), self.now)}
        self.assertEqual(by_key["week"]["pct"], 79)
        self.assertEqual(by_key["fable"]["pct"], 72)

    def test_raises_when_the_session_line_is_present_but_unparsable(self):
        """A stamp format change must not pass for an idle session."""
        drifted = USAGE_SAMPLE.replace(
            "resets Aug 17, 12:20am (Atlantic/Reykjavik)", "resets in 2h 40m", 1)
        with self.assertRaises(ValueError):
            probe.parse_usage(drifted, self.now)

    def test_scopes_the_model_window_without_a_session_line(self):
        """The synthesized gauge carries no reset time for window_start to read."""
        gauges = probe.parse_usage(weekly_only(), self.now)
        self.assertEqual(probe.window_start(gauges), date(2026, 8, 10))


class UnexpiredTest(unittest.TestCase):
    def setUp(self):
        self.now = 1_000_000

    def test_keeps_windows_still_open(self):
        gauges = [{"key": "week", "resetsAt": self.now + 60}]
        self.assertEqual(probe.unexpired(gauges, self.now), gauges)

    def test_drops_windows_that_have_reset(self):
        gauges = [
            {"key": "session", "resetsAt": self.now - 1},
            {"key": "week", "resetsAt": self.now + 60},
        ]
        self.assertEqual([g["key"] for g in probe.unexpired(gauges, self.now)], ["week"])

    def test_keeps_an_inactive_session(self):
        """It has no window to have rolled over, so nothing dates it."""
        session = probe.inactive_session("UTC")
        self.assertEqual(probe.unexpired([session], self.now), [session])


class ClaudeBreakdownsTest(unittest.TestCase):
    def test_selects_the_claude_agent(self):
        day = {"agents": [
            {"agent": "codex", "modelBreakdowns": [{"modelName": "gpt", "outputTokens": 999}]},
            {"agent": "claude", "modelBreakdowns": [{"modelName": "claude-opus-5",
                                                     "outputTokens": 7}]},
        ]}
        self.assertEqual(probe.claude_breakdowns(day),
                         [{"modelName": "claude-opus-5", "outputTokens": 7}])

    def test_returns_nothing_when_claude_is_absent(self):
        day = {"agents": [{"agent": "codex", "modelBreakdowns": [{"outputTokens": 5}]}]}
        self.assertEqual(probe.claude_breakdowns(day), [])

    def test_falls_back_to_the_unified_row(self):
        day = {"modelBreakdowns": [{"modelName": "claude-opus-5", "outputTokens": 4}]}
        self.assertEqual(probe.claude_breakdowns(day),
                         [{"modelName": "claude-opus-5", "outputTokens": 4}])


class FamilyTest(unittest.TestCase):
    def test_maps_dated_model_ids(self):
        self.assertEqual(probe.family("claude-haiku-4-5-20251001"), "haiku")

    def test_maps_versioned_model_ids(self):
        self.assertEqual(probe.family("claude-opus-4-8"), "opus")
        self.assertEqual(probe.family("claude-fable-5"), "fable")

    def test_passes_through_unrecognised_ids(self):
        self.assertEqual(probe.family("some-other-model"), "some-other-model")


class AggregateModelsTest(unittest.TestCase):
    def test_sums_output_tokens_across_days_and_versions(self):
        payload = {
            "daily": [
                {"modelBreakdowns": [
                    {"modelName": "claude-opus-5", "outputTokens": 100},
                    {"modelName": "claude-fable-5", "outputTokens": 10},
                ]},
                {"modelBreakdowns": [
                    {"modelName": "claude-opus-4-8", "outputTokens": 5},
                ]},
            ]
        }
        self.assertEqual(
            probe.aggregate_models(payload),
            [{"name": "fable", "tokens": 10}, {"name": "opus", "tokens": 105}],
        )

    def test_orders_by_family_not_by_size(self):
        payload = {"daily": [{"modelBreakdowns": [
            {"modelName": "claude-haiku-4-5", "outputTokens": 900},
            {"modelName": "claude-sonnet-5", "outputTokens": 50},
            {"modelName": "claude-fable-5", "outputTokens": 1},
        ]}]}
        self.assertEqual(
            [m["name"] for m in probe.aggregate_models(payload)],
            ["fable", "sonnet", "haiku"],
        )

    def test_ignores_cache_and_input_token_fields(self):
        payload = {"daily": [{"modelBreakdowns": [
            {"modelName": "claude-opus-5", "outputTokens": 7,
             "cacheReadTokens": 10 ** 9, "inputTokens": 5000},
        ]}]}
        self.assertEqual(probe.aggregate_models(payload),
                         [{"name": "opus", "tokens": 7}])

    def test_drops_families_with_no_output(self):
        payload = {"daily": [{"modelBreakdowns": [
            {"modelName": "claude-opus-5", "outputTokens": 0},
            {"modelName": "claude-fable-5", "outputTokens": 3},
        ]}]}
        self.assertEqual(probe.aggregate_models(payload),
                         [{"name": "fable", "tokens": 3}])

    def test_handles_empty_and_absent_payloads(self):
        self.assertEqual(probe.aggregate_models({}), [])
        self.assertEqual(probe.aggregate_models({"daily": []}), [])
        self.assertEqual(probe.aggregate_models({"daily": None}), [])

    def test_excludes_other_agent_clis(self):
        payload = {"daily": [{"agents": [
            {"agent": "claude", "modelBreakdowns": [{"modelName": "claude-opus-5",
                                                     "outputTokens": 12}]},
            {"agent": "codex", "modelBreakdowns": [{"modelName": "gpt-5",
                                                    "outputTokens": 500}]},
        ]}]}
        self.assertEqual(probe.aggregate_models(payload),
                         [{"name": "opus", "tokens": 12}])


class WindowStartTest(unittest.TestCase):
    def test_derives_opening_date_from_the_weekly_gauge(self):
        resets = datetime(2026, 8, 17, 11, 0).timestamp()
        gauges = [
            {"key": "session", "resetsAt": resets, "windowSeconds": 5 * 3600},
            {"key": "week", "resetsAt": resets, "windowSeconds": 7 * 86400},
        ]
        self.assertEqual(probe.window_start(gauges), date(2026, 8, 10))

    def test_dates_the_window_in_the_reporting_timezone(self):
        """Dating it locally can land a day off and clip the opening day."""
        resets = datetime(2026, 8, 17, 11, 0, tzinfo=REYKJAVIK).timestamp()
        gauges = [{"key": "week", "resetsAt": resets,
                   "windowSeconds": 7 * 86400, "tz": "Atlantic/Reykjavik"}]
        self.assertEqual(probe.window_start(gauges), date(2026, 8, 10))

    def test_survives_an_unusable_timezone_field(self):
        resets = datetime(2026, 8, 17, 11, 0).timestamp()
        gauges = [{"key": "week", "resetsAt": resets,
                   "windowSeconds": 7 * 86400, "tz": "Not/AZone"}]
        self.assertEqual(probe.window_start(gauges), date(2026, 8, 10))

    def test_falls_back_to_seven_days_back_without_gauges(self):
        now = datetime(2026, 8, 17, 11, 0)
        self.assertEqual(probe.window_start([], now), date(2026, 8, 10))

    def test_ignores_session_only_gauges(self):
        now = datetime(2026, 8, 17, 11, 0)
        gauges = [{"key": "session",
                   "resetsAt": (now + timedelta(hours=1)).timestamp(),
                   "windowSeconds": 5 * 3600}]
        self.assertEqual(probe.window_start(gauges, now), date(2026, 8, 10))


class FallbackTest(unittest.TestCase):
    """main()'s degraded path, which the cache file is the only record of."""

    @staticmethod
    def unavailable(*args, **kwargs):
        raise RuntimeError("claude: command not found")

    def setUp(self):
        cache = Path(tempfile.mkdtemp()) / "claude-usage.json"
        patch = unittest.mock.patch.multiple(
            probe, CACHE=str(cache), run=self.unavailable)
        patch.start()
        self.addCleanup(patch.stop)

    def probe_output(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            probe.main()
        return json.loads(buf.getvalue())

    def test_drops_cached_windows_that_have_since_reset(self):
        now = time.time()
        probe.save_cache({
            "gauges": [
                {"key": "session", "pct": 100, "resetsAt": now - 60},
                {"key": "week", "pct": 39, "resetsAt": now + 86400},
            ],
            "models": [{"name": "opus", "tokens": 5}],
            "modelsTs": now,
        })
        result = self.probe_output()
        self.assertEqual([g["key"] for g in result["gauges"]], ["week"])
        self.assertTrue(result["stale"])

    def test_keeps_a_cached_inactive_session(self):
        probe.save_cache({
            "gauges": [probe.inactive_session("UTC")],
            "models": [], "modelsTs": time.time(),
        })
        result = self.probe_output()
        self.assertEqual([g["key"] for g in result["gauges"]], ["session"])


if __name__ == "__main__":
    unittest.main()
