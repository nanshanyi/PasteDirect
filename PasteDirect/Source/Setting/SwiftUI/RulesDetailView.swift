//
//  RulesDetailView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2025/9/25.
//

import SwiftUI

struct RulesDetailView: View {
    let category: SettingCategory
    @StateObject private var manager = IgnoredAppsManager.shared
    @State private var exporting = false
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // 标题和描述
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ignore application")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Do not save content copied from the following applications")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // 应用列表
                VStack(spacing: 0) {
                    ForEach(manager.ignoredApps) { app in
                        AppRowView(
                            app: app,
                            onRemove: { manager.removeApp(app) }
                        )
                        
                        if !manager.ignoredApps.isEmpty {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                    // 添加按钮
                    AddAppButton {
                        manager.addAppFromFileChooser()
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .navigationTitle(category.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AppRowView: View {
    let app: AppInfo
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 应用图标
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "app")
                            .foregroundColor(.secondary)
                    )
            }
            
            // 应用名称
            Text(app.name)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            
            Spacer()
            
            // 删除按钮
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 添加应用按钮
struct AddAppButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 20))
                
                Text("Add application...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
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

// MARK: - 忽略应用管理器
class IgnoredAppsManager: ObservableObject {
    static let shared = IgnoredAppsManager()
    @Published var ignoredApps: [AppInfo] = []
    var ingoredAppItems: [AppItem] = []
    
    init() {
        loadIgnoredApps()
    }
    
    private func loadIgnoredApps() {
        ingoredAppItems = load()
        ignoredApps = ingoredAppItems.compactMap { item in
            let url = URL(fileURLWithPath: item.path)
            return getAppFromURL(url)
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
