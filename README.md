# Claude Usage — Plasma widget

A Plasma 6 widget showing Claude Code subscription limits as pace-aware ring
gauges, plus the week's output-token split by model.

![Three ring gauges: a large SESSION ring beside smaller WEEK and FABLE rings,
above a stacked orange bar](docs/screenshot.png)

Each ring shows one limit window. The arc is how much of the window's allowance
is spent; the tick on the ring is how far through the window you are *in time*.
Arc behind the tick means you are coasting, arc past it means you will hit the
limit early.

- **Arc colour** — green under pace, amber up to 15 points over, red beyond.
- **Tick colour** — theme text colour well under pace, blue tracking it, amber then red over.
- **Centre** — percent used, with time until the window resets beneath it.
- **Bar** — output tokens per model family over the current weekly window,
  darkest (Fable) to lightest (Haiku).

A refresh button sits in the top right, dimmed while a probe is in flight.
Until the first reading lands the rings show an indeterminate spinner.

## Requirements

- Plasma 6 (developed against 6.7)
- `claude` on `PATH`, authenticated against a Pro/Max subscription — the limit
  gauges come from `claude -p /usage`, which reports nothing on API-key auth
- `npx` — the model bar shells out to [`ccusage`](https://github.com/ryoppippi/ccusage)

## Install

```sh
./install.sh
```

Then: right-click desktop → Add Widgets → "Claude Usage".

The script copies `plasmoid/` into
`~/.local/share/plasma/plasmoids/dev.cwooper.claudeusage`. Pass `--link` to
symlink the checkout instead, so edits land without reinstalling — but remove the
widget from your desktop first. plasmashell reloads an applet whenever its
package changes, and reloading a half-saved file set segfaults it.

## Configuration

Right-click the widget → Configure.

**General** — update interval; which pieces to show (session ring, weekly rings,
model bar, pace marker, countdown, captions); model bar height; ring thickness.

**Colours** — the five pace colours, which follow the desktop theme unless you
switch that off; the model bar's base colour, which the ramp is shaded from; and
the two thresholds deciding how far over pace counts as over, and as well over.

## How it works

`plasmoid/contents/bin/claude-usage-probe` is the only thing that touches the
network. It ships inside the package so a published widget carries it. It runs
`claude -p /usage` for the gauges and `ccusage daily --since` for the model mix,
and prints one JSON object:

```json
{
  "ok": true, "stale": false, "ts": 1786925015.6,
  "gauges": [{"key": "session", "pct": 65, "resetsAt": 1786926000.0, "windowSeconds": 18000}],
  "models": [{"name": "opus", "tokens": 3512671}]
}
```

The widget runs it on the configured interval (5 minutes by default)
and re-renders the countdowns and pace ticks every 30 seconds from the last
reading. Readings are cached to `~/.cache/claude-usage.json`; if a probe fails,
the widget dims and keeps showing the last good values rather than going blank.

### Known limits

- `ccusage daily` buckets by day, so the window's opening day is counted whole
  even though the window opens partway through it.
- The rings are full circles, so a tick at 99% elapsed sits close to one at 0%.
  The tick colour is what tells them apart.
- `/usage` counts usage across all your machines; the model bar only sees local
  transcripts under `~/.claude/projects`.

## Tests

```sh
python3 -m unittest discover -s tests
```

