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

    /// The date printed above the schedule, when the page prints one at all.
    var postedDate: Date?

    /// True when the page dates its schedule and that date isn't today.
    ///
    /// Some masjids serve a fixed page and update it by hand, so what a visitor sees can be
    /// weeks old — londonmosque.ca was serving an August schedule in September. The times that
    /// never move (Fajr, Zuhr) still look right, which is exactly what makes it dangerous: the
    /// ones that track sunset are silently wrong by half an hour. A schedule that says it is
    /// for another day is not evidence about today, so `times` withholds it.
    var isOutOfDate = false

    func match(for label: IqamahLabel) -> LabelMatch {
        matches[label] ?? .notFound
    }

    var missingCoreLabels: [IqamahLabel] {
        IqamahLabel.allCases.filter(\.isCore).filter { match(for: $0) == .notFound }
    }

    /// `nil` unless every core (daily) label resolved, and the page isn't dated for another
    /// day. Jummah rides along if it was found.
    var times: IqamahTimes? {
        guard !isOutOfDate,
              missingCoreLabels.isEmpty,
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
    static func parse(_ html: String, today: Date = .now) -> IqamahScrapeResult {
        let text = plainText(from: html)
        let occurrences = allOccurrences(in: text)

        var rows: [IqamahLabel: Row] = [:]
        for label in IqamahLabel.allCases {
            rows[label] = row(for: label, occurrences: occurrences, text: text)
        }

        // Most masjid pages post one Friday time with no "1st/2nd" qualifier at all.
        if rows[.jummah1] == nil {
            rows[.jummah1] = row(
                forRawVariants: IqamahLabel.unqualifiedJummahVariants,
                occurrences: occurrences,
                text: text
            )
        }

        var tokens: [IqamahLabel: [String]] = [:]
        for (label, row) in rows { tokens[label] = row.times }

        let column = iqamahColumn(in: text, tokens: tokens)

        var matches: [IqamahLabel: LabelMatch] = [:]
        for label in IqamahLabel.allCases {
            let row = tokens[label] ?? []
            // A row shorter than the chosen column falls back to its last time. Jummah is
            // usually posted as a single time even on a page whose daily table has two.
            matches[label] = row.isEmpty ? .notFound : .found(row[min(column, row.count - 1)])
        }

        // Worth naming when none of the five daily prayers came back — that is the "can't read
        // this page" case whatever else was found. Keyed on the core labels rather than on
        // every label, because a page can yield a stray Jummah time from prose and still be an
        // app shell with its real schedule filled in by JavaScript.
        let hint = IqamahScrapeResult(matches: matches).missingCoreLabels.count
            == IqamahLabel.allCases.count(where: \.isCore)
            ? jsFrameworkHint(in: html)
            : nil

        // The date printed just above a daily row. Every row is tried, in document order,
        // rather than only the earliest: londonmosque.ca repeats a "Next: Asr" widget above
        // its dated table, so the first row found sits before the heading and the date that
        // labels the real schedule is further down.
        let posted = IqamahLabel.allCases
            .filter(\.isCore)
            .compactMap { rows[$0]?.at.lowerBound }
            .sorted()
            .lazy
            .compactMap { postedDate(before: $0, in: text) }
            .first

        return IqamahScrapeResult(
            matches: matches,
            jsFrameworkHint: hint,
            postedDate: posted,
            isOutOfDate: posted.map { !Calendar.current.isDate($0, inSameDayAs: today) } ?? false
        )
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

    // MARK: Choosing a column

    /// Column headings that mark the two kinds of time a masjid posts side by side.
    private static let adhanHeadings =
        ["Adhan", "Adhaan", "Athan", "Athaan", "Azan", "Azaan", "Beginning", "Begins"]
    private static let iqamahHeadings =
        ["Iqama", "Iqamah", "Iqaama", "Iqaamah", "Jamaat", "Jamaah", "Congregation"]

    /// How many of a row's times to skip to land on the Iqamah one.
    ///
    /// Plenty of masjids post one table with both columns — Adhan on the left, Iqamah on the
    /// right — and taking the first time in each row then reads back the call to prayer, which
    /// is the calculated time Sajadah already knows and precisely not what the page was
    /// consulted for. Masjid al-Farooq flattens to:
    ///
    ///     Salah Adhan Iqama Fajr 5:21 am 6:00 am Sunrise 6:44 am Dhuhr 1:18 pm 1:40 pm …
    ///
    /// Two conditions, because guessing wrong here is worse than not guessing. Both headings
    /// have to appear, with Adhan's first — that ordering is what says which column is which,
    /// and a page listing Iqamah first is left alone. And most daily rows have to actually
    /// carry a second time, so that a single-column Iqamah page which merely *mentions* Adhan
    /// in prose isn't read a column to the right into the next row's value.
    private static func iqamahColumn(in text: String, tokens: [IqamahLabel: [String]]) -> Int {
        guard let adhanAt = earliestIndex(of: adhanHeadings, in: text),
              let iqamahAt = earliestIndex(of: iqamahHeadings, in: text),
              adhanAt < iqamahAt
        else { return 0 }

        let core = IqamahLabel.allCases.filter(\.isCore)
        let paired = core.count { (tokens[$0]?.count ?? 0) >= 2 }
        return paired * 2 >= core.count ? 1 : 0
    }

    private static func earliestIndex(of variants: [String], in text: String) -> String.Index? {
        variants.flatMap { ranges(of: $0, in: text) }.map(\.lowerBound).min()
    }

    // MARK: Dating the schedule

    /// How far back from the first prayer row to look for the date heading above it.
    ///
    /// Deliberately short. Pages are full of unrelated dates — mwcanada announces a time change
    /// for "Sunday, September 6" and an Eid prayer in May — and a page-wide search would read
    /// one of those as the schedule's own date and reject a page that is perfectly current.
    /// The date that labels a table sits directly above it: "Salah Times September 2, 2026
    /// Salah Adhan Iqama Fajr …".
    private static let dateLookbehind = 120

    /// The date this schedule is printed for, if it prints one.
    ///
    /// Month names only. Numeric forms like 02/09/2026 are ambiguous between British and
    /// American ordering, and guessing wrong would reject a current page or accept a stale one.
    private static func postedDate(before scheduleStart: String.Index, in text: String) -> Date? {
        let from = text.index(scheduleStart, offsetBy: -dateLookbehind, limitedBy: text.startIndex)
            ?? text.startIndex
        let window = String(text[from..<scheduleStart])

        // "September 2, 2026" / "Sep 2 2026", and the "2 September 2026" ordering.
        let monthFirst = /([A-Z][a-z]{2,8})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})/
        let dayFirst = /(\d{1,2})(?:st|nd|rd|th)?\s+([A-Z][a-z]{2,8})\.?,?\s+(\d{4})/

        // Last match in the window: the nearest one to the schedule it labels.
        if let match = window.matches(of: monthFirst).last,
           let month = monthNumber(String(match.1)),
           let day = Int(match.2), let year = Int(match.3) {
            return date(year: year, month: month, day: day)
        }
        if let match = window.matches(of: dayFirst).last,
           let month = monthNumber(String(match.2)),
           let day = Int(match.1), let year = Int(match.3) {
            return date(year: year, month: month, day: day)
        }
        return nil
    }

    private static func monthNumber(_ name: String) -> Int? {
        let months = ["january", "february", "march", "april", "may", "june",
                      "july", "august", "september", "october", "november", "december"]
        let needle = name.lowercased()
        // Prefix match, so "Sept"/"Sep" and the full name all resolve. At least three letters,
        // which is what keeps "May" working without letting "Ma" match it.
        guard needle.count >= 3 else { return nil }
        return months.firstIndex { $0.hasPrefix(needle) || needle.hasPrefix($0) }.map { $0 + 1 }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Plain-text chars searched after a label before giving up on it — generous enough to
    /// cross a little intervening markup-turned-whitespace, short enough that it can't wander
    /// into an unrelated later value.
    private static let lookahead = 60

    /// The window allowed to the unqualified Jummah fallback — the one match that can land in
    /// a sentence rather than a table.
    ///
    /// A schedule puts the time right after its label: "Jummah 1:30 pm". Prose does not.
    /// Masjid al-Farooq posts no Jummah table at all, and the sentence "in addition to above
    /// Jumu'ah timings, there will be a 4th Jumu'ah at 3:30 pm" put a time forty-odd characters
    /// after the word — which was read as that masjid's only Friday prayer. Short enough to
    /// cross a heading like "Jumu'ah Khutbah", too short to cross a sentence.
    private static let proseLookahead = 24

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
    /// The times for a label, along with where in the page they were read from — the position
    /// is what lets `postedDate(before:in:)` find the date heading that labels the schedule.
    private static func row(for label: IqamahLabel, occurrences: [Occurrence], text: String) -> Row? {
        for occurrence in occurrences where occurrence.label == label {
            let found = valuesAfter(occurrence.range, occurrences: occurrences, text: text)
            if !found.isEmpty { return Row(at: occurrence.range, times: found) }
        }
        return nil
    }

    private struct Row {
        let at: Range<String.Index>
        let times: [String]
    }

    private static func row(forRawVariants variants: [String], occurrences: [Occurrence], text: String) -> Row? {
        let matchedRanges = variants.flatMap { ranges(of: $0, in: text) }.sorted { $0.lowerBound < $1.lowerBound }
        for range in matchedRanges where !isOrdinalQualified(range, in: text) {
            let found = valuesAfter(range, occurrences: occurrences, text: text, within: proseLookahead)
            if !found.isEmpty { return Row(at: range, times: found) }
        }
        return nil
    }

    /// Whether a bare "Jumu'ah" is actually an ordinal-numbered one.
    ///
    /// The unqualified spellings are a fallback for masjids that hold a single Friday prayer
    /// and write it with no number at all. Only "1st"/"2nd" have qualified variants of their
    /// own, so without this check a third or fourth slot falls through to the fallback and gets
    /// reported as the first. Masjid al-Farooq posts no Jummah table in its HTML at all, and
    /// the sentence "there will be a 4th Jumu'ah at 3:30 pm" was being read as the 1st.
    private static func isOrdinalQualified(_ range: Range<String.Index>, in text: String) -> Bool {
        let lookbehind = 12
        let start = text.index(range.lowerBound, offsetBy: -lookbehind, limitedBy: text.startIndex)
            ?? text.startIndex
        let preceding = text[start..<range.lowerBound]
        return preceding.firstMatch(
            of: /(?:\d{1,2}(?:st|nd|rd|th)|first|second|third|fourth|fifth)\s*$/.ignoresCase()
        ) != nil
    }

    /// Searches the bounded window right after a label for a time-like token, stopping at
    /// whichever comes first — the lookahead limit, or the next recognised label — so
    /// "Fajr Dhuhr 2:00 PM" (Fajr's own value missing) can't misattribute Dhuhr's time to Fajr.
    private static func valuesAfter(
        _ labelRange: Range<String.Index>,
        occurrences: [Occurrence],
        text: String,
        within limit: Int = lookahead
    ) -> [String] {
        let start = labelRange.upperBound
        guard start < text.endIndex else { return [] }

        let distanceLimit = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        let nextLabelStart = occurrences.first { $0.range.lowerBound >= labelRange.upperBound }?.range.lowerBound
        let windowEnd = [distanceLimit, nextLabelStart ?? text.endIndex].min()!

        guard start < windowEnd else { return [] }
        return text[start..<windowEnd].matches(of: timeToken).map { String($0.output) }
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
