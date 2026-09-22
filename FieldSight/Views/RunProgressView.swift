import SwiftData
import SwiftUI

/// Conduit & cable tray progress: planned vs. installed footage per segment, with AR length measurement.
struct RunProgressView: View {
    @Environment(\.modelContext) private var context
    @Bindable var site: Site
    @State private var editing: RunSegment?
    @State private var addingNew = false
    @State private var search = ""

    private var segments: [RunSegment] {
        site.segments
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.area.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 24) {
                    ProgressRing(value: site.installedFeet / max(site.plannedFeet, 1), color: .green, lineWidth: 12)
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        metric(site.installedFeet, "Installed")
                        metric(site.plannedFeet, "Planned")
                        metric(max(0, site.plannedFeet - site.installedFeet), "Remaining")
                    }
                }
                .padding(.vertical, 8)
                HStack {
                    Label("\(site.segments.filter { $0.statusLabel == "Behind" }.count) behind", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Spacer()
                    Label("\(site.segments.filter { $0.statusLabel == "Complete" }.count) complete", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                .font(.subheadline)
            }

            Section("Segments") {
                ForEach(segments) { seg in
                    Button { editing = seg } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(seg.name).font(.headline)
                                Text(seg.type.rawValue).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Badge(text: seg.statusLabel, color: seg.statusColor)
                            }
                            LinearProgress(value: seg.progress, color: seg.statusColor == .gray ? .secondary : seg.statusColor)
                            HStack {
                                Text("\(Units.number(seg.installedFt)) / \(Units.number(seg.plannedFt)) ft")
                                if !seg.area.isEmpty { Text("· \(seg.area)") }
                                Spacer()
                                Text(seg.variance >= 0 ? "0 ft" : "\(Units.number(seg.variance)) ft")
                                    .foregroundStyle(seg.variance < 0 ? .red : .secondary)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(segments[i]) }
                    try? context.save()
                }
                Button { addingNew = true } label: { Label("Add segment", systemImage: "plus") }
            }
        }
        .searchable(text: $search, prompt: "Search segments")
        .navigationTitle("Conduit Progress")
        .sheet(item: $editing) { RunSegmentEditor(site: site, segment: $0) }
        .sheet(isPresented: $addingNew) { RunSegmentEditor(site: site, segment: nil) }
    }

    private func metric(_ ft: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(Units.number(ft)) ft").font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct RunSegmentEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let site: Site
    let segment: RunSegment?

    @State private var name = ""
    @State private var type: RunType = .conduit
    @State private var area = ""
    @State private var planned = 0.0
    @State private var installed = 0.0
    @State private var notes = ""
    @State private var measuring = false
    @State private var lastMeasured: Double?
    @State private var manualAdd = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Segment") {
                    TextField("Name (e.g. C-12, Tray Run A)", text: $name)
                    Picker("Type", selection: $type) { ForEach(RunType.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("Area / room", text: $area)
                    NumberField(title: "Planned", value: $planned, unit: "ft")
                    NumberField(title: "Installed", value: $installed, unit: "ft")
                }
                Section {
                    if ARMeasure.isSupported {
                        Button { measuring = true } label: {
                            Label("Measure installed run with AR", systemImage: "ruler")
                        }
                    }
                    HStack {
                        NumberField(title: "Add footage", value: $manualAdd, unit: "ft")
                        Button("Add") { installed += manualAdd; manualAdd = 0 }.disabled(manualAdd <= 0)
                    }
                    if let lastMeasured {
                        Label("Added \(Units.number(lastMeasured, digits: 1)) ft from AR measurement", systemImage: "checkmark.circle")
                            .foregroundStyle(.green).font(.footnote)
                    }
                } header: {
                    Text("Log installed footage")
                } footer: {
                    Text(ARMeasure.isSupported
                         ? "Walk the run and drop a point at each bend — the measured length is added to Installed. \(ARMeasure.hasLiDAR ? "LiDAR detected: points snap to the scanned mesh." : "")"
                         : "AR measuring needs a device with ARKit. Enter footage manually.")
                }
                Section("Notes") { TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5) }
            }
            .navigationTitle(segment == nil ? "New Segment" : name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard let segment else { return }
                name = segment.name; type = segment.type; area = segment.area
                planned = segment.plannedFt; installed = segment.installedFt; notes = segment.notes
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.isEmpty || planned <= 0) }
            }
            .fullScreenCover(isPresented: $measuring) {
                ARMeasureScreen(mode: .length, title: name.isEmpty ? "Run" : name) { result in
                    measuring = false
                    if let result {
                        installed += result.lengthFt
                        lastMeasured = result.lengthFt
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func save() {
        let target = segment ?? RunSegment(name: name, plannedFt: planned)
        if segment == nil { context.insert(target); target.site = site }
        target.name = name; target.type = type; target.area = area
        target.plannedFt = planned; target.installedFt = installed; target.notes = notes
        target.updatedAt = .now
        try? context.save()
        dismiss()
    }
}
