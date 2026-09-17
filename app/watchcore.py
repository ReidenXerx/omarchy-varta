"""Deciding what to believe about the feed, and when to say so.

Kept apart from the polling so it can be tested without a network: everything
here is a pure function over a clock, the last successful reading, and what has
happened since.

The rule the whole design turns on: silence must never be ambiguous. "No alert"
and "I cannot see the feed" look identical on a screen, and one of them can get
somebody hurt — so anything other than a fresh, successful reading is a state
the interface has to show as loudly as an alert.
"""
from __future__ import annotations

import datetime as dt
from dataclasses import dataclass, field

# The feed caches upstream for about a minute, so a reading older than this is
# not a network blip — something has stopped.
STALE_AFTER = dt.timedelta(minutes=4)
# Past this with no successful reading at all, the app is not watching anything
# and must stop implying that it is.
BLIND_AFTER = dt.timedelta(minutes=8)

OK, STALE, BLIND = "ok", "stale", "blind"


@dataclass
class Reading:
    """One successful answer from the feed."""
    fetched_at: dt.datetime
    source_time: dt.datetime | None
    alerting: frozenset[str]


@dataclass
class Watch:
    """What the poller knows, updated reading by reading."""
    region: str
    last_ok: Reading | None = None
    last_attempt: dt.datetime | None = None
    consecutive_failures: int = 0
    # When this app first saw the alert for each region begin. The free feed's
    # own `changed` field is the epoch for 24 of 26 regions, so an honest
    # "seen since" is the best that can be offered — and it is labelled as such.
    seen_since: dict[str, dt.datetime] = field(default_factory=dict)

    def observe(self, reading: Reading) -> None:
        previous = self.last_ok.alerting if self.last_ok else frozenset()
        for region in reading.alerting - previous:
            self.seen_since[region] = reading.fetched_at
        for region in previous - reading.alerting:
            self.seen_since.pop(region, None)
        self.last_ok = reading
        self.last_attempt = reading.fetched_at
        self.consecutive_failures = 0

    def failed(self, when: dt.datetime) -> None:
        self.last_attempt = when
        self.consecutive_failures += 1

    def health(self, now: dt.datetime) -> str:
        """Never optimistic: the older evidence gets, the less it claims."""
        if self.last_ok is None:
            return BLIND
        age = now - self.last_ok.fetched_at
        if age >= BLIND_AFTER:
            return BLIND
        if age >= STALE_AFTER:
            return STALE
        # A reading can arrive fresh and still carry an old cache behind it.
        if self.source_age(now) is not None and self.source_age(now) >= STALE_AFTER:
            return STALE
        return OK

    def source_age(self, now: dt.datetime) -> dt.timedelta | None:
        if self.last_ok is None or self.last_ok.source_time is None:
            return None
        return now - self.last_ok.source_time

    def alerting_here(self) -> bool:
        return bool(self.last_ok and self.region in self.last_ok.alerting)

    def snapshot(self, now: dt.datetime) -> dict:
        health = self.health(now)
        since = self.seen_since.get(self.region)
        return {
            "at": now.isoformat(timespec="seconds"),
            "region": self.region,
            "health": health,
            # Only ever true on evidence this app currently trusts. A stale or
            # blind watch reports None, not False: not knowing is its own answer.
            "alert": self.alerting_here() if health == OK else None,
            "since": since.isoformat(timespec="seconds") if since else None,
            "alerting_count": len(self.last_ok.alerting) if self.last_ok else 0,
            "alerting": sorted(self.last_ok.alerting) if self.last_ok else [],
            "reading_age_s": int((now - self.last_ok.fetched_at).total_seconds())
            if self.last_ok else None,
            "source_age_s": int(self.source_age(now).total_seconds())
            if self.source_age(now) is not None else None,
            "failures": self.consecutive_failures,
        }


def backoff(failures: int, base: int = 60, ceiling: int = 300) -> int:
    """How long to wait after a failure.

    The feed rate-limits hard — a burst of retries earns a 429, which would
    keep the app blind for longer than simply waiting. So retries slow down,
    but never past the point of checking a few times an hour.
    """
    if failures <= 0:
        return base
    return min(ceiling, base * (2 ** min(failures - 1, 3)))
