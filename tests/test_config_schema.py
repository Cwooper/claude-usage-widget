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


def spinboxes(path):
    """(id, body) for each QQC2.SpinBox block, matched by brace depth.

    A flat regex over the whole file pairs each id with the next from/to it can
    find, which quietly attributed three controls to unrelated ids.
    """
    text = path.read_text()
    found = []
    for match in re.finditer(r"QQC2\.SpinBox\s*\{", text):
        depth, i = 1, match.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        body = text[match.end():i - 1]
        name = re.search(r"\bid:\s*(\w+)", body)
        if name:
            found.append((name.group(1), body))
    return found


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

    def test_every_spinbox_is_checked(self):
        """Guards the scan below: a regex that silently matched nothing passed."""
        found = {name for page in CONFIG_PAGES for name, _ in spinboxes(page)}
        expected = {n for n, e in self.entries.items()
                    if e.get("type", "").lower() == "int"}
        self.assertEqual(found, expected)

    def test_spinbox_ranges_match_the_schema(self):
        """A control wider than its entry lets users store values it then clamps."""
        for page in CONFIG_PAGES:
            for name, body in spinboxes(page):
                entry = self.entries.get(name)
                if entry is None:
                    continue
                for prop, tag in (("from", "min"), ("to", "max")):
                    literal = re.search(r"\n\s*%s:\s*(-?\d+)\s*\n" % prop, body)
                    bound = entry.find("{%s}%s" % (KCFG_NS["k"], tag))
                    # A bound computed from another control cannot be compared.
                    if literal is None or bound is None:
                        continue
                    with self.subTest(control=name, bound=prop):
                        self.assertEqual(int(literal.group(1)), int(bound.text))


class ConfigWiringTest(unittest.TestCase):
    def test_config_qml_sources_exist(self):
        sources = re.findall(r'source:\s*"([^"]+)"',
                             (PLASMOID / "config" / "config.qml").read_text())
        self.assertTrue(sources)
        for source in sources:
            self.assertTrue((PLASMOID / "ui" / source).is_file(), source)

    def test_gauge_does_not_read_the_configuration(self):
        self.assertNotIn("Plasmoid.configuration",
                         (PLASMOID / "ui" / "Gauge.qml").read_text())


if __name__ == "__main__":
    unittest.main()
