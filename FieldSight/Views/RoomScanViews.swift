import SwiftData
import SwiftUI

struct RoomScanFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let site: Site

    @State private var scanning = false
    @State private var processing = false
    @State private var result: RoomScanResult?
    @State private var name = "Electrical Room"
    @State private var level = ""
    @State private var notes = ""
    // Manual entry (no LiDAR)
    @State private var widthFt = 12.0
    @State private var depthFt = 20.0
    @State private var heightFt = 10.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Room") {
                    TextField("Name", text: $name)
                    TextField("Level / area", text: $level)
                }
                if let result {
                    Section("Scan result") {
                        PlanImage(geometry: result.geometry, height: 260).listRowInsets(EdgeInsets())
                        KeyValueRow(key: "Floor area", value: "\(Units.number(result.floorAreaSqFt)) sq ft")
                        KeyValueRow(key: "Ceiling height", value: "\(Units.number(result.ceilingHeightFt, digits: 1)) ft")
                        KeyValueRow(key: "Walls / openings / objects", value: "\(result.geometry.walls.count) / \(result.geometry.openings.count) / \(result.geometry.objects.count)")
                        Button("Re-scan") { self.result = nil; scanning = true }
                    }
                } else if RoomScanner.isSupported {
                    Section {
                        Button { scanning = true } label: {
                            Label("Start LiDAR Scan", systemImage: "cube.transparent").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).listRowBackground(Color.clear)
                        if processing { ProgressView("Building floor plan…") }
                    } footer: {
                        Text("Walk the room slowly, pointing at each wall, floor and ceiling edge. RoomPlan captures walls, doors, windows and large objects, then FieldSight draws a dimensioned as-built plan.")
                    }
                } else {
                    Section {
                        NumberField(title: "Width", value: $widthFt, unit: "ft")
                        NumberField(title: "Length", value: $depthFt, unit: "ft")
                        NumberField(title: "Ceiling height", value: $heightFt, unit: "ft")
                        PlanImage(geometry: manualGeometry, height: 200).listRowInsets(EdgeInsets())
                    } header: {
                        Text("Dimensions")
                    } footer: {
                        Text("LiDAR room scanning needs an iPhone Pro or iPad Pro. On this device, enter measured dimensions instead.")
                    }
                }
                Section("Notes") { TextField("Clearances, working space, observations…", text: $notes, axis: .vertical).lineLimit(2...6) }
            }
            .navigationTitle("Room Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(RoomScanner.isSupported && result == nil)
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                RoomCaptureScreen { room in
                    scanning = false
                    guard let room else { return }
                    processing = true
                    Task {
                        let converted = RoomScanner.convert(room)
                        result = converted
                        processing = false
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private var manualGeometry: RoomGeometry {
        .rectangle(width: widthFt / Units.feetPerMeter, depth: depthFt / Units.feetPerMeter)
    }

    private func save() {
        let scan: RoomScan
        if let result {
            scan = RoomScan(name: name, level: level, floorAreaSqFt: result.floorAreaSqFt, ceilingHeightFt: result.ceilingHeightFt,
                            notes: notes, fromLiDAR: true, geometry: result.geometry)
            scan.usdzData = result.usdz
        } else {
            scan = RoomScan(name: name, level: level, floorAreaSqFt: widthFt * depthFt, ceilingHeightFt: heightFt,
                            notes: notes, fromLiDAR: false, geometry: manualGeometry)
        }
        context.insert(scan)
        scan.site = site
        try? context.save()
        dismiss()
    }
}

struct RoomScanDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var scan: RoomScan
    @State private var usdzURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    CardHeader(title: scan.name) {
                        Badge(text: scan.fromLiDAR ? "LiDAR" : "Manual", color: scan.fromLiDAR ? .indigo : .gray)
                    }
                    PlanImage(geometry: scan.geometry, height: 380)
                }
                Card {
                    CardHeader("Measurements")
                    KeyValueRow(key: "Floor area", value: "\(Units.number(scan.floorAreaSqFt)) sq ft")
                    KeyValueRow(key: "Ceiling height", value: "\(Units.number(scan.ceilingHeightFt, digits: 1)) ft")
                    let e = scan.geometry.extents
                    KeyValueRow(key: "Overall extents", value: "\(Units.feetInches(e.width)) × \(Units.feetInches(e.depth))")
                    if !scan.level.isEmpty { KeyValueRow(key: "Level", value: scan.level) }
                    KeyValueRow(key: "Captured", value: scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                }
                if !scan.geometry.walls.isEmpty {
                    Card {
                        CardHeader("Walls")
                        ForEach(Array(scan.geometry.walls.enumerated()), id: \.offset) { i, wall in
                            KeyValueRow(key: "Wall \(i + 1)", value: Units.feetInches(wall.length))
                        }
                    }
                }
                if !scan.notes.isEmpty {
                    Card { CardHeader("Notes"); Text(scan.notes).font(.subheadline) }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(scan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let usdzURL {
                ShareLink(item: usdzURL) { Label("Share 3D Model", systemImage: "cube") }
            }
            Button(role: .destructive) {
                context.delete(scan)
                try? context.save()
                dismiss()
            } label: { Label("Delete", systemImage: "trash") }
        }
        .task {
            guard let data = scan.usdzData else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(scan.name.fileSafe).usdz")
            if (try? data.write(to: url)) != nil { usdzURL = url }
        }
    }
}
