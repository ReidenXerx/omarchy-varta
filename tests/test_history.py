"""The history is only worth showing if it cannot invent alerts that never
happened, and cannot lose ones that did."""
import datetime as dt
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "app"))
from history import (IMPLAUSIBLE, Ledger, Transition, spells,  # noqa: E402
                     summarise, trim)

UTC = dt.timezone.utc


def at(hour, minute=0, day=1):
    return dt.datetime(2026, 9, day, hour, minute, tzinfo=UTC)


def test_the_first_sighting_of_a_region_is_not_an_alert():
    # Otherwise every restart of the watcher writes an alert that never happened.
    led = Ledger()
    assert led.observe("Харківська область", True, at(3)) is None
    assert led.observe("Тернопільська область", False, at(3)) is None


def test_only_a_change_is_written_down():
    led = Ledger()
    led.observe("Харківська область", False, at(1))
    assert led.observe("Харківська область", False, at(2)) is None, "still clear"
    t = led.observe("Харківська область", True, at(3))
    assert t and t.alert and t.at == at(3)
    assert led.observe("Харківська область", True, at(4)) is None, "still alerting"
    assert led.observe("Харківська область", False, at(5)).alert is False


def test_spells_pair_up_and_an_unfinished_one_stays_open():
    ts = [Transition("Х", at(2), True), Transition("Х", at(5), False),
          Transition("Х", at(9), True)]
    got = spells(ts, now=at(11))
    assert len(got) == 2
    assert got[0]["end"] == at(5)
    assert got[1]["end"] is None, "the one still running has no end"


def test_a_summary_counts_how_many_and_how_long():
    ts = [Transition("Х", at(2), True), Transition("Х", at(4), False),
          Transition("Х", at(20), True), Transition("Х", at(21), False)]
    s = summarise(ts, now=at(23), days=7)
    assert s["total"] == 2
    assert s["regions"][0]["count"] == 2
    assert s["regions"][0]["seconds"] == 3 * 3600, "2h + 1h"
    assert s["longest"]["seconds"] == 2 * 3600


def test_alerts_are_counted_at_the_hour_they_began_in_your_own_clock():
    ts = [Transition("Х", at(2), True), Transition("Х", at(4), False)]
    s = summarise(ts, now=at(6), days=7)
    hour = at(2).astimezone().hour        # local, not UTC: people ask in their clock
    assert s["byHour"][hour] == 1
    assert sum(s["byHour"]) == 1


def test_a_spell_left_open_by_a_dead_watcher_does_not_poison_the_averages():
    # Watcher died during an alert, came back long after it ended.
    ts = [Transition("Х", at(1, day=1), True), Transition("Х", at(1, day=3), False)]
    s = summarise(ts, now=at(2, day=3), days=7)
    assert s["total"] == 0, "48h is not an alert, it is a gap in the record"
    assert s["longest"] is None
    assert IMPLAUSIBLE < dt.timedelta(days=1)


def test_quiet_is_only_claimed_when_nothing_is_running():
    closed = [Transition("Х", at(2), True), Transition("Х", at(4), False)]
    assert summarise(closed, now=at(6))["quietSeconds"] == 2 * 3600
    running = closed + [Transition("Х", at(5), True)]
    assert summarise(running, now=at(6))["quietSeconds"] is None
    assert len(summarise(running, now=at(6))["ongoing"]) == 1


def test_older_than_the_window_is_left_out():
    old = [Transition("Х", at(2, day=1), True), Transition("Х", at(3, day=1), False)]
    assert summarise(old, now=at(3, day=20), days=7)["total"] == 0


def test_a_line_survives_the_round_trip_and_rubbish_does_not_crash_it():
    t = Transition("Тернопільська область", at(3), True)
    back = Transition.parse(t.as_line())
    assert back == t
    for rubbish in ("", "{", "null", '{"region": "Х"}', '{"at": "nonsense"}', '{"alert": true}'):
        assert Transition.parse(rubbish) is None


def test_a_time_without_a_zone_is_read_as_utc_rather_than_refused():
    t = Transition.parse('{"region": "Х", "at": "2026-09-01T03:00:00", "alert": true}')
    assert t and t.at.tzinfo is not None


def test_trimming_keeps_the_newest():
    assert trim([str(i) for i in range(10)], cap=3) == ["7", "8", "9"]
    assert trim(["a"], cap=3) == ["a"], "under the cap, nothing moves"


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
    print(f"\n{failed} failing" if failed else
          f"\n{sum(1 for n in globals() if n.startswith('test_'))} passing")
    sys.exit(1 if failed else 0)
