"""What has already happened, so the watch is about more than this minute.

Varta knows the present perfectly and forgets it instantly. That is the right
shape for an alarm and the wrong shape for a person, who after a bad week wants
to know how bad it actually was, and whether the thing that keeps waking them
at three in the morning really does prefer three in the morning.

What is stored is transitions, not alerts: one line each time a region goes
under alert or comes out of one. A poller can be killed at any moment, so an
append-only line is the unit that survives -- a half-written one costs a single
record rather than the file. Spells are reconstructed by pairing transitions on
the way out, which also means a spell still running is simply one that has not
been closed yet, with no special case to forget.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import json

# Roughly two years of a heavily-hit oblast. Past this the oldest go, because a
# history that grows without bound eventually costs more than it tells you.
MAX_RECORDS = 5000

# A spell longer than this is not an alert, it is a watcher that died while one
# was running and came back after it ended. Counting it would quietly ruin every
# average on the page.
IMPLAUSIBLE = dt.timedelta(hours=18)


@dataclasses.dataclass(frozen=True)
class Transition:
    """A region crossing into or out of an alert, at a moment."""
    region: str
    at: dt.datetime
    alert: bool

    def as_line(self) -> str:
        return json.dumps({"region": self.region, "at": self.at.isoformat(),
                           "alert": self.alert}, ensure_ascii=False)

    @staticmethod
    def parse(line: str) -> "Transition | None":
        """A line, or None if it is not one. Never raises: the file is read on a
        path that must not fail because somebody hand-edited it."""
        try:
            d = json.loads(line)
            at = dt.datetime.fromisoformat(str(d["at"]))
        except (ValueError, TypeError, KeyError):
            return None
        if at.tzinfo is None:
            at = at.replace(tzinfo=dt.timezone.utc)
        region = str(d.get("region") or "")
        return Transition(region, at, bool(d.get("alert"))) if region else None


class Ledger:
    """Turns a stream of readings into the transitions worth writing down.

    It holds only what it last saw per region, so it costs nothing to keep and
    nothing to rebuild: a watcher that restarts simply learns the current state
    on its first poll and writes a transition only if it genuinely changed.
    """

    def __init__(self, known: dict[str, bool] | None = None) -> None:
        self.state: dict[str, bool] = dict(known or {})

    def observe(self, region: str, alerting: bool, when: dt.datetime) -> Transition | None:
        """The transition this reading caused, or None if nothing changed."""
        if not region:
            return None
        was = self.state.get(region)
        self.state[region] = alerting
        if was is None or was == alerting:
            # The first sighting of a region is not a transition. Treating it as
            # one would invent an alert every time the watcher restarts.
            return None
        return Transition(region, when, alerting)


def spells(transitions: list[Transition], now: dt.datetime) -> list[dict]:
    """Paired into periods: region, start, end (None while it is still running)."""
    open_at: dict[str, dt.datetime] = {}
    out: list[dict] = []
    for t in sorted(transitions, key=lambda t: t.at):
        if t.alert:
            open_at.setdefault(t.region, t.at)
        elif t.region in open_at:
            out.append({"region": t.region, "start": open_at.pop(t.region), "end": t.at})
    for region, start in open_at.items():
        out.append({"region": region, "start": start, "end": None})
    return sorted(out, key=lambda s: s["start"])


def _length(spell: dict, now: dt.datetime) -> dt.timedelta:
    return (spell["end"] or now) - spell["start"]


def summarise(transitions: list[Transition], now: dt.datetime, days: int = 7) -> dict:
    """What the panel shows: how many, how long, and when they tend to come."""
    since = now - dt.timedelta(days=days)
    every = spells(transitions, now)
    recent = [s for s in every if (s["end"] or now) >= since]

    regions: dict[str, dict] = {}
    by_hour = [0] * 24
    longest = None
    for s in recent:
        length = _length(s, now)
        if length > IMPLAUSIBLE:
            continue
        r = regions.setdefault(s["region"], {"region": s["region"], "count": 0, "seconds": 0})
        r["count"] += 1
        r["seconds"] += int(length.total_seconds())
        # Counted at the hour it began, in local time: "when do they start" is
        # the question people actually ask, and they ask it in their own clock.
        by_hour[s["start"].astimezone().hour] += 1
        if longest is None or length > _length(longest, now):
            longest = s

    ongoing = [s for s in every if s["end"] is None]
    last_end = max((s["end"] for s in every if s["end"]), default=None)

    return {
        "days": days,
        "regions": sorted(regions.values(), key=lambda r: -r["seconds"]),
        "byHour": by_hour,
        "total": sum(r["count"] for r in regions.values()),
        "longest": _pack(longest, now),
        "ongoing": [_pack(s, now) for s in ongoing],
        # How long it has been quiet everywhere -- the number you actually want
        # after a bad night.
        "quietSeconds": int((now - last_end).total_seconds()) if last_end and not ongoing else None,
    }


def _pack(spell: dict | None, now: dt.datetime) -> dict | None:
    if not spell:
        return None
    return {"region": spell["region"], "start": spell["start"].isoformat(),
            "end": spell["end"].isoformat() if spell["end"] else None,
            "seconds": int(_length(spell, now).total_seconds())}


def trim(lines: list[str], cap: int = MAX_RECORDS) -> list[str]:
    """The newest `cap` lines. Oldest history is the first thing nobody misses."""
    return lines[-cap:] if len(lines) > cap else lines
