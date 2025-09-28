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
    @State private var selectedApp: String? = nil
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
                            isSelected: selectedApp == app.bundleID,
                            onTap: {
                                if selectedApp == app.bundleID {
                                    selectedApp = nil
                                } else {
                                    selectedApp = app.bundleID
                                }
                            }
                        )
                        
                        if !manager.ignoredApps.isEmpty {
                            if app == manager.ignoredApps.last {
                                Divider()
                            } else {
                                Divider()
                                    .padding(.leading, 50)
                            }
                        }
                    }
                    // 添加和删除按钮
                    HStack(spacing: 1) {
                        AddAppButton {
                            manager.addAppFromFileChooser()
                        }
                        .padding(.leading, 12)
                        Divider()
                            .padding(.vertical, 8)
                        DeleteSelectedButton(
                            action: {
                                // 删除选中的应用
                                if let selectedAppID = selectedApp,
                                   let appToRemove = manager.ignoredApps.first(where: { $0.bundleID == selectedAppID }) {
                                    manager.removeApp(appToRemove)
                                    selectedApp = nil
                                }
                            },
                            hasSelection: selectedApp != nil
                        )
                        Spacer()
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

// preview
struct RulesDetailView_Previews: PreviewProvider {
    static var previews: some View {
        RulesDetailView(category: SettingCategory.ignore)
            .frame(width: 400, height: 500)
            .padding()
    }
}

struct AppRowView: View {
    let app: AppInfo
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - 添加应用按钮
struct AddAppButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .foregroundColor(.secondary)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 删除选中按钮
struct DeleteSelectedButton: View {
    let action: () -> Void
    let hasSelection: Bool
    
    var body: some View {
        Button(action: hasSelection ? action : {}) {
            Image(systemName: "minus")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
    }
}
