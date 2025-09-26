import SwiftUI
import KeyboardShortcuts

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
                        // 添加分割线（除了最后一项）
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
                
            case let .text(title, value):
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
            case .slider(_, let key, let range, let step):
                VStack {
                    Slider(
                        value: Binding(
                            get: { settingsStore.getDouble(key)},
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
                    HStack {
                        Text("Day")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Week")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("Month")
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("Forever")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    
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

// MARK: - Helper View Extension
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
