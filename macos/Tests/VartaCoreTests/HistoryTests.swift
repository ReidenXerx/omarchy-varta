import Foundation
import Testing
@testable import VartaCore

// Port of tests/test_history.py. The history is only worth showing if it cannot
// invent alerts that never happened, and cannot lose ones that did.

func at(_ hour: Int, _ minute: Int = 0, day: Int = 1) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute) = (2026, 9, day, hour, minute)
    c.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: c)!
}

func tr(_ hour: Int, _ alert: Bool, day: Int = 1) -> Transition {
    Transition(region: "Х", at: at(hour, day: day), alert: alert)
}

@Test func theFirstSightingOfARegionIsNotAnAlert() {
    var led = Ledger()
    #expect(led.observe("Харківська область", alerting: true, at: at(3)) == nil)
    #expect(led.observe("Тернопільська область", alerting: false, at: at(3)) == nil)
}

@Test func onlyAChangeIsWrittenDown() {
    var led = Ledger()
    _ = led.observe("Харківська область", alerting: false, at: at(1))
    #expect(led.observe("Харківська область", alerting: false, at: at(2)) == nil, "still clear")
    let t = led.observe("Харківська область", alerting: true, at: at(3))
    #expect(t?.alert == true && t?.at == at(3))
    #expect(led.observe("Харківська область", alerting: true, at: at(4)) == nil, "still alerting")
    #expect(led.observe("Харківська область", alerting: false, at: at(5))?.alert == false)
}

@Test func spellsPairUpAndAnUnfinishedOneStaysOpen() {
    let got = spells([tr(2, true), tr(5, false), tr(9, true)])
    #expect(got.count == 2)
    #expect(got[0].end == at(5))
    #expect(got[1].end == nil, "the one still running has no end")
}

@Test func aSummaryCountsHowManyAndHowLong() {
    let s = summarise([tr(2, true), tr(4, false), tr(20, true), tr(21, false)], now: at(23))
    #expect(s.total == 2)
    #expect(s.regions[0].count == 2)
    #expect(s.regions[0].seconds == 3 * 3600, "2h + 1h")
    #expect(s.longest.map { Int($0.length(at: at(23))) } == 2 * 3600)
}

@Test func alertsAreCountedAtTheHourTheyBeganInYourOwnClock() {
    var kyiv = Calendar(identifier: .gregorian)
    kyiv.timeZone = TimeZone(identifier: "Europe/Kyiv")!
    let s = summarise([tr(2, true), tr(4, false)], now: at(6), calendar: kyiv)
    #expect(s.byHour[5] == 1, "02:00 UTC is 05:00 in Kyiv in September")
    #expect(s.byHour.reduce(0, +) == 1)
}

@Test func aSpellLeftOpenByADeadWatcherDoesNotPoisonTheAverages() {
    let s = summarise([tr(1, true, day: 1), tr(1, false, day: 3)], now: at(2, day: 3))
    #expect(s.total == 0, "48h is not an alert, it is a gap in the record")
    #expect(s.longest == nil)
    #expect(History.implausible < 86_400)
}

@Test func quietIsOnlyClaimedWhenNothingIsRunning() {
    let closed = [tr(2, true), tr(4, false)]
    #expect(summarise(closed, now: at(6)).quietSeconds == 2 * 3600)
    let running = closed + [tr(5, true)]
    #expect(summarise(running, now: at(6)).quietSeconds == nil)
    #expect(summarise(running, now: at(6)).ongoing.count == 1)
}

@Test func olderThanTheWindowIsLeftOut() {
    #expect(summarise([tr(2, true, day: 1), tr(3, false, day: 1)], now: at(3, day: 20)).total == 0)
}

@Test func aLineSurvivesTheRoundTripAndRubbishDoesNotCrashIt() {
    let t = Transition(region: "Тернопільська область", at: at(3), alert: true)
    #expect(Transition.parse(t.line) == t)
    for rubbish in ["", "{", "null", #"{"region": "Х"}"#, #"{"at": "nonsense"}"#, #"{"alert": true}"#] {
        #expect(Transition.parse(rubbish) == nil, "\(rubbish)")
    }
}

@Test func aTimeWithoutAZoneIsReadAsUTCRatherThanRefused() {
    let t = Transition.parse(#"{"region": "Х", "at": "2026-09-01T03:00:00", "alert": true}"#)
    #expect(t?.at == at(3))
}

@Test func linesWrittenOnLinuxAreRead() {
    // Python's isoformat(), offset and microseconds included.
    #expect(Transition.parse(#"{"region": "Х", "at": "2026-09-01T03:00:00+00:00", "alert": true}"#)?.at == at(3))
    #expect(Transition.parse(#"{"region": "Х", "at": "2026-09-01T03:00:00.250000+00:00", "alert": false}"#) != nil)
}

@Test func trimmingKeepsTheNewest() {
    #expect(trim((0..<10).map(String.init), cap: 3) == ["7", "8", "9"])
    #expect(trim(["a"], cap: 3) == ["a"], "under the cap, nothing moves")
}

@Test func theSummaryCountsOnlyTheRegionsYouWatch() {
    let ts = [tr(2, true), tr(3, false),
              Transition(region: "Інша", at: at(2), alert: true), Transition(region: "Інша", at: at(4), alert: false)]
    #expect(summarise(ts, now: at(6), only: ["Х"]).total == 1)
}

@Test func anAlertThatEndedWhileNobodyWasWatchingIsNotTimed() {
    // Varta quit at 10:23 during an alert and came back at 22:38 to calm. The
    // alert ended somewhere in those twelve hours; it was not twelve hours long.
    let ts = [tr(10, true), Transition(region: "Х", at: at(22), alert: false, uncertain: true)]
    let s = summarise(ts, now: at(23))
    #expect(s.total == 0)
    #expect(s.longest == nil)
    #expect(s.byHour.reduce(0, +) == 0)
    #expect(s.quietSeconds == nil, "quiet since an unknown moment is not a number")
    #expect(spells(ts).first?.uncertain == true)
    #expect(s.untimed == 1, "it happened, and that is still said")
}

@Test func uncertaintyIsWrittenOnlyWhenTrueAndReadBack() {
    let sure = Transition(region: "Х", at: at(3), alert: true)
    #expect(!sure.line.contains("uncertain"), "lines stay the Linux shape")
    let unsure = Transition(region: "Х", at: at(3), alert: false, uncertain: true)
    #expect(Transition.parse(unsure.line) == unsure)
}
