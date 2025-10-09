import KeyboardShortcuts
import SwiftUI

// MARK: - Detail View

struct DetailView: View {
    let category: SettingCategory?

    var body: some View {
        Group {
            if let category = category {
                switch category.type {
                case .common:
                    commonCategoryView(category)
                case .custom:
                    RulesDetailView(category: category)
                }
            } else {
                emptyView
            }
        }
    }

    @ViewBuilder
    private func commonCategoryView(_ category: SettingCategory) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(category.sections, id: \.id) { section in
                    SettingSectionView(section: section)
                }
            }
            .padding()
        }
        .navigationTitle(category.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyView: some View {
        Text("Select a category from the sidebar")
            .foregroundStyle(.secondary)
    }
}

// MARK: - Setting Section View

struct SettingSectionView: View {
    let section: SettingSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 1) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        SettingItemView(item: item)
                            .background(Color(NSColor.controlBackgroundColor))
                        if index < section.items.count - 1 {
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Setting Item View

struct SettingItemView: View {
    let item: SettingItem
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var showAlert = false
    @State private var showClearAlert = false
    @State private var pendingAlertValue: (key: PrefKey, value: Int, origin: Int)?

    var body: some View {
        HStack {
            itemContent
        }
        .frame(alignment: .center)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .alert("", isPresented: $showAlert) {
            Button("Cancel", role: .cancel) {
                handleAlertCancel()
            }
            Button("Sure") {
                handleAlertConfirm()
            }
            .background(Color.blue)
        } message: {
            Text("You have items that are older than the new history limit. Do you want to delete these older items and apply the new limit?")
        }
        .alert("Clear all clipboard history", isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                handleClearAll()
            }
        } message: {
            Text("This action cannot be undone. All clipboard data will be permanently deleted.")
        }
    }

    @ViewBuilder
    private var itemContent: some View {
        switch item {
        case let .toggle(title, key):
            toggleItem(title: title, key: key)
        case let .text(title, _):
            textItem(title: title)
        case let .slider(_, key, range, step):
            sliderItem(key: key, range: range, step: step)
        case let .button(title):
            buttonItem(title: title)
        case let .shortCut(title, name):
            shortcutItem(title: title, name: name)
        }
    }

    // MARK: - Item Components

    private func toggleItem(title: LocalizedStringKey, key: PrefKey) -> some View {
        Group {
            textLabel(title)
            Spacer()
            Toggle("", isOn: Binding(
                get: { settingsStore.getBool(key) },
                set: { settingsStore.setBool(key, value: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private func textItem(title: LocalizedStringKey) -> some View {
        Group {
            textLabel(title)
            Text(settingsStore.totalCountString)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func sliderItem(key: PrefKey, range: ClosedRange<Double>, step: Double) -> some View {
        VStack {
            Slider(
                value: Binding(
                    get: { Double(settingsStore.getInt(key)) },
                    set: { value in
                        handleSliderChange(key: key, newValue: Int(value))
                    }
                ),
                in: range,
                step: step
            )
            .padding(10)
            .controlSize(.small)

            sliderLabels
        }
    }

    private var sliderLabels: some View {
        HStack(spacing: 0) {
            Text("Day")
            Spacer()
            Text("Week")
            Spacer()
            Text("Month")
                .padding(.leading, 5)
            Spacer()
            Text("Forever")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .padding(.trailing, -2)
    }

    private func buttonItem(title: LocalizedStringKey) -> some View {
        Group {
            Spacer()
            Button(title) {
                showClearAlert = true
            }
        }
    }

    private func shortcutItem(title: LocalizedStringKey, name: KeyboardShortcuts.Name) -> some View {
        Group {
            textLabel(title)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .padding(.trailing, 10)
        }
    }

    // MARK: - Helper Views

    private func textLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.primary)
    }

    // MARK: - Helper Methods

    private func handleSliderChange(key: PrefKey, newValue: Int) {
        let originalValue = settingsStore.getInt(key)
        if newValue < originalValue {
            pendingAlertValue = (key: key, value: newValue, origin: originalValue)
            showAlert = true
        } else {
            settingsStore.setInt(key, value: newValue)
        }
    }

    private func handleAlertCancel() {
        if let pending = pendingAlertValue {
            settingsStore.setInt(pending.key, value: pending.origin)
        }
        pendingAlertValue = nil
    }

    private func handleAlertConfirm() {
        guard let pending = pendingAlertValue else { return }
        settingsStore.setInt(pending.key, value: pending.value)
        pendingAlertValue = nil
    }

    private func handleClearAll() {
        PasteDataStore.main.clearAllData()
    }
}

// MARK: - Preview

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        DetailView(category: SettingCategory.general)
            .environmentObject(SettingsStore())
            .frame(width: 400, height: 600)
    }
}
