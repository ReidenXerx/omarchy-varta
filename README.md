# Varta

An air raid alert watch for [Omarchy](https://omarchy.org): your oblast in the
bar, and a band across every screen the moment it goes under alert.

**This is a companion to the official app and to the sirens outside. It is not a
replacement for either, and it is not an official source.** Its whole job is to
make sure you do not miss one while you are at the desk in headphones.

## The problem it is actually built around

A monitor that cannot reach its source looks exactly like a monitor reporting
calm. Silence means "nothing is happening" and it means "I stopped looking", and
on a screen those are the same picture.

That is not hypothetical here. The first free feed this project tried,
`alerts.com.ua`, answers `HTTP 200` with a `last_update` timestamp from a minute
ago — and the median time since any region's alert state last *changed* in it is
**318 days**. In Ukraine. It is frozen data behind a live-looking heartbeat.
While it claimed one oblast was alerting, the live feed said ten.

So Varta has three answers, not two:

| | |
|---|---|
| **clear** | a fresh reading, and your oblast is not in it |
| **ПОВІТРЯНА ТРИВОГА** | a fresh reading, and your oblast is |
| **not watching** | anything else — and it says so as loudly as an alert |

The watch never reports "no alert" from evidence it does not trust. Stale after
four minutes, blind after eight, and a fresh `200` carrying an hour-old cache
counts as stale: the request succeeded, the information did not.

## What it does

- **Finds your region by itself**, from one IP lookup cross-checked across two
  services — and only believes an answer both of them give. If they disagree, or
  it sees a VPN, it refuses to guess and asks you to pick. A confident wrong
  region would watch the wrong place while looking like it worked.
- **A band across every screen** when your oblast goes under alert. It takes no
  keyboard focus and its mask is empty, so every click and keystroke passes
  straight through — loud, but never in the way. It sits on the overlay layer,
  so a fullscreen game or film does not hide it.
- **A sound built to be noticed, not dreaded.** Struck tones with a soft attack
  and partials that decay like a real bell, in consonant intervals — the
  reference is a station chime, which exists to make a room look up without
  raising anyone's pulse. An alert you dread is an alert you eventually mute,
  and a muted alert is worse than none. Deliberately nothing like a siren:
  outside is where sirens come from.
- **A rehearsal you can run any time**, so you do not first find out whether it
  works during an attack. It is drawn blue and headed **ТЕСТ** throughout.

## Using it

Put the widget on your bar. It finds your oblast on its own; if you would rather
it never made that request, choose your region from the widget's settings and
the lookup never runs.

| The shield | Means |
|---|---|
| hollow | a fresh reading, and your oblast is clear |
| filled, pulsing | your oblast is under alert |
| struck through, amber | **not watching** — the feed cannot be read |
| grey | no region chosen yet |

**Click the shield** for what it knows: how old the reading is, every region it
is watching and the state of each, and two things worth doing — *Test the alert*
and *Find my region again*.

**Changing which regions it watches** is done where every Omarchy widget keeps
its options, not in a second place that can disagree with the first: the
widget's settings. Either edit the bar with
[Barber](https://github.com/ReidenXerx/omarchy-barber), or from a terminal:

```bash
omarchy bar set reidenxerx.varta region "Львівська область"
omarchy bar set reidenxerx.varta also   "Київська область, Харківська область"
omarchy-restart-shell     # per-widget options are read at start
```

```bash
# rehearse the whole path for 20 seconds, clearly marked as a test
qs -p /usr/share/omarchy/shell ipc call varta test

# what the watch currently knows
qs -p /usr/share/omarchy/shell ipc call varta status
```

## Settings

**Your region** — an oblast, or *Detect automatically*. **Sound** on or off, in
three voices: Glass rings longest, Bell is warm and round, Marimba is the
shortest. **Repeat every** — how often the sound says so again while an alert
stands, because the first one can be missed.

## What it touches

Nothing on disk: no files written, no state kept, no privileged operations.

It makes two kinds of request. Once a minute, to
`ubilling.net.ua/aerialalerts/` — a free mirror of Vadym Klymenko's feed — which
caches for about that long and rate-limits hard, so Varta asks gently, backs off
when refused, and identifies itself. And once, at setup only, to two IP
geolocation services, unless you picked your region by hand, in which case it
never asks at all.

## The feed's limits, plainly

It reports **whole oblasts**. An alert in yours does not mean an alert over your
street, and for a large oblast that difference is most of it. It also cannot say
when an alert *began* — its own field for that is the epoch for 24 of 26 regions
— so Varta times from when it first saw the alert itself, and the banner says
"seen for", never "alert since".

If you want hromada-level precision and real start times, that needs a personal
token from [alerts.in.ua](https://devs.alerts.in.ua/); Varta does not use one,
by choice, so that it works the moment it is installed with nothing to sign up
for.

## Building on it

```bash
python3 tests/test_watchcore.py    # when the watch may and may not claim calm
python3 tests/test_regions.py      # every region reachable, and Kyiv city is not Kyiv oblast
python3 tools/make_sounds.py       # regenerate the sounds from their description
./bin/varta-watch --list           # the regions the feed knows, and which are alerting
./bin/varta-locate                 # where this machine appears to be, and how sure
```

`app/watchcore.py` is pure functions over a clock and the last reading, with no
network in it, which is how "a stale watch must not claim there is no alert"
gets to be a test rather than a hope.

## Requirements

Omarchy's Quickshell-based shell, and `paplay` for the sound. Nothing else.

## Licence

MIT

## Support

Varta is free and always will be. If it earns a place on your bar, you can
support its development at [donatello.to/DuduPhudu](https://donatello.to/DuduPhudu).
