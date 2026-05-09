//
//  UpdateChecker.swift
//  PasteDirect
//
//  Created by 南山忆 on 2026/05/09.
//

import Foundation

struct AppRelease: Sendable {
    let version: String
    let tagName: String
    let notes: String
    let htmlURL: URL
    let downloadURL: URL?
}

enum UpdateCheckResult: Sendable {
    case upToDate
    case newer(AppRelease)
}

enum UpdateCheckError: Error {
    case invalidResponse
    case network(Error)
    case decoding(Error)
}

enum UpdateChecker {
    static let releaseAPI = URL(string: "https://api.github.com/repos/nanshanyi/PasteDirect/releases/latest")!

    static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static func fetchLatest() async throws -> AppRelease {
        var request = URLRequest(url: releaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.network(error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.invalidResponse
        }

        do {
            let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let tag = payload.tagName
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let dmg = payload.assets.first { $0.name.hasSuffix(".dmg") }?.browserDownloadURL
            let zip = payload.assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadURL
            return AppRelease(
                version: version,
                tagName: tag,
                notes: payload.body ?? "",
                htmlURL: payload.htmlURL,
                downloadURL: dmg ?? zip
            )
        } catch {
            throw UpdateCheckError.decoding(error)
        }
    }

    static func check() async throws -> UpdateCheckResult {
        let latest = try await fetchLatest()
        if compare(latest.version, currentVersion()) == .orderedDescending {
            return .newer(latest)
        }
        return .upToDate
    }

    /// 语义化版本比较，忽略非数字后缀（如 -beta）
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = numericComponents(lhs)
        let r = numericComponents(rhs)
        let count = max(l.count, r.count)
        for i in 0..<count {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericComponents(_ version: String) -> [Int] {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        return core.split(separator: ".").map { part -> Int in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}
