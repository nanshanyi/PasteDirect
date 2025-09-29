import KeyboardShortcuts
import SwiftUI

// MARK: - Data Models

enum SettingContentType {
    case common
    case custom
}

struct SettingCategory: Identifiable, Hashable {
    let id = UUID()
    let type: SettingContentType
    let title: LocalizedStringKey
    let icon: String
    let sections: [SettingSection]

    static let general = SettingCategory(
        type: .common,
        title: "General",
        icon: "gearshape",
        sections: [
            SettingSection(title: "", items: [
                .toggle("Launch at Login", key: .onStart),
                .toggle("Displayed on the status bar", key: .statusDisplay),
            ]),
            SettingSection(title: "Paste settings", items: [
                .toggle("Paste to the currently active application", key: .pasteDirect),
                .toggle("Always paste as plain text", key: .pasteOnlyText),
            ]),
            SettingSection(title: "Paste history", items: [
                .slider("", key: .historyTime, range: 0 ... 100, step: 33),
                .text("Total number of items", value: PasteDataStore.main.totalCount.description),
                .button("Clear all clipboard history", action: {
                    PasteDataStore.main.clearAllData()
                }),
            ]),
        ]
    )

    static let shortcuts = SettingCategory(
        type: .common,
        title: "Shortcuts",
        icon: "command",
        sections: [
            SettingSection(title: "", items: [
                .shortCut("Launch PasteDirect", key: .pasteKey),
            ]),
        ]
    )
    static let ignore = SettingCategory(
        type: .custom,
        title: "Rules",
        icon: "list.bullet",
        sections: []
    )

    static let allCategories = [general, shortcuts, ignore]

    static func == (lhs: SettingCategory, rhs: SettingCategory) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SettingSection: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let items: [SettingItem]
}

enum SettingItem: Identifiable {
    case toggle(LocalizedStringKey, key: PrefKey)
    case text(LocalizedStringKey, value: String)
    case slider(LocalizedStringKey, key: PrefKey, range: ClosedRange<Double>, step: Double)
    case button(LocalizedStringKey, action: () -> Void)
    case shortCut(LocalizedStringKey, key: KeyboardShortcuts.Name)
    var id: String {
        switch self {
        case .toggle(let title, let key):
            return "toggle_\(key)_\(title)"
        case .text(let title, _):
            return "text_\(title)"
        case .slider(let title, let key, _, _):
            return "slider_\(key)_\(title)"
        case .button(let title, _):
            return "button_\(title)"
        case .shortCut(let title, let key):
            return "shortcut_\(key)_\(title)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .toggle(let title, _), .text(let title, _), .slider(let title, _, _, _), .button(let title, _), .shortCut(let title, _):
            return title
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
