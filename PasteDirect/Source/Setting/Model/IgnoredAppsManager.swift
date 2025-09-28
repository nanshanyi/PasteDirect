//
//  File.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/28.
//

import Cocoa

class IgnoredAppsManager: ObservableObject {
    static let shared = IgnoredAppsManager()
    @Published var ignoredApps: [AppInfo] = []
    var ingoredAppItems: [AppItem] = []
    var defaultApps:[AppItem] = [
        AppItem(bundleID: "com.apple.Passwords", path: "/Applications/PasteDirect.app"),
        AppItem(bundleID: "com.apple.keychainaccess", path: "/System/Library/CoreServices/Applications/Keychain Access.app")
    ]
    
    init() {
        loadIgnoredApps()
    }
    
    private func loadIgnoredApps() {
        if PasteUserDefaults.appAlreadyLaunched {
            ingoredAppItems = load()
            ignoredApps = ingoredAppItems
                .lazy.map{URL.init(fileURLWithPath: $0.path)}
                .compactMap(getAppFromURL)
        } else {
            ingoredAppItems = defaultApps
            ignoredApps = ingoredAppItems
                .lazy.map{URL.init(fileURLWithPath: $0.path)}
                .compactMap(getAppFromURL)
        }
    }
    
    private var defaultStorageURL: URL {
        let targetURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return targetURL.appendingPathComponent("appItems.json")
    }
    
    private func load() -> [AppItem] {
        let targetURL = defaultStorageURL
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return []
        }
        guard let data = try? Data(contentsOf: targetURL),
              let appItems = try? JSONDecoder().decode([AppItem].self, from: data) else { return [] }
        return appItems
    }
    
    private func getAppFromURL(_ url: URL) -> AppInfo? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              let displayName = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                bundle.infoDictionary?["CFBundleName"] as? String else {
            return nil
        }
        
        // 检查是否已存在
        if ignoredApps.contains(where: { $0.bundleID == bundleID }) {
            return nil
        }
        return AppInfo( name: displayName, bundleID: bundleID, path: url.path)
    }
    
    private func addAppInfoFromURL(_ url: URL) {
        guard let appInfo = getAppFromURL(url) else { return }
        ignoredApps.append(appInfo)
        ingoredAppItems.append(AppItem(bundleID: appInfo.bundleID, path: appInfo.path))
        save()
        PasteUserDefaults.ignoreList = ingoredAppItems.map { $0.bundleID }
    }
    
    private func save() {
        let targetURL = defaultStorageURL
        let data = try? JSONEncoder().encode(ingoredAppItems)
        try? data?.write(to: targetURL)
    }
    
    func removeApp(_ app: AppInfo) {
        ignoredApps.removeAll { $0.bundleID == app.bundleID }
        ingoredAppItems.removeAll { $0.bundleID == app.bundleID }
        save()
        PasteUserDefaults.ignoreList = ingoredAppItems.map { $0.bundleID }
    }
    
    func addAppFromFileChooser() {
        let panel = NSOpenPanel()
        panel.title = "选择应用程序"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin {[weak self] response in
            if response == .OK, let url = panel.url {
                self?.addAppInfoFromURL(url)
            }
        }
    }
    
    func frontmostApplication() -> AppInfo? {
        let app = NSWorkspace.shared.frontmostApplication
        if ignoredApps.contains(where: {
            $0.bundleID == app?.bundleIdentifier
        }){ return nil }
        guard let url = app?.bundleURL else {
            return nil
        }
        return getAppFromURL(url)
    }
}

struct AppInfo: Identifiable, Hashable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let path: String
    var icon: NSImage? {
        NSWorkspace.shared.icon(forFile: path)
    }
}

struct AppItem: Codable, Hashable {
    let bundleID: String
    let path: String
}
