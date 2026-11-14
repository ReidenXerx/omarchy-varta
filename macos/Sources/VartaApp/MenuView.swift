import Charts
import SwiftUI
import VartaCore

/// The dropdown: what Varta knows, how old that is, what has happened lately,
/// and the few things worth doing from here.
struct MenuView: View {
    @Bindable var varta: Varta
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VARTA")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            if varta.region.isEmpty {
                pickRegion
            } else {
                headline
                freshness
                if !varta.monitor.watch.others.isEmpty { elsewhere }
                HistoryView(summary: varta.summary)
            }

            Divider()
            actions
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: pieces

    private var pickRegion: some View {
        VStack(alignment: .leading, spacing: 8) {
            if varta.detecting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding your region…").font(.headline)
                }
            } else {
                Text(varta.detected == nil ? "Pick the region to watch" : "Could not tell where you are")
                    .font(.headline)
                if let why = varta.detected?.why {
                    Text(why.prefix(1).uppercased() + why.dropFirst() + ". Pick your region instead.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            RegionPicker(choice: $varta.choice).labelsHidden()
            Text("The feed reports whole oblasts, so an alert does not mean an alert over your street.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headline: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: ShieldIcon.image(for: varta.status, rehearsing: varta.rehearsing))
                .resizable().scaledToFit().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(titleColor)
                Text(varta.region).font(.callout)
                if let source = regionSource {
                    Text(source).font(.caption2).foregroundStyle(.tertiary)
                }
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// When the region was detected, say how, so a wrong guess is noticeable.
    private var regionSource: String? {
        guard varta.choice == Varta.auto, let answer = varta.detected else { return nil }
        return switch answer.confidence {
        case .located: "from this Mac's location"
        case .agreed: "from your internet address (two services agree)"
        case .single: "from your internet address (one service only, worth checking)"
        default: nil
        }
    }

    private var title: String {
        switch varta.status {
        case .unset: "No region"
        case .starting: "Starting…"
        case .calm: "Calm"
        case .alert: varta.rehearsing ? "ТЕСТ · ТРИВОГА" : "ПОВІТРЯНА ТРИВОГА"
        case .notWatching: "Not watching"
        }
    }

    private var titleColor: Color {
        switch varta.status {
        case .alert: varta.rehearsing ? .blue : .red
        case .notWatching: .orange
        default: .primary
        }
    }

    private var detail: String? {
        switch varta.status {
        case .alert(let since?):
            "Seen by this Mac since \(since.formatted(date: .omitted, time: .shortened))"
        case .alert:
            varta.rehearsing ? "A rehearsal. Nothing is happening." : nil
        case .notWatching(let reason):
            "\(reason.prefix(1).uppercased() + reason.dropFirst()). Silence from Varta does not mean calm right now."
        case .starting:
            "Reading the feed for the first time."
        default:
            nil
        }
    }

    private var freshness: some View {
        let watch = varta.monitor.watch
        return VStack(alignment: .leading, spacing: 2) {
            if let age = watch.readingAge(at: varta.now) {
                if let sourceAge = watch.sourceAge(at: varta.now), sourceAge >= staleAfter {
                    // Answered, but with old data: say so rather than "read 0 s ago".
                    Text("Feed answered \(ago(age)), but its data is \(Int(sourceAge / 60)) min old")
                } else if watch.health(at: varta.now) == .ok {
                    Text("Feed read \(ago(age)) · \(watch.alertingCount) of 26 regions under alert")
                } else {
                    // No count from evidence the watch no longer trusts.
                    Text("Last good reading \(ago(age))")
                }
            } else {
                Text("No reading yet")
            }
            if watch.consecutiveFailures > 0 {
                Text("\(watch.consecutiveFailures) failed \(watch.consecutiveFailures == 1 ? "try" : "tries") in a row, retrying more slowly")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var elsewhere: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ALSO WATCHING").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            ForEach(varta.monitor.elsewhere(at: varta.now), id: \.region) { place in
                HStack(spacing: 8) {
                    Circle()
                        .fill(place.alert == true ? Color.red : place.alert == false ? Color.secondary.opacity(0.4) : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(place.region).font(.callout)
                    Spacer()
                    Text(place.alert == true ? "тривога" : place.alert == false ? "calm" : "unknown")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if varta.rehearsing {
                Button("End the rehearsal") { varta.endRehearsal() }
            } else {
                Button("Test the alert") { varta.rehearse() }
            }
            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate()
            }
            Button("Quit Varta") { NSApp.terminate(nil) }
        }
        .buttonStyle(.link)
    }

    private func ago(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) s ago" : "\(Int(seconds / 60)) min ago"
    }
}

/// "Detect automatically" plus the 26 regions, as one picker.
struct RegionPicker: View {
    @Binding var choice: String

    var body: some View {
        Picker("Your region", selection: $choice) {
            Text("Choose…").tag("")
            Text("Detect automatically").tag(Varta.auto)
            Divider()
            ForEach(Regions.all, id: \.self) { Text($0).tag($0) }
        }
    }
}

/// How many, how long, and when they tend to come, for the watched regions.
struct HistoryView: View {
    let summary: Summary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALERTS BY HOUR · LAST \(summary.days) DAYS")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            if summary.total == 0 && summary.ongoing.isEmpty {
                Text(untimedOnly)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ByHourChart(byHour: summary.byHour).frame(height: 64)
                Text(line).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var untimedNote: String? {
        guard let n = summary.untimed, n > 0 else { return nil }
        return "\(n) more seen only after a gap in watching, so when and how long are unknown"
    }

    private var untimedOnly: String {
        if let n = summary.untimed, n > 0 {
            return "No timed alerts yet. \(n) \(n == 1 ? "alert was" : "alerts were") seen only after a gap in watching, so when and how long are unknown."
        }
        return "Nothing recorded yet. The history builds up while Varta watches."
    }

    private var line: String {
        var parts = ["\(summary.total) \(summary.total == 1 ? "alert" : "alerts")"]
        if let longest = summary.longest {
            parts.append("longest \(spell(Int(longest.length(at: Date()))))")
        }
        if let quiet = summary.quietSeconds {
            parts.append("quiet for \(spell(quiet))")
        } else if !summary.ongoing.isEmpty {
            parts.append("one running now")
        }
        if let busiest = summary.byHour.indices.max(by: { summary.byHour[$0] < summary.byHour[$1] }),
           summary.byHour[busiest] > 0 {
            parts.append(String(format: "most often from %02d:00", busiest))
        }
        if let note = untimedNote { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

struct ByHourChart: View {
    let byHour: [Int]

    var body: some View {
        Chart(Array(byHour.enumerated()), id: \.offset) { hour, count in
            BarMark(x: .value("Hour", hour), y: .value("Alerts", count), width: .fixed(7))
                .foregroundStyle(Color.accentColor)
        }
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                AxisValueLabel { Text(String(format: "%02d", value.as(Int.self) ?? 0)) }
            }
        }
        .chartYAxis(.hidden)
        .accessibilityLabel("Alerts by the hour they began")
    }
}

/// 4 h 10 m, 25 m, 2 d 3 h.
func spell(_ seconds: Int) -> String {
    let m = seconds / 60, h = m / 60, d = h / 24
    if d > 0 { return "\(d) d \(h % 24) h" }
    if h > 0 { return "\(h) h \(m % 60) m" }
    return "\(max(1, m)) m"
}
