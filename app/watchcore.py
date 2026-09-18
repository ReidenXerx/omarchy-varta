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
    """What the poller knows, updated reading by reading.

    `region` is where you are: the one that earns a band across the screen.
    `others` are places you are keeping an eye on — family, friends — which are
    worth knowing about without being interrupted for.
    """
    region: str
    others: tuple[str, ...] = ()
    last_ok: Reading | None = None
    last_attempt: dt.datetime | None = None
    consecutive_failures: int = 0
    # When this app first saw the alert for each region begin. The free feed's
    # own `changed` field is the epoch for 24 of 26 regions, so an honest
    # "seen since" is the best that can be offered — and it is labelled as such.
    seen_since: dict[str, dt.datetime] = field(default_factory=dict)

    def observe(self, reading: Reading) -> None:
        previous = self.last_ok.alerting if self.last_ok else frozenset()
        watched = {self.region, *self.others}
        for region in (reading.alerting - previous) & watched:
            self.seen_since[region] = reading.fetched_at
        for region in (previous - reading.alerting) & watched:
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

    def alerting_in(self, region: str) -> bool:
        return bool(self.last_ok and region in self.last_ok.alerting)

    def alerting_here(self) -> bool:
        return self.alerting_in(self.region)

    def elsewhere(self, now: dt.datetime) -> list[dict]:
        """The places being kept an eye on, in the order they were given."""
        trusted = self.health(now) == OK
        out = []
        for region in self.others:
            since = self.seen_since.get(region)
            out.append({
                "region": region,
                "alert": self.alerting_in(region) if trusted else None,
                "since": since.isoformat(timespec="seconds") if since else None,
            })
        return out

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
            "also": self.elsewhere(now),
            "alerting_count": len(self.last_ok.alerting) if self.last_ok else 0,
            "alerting": sorted(self.last_ok.alerting) if self.last_ok else [],
            "reading_age_s": int((now - self.last_ok.fetched_at).total_seconds())
            if self.last_ok else None,
            "source_age_s": int(self.source_age(now).total_seconds())
            if self.source_age(now) is not None else None,
            "failures": self.consecutive_failures,
        }


def plainly(error: str) -> str:
    """What to tell a person about a failure.

    The band this ends up on is read by somebody deciding whether to move, at
    three in the morning, possibly from across a room. "URLError: <urlopen
    error [Errno -3] Temporary failure in name resolution>" is a sentence for
    whoever wrote this, not for them.
    """
    text = (error or "").lower()
    if "name resolution" in text or "name or service not known" in text \
            or "temporary failure" in text or "errno -2" in text or "errno -3" in text:
        return "waiting for the network"
    if "429" in text or "too often" in text:
        return "the feed asked us to slow down"
    if "timed out" in text or "timeout" in text:
        return "the feed is not answering"
    if "refused" in text or "unreachable" in text or "no route" in text:
        return "cannot reach the feed"
    if "certificate" in text or "ssl" in text:
        return "the connection to the feed could not be trusted"
    if "http 5" in text:
        return "the feed is having trouble"
    if "json" in text or "no regions" in text or "too large" in text:
        return "the feed sent something unexpected"
    return "cannot read the feed"


def backoff(failures: int, base: int = 60, ceiling: int = 300) -> int:
    """How long to wait after a failure.

    The feed rate-limits hard — a burst of retries earns a 429, which would
    keep the app blind for longer than simply waiting. So retries slow down,
    but never past the point of checking a few times an hour.
    """
    if failures <= 0:
        return base
    return min(ceiling, base * (2 ** min(failures - 1, 3)))
