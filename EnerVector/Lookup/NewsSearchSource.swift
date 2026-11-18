import Foundation

/// Finds cancelled data center projects in news coverage. The app calls a Xano endpoint, which holds the
/// Claude API key and runs a Claude web search; see docs/xano-cancelled-search.md for the endpoint setup.
struct NewsSearchSource {
    let endpoint: URL
    let appKey: String

    static var configured: NewsSearchSource? {
        let defaults = UserDefaults.standard
        guard var raw = defaults.string(forKey: AppSettings.newsSearchURL)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        guard let url = URL(string: raw), url.scheme == "https", url.host() != nil else { return nil }
        let key = (defaults.string(forKey: AppSettings.newsSearchKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return NewsSearchSource(endpoint: url, appKey: key)
    }

    enum SearchError: LocalizedError {
        case server(Int), incomplete, refused, noResult
        var errorDescription: String? {
            switch self {
            case .server(let code): "The search service returned an error (\(code)). Check the endpoint and key in Settings."
            case .incomplete: "The search ran out of time before finishing. Try again."
            case .refused: "The search was declined. Try a different state."
            case .noResult: "The search finished without returning a list. Try again."
            }
        }
    }

    // The Claude Messages API response, passed through unchanged by Xano.
    private struct MessageResponse: Decodable {
        /// Only the report tool's input is decoded; web search and other blocks carry differently shaped inputs.
        struct Block: Decodable {
            let type: String
            let name: String?
            let input: Report?

            private enum CodingKeys: String, CodingKey { case type, name, input }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                type = try c.decode(String.self, forKey: .type)
                name = try c.decodeIfPresent(String.self, forKey: .name)
                input = (type == "tool_use" && name == "report_cancelled_projects")
                    ? try c.decodeIfPresent(Report.self, forKey: .input) : nil
            }
        }
        let content: [Block]
        let stop_reason: String?
    }

    struct Report: Decodable {
        struct Item: Decodable {
            let name: String
            let developer: String?
            let county: String?
            let state: String
            let megawatts: Double?
            let status: String
            let date: String?
            let reason: String?
            let summary: String
            let source_url: String
            let source_title: String?
        }
        let projects: [Item]
    }

    func search(state: String) async throws -> [CancelledProject] {
        var request = URLRequest(url: endpoint, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.httpBody = try JSONEncoder().encode(["state": state, "app_key": appKey])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SearchError.server(status) }

        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        if message.stop_reason == "refusal" { throw SearchError.refused }
        guard let report = message.content.first(where: { $0.type == "tool_use" && $0.name == "report_cancelled_projects" })?.input else {
            throw message.stop_reason == "pause_turn" ? SearchError.incomplete : SearchError.noResult
        }
        return report.projects.compactMap { item in
            guard let url = URL(string: item.source_url), url.scheme?.hasPrefix("http") == true else { return nil }
            return CancelledProject(source: "News", projectNumber: Self.slug(item.name, item.state),
                                    state: item.state, county: item.county ?? "", fuelType: "Data Center",
                                    megawatts: item.megawatts ?? 0, queueDate: nil, withdrawnDate: Self.date(item.date),
                                    plannedInService: nil, transmissionOwner: item.developer ?? "", pointOfInterconnection: "",
                                    name: item.name, status: item.status, reason: item.reason, summary: item.summary,
                                    sourceURL: url, sourceTitle: item.source_title)
        }
    }

    /// Stable id for a news project, so the same one isn't imported twice.
    private static func slug(_ name: String, _ state: String) -> String {
        "\(state)-\(name)".lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }

    /// Accepts "2026-03-14", "2026-03" or "2026".
    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        for format in ["yyyy-MM-dd", "yyyy-MM", "yyyy"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

enum USStates {
    static let all: [(code: String, name: String)] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"), ("CO", "Colorado"),
        ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"), ("FL", "Florida"), ("GA", "Georgia"),
        ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"), ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"),
        ("KY", "Kentucky"), ("LA", "Louisiana"), ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"),
        ("MI", "Michigan"), ("MN", "Minnesota"), ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"),
        ("NE", "Nebraska"), ("NV", "Nevada"), ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"),
        ("NY", "New York"), ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"),
        ("OR", "Oregon"), ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"), ("WA", "Washington"),
        ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming"),
    ]
}
