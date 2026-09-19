//
//  AladhanAPI.swift
//  Sajadah
//

import CoreLocation
import Foundation

// MARK: - Errors

nonisolated enum AladhanError: LocalizedError, Equatable {
    case badURL
    case offline
    case network(String)
    case badStatus(Int)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            "Couldn’t build the request URL."
        case .offline:
            "No internet connection."
        case .network(let detail):
            detail
        case .badStatus(let code):
            "The prayer times service returned an error (HTTP \(code))."
        case .decoding(let detail):
            "Couldn’t read the prayer times service response. \(detail)"
        }
    }
}

// MARK: - Calculation Methods

/// The subset of Aladhan's `/v1/methods` worth putting in a picker. IDs are the API's, except
/// `automaticID`, which is ours: it stands for leaving `method` off the request altogether, so
/// the API picks the authority nearest the coordinates and says which in `meta.method`.
nonisolated struct CalculationMethod: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String

    /// Not an Aladhan ID — the API's start at 1.
    static let automaticID = 0

    static let all: [CalculationMethod] = [
        CalculationMethod(id: automaticID, name: "Automatic (by location)"),
        CalculationMethod(id: 3, name: "Muslim World League"),
        CalculationMethod(id: 2, name: "Islamic Society of North America (ISNA)"),
        CalculationMethod(id: 4, name: "Umm al-Qura University, Makkah"),
        CalculationMethod(id: 5, name: "Egyptian General Authority of Survey"),
        CalculationMethod(id: 1, name: "University of Islamic Sciences, Karachi"),
        CalculationMethod(id: 8, name: "Gulf Region"),
        CalculationMethod(id: 9, name: "Kuwait"),
        CalculationMethod(id: 10, name: "Qatar"),
        CalculationMethod(id: 11, name: "Singapore (MUIS)"),
        CalculationMethod(id: 12, name: "France (UOIF)"),
        CalculationMethod(id: 13, name: "Turkey (Diyanet)"),
        CalculationMethod(id: 15, name: "Moonsighting Committee Worldwide"),
        CalculationMethod(id: 16, name: "Dubai"),
        CalculationMethod(id: 17, name: "Malaysia (JAKIM)"),
        CalculationMethod(id: 20, name: "Indonesia (Kemenag)"),
        CalculationMethod(id: 21, name: "Morocco"),
        CalculationMethod(id: 23, name: "Jordan"),
    ]

    /// Automatic rather than any one authority: a fixed default is right for one region and
    /// quietly 15–20 minutes off at Fajr for the rest.
    static let defaultID = automaticID

    static func name(for id: Int) -> String {
        all.first { $0.id == id }?.name ?? "Method \(id)"
    }
}

/// One month of timings plus the method they were computed with.
nonisolated struct MonthlyCalendar: Sendable {
    let days: [DayTimings]
    let resolvedMethod: ResolvedMethod?
}

/// Asr shadow-length convention. The API calls this `school`.
nonisolated enum AsrSchool: Int, CaseIterable, Identifiable, Sendable {
    case standard = 0
    case hanafi = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Standard (Shafi‘i, Maliki, Hanbali)"
        case .hanafi: "Hanafi"
        }
    }
}

// MARK: - Client

nonisolated struct AladhanAPI: Sendable {
    static let shared = AladhanAPI()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        // A menubar app must never hang waiting on the network; fall back to cache instead.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// One request covers a whole calendar month, which is what keeps this app to roughly
    /// one network call a month per location.
    func monthlyCalendar(
        year: Int,
        month: Int,
        coordinate: CLLocationCoordinate2D,
        method: Int,
        school: Int
    ) async throws -> MonthlyCalendar {
        guard var components = URLComponents(string: "https://api.aladhan.com/v1/calendar/\(year)/\(month)") else {
            throw AladhanError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "school", value: String(school)),
            // Without this the API returns "04:31 (EDT)", which would need hand-rolled
            // timezone maths. With it, every timing is a fully-offset ISO 8601 instant.
            URLQueryItem(name: "iso8601", value: "true"),
            // The API's default today, pinned rather than inherited: Umm al-Qura adjusted to
            // Saudi Arabia's sighting announcements. The offline fallback in `HijriDate` is
            // chosen to agree with this one, and a silent change of default would break that.
            URLQueryItem(name: "calendarMethod", value: "HJCoSA"),
        ]
        // Left off for Automatic: with no `method` the API chooses by the coordinates.
        if method != CalculationMethod.automaticID {
            components.queryItems?.append(URLQueryItem(name: "method", value: String(method)))
        }
        guard let url = components.url else { throw AladhanError.badURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .dataNotAllowed {
            throw AladhanError.offline
        } catch {
            throw AladhanError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AladhanError.badStatus(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(CalendarResponse.self, from: data)
            // The same for every day of the month; the first will do.
            let resolved = payload.data.first.map {
                ResolvedMethod(id: $0.meta.method.id, name: $0.meta.method.name)
            }
            return MonthlyCalendar(
                days: payload.data.compactMap(DayTimings.init(day:)),
                resolvedMethod: resolved
            )
        } catch {
            throw AladhanError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Wire Format

/// Mirrors the API response exactly, so the on-disk cache format (`DayTimings`) can change
/// without being dragged around by the shape of somebody else's JSON.
private nonisolated struct CalendarResponse: Decodable {
    let code: Int
    let data: [Day]

    struct Day: Decodable {
        let timings: Timings
        let date: DateInfo
        let meta: Meta
    }

    struct Timings: Decodable {
        // The API also returns Imsak, Sunset, Midnight, Firstthird and Lastthird; we ignore them.
        let fajr: Date
        let sunrise: Date
        let dhuhr: Date
        let asr: Date
        let maghrib: Date
        let isha: Date

        enum CodingKeys: String, CodingKey {
            case fajr = "Fajr"
            case sunrise = "Sunrise"
            case dhuhr = "Dhuhr"
            case asr = "Asr"
            case maghrib = "Maghrib"
            case isha = "Isha"
        }
    }

    struct DateInfo: Decodable {
        let gregorian: Gregorian
        let hijri: Hijri

        struct Gregorian: Decodable {
            /// `DD-MM-YYYY` — deliberately typed as `String`, since decoding it as a `Date`
            /// would collide with the decoder's ISO 8601 strategy.
            let date: String
        }

        struct Hijri: Decodable {
            /// Strings on the wire, unlike `month.number` — the API is not consistent here.
            let day: String
            let year: String
            let month: Month

            struct Month: Decodable {
                let number: Int
                let en: String
            }
        }
    }

    struct Meta: Decodable {
        let timezone: String
        let method: Method

        /// Also carries `params` and `location`; neither is needed.
        struct Method: Decodable {
            let id: Int
            let name: String
        }
    }
}

private extension DayTimings {
    /// Explicitly `nonisolated` so the mapping can run off the main actor: this file's default
    /// isolation is `MainActor`, and an extension does not inherit the type's `nonisolated`.
    nonisolated init?(day: CalendarResponse.Day) {
        // "14-08-2026" -> "2026-08-14"
        let parts = day.date.gregorian.date.split(separator: "-")
        guard parts.count == 3 else { return nil }

        let hijri = day.date.hijri
        self.init(
            dayKey: "\(parts[2])-\(parts[1])-\(parts[0])",
            hijri: "\(hijri.day) \(hijri.month.en) \(hijri.year) AH",
            hijriDate: Int(hijri.day).flatMap { day in
                Int(hijri.year).map { HijriDate(day: day, month: hijri.month.number, year: $0) }
            },
            timeZoneIdentifier: day.meta.timezone,
            fajr: day.timings.fajr,
            sunrise: day.timings.sunrise,
            dhuhr: day.timings.dhuhr,
            asr: day.timings.asr,
            maghrib: day.timings.maghrib,
            isha: day.timings.isha
        )
    }
}
