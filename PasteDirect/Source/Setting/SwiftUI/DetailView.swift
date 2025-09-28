import KeyboardShortcuts
import SwiftUI

// MARK: - Detail View

struct DetailView: View {
    let category: SettingCategory?

    var body: some View {
        if let category = category {
            if category.type == .common {
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
            } else if category.type == .custom {
                RulesDetailView(category: category)
            }
        } else {
            Text("Select a category from the sidebar")
        }
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
    @State var showAlert = false
    @State private var pendingAlertValue: (key: PrefKey, value: Double, origin: Double)? = nil
    
    var body: some View {
        HStack {
            switch item {
            case let .toggle(title, key):
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settingsStore.getBool(key) },
                    set: {
                        settingsStore.setBool(key, value: $0)
                        if key == .statusDisplay {
                            let app = NSApplication.shared.delegate as? PasteAppDelegate
                            app?.statusItemVisible($0)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            case let .text(title, _):
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Text(settingsStore.totalCountString)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
            case let .slider(_, key, range, step):
                VStack {
                    Slider(
                        value: Binding(
                            get: { settingsStore.getDouble(key) },
                            set: { newValue in
                                // 记录原始值并显示警告
                                let originalValue = settingsStore.getDouble(key)
                                if newValue < originalValue {
                                    pendingAlertValue = (key: key, value: newValue, origin: originalValue)
                                    showAlert = true
                                    return
                                }
                                settingsStore.setDouble(key, value: newValue)
                            }
                        ),
                        in: range,
                        step: step
                    )
                    .padding(10)
                    .controlSize(.small)

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
                    .padding(.leading, 10)
                    .padding(.trailing, -2)
                }
            case let .button(title, action):
                Spacer()
                Button(title, action: action)
            case let .shortCut(title, name):
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                KeyboardShortcuts.Recorder(for: name)
                    .padding(.trailing, 10)
            }
        }
        .frame(alignment: .center)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .alert("", isPresented: $showAlert) {
            Button("Cancel", role: .cancel) {
                // 恢复原始值
                if let pending = pendingAlertValue {
                    settingsStore.setDouble(pending.key, value: pending.origin)
                }
                pendingAlertValue = nil
            }
            Button("Sure") {
                // 应用零值
                guard let pending = pendingAlertValue else { return }
                if let type = HistoryTime(rawValue: pending.value) {
                    PasteDataStore.main.clearData(for: type)
                    PasteUserDefaults.historyTime = type.rawValue
                }
                settingsStore.setDouble(pending.key, value: pending.value)
                pendingAlertValue = nil
            }
        } message: {
            Text("You have items that are older than the new history limit. Do you want to delete these older items and apply the new limit?")
        }
    }
}

// preview
struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        DetailView(category: SettingCategory.general)
            .environmentObject(SettingsStore())
            .frame(width: 400, height: 600)
    }
}

