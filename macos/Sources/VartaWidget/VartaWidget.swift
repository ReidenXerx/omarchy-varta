import Charts
import SwiftUI
import VartaCore
import WidgetKit

// Varta on the desktop. It cannot poll the feed itself; it shows what the app
// last wrote, always with when that was, and says "not watching" on its own once
// the app has clearly stopped.

/// WidgetKit refreshes on its own budget; see Shared.shown(at:slack:).
let slack: TimeInterval = 15 * 60

struct Entry: TimelineEntry {
    let date: Date
    let shared: Shared?
}

struct Provider: TimelineProvider {
    var directory: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "VartaAppGroup") as? String)
            .flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    func placeholder(in context: Context) -> Entry {
        // Invented, never real data: this is what the widget gallery shows.
        Entry(date: .now, shared: Shared(region: "Your region", kind: .calm, since: nil, reason: nil,
                                         trustedUntil: .now.addingTimeInterval(staleAfter),
                                         summary: .empty(days: 30), writtenAt: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Entry(date: .now, shared: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let shared = read()
        let now = Date.now
        var entries = [Entry(date: now, shared: shared)]
        // The moment it must stop vouching, written into the timeline in advance
        // so it happens even if the app never speaks again.
        if let until = shared?.trustedUntil?.addingTimeInterval(slack), until > now {
            entries.append(Entry(date: until, shared: shared))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(10 * 60))))
    }

    private func read() -> Shared? { directory.flatMap(Shared.read(from:)) }
}

struct VartaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        Group {
            if let shared = entry.shared {
                let shown = shared.shown(at: entry.date, slack: slack)
                if family == .systemSmall {
                    status(shared, shown)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        status(shared, shown)
                        history(shared.summary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "shield.slash.fill").font(.title).foregroundStyle(.orange)
                    Text("Not watching").font(.headline).foregroundStyle(.orange)
                    Text("Open Varta to start watching.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func status(_ shared: Shared, _ shown: (kind: Shared.Kind, reason: String?)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol(shown.kind))
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, color(shown.kind))
            Text(title(shown.kind)).font(.headline).foregroundStyle(color(shown.kind == .calm ? .unset : shown.kind))
                .lineLimit(2).minimumScaleFactor(0.7)
            Text(shared.region).font(.caption).lineLimit(1)
            Spacer(minLength: 0)
            if let reason = shown.reason {
                Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            } else if let checked = shared.checkedAt {
                Text("checked \(checked.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func history(_ summary: Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BY HOUR · \(summary.days) DAYS").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            if summary.total == 0 {
                Text((summary.untimed ?? 0) > 0 ? "No timed alerts yet; \(summary.untimed!) seen only after a gap in watching" : "Nothing recorded yet")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                Spacer(minLength: 0)
            } else {
                Chart(Array(summary.byHour.enumerated()), id: \.offset) { hour, count in
                    BarMark(x: .value("Hour", hour), y: .value("Alerts", count), width: .fixed(4))
                        .foregroundStyle(Color.accentColor)
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis {
                    AxisMarks(values: [0, 12, 23]) { value in
                        AxisValueLabel { Text(String(format: "%02d", value.as(Int.self) ?? 0)).font(.system(size: 8)) }
                    }
                }
                .chartYAxis(.hidden)
                Text("\(summary.total) alerts").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func symbol(_ kind: Shared.Kind) -> String {
        switch kind {
        case .unset: "shield"
        case .starting: "shield.lefthalf.filled"
        case .calm: "shield"
        case .alert: "exclamationmark.shield.fill"
        case .lost: "shield.slash.fill"
        }
    }

    private func title(_ kind: Shared.Kind) -> String {
        switch kind {
        case .unset: "No region"
        case .starting: "Starting…"
        case .calm: "Calm"
        case .alert: "ПОВІТРЯНА ТРИВОГА"
        case .lost: "Not watching"
        }
    }

    private func color(_ kind: Shared.Kind) -> Color {
        switch kind {
        case .alert: .red
        case .lost: .orange
        case .calm: .primary
        default: .secondary
        }
    }
}

@main
struct VartaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VartaWidget", provider: Provider()) { entry in
            VartaWidgetView(entry: entry)
        }
        .configurationDisplayName("Varta")
        .description("Your region's air raid alert status, and when alerts tend to come.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
