import Foundation
import Testing
@testable import VartaCore

// New on the Mac: the parser against a cached real response, and the rules
// shell/Service.qml applied on Linux, now pure and tested.

func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "feed", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func theCachedFeedParses() throws {
    let answer = try Feed.parse(try fixture())
    #expect(Set(answer.names) == feedRegions, "the feed's names are the ones Regions knows")
    #expect(answer.alerting.isSubset(of: feedRegions))
    #expect(answer.sourceTime != nil)
}

@Test func theCacheStampIsKyivTimeWhereverTheMacIs() throws {
    let json = #"{"cachedat":"2026-11-13 12:00:00","states":{"м. Київ":{"alertnow":false}}}"#
    let answer = try Feed.parse(Data(json.utf8))
    // 12:00 in Kyiv in November (EET, UTC+2) is 10:00 UTC.
    #expect(answer.sourceTime == Date(timeIntervalSince1970: 1_794_564_000))
}

@Test func onlyARealTrueIsAnAlert() throws {
    let json = #"{"states":{"A":{"alertnow":true},"B":{"alertnow":1},"C":{"alertnow":"true"},"D":{}}}"#
    #expect(try Feed.parse(Data(json.utf8)).alerting == ["A"])
}

@Test func somethingThatIsNotTheFeedIsRefused() {
    #expect(throws: Feed.Problem.self) { try Feed.parse(Data("<html>".utf8)) }
    #expect(throws: Feed.Problem.self) { try Feed.parse(Data(#"{"states":{}}"#.utf8)) }
    #expect(throws: Feed.Problem.self) { try Feed.parse(Data(count: Feed.ceiling + 1)) }
}

// MARK: Monitor

@Test func startingIsNotLosing() {
    var m = Monitor(region: here, now: t0)
    #expect(m.status(at: t0) == .starting, "no flash of 'not watching' at launch")
    #expect(m.failed("timed out", now: t0.plus(minutes: 0.5)).isEmpty)
    #expect(m.status(at: t0.plus(minutes: 1)) == .starting)
    // Past the grace period with nothing read: that is no longer a hiccup.
    let late = t0.plus(minutes: 2)
    #expect(m.tick(now: late) == [.lost(reason: "the feed is not answering")])
    #expect(m.status(at: late) == .notWatching(reason: "the feed is not answering"))
}

@Test func anAlertIsAnnouncedOnceAndItsEndToo() {
    var m = Monitor(region: here, now: t0)
    #expect(m.observe(reading(t0), now: t0).isEmpty)
    #expect(m.status(at: t0) == .calm)

    let begun = t0.plus(minutes: 1)
    #expect(m.observe(reading(begun, [here]), now: begun) == [.alertHere(region: here)])
    #expect(m.status(at: begun) == .alert(since: begun))
    let still = begun.plus(minutes: 1)
    #expect(m.observe(reading(still, [here]), now: still).isEmpty, "said once, not every minute")

    let over = still.plus(minutes: 1)
    #expect(m.observe(reading(over), now: over) == [.clearHere(region: here)])
}

@Test func anAlertAlreadyRunningAtLaunchIsAnnounced() {
    var m = Monitor(region: here, now: t0)
    #expect(m.observe(reading(t0, [here]), now: t0) == [.alertHere(region: here)])
}

@Test func goingBlindMidAlertNeitherEndsNorRepeatsIt() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0, [here]), now: t0)
    let blind = t0.plus(minutes: 10)
    let events = m.failed("timed out", now: blind)
    #expect(events == [.lost(reason: "the feed is not answering")], "lost, but not 'clear'")
    let back = blind.plus(minutes: 1)
    #expect(m.observe(reading(back, [here]), now: back) == [.regained], "same alert, not a new one")
}

@Test func aFrozenFeedIsCalledOut() {
    // Answers every minute, but its cache stopped an hour ago.
    var m = Monitor(region: here, now: t0)
    let events = m.observe(reading(t0, source: .some(t0.plus(minutes: -60))), now: t0.plus(minutes: 2))
    #expect(events == [.lost(reason: "the feed has stopped updating")])
}

@Test func aStaleReadingIsNewsWithoutANewReading() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0), now: t0)
    #expect(m.tick(now: t0.plus(minutes: 3)).isEmpty)
    #expect(m.tick(now: t0.plus(minutes: 5)) == [.lost(reason: "the last reading is 5 min old")])
    #expect(m.tick(now: t0.plus(minutes: 6)).isEmpty, "once per episode")
}

@Test func wakingUpGetsTheSameGraceAsStarting() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0), now: t0)
    let woke = t0.plus(minutes: 480) // a night with the lid shut
    m.resumed(now: woke)
    #expect(m.status(at: woke) == .starting)
    #expect(m.tick(now: woke).isEmpty, "no 'not watching' every morning")
    #expect(m.observe(reading(woke.plus(minutes: 0.2)), now: woke.plus(minutes: 0.2)).isEmpty)
}

@Test func elsewhereIsSaidOnceQuietly() {
    let lviv = "Львівська область", kyiv = "м. Київ"
    var m = Monitor(region: here, others: [lviv, kyiv], now: t0)
    #expect(m.observe(reading(t0, [lviv]), now: t0) == [.alertElsewhere(regions: [lviv])])
    let next = t0.plus(minutes: 1)
    #expect(m.observe(reading(next, [lviv, kyiv]), now: next) == [.alertElsewhere(regions: [kyiv])])
    let again = next.plus(minutes: 1)
    #expect(m.observe(reading(again, [lviv, kyiv]), now: again).isEmpty)
}

@Test func noRegionIsItsOwnState() {
    let m = Monitor(region: "", now: t0)
    #expect(m.status(at: t0) == .unset)
}
