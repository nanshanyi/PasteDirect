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
    @State private var selection: SettingCategory? = SettingCategory.general

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $selection)
        } detail: {
            DetailView(category: selection)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .environmentObject(settingsStore)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            selection = navigationModel.selectedCategory
        }
        .onChange(of: navigationModel.selectedCategory) { newValue in
            if selection?.id != newValue?.id {
                selection = newValue
            }
        }
        .onChange(of: selection) { newValue in
            if navigationModel.selectedCategory?.id != newValue?.id {
                navigationModel.selectedCategory = newValue
            }
        }
    }
}
