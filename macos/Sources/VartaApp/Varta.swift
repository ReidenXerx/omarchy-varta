import AppKit
import Observation
import ServiceManagement
import UserNotifications
import VartaCore

/// The app's state: settings, the monitor, the poll loop, and what gets said.
@MainActor @Observable
final class Varta {
    // MARK: settings (persisted)

    /// What the person chose: a region, `Varta.auto`, or "" for nothing yet.
    var choice: String { didSet { save("region", choice); detected = nil; restart(); if choice == Self.auto { detect() } } }
    var others: [String] { didSet { save("also", others); restart() } }
    var soundOn: Bool { didSet { save("sound", soundOn) } }
    var voice: String { didSet { save("voice", voice) } }
    /// Seconds between soundings at the start of an alert.
    var repeatEvery: Int { didSet { save("repeatEvery", repeatEvery) } }
    /// An alert can stand for hours; after this many soundings it goes quiet.
    var sayTimes: Int { didSet { save("sayTimes", sayTimes) } }

    static let voices = ["Glass", "Bell", "Marimba"]
    static let auto = "auto"
    /// How far back the history in the dropdown and the widget looks.
    static let historyDays = 30

    /// The region actually watched.
    var region: String { choice == Self.auto ? (detected?.region ?? "") : choice }

    // MARK: state

    private(set) var monitor: Monitor
    /// Ticks forward so "40 s ago" and stale/blind stay true without a reading.
    private(set) var now = Date()
    private(set) var rehearsing = false
    private(set) var notificationsAllowed: Bool?
    /// What detection found, when the choice is automatic.
    private(set) var detected: Locate.Answer?
    private(set) var detecting = false
    private(set) var summary = Summary.empty(days: Varta.historyDays)

    var status: Status { rehearsing ? .alert(since: nil) : monitor.status(at: now) }

    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var sayTask: Task<Void, Never>?
    private var lastRequest: Date?
    private let notifier = Notifier()
    private let store = Store()
    private let locator = Locator()
    private var sound: NSSound?

    init() {
        let d = UserDefaults.standard
        // A first launch detects, like the Omarchy widget's default.
        choice = d.string(forKey: "region") ?? Varta.auto
        others = d.stringArray(forKey: "also") ?? []
        soundOn = d.object(forKey: "sound") as? Bool ?? true
        voice = d.string(forKey: "voice") ?? "Glass"
        repeatEvery = d.object(forKey: "repeatEvery") as? Int ?? 45
        sayTimes = d.object(forKey: "sayTimes") as? Int ?? 3
        monitor = Monitor(region: "", now: Date())

        Task { notificationsAllowed = await notifier.authorize() }
        observeSleep()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.tick()
            }
        }
        restart()
        if choice == Self.auto { detect() }
    }

    private func save(_ key: String, _ value: Any) { UserDefaults.standard.set(value, forKey: key) }

    // MARK: polling

    /// Settings changed: start a fresh watch. Same grace as a launch, so picking
    /// a region never flashes "not watching".
    private func restart() {
        let others = self.others.filter { $0 != region }
        monitor = Monitor(region: region, others: others, now: Date())
        refreshSummary()
        startPolling()
    }

    /// Asked once per launch or choice, never on a timer: a Mac rarely changes
    /// oblast, and each ask costs a location fix or two IP lookups.
    func detect() {
        guard choice == Self.auto, !detecting else { return }
        detecting = true
        Task { [weak self] in
            guard let self else { return }
            let answer = await self.locator.locate()
            self.detecting = false
            guard self.choice == Self.auto else { return }
            self.detected = answer
            self.restart()
        }
    }

    private func refreshSummary() {
        let watched = Set([region] + others).subtracting([""])
        summary = summarise(store.transitions, now: Date(), days: Self.historyDays, only: watched)
    }

    private func publish() {
        store.publish(Shared(monitor: monitor, summary: summary, now: now))
    }

    private func startPolling() {
        pollTask?.cancel()
        guard !region.isEmpty else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                await self.pollOnce()
                let failures = self.monitor.watch.consecutiveFailures
                let wait = failures == 0 ? Feed.interval : backoff(failures: failures, base: Feed.interval)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func pollOnce() async {
        // Never faster than the feed tolerates, however often settings change
        // or the lid opens. It rate-limits by IP, and the same IP may be running
        // another watch.
        if let last = lastRequest {
            let gap = Date().timeIntervalSince(last)
            if gap < Feed.minimumInterval {
                try? await Task.sleep(for: .seconds(Feed.minimumInterval - gap))
                if Task.isCancelled { return }
            }
        }
        lastRequest = Date()
        let events: [Event]
        do {
            let answer = try await Poller.fetch()
            if Task.isCancelled { return }
            let at = Date()
            events = monitor.observe(Reading(fetchedAt: at, sourceTime: answer.sourceTime, alerting: answer.alerting), now: at)
            if monitor.watch.health(at: at) == .ok {
                store.record(answer.alerting, regions: answer.names, at: at)
                refreshSummary()
            }
        } catch {
            if Task.isCancelled { return }
            events = monitor.failed(String(describing: error), now: Date())
        }
        now = Date()
        handle(events)
        publish()
    }

    private func tick() {
        now = Date()
        let events = monitor.tick(now: now)
        handle(events)
        if !events.isEmpty { publish() }
    }

    // MARK: sleep and wake

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollTask?.cancel() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A Mac that slept has not "lost the feed"; it has just woken,
                // and its network is usually a moment behind it.
                self.monitor.resumed(now: Date())
                self.now = Date()
                self.startPolling()
            }
        }
    }

    // MARK: speaking up

    private func handle(_ events: [Event]) {
        for event in events {
            switch event {
            case .alertHere(let region):
                notifier.post(.alert(region: region))
                startSaying()
            case .clearHere(let region):
                stopSaying()
                notifier.post(.clear(region: region))
                play("clear")
            case .alertElsewhere(let regions):
                notifier.post(.elsewhere(regions: regions))
                play("alert", quietly: true)
            case .lost(let reason):
                notifier.post(.lost(reason: reason))
            case .regained:
                notifier.withdrawLost()
            }
        }
    }

    /// The first sounding can be missed; the eightieth is just noise. So: say
    /// it now, again every `repeatEvery` seconds, `sayTimes` in all, then leave
    /// the menu bar to do the work.
    private func startSaying() {
        sayTask?.cancel()
        sayTask = Task { [weak self] in
            var said = 0
            while !Task.isCancelled, let self, self.status.isAlert, said < max(1, self.sayTimes) {
                self.play("alert")
                said += 1
                try? await Task.sleep(for: .seconds(max(15, self.repeatEvery)))
            }
        }
    }

    private func stopSaying() {
        sayTask?.cancel()
        sound?.stop()
    }

    private func play(_ kind: String, quietly: Bool = false) {
        guard soundOn else { return }
        let name = "\(kind)-\(voice.lowercased())"
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let s = NSSound(contentsOf: url, byReference: true) else { return }
        s.volume = quietly ? 0.4 : 1.0
        sound?.stop()
        sound = s
        s.play()
    }

    // MARK: rehearsal

    /// So you do not first find out whether it works during an attack.
    func rehearse() {
        rehearsing = true
        notifier.post(.rehearsal(region: region.isEmpty ? "your region" : region))
        play("alert")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.rehearsing = false
        }
    }

    func endRehearsal() {
        rehearsing = false
        sound?.stop()
    }

    // MARK: login item

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Varta: login item: \(error)")
            }
        }
    }
}
