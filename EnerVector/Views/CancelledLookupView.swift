import SwiftData
import SwiftUI

/// Browse projects withdrawn from public interconnection queues and add one as a cancelled site.
struct CancelledLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var sites: [Site]
    @State private var store = CancelledProjectStore.shared
    @State private var search = ""
    @State private var state = ""
    @State private var fuel = ""
    @State private var minMW: Double = 0
    @State private var sortByMW = false
    @State private var mode = Mode.queues
    @State private var newsState = "VA"
    @State private var newsResults: [String: [CancelledProject]] = [:]
    @State private var newsLoading = false
    @State private var newsError: String?
    @State private var newsWindow = NewsWindow.months12
    @State private var flags = ArticleFlags.shared

    enum Mode: String, CaseIterable { case queues = "Grid queues", news = "Data centers (news)" }

    private var states: [String] { Array(Set(store.projects.map(\.state).filter { !$0.isEmpty })).sorted() }
    private var fuels: [String] { Array(Set(store.projects.map(\.fuelLabel))).sorted() }
    private var importedRefs: Set<String> { Set(sites.compactMap(\.externalRef)) }

    private var results: [CancelledProject] {
        let filtered = store.projects.filter { p in
            (state.isEmpty || p.state == state)
                && (fuel.isEmpty || p.fuelLabel == fuel)
                && p.megawatts >= minMW
                && (search.isEmpty || [p.projectNumber, p.county, p.transmissionOwner, p.pointOfInterconnection, p.fuelType]
                    .contains { $0.localizedCaseInsensitiveContains(search) })
        }
        return sortByMW ? filtered.sorted { $0.megawatts > $1.megawatts } : filtered
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Source", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if mode == .queues { queueSections } else { newsSections }
            }
            .overlay {
                if mode == .news {
                    EmptyView()
                } else if store.projects.isEmpty && store.isLoading {
                    ProgressView("Loading withdrawn projects…")
                } else if store.projects.isEmpty, let error = store.error {
                    ContentUnavailableView {
                        Label("No data", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Try Again") { Task { await store.load(force: true) } }.buttonStyle(.borderedProminent)
                    }
                } else if !store.projects.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Project #, county, utility, substation")
            .refreshable { await store.load(force: true) }
            .navigationTitle("Cancelled Projects")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CancelledProject.self) { CancelledProjectDetail(project: $0) }
            .withAppDestinations()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await store.load() }
        }
    }

    @ViewBuilder private var queueSections: some View {
        Section {
            filters
        } footer: {
            Text(summary)
        }
        Section {
            ForEach(results.prefix(300)) { project in
                NavigationLink(value: project) {
                    ProjectRow(project: project, imported: importedRefs.contains(project.ref))
                }
            }
        } footer: {
            if results.count > 300 { Text("Showing the first 300 of \(results.count). Narrow the filters to see more.") }
        }
    }

    @ViewBuilder private var newsSections: some View {
        if let source = NewsSearchSource.configured {
            Section {
                Picker("State", selection: $newsState) {
                    ForEach(USStates.all, id: \.code) { Text($0.name).tag($0.code) }
                }
                Picker("Time frame", selection: $newsWindow) {
                    ForEach(NewsWindow.allCases) { Text($0.label).tag($0) }
                }
                Button {
                    Task { await runNewsSearch(source) }
                } label: {
                    HStack {
                        Label(newsResults[newsState] == nil ? "Search news" : "Search again", systemImage: "sparkle.magnifyingglass")
                        if newsLoading { Spacer(); ProgressView() }
                    }
                }
                .disabled(newsLoading)
            } footer: {
                Text(newsLoading ? "Searching recent news and public records — this can take a minute or two."
                     : "Claude searches the web for data center projects in this state that were cancelled, withdrawn, paused or denied in the chosen time frame. Flag any article that's wrong. Results are AI-gathered from news coverage — open the source to verify before relying on them.")
            }
            if let newsError {
                Section { Label(newsError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            if let found = newsResults[newsState] {
                Section {
                    if found.isEmpty {
                        Text("No cancelled data center projects found for this state.").foregroundStyle(.secondary)
                    }
                    // Flagged articles sink to the bottom.
                    ForEach(found.sorted { (flags.reason(for: $0.sourceURL) == nil) && (flags.reason(for: $1.sourceURL) != nil) }) { project in
                        NavigationLink(value: project) {
                            ProjectRow(project: project, imported: importedRefs.contains(project.ref),
                                       flag: flags.reason(for: project.sourceURL))
                        }
                    }
                } header: {
                    let flagged = found.filter { flags.reason(for: $0.sourceURL) != nil }.count
                    Text("\(found.count) found" + (flagged > 0 ? " · \(flagged) flagged" : ""))
                }
            }
        } else {
            Section {
                Label("News search isn't set up yet", systemImage: "gearshape")
            } footer: {
                Text("Add the search endpoint and app key in Settings › Data Center News Search.")
            }
        }
    }

    private func runNewsSearch(_ source: NewsSearchSource) async {
        newsLoading = true
        newsError = nil
        defer { newsLoading = false }
        do {
            newsResults[newsState] = try await source.search(state: USStates.all.first { $0.code == newsState }?.name ?? newsState,
                                                              since: newsWindow.since)
        } catch {
            newsError = (error as? LocalizedError)?.errorDescription ?? "The search couldn't be completed. Check your connection and try again."
        }
    }

    private var filters: some View {
        Group {
            Picker("State", selection: $state) {
                Text("All states").tag("")
                ForEach(states, id: \.self) { Text($0).tag($0) }
            }
            Picker("Type", selection: $fuel) {
                Text("All types").tag("")
                ForEach(fuels, id: \.self) { Text($0).tag($0) }
            }
            Picker("Size", selection: $minMW) {
                Text("Any size").tag(0.0)
                Text("50 MW +").tag(50.0)
                Text("100 MW +").tag(100.0)
                Text("250 MW +").tag(250.0)
            }
            Picker("Sort", selection: $sortByMW) {
                Text("Most recently withdrawn").tag(false)
                Text("Largest first").tag(true)
            }
        }
    }

    private var summary: String {
        let mw = results.reduce(0) { $0 + $1.megawatts }
        var parts = ["\(results.count) withdrawn projects · \(Units.number(mw)) MW"]
        if let updated = store.updatedAt {
            parts.append(Date.now.timeIntervalSince(updated) < 60 ? "Updated just now" : "Updated \(updated.relativeShort)")
        }
        if let error = store.error, !store.projects.isEmpty { parts.append(error) }
        parts.append("Source: \(store.sources.map(\.coverage).joined(separator: "; ")). Pull to refresh.")
        return parts.joined(separator: "\n")
    }
}

private struct ProjectRow: View {
    let project: CancelledProject
    let imported: Bool
    var flag: ArticleFlags.Reason? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(project.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let flag { Image(systemName: "flag.fill").foregroundStyle(.orange).accessibilityLabel("Flagged: \(flag.rawValue)") }
                if imported { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Added") }
            }
            if let flag {
                Text("Flagged: \(flag.rawValue)").font(.caption).foregroundStyle(.orange)
            }
            Text([project.location, project.transmissionOwner].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let withdrawn = project.withdrawnDate {
                Text("\(project.status?.capitalized ?? "Withdrawn") \(withdrawn.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(flag == nil ? 1 : 0.6)
    }
}

struct CancelledProjectDetail: View {
    @Environment(\.modelContext) private var context
    @Query private var sites: [Site]
    @State private var flags = ArticleFlags.shared
    @State private var choosingFlag = false
    let project: CancelledProject

    private var existing: Site? { sites.first { $0.externalRef == project.ref } }

    var body: some View {
        Form {
            Section {
                Text(project.title).font(.headline)
                KeyValueRow(key: "Location", value: project.location.isEmpty ? "—" : project.location)
                KeyValueRow(key: "Capacity", value: project.megawatts > 0 ? "\(Units.number(project.megawatts)) MW" : "—")
                KeyValueRow(key: "Type", value: project.fuelLabel)
                KeyValueRow(key: project.isFromNews ? "Developer" : "Utility / TO", value: project.transmissionOwner.isEmpty ? "—" : project.transmissionOwner)
                if !project.pointOfInterconnection.isEmpty {
                    KeyValueRow(key: "Point of interconnection", value: project.pointOfInterconnection)
                }
            }
            if project.isFromNews {
                Section("From the news") {
                    if let status = project.status { KeyValueRow(key: "Status", value: status.capitalized) }
                    if let reason = project.reason, !reason.isEmpty { KeyValueRow(key: "Reason", value: reason) }
                    if let summary = project.summary { Text(summary).font(.subheadline) }
                    if let url = project.sourceURL {
                        Link(destination: url) {
                            Label(project.sourceTitle ?? url.host() ?? "Source", systemImage: "safari")
                        }
                    }
                }
                if let url = project.sourceURL {
                    Section {
                        if let reason = flags.reason(for: url) {
                            Label("Flagged: \(reason.rawValue)", systemImage: "flag.fill").foregroundStyle(.orange)
                            Button("Remove flag") { flags.unflag(url) }
                        } else {
                            Button { choosingFlag = true } label: { Label("Flag this article", systemImage: "flag") }
                                .tint(.orange)
                        }
                    } footer: {
                        Text("Flags are saved on this device and stay with the article in future searches.")
                    }
                    .confirmationDialog("What's wrong with this article?", isPresented: $choosingFlag, titleVisibility: .visible) {
                        ForEach(ArticleFlags.Reason.allCases) { reason in
                            Button(reason.rawValue) { flags.flag(url, reason) }
                        }
                    }
                }
            }
            Section("Timeline") {
                KeyValueRow(key: "Entered queue", value: Self.day(project.queueDate))
                KeyValueRow(key: "Planned in-service", value: Self.day(project.plannedInService))
                KeyValueRow(key: project.isFromNews ? "Cancelled / reported" : "Withdrawn", value: Self.day(project.withdrawnDate))
            }
            Section {
                if let existing {
                    NavigationLink(value: existing) { Label("Open site", systemImage: "building.2") }
                } else {
                    Button { add() } label: { Label("Add as Cancelled Site", systemImage: "plus.circle.fill") }
                }
            } footer: {
                Text(project.isFromNews
                     ? "Creates a site under Cancelled · Stranded Assets with the news source in its notes. Verify the details against the source before surveying."
                     : "Creates a site under Cancelled · Stranded Assets so you can survey and document any equipment left on site. Queue data shows the project was withdrawn, not what was built.")
            }
        }
        .navigationTitle(project.projectNumber)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func day(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .omitted) ?? "—" }

    private func add() {
        let site: Site
        if project.isFromNews {
            site = Site(name: project.name ?? project.title, client: project.transmissionOwner, address: project.location,
                        discipline: .dataCenter, notes: "Found in news coverage: \(project.sourceURL?.absoluteString ?? "")")
            context.insert(site)
            site.cancelReason = Self.reason(for: project)
            site.cancelNotes = [
                project.megawatts > 0 ? "\(Units.number(project.megawatts)) MW planned." : nil,
                project.status.map { "Status: \($0)." },
                project.reason.flatMap { $0.isEmpty ? nil : "Reason: \($0)." },
                project.summary,
                project.sourceURL.map { "Source: \($0.absoluteString)" },
            ].compactMap { $0 }.joined(separator: " ")
        } else {
            let discipline: Discipline = project.fuelType == "Solar" ? .solarSurvey : .electrical
            let mw = project.megawatts > 0 ? "\(Units.number(project.megawatts)) MW " : ""
            site = Site(name: "\(project.source) \(project.projectNumber) — \(mw)\(project.fuelLabel)",
                        client: project.transmissionOwner, address: project.location, discipline: discipline,
                        notes: "Imported from the \(project.source) interconnection queue.")
            context.insert(site)
            site.cancelReason = .queueWithdrawal
            site.cancelNotes = [
                "Withdrawn from the \(project.source) queue as project \(project.projectNumber).",
                project.queueDate.map { "Entered queue \(Self.day($0))." },
                project.plannedInService.map { "Planned in-service \(Self.day($0))." },
                project.pointOfInterconnection.isEmpty ? nil : "POI: \(project.pointOfInterconnection).",
            ].compactMap { $0 }.joined(separator: " ")
        }
        site.externalRef = project.ref
        site.cancelledAt = project.withdrawnDate ?? .now
        try? context.save()
    }

    /// Best-effort mapping of the reported reason onto the app's cancellation reasons.
    private static func reason(for project: CancelledProject) -> CancelReason {
        let text = "\(project.reason ?? "") \(project.status ?? "")".lowercased()
        if ["power", "grid", "interconnect", "utility", "transmission", "capacity"].contains(where: text.contains) { return .noInterconnection }
        if ["zoning", "rezon", "permit", "denied", "board", "county"].contains(where: text.contains) { return .permitting }
        if ["financ", "demand", "tenant", "funding", "market"].contains(where: text.contains) { return .demand }
        return .other
    }
}
