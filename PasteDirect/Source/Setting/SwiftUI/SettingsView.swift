import SwiftUI

// MARK: - Navigation Model

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedCategory: SettingCategory? = SettingCategory.general
}

// MARK: - Main Settings View

struct SettingsView: View {
    @StateObject private var settingsStore = SettingsStore.shared
    @ObservedObject var navigationModel: SettingsNavigationModel

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $navigationModel.selectedCategory)
        } detail: {
            DetailView(category: navigationModel.selectedCategory)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .environmentObject(settingsStore)
        .frame(minWidth: 600, minHeight: 500)
    }
}
