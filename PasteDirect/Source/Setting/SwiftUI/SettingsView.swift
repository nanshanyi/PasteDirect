import SwiftUI
internal import Combine

// MARK: - Settings Store
@MainActor
class SettingsStore: ObservableObject {
    @Published var settings: [PrefKey: Any] = [:]
    
    init() {
        loadDefaultSettings()
    }

    private func loadDefaultSettings() {
        settings = [
            .onStart: PasteUserDefaults.onStart,
            .statusDisplay: PasteUserDefaults.statusDisplay,
            .pasteDirect: PasteUserDefaults.pasteDirect,
            .pasteOnlyText: PasteUserDefaults.pasteOnlyText,
            .historyTime: PasteUserDefaults.historyTime,
            .appAlreadyLaunched: PasteUserDefaults.appAlreadyLaunched,
            .appColorData: PasteUserDefaults.appColorData,
            .lastClearDate: PasteUserDefaults.lastClearDate,
            .ignoreList: PasteUserDefaults.ignoreList,
        ]
    }

    func getBool(_ key: PrefKey, defaultValue: Bool = false) -> Bool {
        return settings[key] as? Bool ?? defaultValue
    }

    func getDouble(_ key: PrefKey, defaultValue: Double = 0.0) -> Double {
        return settings[key] as? Double ?? defaultValue
    }

    func setBool(_ key: PrefKey, value: Bool) {
        settings[key] = value
        PasteUserDefaults.setValue(for: key, value: value)
    }

    func setDouble(_ key: PrefKey, value: Double) {
        settings[key] = value
        PasteUserDefaults.setValue(for: key, value: value)
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @StateObject private var settingsStore = SettingsStore()
    @State private var selectedCategory: SettingCategory? = SettingCategory.general

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $selectedCategory)
        } detail: {
            DetailView(category: selectedCategory)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .environmentObject(settingsStore)
        .frame(minWidth: 600, minHeight: 500)
    }
}
