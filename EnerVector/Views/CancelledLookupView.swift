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
            .overlay {
                if store.projects.isEmpty && store.isLoading {
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
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CancelledProject.self) { CancelledProjectDetail(project: $0) }
            .withAppDestinations()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await store.load() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(project.title).font(.subheadline.weight(.semibold))
                Spacer()
                if imported { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Added") }
            }
            Text([project.location, project.transmissionOwner].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let withdrawn = project.withdrawnDate {
                Text("Withdrawn \(withdrawn.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CancelledProjectDetail: View {
    @Environment(\.modelContext) private var context
    @Query private var sites: [Site]
    let project: CancelledProject

    private var existing: Site? { sites.first { $0.externalRef == project.ref } }

    var body: some View {
        Form {
            Section {
                Text(project.title).font(.headline)
                KeyValueRow(key: "Location", value: project.location.isEmpty ? "—" : project.location)
                KeyValueRow(key: "Capacity", value: project.megawatts > 0 ? "\(Units.number(project.megawatts)) MW" : "—")
                KeyValueRow(key: "Type", value: project.fuelLabel)
                KeyValueRow(key: "Utility / TO", value: project.transmissionOwner.isEmpty ? "—" : project.transmissionOwner)
                if !project.pointOfInterconnection.isEmpty {
                    KeyValueRow(key: "Point of interconnection", value: project.pointOfInterconnection)
                }
            }
            Section("Timeline") {
                KeyValueRow(key: "Entered queue", value: Self.day(project.queueDate))
                KeyValueRow(key: "Planned in-service", value: Self.day(project.plannedInService))
                KeyValueRow(key: "Withdrawn", value: Self.day(project.withdrawnDate))
            }
            Section {
                if let existing {
                    NavigationLink(value: existing) { Label("Open site", systemImage: "building.2") }
                } else {
                    Button { add() } label: { Label("Add as Cancelled Site", systemImage: "plus.circle.fill") }
                }
            } footer: {
                Text("Creates a site under Cancelled · Stranded Assets so you can survey and document any equipment left on site. Queue data shows the project was withdrawn, not what was built.")
            }
        }
        .navigationTitle(project.projectNumber)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func day(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .omitted) ?? "—" }

    private func add() {
        let discipline: Discipline = project.fuelType == "Solar" ? .solarSurvey : .electrical
        let mw = project.megawatts > 0 ? "\(Units.number(project.megawatts)) MW " : ""
        let site = Site(name: "\(project.source) \(project.projectNumber) — \(mw)\(project.fuelLabel)",
                        client: project.transmissionOwner, address: project.location, discipline: discipline,
                        notes: "Imported from the \(project.source) interconnection queue.")
        context.insert(site)
        site.externalRef = project.ref
        site.cancelledAt = project.withdrawnDate ?? .now
        site.cancelReason = .queueWithdrawal
        site.cancelNotes = [
            "Withdrawn from the \(project.source) queue as project \(project.projectNumber).",
            project.queueDate.map { "Entered queue \(Self.day($0))." },
            project.plannedInService.map { "Planned in-service \(Self.day($0))." },
            project.pointOfInterconnection.isEmpty ? nil : "POI: \(project.pointOfInterconnection).",
        ].compactMap { $0 }.joined(separator: " ")
        try? context.save()
    }
}
