import AppKit
import SwiftUI
import VartaCore

@main
struct VartaApp: App {
    @State private var varta = Varta()

    var body: some Scene {
        MenuBarExtra {
            MenuView(varta: varta)
        } label: {
            Image(nsImage: ShieldIcon.image(for: varta.status, rehearsing: varta.rehearsing))
                .accessibilityLabel(ShieldIcon.words(for: varta.status))
        }
        .menuBarExtraStyle(.window)

        Window("Varta Settings", id: "settings") {
            SettingsView(varta: varta)
        }
        .windowResizability(.contentSize)
    }
}

/// The shield in the menu bar. Coloured on purpose: "not watching" must look as
/// loud as an alert, and a template image would draw both in the same grey.
enum ShieldIcon {
    static func image(for status: Status, rehearsing: Bool) -> NSImage {
        let (symbol, color): (String, NSColor?) = switch status {
        case .unset: ("shield", .tertiaryLabelColor)
        case .starting: ("shield.lefthalf.filled", .secondaryLabelColor)
        case .calm: ("shield", nil)
        case .alert: ("exclamationmark.shield.fill", rehearsing ? .systemBlue : .systemRed)
        case .notWatching: ("shield.slash.fill", .systemOrange)
        }
        let size = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: words(for: status))!
        guard let color else {
            let image = base.withSymbolConfiguration(size)!
            image.isTemplate = true // calm follows the menu bar's own colour
            return image
        }
        // Two colours: the mark inside the shield must not vanish into it.
        let image = base.withSymbolConfiguration(size.applying(.init(paletteColors: [.white, color])))!
        image.isTemplate = false
        return image
    }

    static func words(for status: Status) -> String {
        switch status {
        case .unset: "Varta: no region chosen"
        case .starting: "Varta: starting"
        case .calm: "Varta: calm"
        case .alert: "Varta: air raid alert"
        case .notWatching: "Varta: not watching"
        }
    }
}
