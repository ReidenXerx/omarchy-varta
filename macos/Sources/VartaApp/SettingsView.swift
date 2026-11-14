import SwiftUI
import VartaCore

/// The same settings as the Omarchy widget's schema (manifest.json), minus the
/// band, which the Mac does with a notification instead.
struct SettingsView: View {
    @Bindable var varta: Varta
    @State private var atLogin = false

    var body: some View {
        Form {
            Section {
                RegionPicker(choice: $varta.choice)
                if varta.choice == Varta.auto {
                    LabeledContent("Watching", value: varta.detecting ? "finding…" : (varta.region.isEmpty ? "could not tell" : varta.region))
                }
            } footer: {
                Text("Detect asks this Mac's location first and, if that is not allowed, two public services where your internet address appears to be, believing them only when they agree. Pick a region and neither is ever asked. The feed reports whole oblasts, so an alert does not mean an alert over your street.")
            }

            Section {
                DisclosureGroup("Also keep an eye on (\(varta.others.count))") {
                    ForEach(Regions.all.filter { $0 != varta.region }, id: \.self) { region in
                        Toggle(region, isOn: Binding(
                            get: { varta.others.contains(region) },
                            set: { on in
                                if on { varta.others.append(region) } else { varta.others.removeAll { $0 == region } }
                            }
                        ))
                    }
                }
            } footer: {
                Text("Family, friends, somewhere you are heading. Said once, quietly. They never break through Focus: that is kept for where you are.")
            }

            Section("Sound") {
                Toggle("Play a sound", isOn: $varta.soundOn)
                Picker("Sound", selection: $varta.voice) {
                    ForEach(Varta.voices, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!varta.soundOn)
                Stepper("Say it again every \(varta.repeatEvery) s", value: $varta.repeatEvery, in: 15...600, step: 15)
                    .disabled(!varta.soundOn)
                Stepper("Say it \(varta.sayTimes) \(varta.sayTimes == 1 ? "time" : "times")", value: $varta.sayTimes, in: 1...20)
                    .disabled(!varta.soundOn)
            }

            Section {
                Toggle("Open at login", isOn: $atLogin)
                    .onChange(of: atLogin) { _, on in varta.opensAtLogin = on }
            } footer: {
                Text("Varta is a companion to the official app and to the sirens outside, not a replacement for either, and not an official source.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .frame(minHeight: 520)
        .onAppear { atLogin = varta.opensAtLogin }
    }
}
