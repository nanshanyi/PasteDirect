//
//  AboutView.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/04/29.
//

import SwiftUI

struct AboutView: View {
    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "\(version)"
    }()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            appIconView

            VStack(spacing: 6) {
                Text("PasteDirect")
                    .font(.system(size: 22, weight: .semibold))

                Text("Version \(appVersion)", comment: "App version display")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Text("A lightweight clipboard manager for macOS")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/nanshanyi/PasteDirect")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("GitHub")
                    }
                    .font(.system(size: 13))
                }

                Text("© 2022-2026 南山忆")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }

    private var appIconView: some View {
        Group {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, height: 96)
            }
        }
    }
}
