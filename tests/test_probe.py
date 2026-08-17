#!/usr/bin/env python3
"""Tests for the probe's parsing and aggregation."""

import importlib.machinery
import importlib.util
import unittest
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
        """Falling back to local time would shift countdowns while looking fine."""
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

    def test_raises_when_only_the_session_line_is_missing(self):
        """Otherwise the window that actually stops work vanishes silently."""
        weekly_only = "\n".join(
            line for line in USAGE_SAMPLE.splitlines()
            if not line.startswith("Current session")
        )
        with self.assertRaises(ValueError):
            probe.parse_usage(weekly_only, self.now)


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
        """Their tokens do not count against Claude's limit windows."""
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

    def test_falls_back_to_seven_days_back_without_gauges(self):
        now = datetime(2026, 8, 17, 11, 0)
        self.assertEqual(probe.window_start([], now), date(2026, 8, 10))

    def test_ignores_session_only_gauges(self):
        now = datetime(2026, 8, 17, 11, 0)
        gauges = [{"key": "session",
                   "resetsAt": (now + timedelta(hours=1)).timestamp(),
                   "windowSeconds": 5 * 3600}]
        self.assertEqual(probe.window_start(gauges, now), date(2026, 8, 10))


if __name__ == "__main__":
    unittest.main()
