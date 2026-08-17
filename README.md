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
- **Tick colour** — white well under pace, blue tracking it, amber then red over.
- **Centre** — percent used, with time until the window resets beneath it.
- **Bar** — output tokens per model family over the current weekly window,
  darkest (Fable) to lightest (Haiku).

Plasma's own System Monitor widgets already cover CPU, GPU, RAM, disk, network
and temperatures; this only adds what they cannot reach.

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

The script symlinks `bin/claude-usage-probe` into `~/.local/bin` and `plasmoid/`
into `~/.local/share/plasma/plasmoids/dev.cwooper.claudeusage`, so edits in the
checkout take effect on the next plasmashell restart.

## How it works

`bin/claude-usage-probe` is the only thing that touches the network. It runs
`claude -p /usage` for the gauges and `ccusage daily --since` for the model mix,
and prints one JSON object:

```json
{
  "ok": true, "stale": false, "ts": 1786925015.6,
  "gauges": [{"key": "session", "pct": 65, "resetsAt": 1786926000.0, "windowSeconds": 18000}],
  "models": [{"name": "opus", "tokens": 3512671}]
}
```

The widget runs it every 5 minutes (`pollInterval` in `contents/ui/main.qml`)
and re-renders the countdowns and pace ticks every 30 seconds from the last
reading. Readings are cached to `~/.cache/claude-usage.json`; if a probe fails,
the widget dims and keeps showing the last good values rather than going blank.

The model bar is scoped to the weekly window derived from the gauge's own reset
time, not to `ccusage`'s Monday-start week. Those differ by however many hours
separate midnight from the weekly reset, and using ccusage's buckets blanks the
bar for that stretch every week.

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

Covers the `/usage` text parsing, reset-stamp handling (missing year, New Year
rollover, leap day), and the ccusage aggregation.
