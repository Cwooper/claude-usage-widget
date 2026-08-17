#!/usr/bin/env python3
"""Cross-checks the config schema against the QML that reads and writes it.

A `cfg_` alias whose name does not match a kcfg entry binds to nothing: the
control renders, accepts input, and silently discards it. Neither qmllint nor a
screenshot catches that, so it is checked here.
"""

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLASMOID = ROOT / "plasmoid" / "contents"
SCHEMA = PLASMOID / "config" / "main.xml"
KCFG_NS = {"k": "http://www.kde.org/standards/kcfg/1.0"}

CONFIG_PAGES = sorted(PLASMOID.glob("ui/config*.qml"))
UI_FILES = sorted(PLASMOID.glob("ui/*.qml"))


def schema_entries():
    root = ET.parse(SCHEMA).getroot()
    return {e.get("name"): e for e in root.iter("{%s}entry" % KCFG_NS["k"])}


def aliases_in(path):
    return set(re.findall(r"property alias cfg_(\w+):", path.read_text()))


def configuration_reads():
    used = set()
    for path in UI_FILES:
        used |= set(re.findall(r"Plasmoid\.configuration\.(\w+)", path.read_text()))
    return used


class ConfigSchemaTest(unittest.TestCase):
    def setUp(self):
        self.entries = schema_entries()

    def test_schema_parses_and_is_not_empty(self):
        self.assertTrue(self.entries)

    def test_every_entry_has_a_default(self):
        missing = [n for n, e in self.entries.items()
                   if e.find("{%s}default" % KCFG_NS["k"]) is None]
        self.assertEqual(missing, [], "entries without a default: %s" % missing)

    def test_every_alias_matches_an_entry(self):
        for page in CONFIG_PAGES:
            unknown = sorted(aliases_in(page) - set(self.entries))
            self.assertEqual(unknown, [],
                             "%s aliases unknown keys: %s" % (page.name, unknown))

    def test_every_entry_is_exposed_by_a_config_page(self):
        exposed = set()
        for page in CONFIG_PAGES:
            exposed |= aliases_in(page)
        self.assertEqual(sorted(set(self.entries) - exposed), [])

    def test_every_entry_is_read_by_the_widget(self):
        """An entry nothing reads is a control that appears to do nothing."""
        self.assertEqual(sorted(set(self.entries) - configuration_reads()), [])

    def test_numeric_entries_declare_bounds(self):
        for name, entry in self.entries.items():
            if entry.get("type", "").lower() != "int":
                continue
            with self.subTest(entry=name):
                self.assertIsNotNone(entry.find("{%s}min" % KCFG_NS["k"]))
                self.assertIsNotNone(entry.find("{%s}max" % KCFG_NS["k"]))

    def test_spinbox_ranges_match_the_schema(self):
        """A control wider than its entry lets users store clamped values."""
        for page in CONFIG_PAGES:
            text = page.read_text()
            for alias, frm, to in re.findall(
                    r"id:\s*(\w+)\b.*?from:\s*(-?\d+).*?to:\s*(-?\d+)", text, re.S):
                entry = self.entries.get(alias)
                if entry is None:
                    continue
                lo = entry.find("{%s}min" % KCFG_NS["k"])
                hi = entry.find("{%s}max" % KCFG_NS["k"])
                if lo is None or hi is None:
                    continue
                with self.subTest(control=alias):
                    self.assertEqual((int(frm), int(to)), (int(lo.text), int(hi.text)))


class ConfigWiringTest(unittest.TestCase):
    def test_config_qml_sources_exist(self):
        sources = re.findall(r'source:\s*"([^"]+)"',
                             (PLASMOID / "config" / "config.qml").read_text())
        self.assertTrue(sources)
        for source in sources:
            self.assertTrue((PLASMOID / "ui" / source).is_file(), source)

    def test_gauge_does_not_read_the_configuration(self):
        """Gauge stays reusable; StyledGauge is the only config-aware wrapper."""
        self.assertNotIn("Plasmoid.configuration",
                         (PLASMOID / "ui" / "Gauge.qml").read_text())


if __name__ == "__main__":
    unittest.main()
