import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    @StateObject private var settingsStore = SettingsStore.shared
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
