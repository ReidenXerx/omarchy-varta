import Foundation
import VartaCore
import WidgetKit

/// Where Varta keeps what outlives a launch: the history file, and the snapshot
/// the desktop widget reads. Both live in the app group container so the
/// sandboxed widget can see them.
@MainActor
final class Store {
    let directory: URL
    private(set) var transitions: [Transition] = []
    private var ledger = Ledger()
    /// The last trusted reading, across launches (the widget snapshot keeps it).
    private var lastTrusted: Date?
    private var lastWidgetKind: Shared.Kind?
    private var lastWidgetSince: Date?
    private var lastWidgetReload = Date.distantPast

    init() {
        let group = Bundle.main.object(forInfoDictionaryKey: "VartaAppGroup") as? String
        let shared = group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Varta")
        directory = shared ?? fallback
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        load()
    }

    private var historyURL: URL { directory.appendingPathComponent("history.jsonl") }

    private func load() {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return }
        transitions = text.split(separator: "\n").compactMap { Transition.parse(String($0)) }
        // Seed the ledger with the last known state of each region, so an alert
        // that ended while Varta was not running is closed on the first reading
        // instead of staying open forever.
        var last: [String: Bool] = [:]
        for t in transitions.sorted(by: { $0.at < $1.at }) { last[t.region] = t.alert }
        ledger = Ledger(known: last)
        lastTrusted = Shared.read(from: directory)?.checkedAt
    }

    /// A trusted reading. Only ever called with evidence the watch believes: a
    /// blind watcher writing "clear" would invent the end of an alert that may
    /// still be running.
    func record(_ alerting: Set<String>, regions: [String], at when: Date) {
        // After a gap (quit, asleep, feed down) a change happened at some
        // unknown moment inside it, not now.
        let uncertain = lastTrusted.map { when.timeIntervalSince($0) > History.gapLimit } ?? true
        lastTrusted = when
        let changes = regions.compactMap {
            ledger.observe($0, alerting: alerting.contains($0), at: when, uncertain: uncertain)
        }
        guard !changes.isEmpty else { return }
        transitions.append(contentsOf: changes)
        append(changes)
    }

    /// Best effort on purpose: a watch that cannot write its diary must still
    /// watch, so failures here are swallowed.
    private func append(_ changes: [Transition]) {
        let text = changes.map { $0.line + "\n" }.joined()
        let url = historyURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
        if transitions.count > History.maxRecords + 1000 {
            transitions = Array(transitions.suffix(History.maxRecords))
            let all = transitions.map { $0.line }.joined(separator: "\n") + "\n"
            try? Data(all.utf8).write(to: url, options: .atomic)
        }
    }

    // MARK: widget

    /// The widget's timeline is budgeted, so it is reloaded when what it shows
    /// changes, and otherwise every few minutes so its "checked at" stays fresh.
    func publish(_ shared: Shared) {
        try? shared.write(to: directory)
        let changed = shared.kind != lastWidgetKind || shared.since != lastWidgetSince
        if changed || Date().timeIntervalSince(lastWidgetReload) > 5 * 60 {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetKind = shared.kind
            lastWidgetSince = shared.since
            lastWidgetReload = Date()
        }
    }
}
