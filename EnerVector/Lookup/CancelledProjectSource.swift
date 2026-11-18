import Foundation

/// A project withdrawn or cancelled before completion, from a public or licensed data source.
struct CancelledProject: Identifiable, Hashable, Codable {
    let source: String
    let projectNumber: String
    let state: String
    let county: String
    let fuelType: String
    let megawatts: Double
    let queueDate: Date?
    let withdrawnDate: Date?
    let plannedInService: Date?
    let transmissionOwner: String
    let pointOfInterconnection: String
    // Filled in for projects found in news coverage rather than a grid queue.
    var name: String? = nil
    var status: String? = nil
    var reason: String? = nil
    var summary: String? = nil
    var sourceURL: URL? = nil
    var sourceTitle: String? = nil

    var isFromNews: Bool { sourceURL != nil }

    var id: String { ref }
    /// Stable key stored on an imported Site so the same project isn't added twice.
    var ref: String { "\(source):\(projectNumber)" }

    var fuelLabel: String { fuelType.isEmpty ? "Unspecified" : fuelType }

    var location: String {
        let suffixed = ["County", "Parish", "Borough", "City", "city"].contains { county.contains($0) }
        let countyName = county.isEmpty ? nil : suffixed ? county : "\(county) County"
        return [countyName, state.isEmpty ? nil : state].compactMap { $0 }.joined(separator: ", ")
    }

    var title: String {
        if let name, !name.isEmpty { return megawatts > 0 ? "\(name) · \(Units.number(megawatts)) MW" : name }
        let mw = megawatts > 0 ? "\(Units.number(megawatts)) MW " : ""
        return "\(source) \(projectNumber) · \(mw)\(fuelLabel)"
    }
}

/// Where cancelled projects come from. MISO's queue is public; PJM, Enverus or Pearl Street can be added as further sources.
protocol CancelledProjectSource {
    var name: String { get }
    var coverage: String { get }
    func fetch() async throws -> [CancelledProject]
}

/// MISO's public generator interconnection queue (15 Midwest/South states plus Manitoba). No account needed.
struct MISOQueueSource: CancelledProjectSource {
    let name = "MISO"
    let coverage = "MISO interconnection queue · generation & storage projects in 15 states"
    private let url = URL(string: "https://www.misoenergy.org/api/giqueue/getprojects")!

    private struct Row: Decodable {
        let projectNumber: String?
        let applicationStatus: String?
        let state: String?
        let county: String?
        let fuelType: String?
        let summerNetMW: Double?
        let queueDate: String?
        let withdrawnDate: String?
        let inService: String?
        let transmissionOwner: String?
        let poiName: String?
    }

    func fetch() async throws -> [CancelledProject] {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        return rows.compactMap { row in
            guard row.applicationStatus == "Withdrawn", let number = row.projectNumber, !number.isEmpty else { return nil }
            return CancelledProject(source: name, projectNumber: number,
                                    state: row.state ?? "", county: (row.county ?? "").capitalized,
                                    fuelType: row.fuelType ?? "", megawatts: row.summerNetMW ?? 0,
                                    queueDate: Self.date(row.queueDate), withdrawnDate: Self.date(row.withdrawnDate),
                                    plannedInService: Self.date(row.inService),
                                    transmissionOwner: row.transmissionOwner ?? "", pointOfInterconnection: row.poiName ?? "")
        }
    }

    private static let iso = ISO8601DateFormatter()
    private static func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) } }
}

/// Loads projects from every source and keeps a copy on disk so the list opens instantly and works offline.
@MainActor
@Observable
final class CancelledProjectStore {
    static let shared = CancelledProjectStore()

    let sources: [any CancelledProjectSource] = [MISOQueueSource()]
    private(set) var projects: [CancelledProject] = []
    private(set) var updatedAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?

    private struct Cache: Codable { let updatedAt: Date; let projects: [CancelledProject] }
    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("cancelled-projects.json")
    }

    private init() {
        if let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            projects = cache.projects
            updatedAt = cache.updatedAt
        }
    }

    /// Refreshes when there's no data yet or it's more than a day old (or always, when forced).
    func load(force: Bool = false) async {
        if !force, let updatedAt, Date.now.timeIntervalSince(updatedAt) < 86_400 { return }
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            var all: [CancelledProject] = []
            for source in sources { all += try await source.fetch() }
            projects = all.sorted { ($0.withdrawnDate ?? .distantPast) > ($1.withdrawnDate ?? .distantPast) }
            updatedAt = .now
            if let data = try? JSONEncoder().encode(Cache(updatedAt: .now, projects: projects)) {
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            self.error = projects.isEmpty ? "Couldn't load cancelled projects. Check your connection and try again."
                                          : "Couldn't refresh — showing data from \(updatedAt?.formatted(date: .abbreviated, time: .omitted) ?? "earlier")."
        }
    }
}
