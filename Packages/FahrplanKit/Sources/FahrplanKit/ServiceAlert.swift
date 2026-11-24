// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Störungs- oder Baustellenhinweis (VVO-Streckenänderungen bzw. Echtzeit-Meldungen von Transitous).
public struct ServiceAlert: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Ausführlicher Text (ohne HTML).
    public var text: String?
    public var validFrom: Date?
    public var validUntil: Date?
    public var url: URL?
    /// Einzelne Gültigkeitszeiträume (z. B. nur bestimmte Tage); `nil` = von `validFrom` bis `validUntil`.
    public var periods: [DateInterval]?

    public init(id: String, title: String, text: String? = nil, validFrom: Date? = nil, validUntil: Date? = nil,
                url: URL? = nil, periods: [DateInterval]? = nil) {
        self.periods = periods
        self.id = id
        self.title = title
        self.text = text
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.url = url
    }

    /// Gilt die Meldung zum Zeitpunkt `date`? (Ohne Zeitraum: immer.)
    public func isValid(at date: Date) -> Bool {
        if let periods, !periods.isEmpty { return periods.contains { $0.contains(date) } }
        if let validFrom, date < validFrom { return false }
        if let validUntil, date > validUntil { return false }
        return true
    }

    /// Einfache Umwandlung von HTML in lesbaren Text (Zeilenumbrüche bleiben erhalten).
    static func plainText(fromHTML html: String) -> String {
        var s = html
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</h1>", "</h2>", "</h3>", "</li>"] {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<li>", with: "• ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&#39;": "'",
                        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü",
                        "&szlig;": "ß", "&bdquo;": "„", "&ldquo;": "“", "&ndash;": "–"]
        for (entity, value) in entities { s = s.replacingOccurrences(of: entity, with: value) }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Mehrere Leerzeilen zusammenfassen.
        var result: [String] = []
        for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) { result.append(line) }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - VVO-Streckenänderungen (`/rc`)

struct RouteChangesResponse: Decodable, StatusCarrying {
    let status: VVOStatus
    let changes: [Change]

    enum CodingKeys: String, CodingKey {
        case status = "Status"
        case changes = "Changes"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(VVOStatus.self, forKey: .status)
        changes = try c.decodeIfPresent([Change].self, forKey: .changes) ?? []
    }

    struct Change: Decodable {
        let id: String
        let title: String?
        let description: String?
        let validityPeriods: [Period]?

        struct Period: Decodable {
            let begin: String?
            let end: String?
            enum CodingKeys: String, CodingKey { case begin = "Begin", end = "End" }
        }

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case title = "Title"
            case description = "Description"
            case validityPeriods = "ValidityPeriods"
        }
    }

    /// Je Meldungs-ID die Meldung; Meldungen mit mehreren Zeiträumen gelten vom frühesten Beginn bis zum spätesten Ende.
    var alerts: [String: ServiceAlert] {
        var result: [String: ServiceAlert] = [:]
        for change in changes {
            let begins = (change.validityPeriods ?? []).compactMap { $0.begin.flatMap(VVODecoding.parseDate) }
            let ends = (change.validityPeriods ?? []).compactMap { $0.end.flatMap(VVODecoding.parseDate) }
            var text = change.description.map(ServiceAlert.plainText(fromHTML:))
            let title = change.title?.trimmingCharacters(in: .whitespaces) ?? "Hinweis"
            // Der Text beginnt oft mit der Überschrift – nicht doppelt zeigen.
            if let t = text, t.hasPrefix(title) {
                text = String(t.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let periods: [DateInterval] = (change.validityPeriods ?? []).compactMap { period in
                guard let begin = period.begin.flatMap(VVODecoding.parseDate),
                      let end = period.end.flatMap(VVODecoding.parseDate), end >= begin else { return nil }
                return DateInterval(start: begin, end: end)
            }
            result[change.id] = ServiceAlert(id: "vvo:\(change.id)", title: title,
                                             text: text?.isEmpty == true ? nil : text,
                                             validFrom: begins.min(), validUntil: ends.max(),
                                             periods: periods.isEmpty ? nil : periods)
        }
        return result
    }
}

/// Streckenänderungen werden einmal geladen und 15 Minuten zwischengespeichert.
actor VVORouteChangeCache {
    static let shared = VVORouteChangeCache()
    private var loaded: (Date, [String: ServiceAlert])?
    private var running: Task<[String: ServiceAlert], Never>?

    func alerts(using load: @escaping @Sendable () async throws -> [String: ServiceAlert]) async -> [String: ServiceAlert] {
        if let (date, value) = loaded, date.timeIntervalSinceNow > -15 * 60 { return value }
        if let running { return await running.value }
        let task = Task<[String: ServiceAlert], Never> { (try? await load()) ?? [:] }
        running = task
        let value = await task.value
        running = nil
        if !value.isEmpty { loaded = (.now, value) }
        return value
    }
}

extension ServiceAlert {
    /// Platzhalter mit der VVO-Meldungs-ID; wird nach dem Laden der Streckenänderungen ersetzt.
    static func vvoPlaceholder(_ id: String) -> ServiceAlert { ServiceAlert(id: "vvo:\(id)", title: "") }
}

extension [ServiceAlert] {
    /// VVO-Platzhalter durch die echten Meldungen ersetzen; unbekannte und zum Zeitpunkt ungültige fallen weg.
    func resolvingVVO(_ known: [String: ServiceAlert], at date: Date) -> [ServiceAlert] {
        compactMap { alert in
            guard alert.title.isEmpty, alert.id.hasPrefix("vvo:") else { return alert }
            guard let full = known[String(alert.id.dropFirst(4))], full.isValid(at: date) else { return nil }
            return full
        }
    }
}
