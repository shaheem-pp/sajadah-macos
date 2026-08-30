//
//  IqamahScraper.swift
//  Sajadah
//
//  Reads a masjid's own prayer-times page for its posted Iqamah times. There is no API for
//  this — every masjid just publishes a page — so this looks for recognisable prayer-name
//  labels near a time, rather than at any DOM structure (class names, tag nesting). DOM
//  structure is not a stable anchor: a real WordPress/Elementor page inspected while building
//  this has every element's class auto-generated ("elementor-element-0006389") and gets
//  regenerated on every redesign, while the label text itself is exactly what a human visitor
//  reads to find the times, so it is the one thing unlikely to disappear.
//
//  This is deliberately best-effort. It reads plain, server-rendered text; it cannot see a
//  schedule that is an image, a PDF, or rendered by JavaScript after load. Callers are expected
//  to surface a clear "couldn't find prayer times on this page" rather than pretend it always
//  works.
//

import Foundation

// MARK: - Errors

nonisolated enum IqamahScrapeError: LocalizedError, Equatable {
    case badURL
    case offline
    case network(String)
    case badStatus(Int)
    case notText

    var errorDescription: String? {
        switch self {
        case .badURL:
            "That doesn’t look like a valid URL."
        case .offline:
            "No internet connection."
        case .network(let detail):
            detail
        case .badStatus(let code):
            "The page returned an error (HTTP \(code))."
        case .notText:
            "That page isn’t readable as text — it may be a PDF or an image."
        }
    }
}

// MARK: - Labels

/// The prayer names this looks for, and the spellings each is commonly posted under. Order
/// matches the widget's display order.
nonisolated enum IqamahLabel: String, CaseIterable, Sendable {
    case fajr, dhuhr, asr, maghrib, isha, jummah1, jummah2

    var displayName: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        case .jummah1: "1st Jummah"
        case .jummah2: "2nd Jummah"
        }
    }

    /// The five daily prayers are required for a page to count as usable; Jummah is a bonus —
    /// plenty of masjid pages don't list Friday separately at all.
    var isCore: Bool { self != .jummah1 && self != .jummah2 }

    /// Tried in order; every occurrence of every variant is considered, not just the first.
    var variants: [String] {
        switch self {
        case .fajr: ["Fajr", "Fajar"]
        case .dhuhr: ["Dhuhr", "Zuhr", "Duhr"]
        case .asr: ["Asr"]
        case .maghrib: ["Maghrib", "Magrib"]
        case .isha: ["Isha", "Ishaa", "Isya"]
        case .jummah1:
            ["1st Jummah", "1st Jumah", "1st Jumu'ah", "1st Jumuah",
             "First Jummah", "First Jumu'ah", "Jummah 1", "Jumuah 1"]
        case .jummah2:
            ["2nd Jummah", "2nd Jumah", "2nd Jumu'ah", "2nd Jumuah",
             "Second Jummah", "Second Jumu'ah", "Jummah 2", "Jumuah 2"]
        }
    }

    /// Tried for `jummah1` only when no ordinal-qualified variant matched anywhere — most
    /// small masjids post exactly one Friday time with no "1st/2nd" at all.
    static let unqualifiedJummahVariants =
        ["Jummah", "Jumah", "Jumu'ah", "Jumuah", "Friday Prayer", "Friday Salah", "Friday Khutbah"]
}

// MARK: - Result

/// Whether one label was found, and its posted value if so.
nonisolated enum LabelMatch: Sendable, Equatable {
    case found(String)
    case notFound

    var value: String? {
        if case .found(let value) = self { value } else { nil }
    }
}

/// Never all-or-nothing: a page missing one prayer still reports the other six, so a caller can
/// say exactly what went wrong. `times` is the single place "found enough to show" is decided —
/// a property of the type, not a rule every caller has to remember to apply.
nonisolated struct IqamahScrapeResult: Sendable, Equatable {
    var matches: [IqamahLabel: LabelMatch]
    /// The JS framework this page fingerprints as (e.g. "Next.js"), set only when nothing at
    /// all was found — a confirmed diagnosis rather than the generic "might be JavaScript"
    /// guess, for a page whose schedule is injected client-side and never appears in the plain
    /// HTTP response this scraper reads.
    var jsFrameworkHint: String?

    func match(for label: IqamahLabel) -> LabelMatch {
        matches[label] ?? .notFound
    }

    var missingCoreLabels: [IqamahLabel] {
        IqamahLabel.allCases.filter(\.isCore).filter { match(for: $0) == .notFound }
    }

    /// `nil` unless every core (daily) label resolved. Jummah rides along if it was found.
    var times: IqamahTimes? {
        guard missingCoreLabels.isEmpty,
              let fajr = match(for: .fajr).value,
              let dhuhr = match(for: .dhuhr).value,
              let asr = match(for: .asr).value,
              let maghrib = match(for: .maghrib).value,
              let isha = match(for: .isha).value
        else { return nil }

        return IqamahTimes(
            fajr: fajr, dhuhr: dhuhr, asr: asr, maghrib: maghrib, isha: isha,
            jummah1: match(for: .jummah1).value,
            jummah2: match(for: .jummah2).value
        )
    }
}

// MARK: - Scraper

nonisolated struct IqamahScraper: Sendable {
    static let shared = IqamahScraper()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        // Same rule as AladhanAPI: a menubar app must never hang waiting on someone else's site.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func scrape(url: URL) async throws -> IqamahScrapeResult {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .dataNotAllowed {
            throw IqamahScrapeError.offline
        } catch {
            throw IqamahScrapeError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                throw IqamahScrapeError.badStatus(http.statusCode)
            }
            // A missing Content-Type is treated as fine — some small sites misconfigure this
            // even for plain HTML — but an explicit non-text type (a PDF, an image) is not.
            if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
               !contentType.contains("text/") {
                throw IqamahScrapeError.notText
            }
        }

        guard let html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw IqamahScrapeError.notText
        }

        return Self.parse(html)
    }

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Sajadah/\(version) (macOS menubar app; +https://github.com/shaheem-pp/sajadah-macos)"
    }()

    // MARK: Parsing

    /// Pure and static so it can be exercised directly against a saved page — no networking
    /// involved past this point.
    static func parse(_ html: String) -> IqamahScrapeResult {
        let text = plainText(from: html)
        let occurrences = allOccurrences(in: text)

        var matches: [IqamahLabel: LabelMatch] = [:]
        for label in IqamahLabel.allCases {
            matches[label] = value(for: label, occurrences: occurrences, text: text)
                .map(LabelMatch.found) ?? .notFound
        }

        // Most masjid pages post one Friday time with no "1st/2nd" qualifier at all.
        if matches[.jummah1] == .notFound,
           let value = value(forRawVariants: IqamahLabel.unqualifiedJummahVariants, occurrences: occurrences, text: text) {
            matches[.jummah1] = .found(value)
        }

        // Only worth naming when nothing at all was found — a page that yielded some real
        // matches isn't the "can't read this page" case, whatever markup it also happens to use.
        let allMissing = matches.values.allSatisfy { $0 == .notFound }
        let hint = allMissing ? jsFrameworkHint(in: html) : nil

        return IqamahScrapeResult(matches: matches, jsFrameworkHint: hint)
    }

    /// Fingerprints a page as a known JS framework's output, purely from markers a plain HTTP
    /// fetch can already see — no execution, just recognising the shape of an app shell whose
    /// real content is filled in by client-side JavaScript this scraper never runs.
    private static func jsFrameworkHint(in html: String) -> String? {
        let signatures: [(needle: String, framework: String)] = [
            ("_next/static", "Next.js"),
            ("__NEXT_DATA__", "Next.js"),
            ("window.__NUXT__", "Nuxt"),
            ("id=\"__nuxt\"", "Nuxt"),
            ("ng-version=", "Angular"),
            ("data-reactroot", "React"),
        ]
        for (needle, framework) in signatures where html.contains(needle) {
            return framework
        }
        return nil
    }

    /// Plain-text chars searched after a label before giving up on it — generous enough to
    /// cross a little intervening markup-turned-whitespace, short enough that it can't wander
    /// into an unrelated later value.
    private static let lookahead = 60

    private struct Occurrence {
        let label: IqamahLabel
        let range: Range<String.Index>
    }

    private static func allOccurrences(in text: String) -> [Occurrence] {
        IqamahLabel.allCases
            .flatMap { label in
                label.variants.flatMap { ranges(of: $0, in: text) }.map { Occurrence(label: label, range: $0) }
            }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The value for a label: among every occurrence of any of its variants, in document
    /// order, the first one that actually has a time-like token nearby. Document order matters
    /// here, not just "any occurrence" — a real masjid page inspected while building this
    /// repeats old/upcoming times lower down under an "Announcements" section for schedule
    /// changes, and the live schedule always renders first. A page where a decoy like that
    /// happens to render *before* the real schedule would be read wrong; there's no way to
    /// tell the two apart from text alone, so this is an accepted limitation rather than
    /// something to add more heuristics for.
    private static func value(for label: IqamahLabel, occurrences: [Occurrence], text: String) -> String? {
        for occurrence in occurrences where occurrence.label == label {
            if let value = valueAfter(occurrence.range, occurrences: occurrences, text: text) {
                return value
            }
        }
        return nil
    }

    private static func value(forRawVariants variants: [String], occurrences: [Occurrence], text: String) -> String? {
        let matchedRanges = variants.flatMap { ranges(of: $0, in: text) }.sorted { $0.lowerBound < $1.lowerBound }
        for range in matchedRanges {
            if let value = valueAfter(range, occurrences: occurrences, text: text) {
                return value
            }
        }
        return nil
    }

    /// Searches the bounded window right after a label for a time-like token, stopping at
    /// whichever comes first — the lookahead limit, or the next recognised label — so
    /// "Fajr Dhuhr 2:00 PM" (Fajr's own value missing) can't misattribute Dhuhr's time to Fajr.
    private static func valueAfter(
        _ labelRange: Range<String.Index>,
        occurrences: [Occurrence],
        text: String
    ) -> String? {
        let start = labelRange.upperBound
        guard start < text.endIndex else { return nil }

        let distanceLimit = text.index(start, offsetBy: lookahead, limitedBy: text.endIndex) ?? text.endIndex
        let nextLabelStart = occurrences.first { $0.range.lowerBound >= labelRange.upperBound }?.range.lowerBound
        let windowEnd = [distanceLimit, nextLabelStart ?? text.endIndex].min()!

        guard start < windowEnd, let match = text[start..<windowEnd].firstMatch(of: timeToken) else { return nil }
        return String(match.output)
    }

    private static let timeToken = /\d{1,2}:\d{2}\s*[AP]\.?M\.?|\bSunset\b/.ignoresCase()

    private static func ranges(of variant: String, in text: String) -> [Range<String.Index>] {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: variant))\\b"
        guard let regex = try? Regex(pattern).ignoresCase() else { return [] }
        return Array(text.ranges(of: regex))
    }

    /// Strips markup down to visible text so a label and its value line up regardless of what
    /// tags separated them, without ever inspecting the tags themselves — see the file-level
    /// comment on why DOM structure isn't a usable anchor here.
    private static func plainText(from html: String) -> String {
        var text = html
        text.replace(/<(?:script|style)\b[^>]*>[\s\S]*?<\/(?:script|style)>/.ignoresCase(), with: " ")
        text.replace(/<[^>]+>/, with: " ")
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        text.replace(/&#0?39;|&apos;|&rsquo;|&#8217;/, with: "'")
        text.replace(/\s+/, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
