import SwiftData
import SwiftUI

struct CapturesView: View {
    @Query(sort: \Equipment.capturedAt, order: .reverse) private var equipment: [Equipment]
    @State private var search = ""
    @State private var status: EquipmentStatus?
    @State private var csvURL: URL?

    private var filtered: [Equipment] {
        equipment.filter { e in
            (status == nil || e.status == status)
                && (search.isEmpty || [e.tag, e.manufacturer, e.model, e.serial, e.kind.rawValue, e.site?.name ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    private var grouped: [(String, [Equipment])] {
        Dictionary(grouping: filtered) { $0.site?.name ?? "Unassigned" }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.0) { siteName, items in
                Section(siteName) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { EquipmentRow(equipment: item) }
                    }
                }
            }
        }
        .overlay {
            if equipment.isEmpty {
                ContentUnavailableView("No captures yet", systemImage: "camera.viewfinder",
                                       description: Text("Open a site and scan a nameplate to get started."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "Search tag, make, model, serial")
        .navigationTitle("Captures")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Picker("Status", selection: $status) {
                    Text("All statuses").tag(EquipmentStatus?.none)
                    ForEach(EquipmentStatus.allCases, id: \.self) { Text($0.rawValue).tag(EquipmentStatus?.some($0)) }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if let csvURL {
                    ShareLink(item: csvURL) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .task(id: filtered.count) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FieldSight Equipment.csv")
            if (try? CSVExporter.equipment(filtered).write(to: url, atomically: true, encoding: .utf8)) != nil { csvURL = url }
        }
    }
}
