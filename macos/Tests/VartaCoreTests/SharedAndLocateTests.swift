import Foundation
import Testing
@testable import VartaCore

// The widget and the region finder: the two places a confident wrong answer
// would look exactly like a right one.

@Test func aWidgetLeftBehindByADeadAppStopsSayingCalm() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0), now: t0)
    let shared = Shared(monitor: m, summary: .empty(days: 30), now: t0)
    #expect(shared.shown(at: t0.plus(minutes: 1)).kind == .calm)
    let later = shared.shown(at: t0.plus(minutes: 5))
    #expect(later.kind == .lost, "past four minutes the widget cannot vouch for calm")
    #expect(later.reason?.hasPrefix("Varta has not read the feed since") == true)
}

@Test func anAlertInTheWidgetExpiresToo() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0, [here]), now: t0)
    let shared = Shared(monitor: m, summary: .empty(days: 30), now: t0)
    #expect(shared.shown(at: t0).kind == .alert)
    #expect(shared.shown(at: t0.plus(minutes: 10)).kind == .lost)
}

@Test func aFrozenCacheShortensTheWidgetsTrust() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0, source: .some(t0.plus(minutes: -3))), now: t0)
    let shared = Shared(monitor: m, summary: .empty(days: 30), now: t0)
    #expect(shared.trustedUntil == t0.plus(minutes: 1), "the cache was already 3 of its 4 minutes old")
}

@Test func theWidgetDoesNotSitOnStartingForever() {
    let m = Monitor(region: here, now: t0)
    let shared = Shared(monitor: m, summary: .empty(days: 30), now: t0)
    #expect(shared.shown(at: t0.plus(minutes: 1)).kind == .starting)
    #expect(shared.shown(at: t0.plus(minutes: 5)).kind == .lost)
}

@Test func theSnapshotSurvivesTheRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0, [here]), now: t0)
    let shared = Shared(monitor: m, summary: .empty(days: 30), now: t0)
    try shared.write(to: dir)
    #expect(Shared.read(from: dir) == shared)
}

// MARK: locate

@Test func twoServicesThatAgreeAreBelieved() {
    let a = Locate.decide(seen: ["a": "Тернопільська область", "b": "Тернопільська область"], masked: false)
    #expect(a == .init(region: "Тернопільська область", confidence: .agreed))
}

@Test func oneServiceAloneIsWorthCheckingNotTrusting() {
    #expect(Locate.decide(seen: ["a": "м. Київ"], masked: false).confidence == .single)
    #expect(Locate.decide(seen: ["a": "м. Київ", "b": String?.none], masked: false).confidence == .single)
}

@Test func disagreementAndVPNsRefuseToGuess() {
    #expect(Locate.decide(seen: ["a": "м. Київ", "b": "Київська область"], masked: false).region == nil)
    #expect(Locate.decide(seen: ["a": "м. Київ", "b": "м. Київ"], masked: true).confidence == .masked)
    #expect(Locate.decide(seen: [:], masked: false).confidence == .unknown)
}

@Test func servicesAreReadInTheirOwnShapes() {
    // ipwho.is
    #expect(Locate.read(["country": "Ukraine", "region_code": "61", "region": "Ternopil Oblast"]).region == "Тернопільська область")
    // ip-api.com
    #expect(Locate.read(["country": "Ukraine", "region": "30", "regionName": "Kyiv City", "proxy": false]).region == "м. Київ")
    #expect(Locate.read(["country": "Ukraine", "region": "30", "hosting": true]).masked)
    #expect(Locate.read(["country": "Poland", "region": "MZ"]).region == nil)
}

@Test func coreLocationNamesMapToFeedRegions() {
    #expect(Locate.fromPlacemark(countryCode: "UA", administrativeArea: "Kyiv", locality: "Kyiv") == "м. Київ")
    #expect(Locate.fromPlacemark(countryCode: "UA", administrativeArea: "Kyiv Oblast", locality: "Brovary") == "Київська область")
    #expect(Locate.fromPlacemark(countryCode: "UA", administrativeArea: "Lviv Oblast", locality: "Lviv") == "Львівська область")
    #expect(Locate.fromPlacemark(countryCode: "PL", administrativeArea: "Masovian", locality: "Warsaw") == nil)
}

@Test func theWidgetsSlackDelaysButNeverCancelsGivingUp() {
    var m = Monitor(region: here, now: t0)
    _ = m.observe(reading(t0), now: t0)
    let shared = Shared(monitor: m, summary: .empty(days: 30), now: t0)
    #expect(shared.checkedAt == t0)
    #expect(shared.shown(at: t0.plus(minutes: 10), slack: 15 * 60).kind == .calm)
    #expect(shared.shown(at: t0.plus(minutes: 20), slack: 15 * 60).kind == .lost)
}
