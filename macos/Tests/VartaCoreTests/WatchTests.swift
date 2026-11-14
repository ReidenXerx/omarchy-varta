import Foundation
import Testing
@testable import VartaCore

// Port of tests/test_watchcore.py. The first test is the one that matters: when
// the app cannot see the feed, it must not answer "no alert".

let t0 = Date(timeIntervalSince1970: 1_789_668_000) // 2026-09-17 18:00 UTC
let here = "Харківська область"

func reading(_ when: Date, _ alerting: [String] = [], source: Date?? = .none) -> Reading {
    Reading(fetchedAt: when, sourceTime: source ?? when, alerting: Set(alerting))
}

extension Date {
    func plus(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
}

@Test func silenceIsNeverReportedAsCalm() {
    var w = Watch(region: here)
    w.observe(reading(t0))
    #expect(w.alertHere(at: t0) == false, "a fresh, clear reading is a real answer")

    let later = t0.plus(minutes: 5)
    #expect(w.health(at: later) == .stale)
    #expect(w.alertHere(at: later) == nil, "a stale watch must not claim there is no alert")

    let muchLater = t0.plus(minutes: 30)
    #expect(w.health(at: muchLater) == .blind)
    #expect(w.alertHere(at: muchLater) == nil)
}

@Test func aWatchThatNeverReachedTheFeedIsBlind() {
    var w = Watch(region: here)
    w.failed(at: t0)
    #expect(w.health(at: t0) == .blind)
    #expect(w.alertHere(at: t0) == nil)
}

@Test func anAlertForThisRegionIsReported() {
    var w = Watch(region: here)
    w.observe(reading(t0, [here, "Сумська область"]))
    #expect(w.alertHere(at: t0) == true)
    #expect(w.alertingCount == 2)
}

@Test func anAlertElsewhereIsNotAnAlertHere() {
    var w = Watch(region: here)
    w.observe(reading(t0, ["Львівська область"]))
    #expect(w.alertHere(at: t0) == false)
}

@Test func startTimeIsRememberedAndForgotten() {
    var w = Watch(region: here)
    w.observe(reading(t0))
    let begun = t0.plus(minutes: 1)
    w.observe(reading(begun, [here]))
    #expect(w.since(here) == begun)

    // It keeps the original start across later readings, not the latest one.
    let still = begun.plus(minutes: 1)
    w.observe(reading(still, [here]))
    #expect(w.since(here) == begun)

    let over = still.plus(minutes: 1)
    w.observe(reading(over))
    #expect(w.since(here) == nil)
}

@Test func aFreshAnswerCarryingAStaleCacheIsStale() {
    // The feed answers instantly with a cache from an hour ago: the request
    // succeeded, the information did not.
    var w = Watch(region: here)
    w.observe(reading(t0, source: .some(t0.plus(minutes: -60))))
    #expect(w.health(at: t0) == .stale)
    #expect(w.alertHere(at: t0) == nil)
}

@Test func aFeedWithNoTimestampIsStillUsable() {
    var w = Watch(region: here)
    w.observe(reading(t0, [here], source: .some(nil)))
    #expect(w.health(at: t0) == .ok)
    #expect(w.alertHere(at: t0) == true)
    #expect(w.sourceAge(at: t0) == nil)
}

@Test func failuresAreExplainedToAPersonNotAProgrammer() {
    let woke = "URLError: <urlopen error [Errno -3] Temporary failure in name resolution>"
    #expect(plainly(woke) == "waiting for the network")
    #expect(plainly("RuntimeError: feed refused us for asking too often (429)") == "the feed asked us to slow down")
    #expect(plainly("TimeoutError: timed out") == "the feed is not answering")
    #expect(plainly("JSONDecodeError: Expecting value") == "the feed sent something unexpected")
    #expect(plainly("") == "cannot read the feed")
    // What URLSession actually says on a Mac.
    #expect(plainly("The Internet connection appears to be offline. (not connected to the internet)") == "waiting for the network")
    #expect(plainly("The request timed out.") == "the feed is not answering")
    // Whatever it says, it never says something reassuring.
    for text in [woke, "boom", "", "HTTP 503"] {
        #expect(!plainly(text).split(separator: " ").contains("ok"), "\(plainly(text))")
    }
}

@Test func otherPlacesAreWatchedWithoutBeingShoutedAbout() {
    var w = Watch(region: here, others: ["Львівська область", "м. Київ"])
    w.observe(reading(t0, ["Львівська область"]))
    let also = w.elsewhere(at: t0)
    #expect(w.alertHere(at: t0) == false, "here is clear")
    #expect(also.map(\.region) == ["Львівська область", "м. Київ"], "kept in the order they were given")
    #expect(also[0].alert == true)
    #expect(also[1].alert == false)
    #expect(also[0].since == t0)
}

@Test func aBlindWatchKnowsNothingAboutAnywhere() {
    var w = Watch(region: here, others: ["Львівська область"])
    w.observe(reading(t0, ["Львівська область"]))
    let later = t0.plus(minutes: 30)
    #expect(w.alertHere(at: later) == nil)
    #expect(w.elsewhere(at: later)[0].alert == nil, "blind about here means blind about there too")
}

@Test func retriesSlowDownButKeepTrying() {
    #expect(backoff(failures: 0) == 60)
    #expect(backoff(failures: 1) == 60)
    #expect(backoff(failures: 2) == 120)
    #expect(backoff(failures: 3) == 240)
    #expect(backoff(failures: 9) == 300, "capped, so it never stops checking")
}

@Test func namesFromTheFeedAreFlattenedBeforeAnyoneDrawsThem() {
    #expect(plain("Київська область") == "Київська область", "a real name survives intact")
    #expect(!plain("<b>Київська</b>").contains("<") && !plain("<b>Київська</b>").contains(">"))
    #expect(plain("two\nlines") == "two lines", "nothing can rearrange a line")
    #expect(plain("  padded  ") == "padded")
    #expect(plain(String(repeating: "x", count: 500)).count == 120, "a region name is never this long")
    #expect(plain(nil) == "" && plain("") == "")
    #expect(plain("Київ\u{202E}ська") == "Київська", "a bidi override cannot reverse the line")
}
