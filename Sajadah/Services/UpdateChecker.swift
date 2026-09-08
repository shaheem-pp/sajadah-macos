//
//  UpdateChecker.swift
//  Sajadah
//

import Foundation

// MARK: - Version

/// A dotted release version, compared numerically.
///
/// String comparison is the tempting shortcut and it is wrong at the first double digit:
/// `"1.10.0" < "1.9.0"` lexically, which would tell everyone on 1.9 that they were ahead of a
/// release they don't have. Components are compared as integers, and a missing component reads
/// as zero so `1.3` and `1.3.0` are the same release.
nonisolated struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let components: [Int]
    let description: String

    /// Parses `v1.3.1`, `1.3.1`, or `1.3.1-beta.2`.
    ///
    /// GitHub's `releases/latest` already excludes prereleases, so the suffix should never
    /// arrive — it is dropped rather than rejected because a tag typed by hand is not worth
    /// failing the whole check over.
    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<dash])
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == parts.count else { return nil }

        components = numbers
        description = text
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    /// This build's own version, from `CFBundleShortVersionString`.
    static var current: AppVersion {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return AppVersion(raw ?? "") ?? AppVersion("0.0.0")!
    }
}

// MARK: - Release

nonisolated struct ReleaseInfo: Codable, Equatable, Sendable {
    /// The tag as published, e.g. `v1.3.1` — kept verbatim so it can be shown and compared
    /// against a dismissal without re-deriving it.
    let tag: String
    let pageURL: URL
    let notes: String?

    var version: AppVersion? { AppVersion(tag) }
}

// MARK: - Errors

nonisolated enum UpdateError: LocalizedError, Equatable {
    case offline
    case network(String)
    case badStatus(Int)
    case rateLimited
    case unreadable

    var errorDescription: String? {
        switch self {
        case .offline:
            "No internet connection."
        case .network(let detail):
            detail
        case .badStatus(let code):
            "GitHub returned an error (HTTP \(code))."
        case .rateLimited:
            "GitHub is rate-limiting this Mac. Try again later."
        case .unreadable:
            "Couldn’t read GitHub’s response."
        }
    }
}

// MARK: - Client

/// Asks GitHub what the newest release is.
///
/// Deliberately not Sparkle. Sparkle's value is installing the update for you, and that is the
/// one thing this app cannot safely do: releases are ad-hoc signed, and replacing the bundle
/// in place needs the delete-then-copy that `cp -R`'s directory *merge* otherwise breaks — a
/// bundle holding files its signature doesn't account for fails validation and won't open. So
/// there is no appcast to host and no EdDSA key to manage; the app notices, says so, and hands
/// over the same command the README documents.
nonisolated struct UpdateChecker: Sendable {
    static let shared = UpdateChecker()

    /// A fork changes this one line. Everything else — the API URL, the release page, the
    /// install command — is derived from it.
    static let repository = "shaheem-pp/sajadah-macos"

    /// The command that actually performs the upgrade, matching the README's. Quitting first
    /// matters because the running copy owns the bundle being replaced, and the `rm -rf`
    /// matters because `cp -R` onto an existing app merges rather than replaces.
    static var updateCommand: String {
        """
        killall Sajadah 2>/dev/null; \
        curl -fsSL https://github.com/\(repository)/releases/latest/download/Sajadah.dmg -o /tmp/Sajadah.dmg && \
        hdiutil attach -quiet /tmp/Sajadah.dmg && \
        rm -rf /Applications/Sajadah.app && \
        cp -R /Volumes/Sajadah/Sajadah.app /Applications/ && \
        hdiutil detach -quiet /Volumes/Sajadah && \
        rm /tmp/Sajadah.dmg && \
        open /Applications/Sajadah.app
        """
    }

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repository)/releases/latest")!
    }

    private static var endpoint: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        // An update check is never the reason to hold a request open waiting for a network.
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// The newest published release. `releases/latest` already skips drafts and prereleases.
    func latest() async throws -> ReleaseInfo {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub answers 403 to an API request with no User-Agent, so this is required rather
        // than polite.
        request.setValue("Sajadah/\(AppVersion.current) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .dataNotAllowed {
            throw UpdateError.offline
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Unauthenticated calls get 60 an hour per IP. A once-a-day check never reaches
            // that on its own, but a shared address behind NAT can, and it is worth naming
            // rather than reporting as a generic failure.
            if http.statusCode == 403 || http.statusCode == 429 { throw UpdateError.rateLimited }
            throw UpdateError.badStatus(http.statusCode)
        }

        guard let wire = try? JSONDecoder().decode(WireRelease.self, from: data),
              let page = URL(string: wire.htmlURL)
        else { throw UpdateError.unreadable }

        let notes = wire.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseInfo(
            tag: wire.tagName,
            pageURL: page,
            notes: (notes?.isEmpty ?? true) ? nil : notes
        )
    }
}

// MARK: - Wire Format

private nonisolated struct WireRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}
