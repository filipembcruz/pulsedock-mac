import SwiftUI
import AppKit

struct SettingsPage: View {
    @ObservedObject var store = SettingsStore.shared
    @ObservedObject var model = AppModel.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    private let intervals: [Double] = [0.5, 1, 2, 3, 5]

    var body: some View {
        Form {
            Section(L("set.general")) {
                Picker(L("set.language"), selection: languageBinding) {
                    Text(L("set.lang.auto")).tag("auto")
                    Text("English").tag("en")
                    Text("Português").tag("pt")
                }
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { v in
                    if LoginItem.set(v) { launchAtLogin = v } else { launchAtLogin = LoginItem.isEnabled }
                })) {
                    VStack(alignment: .leading) {
                        Text(L("set.launchAtLogin"))
                        Text(L("loginItemNote")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker(L("set.menuBar"), selection: $store.s.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text(L("set.mb.\($0.rawValue)")).tag($0) }
                }
                Picker(L("set.interval"), selection: $store.s.interval) {
                    ForEach(intervals, id: \.self) { v in
                        Text(L10n.f("set.seconds", v == 0.5 ? "0.5" : String(Int(v)))).tag(v)
                    }
                }
            }

            Section(L("set.widget")) {
                Picker(L("set.mode"), selection: $store.s.mode) {
                    ForEach(DisplayMode.allCases) { Text(L("mode.\($0.rawValue)")).tag($0) }
                }
                Picker(L("set.layout"), selection: $store.s.layout) {
                    ForEach(WidgetLayout.allCases) { Text(L("layout.\($0.rawValue)")).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("set.corner"), selection: cornerBinding) {
                    ForEach(Corner.allCases) { Text(L("corner.\($0.rawValue)")).tag($0) }
                }
                if store.s.freePosition {
                    HStack {
                        Text(L("set.freePosition")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("set.resetPosition")) { model.resetWidgetPosition() }
                    }
                }
                Picker(L("set.screen"), selection: $store.s.screenID) {
                    Text(L("set.mainScreen")).tag(UInt32(0))
                    ForEach(NSScreen.screens, id: \.displayID) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                }
                LabeledContent(L("set.margin")) {
                    HStack {
                        Slider(value: $store.s.edgeMargin, in: 0...80, step: 2)
                        Text("\(Int(store.s.edgeMargin)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent(L("set.opacity")) {
                    HStack {
                        Slider(value: $store.s.opacity, in: 0.4...1, step: 0.05)
                        Text(Fmt.percent(store.s.opacity)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle(L("set.lock"), isOn: $store.s.lockPosition)
                Toggle(L("set.clickThrough"), isOn: $store.s.clickThrough)
                Toggle(L("set.hideFullscreen"), isOn: $store.s.hideInFullscreen)
            }

            Section(L("set.metrics")) {
                Toggle(L("cpu"), isOn: $store.s.showCPU)
                Toggle(L("memory"), isOn: $store.s.showMemory)
                Toggle(L("disk"), isOn: $store.s.showDisk)
                Toggle(L("gpu"), isOn: $store.s.showGPU)
                Toggle(L("network"), isOn: $store.s.showNetwork)
                Toggle(L("battery"), isOn: $store.s.showBattery)
            }

            Section(L("set.about")) {
                LabeledContent("PulseDock", value: L10n.f("set.version", AppInfo.version))
                Link("github.com/filipembcruz/pulsedock-mac", destination: URL(string: "https://github.com/filipembcruz/pulsedock-mac")!)
                Button(L("set.reset"), role: .destructive) { store.reset() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var languageBinding: Binding<String> {
        Binding(get: { store.s.language }, set: { v in
            store.s.language = v
            model.languageTick += 1
        })
    }

    private var cornerBinding: Binding<Corner> {
        Binding(get: { store.s.corner }, set: {
            store.s.corner = $0
            store.s.freePosition = false
        })
    }
}
