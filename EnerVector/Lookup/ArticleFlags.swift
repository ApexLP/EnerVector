import Foundation

/// Articles the user has flagged as unreliable, keyed by source URL and kept on this device.
@MainActor
@Observable
final class ArticleFlags {
    static let shared = ArticleFlags()

    enum Reason: String, CaseIterable, Identifiable {
        case notCancelled = "Not actually cancelled"
        case wrongDetails = "Wrong details"
        case duplicate = "Duplicate"
        case brokenLink = "Broken link"
        case other = "Other"
        var id: String { rawValue }
    }

    private static let key = "flaggedArticles"
    private(set) var flags: [String: String] = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]

    func reason(for url: URL?) -> Reason? {
        guard let url, let raw = flags[url.absoluteString] else { return nil }
        return Reason(rawValue: raw) ?? .other
    }

    func flag(_ url: URL, _ reason: Reason) { flags[url.absoluteString] = reason.rawValue; save() }
    func unflag(_ url: URL) { flags[url.absoluteString] = nil; save() }
    private func save() { UserDefaults.standard.set(flags, forKey: Self.key) }
}

/// How far back the news search looks.
enum NewsWindow: Int, CaseIterable, Identifiable {
    case months6 = 6, months12 = 12, months36 = 36
    var id: Int { rawValue }
    var label: String { self == .months36 ? "Last 3 years" : "Last \(rawValue) months" }
    var since: Date { Calendar.current.date(byAdding: .month, value: -rawValue, to: .now) ?? .now }
}
