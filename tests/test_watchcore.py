"""What the watch must never get wrong.

The first test is the one that matters: when the app cannot see the feed, it
must not answer "no alert". Reporting False there is the failure that gets
somebody hurt, and it is indistinguishable from the truth on a screen.
"""
import datetime as dt
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "app"))
from watchcore import BLIND, OK, STALE, Reading, Watch, backoff, plainly  # noqa: E402

T0 = dt.datetime(2026, 9, 17, 18, 0, 0, tzinfo=dt.timezone.utc)
HERE = "Харківська область"


def reading(when, alerting=(), source_time=...):
    return Reading(fetched_at=when,
                   source_time=when if source_time is ... else source_time,
                   alerting=frozenset(alerting))


def test_silence_is_never_reported_as_calm():
    w = Watch(region=HERE)
    w.observe(reading(T0, alerting=[]))
    assert w.snapshot(T0)["alert"] is False, "a fresh, clear reading is a real answer"

    later = T0 + dt.timedelta(minutes=5)
    snap = w.snapshot(later)
    assert snap["health"] == STALE
    assert snap["alert"] is None, "a stale watch must not claim there is no alert"

    much_later = T0 + dt.timedelta(minutes=30)
    assert w.snapshot(much_later)["health"] == BLIND
    assert w.snapshot(much_later)["alert"] is None


def test_a_watch_that_never_reached_the_feed_is_blind():
    w = Watch(region=HERE)
    w.failed(T0)
    snap = w.snapshot(T0)
    assert snap["health"] == BLIND
    assert snap["alert"] is None


def test_an_alert_for_this_region_is_reported():
    w = Watch(region=HERE)
    w.observe(reading(T0, alerting=[HERE, "Сумська область"]))
    snap = w.snapshot(T0)
    assert snap["alert"] is True
    assert snap["alerting_count"] == 2


def test_an_alert_elsewhere_is_not_an_alert_here():
    w = Watch(region=HERE)
    w.observe(reading(T0, alerting=["Львівська область"]))
    assert w.snapshot(T0)["alert"] is False


def test_start_time_is_remembered_and_forgotten():
    w = Watch(region=HERE)
    w.observe(reading(T0, alerting=[]))
    begun = T0 + dt.timedelta(minutes=1)
    w.observe(reading(begun, alerting=[HERE]))
    assert w.snapshot(begun)["since"] == begun.isoformat(timespec="seconds")

    # It keeps the original start across later readings, not the latest one.
    still = begun + dt.timedelta(minutes=1)
    w.observe(reading(still, alerting=[HERE]))
    assert w.snapshot(still)["since"] == begun.isoformat(timespec="seconds")

    over = still + dt.timedelta(minutes=1)
    w.observe(reading(over, alerting=[]))
    assert w.snapshot(over)["since"] is None


def test_a_fresh_answer_carrying_a_stale_cache_is_stale():
    # The feed answers instantly with a cache from an hour ago: the request
    # succeeded, the information did not.
    w = Watch(region=HERE)
    w.observe(reading(T0, alerting=[], source_time=T0 - dt.timedelta(hours=1)))
    snap = w.snapshot(T0)
    assert snap["health"] == STALE
    assert snap["alert"] is None


def test_a_feed_with_no_timestamp_is_still_usable():
    w = Watch(region=HERE)
    w.observe(reading(T0, alerting=[HERE], source_time=None))
    snap = w.snapshot(T0)
    assert snap["health"] == OK
    assert snap["alert"] is True
    assert snap["source_age_s"] is None


def test_failures_are_explained_to_a_person_not_a_programmer():
    # The real text seen on screen when the laptop woke before its wifi did.
    woke = "URLError: <urlopen error [Errno -3] Temporary failure in name resolution>"
    assert plainly(woke) == "waiting for the network"
    assert plainly("RuntimeError: feed refused us for asking too often (429)") \
        == "the feed asked us to slow down"
    assert plainly("TimeoutError: timed out") == "the feed is not answering"
    assert plainly("JSONDecodeError: Expecting value") == "the feed sent something unexpected"
    assert plainly("") == "cannot read the feed"
    # Whatever it says, it never says something reassuring.
    for text in (woke, "boom", "", "HTTP 503"):
        assert "ok" not in plainly(text).split(), plainly(text)


def test_retries_slow_down_but_keep_trying():
    assert backoff(0) == 60
    assert backoff(1) == 60
    assert backoff(2) == 120
    assert backoff(3) == 240
    assert backoff(9) == 300, "capped, so it never stops checking"


if __name__ == "__main__":
    failed = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
            print("  ok   " + name[5:].replace("_", " "))
        except AssertionError as e:
            failed += 1
            print(f"  FAIL {name[5:].replace('_', ' ')}\n       {e}")
    print(f"\n{failed} failing" if failed else f"\n{sum(1 for n in globals() if n.startswith('test_'))} passing")
    sys.exit(1 if failed else 0)
