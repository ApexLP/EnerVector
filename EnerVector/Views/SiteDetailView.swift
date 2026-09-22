import SwiftData
import SwiftUI

enum SiteSheet: String, Identifiable {
    case nameplate, roomScan, newRoof, report, edit, addFlag, runs
    var id: String { rawValue }
}

struct SiteDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var site: Site
    @State private var sheet: SiteSheet?
    @State private var confirmDelete = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var sortedEquipment: [Equipment] { site.equipment.sorted { $0.capturedAt > $1.capturedAt } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                captureActions
                if !site.openFlags.isEmpty { flagsCard }
                equipmentCard
                if !site.roomScans.isEmpty { scansCard }
                if !site.segments.isEmpty || site.discipline == .electrical || site.discipline == .dataCenter { runsCard }
                if !site.roofSurveys.isEmpty { roofCard }
                if site.discipline == .energyAudit || site.equipment.contains(where: { $0.kind.isHVAC }) {
                    LoadEstimateCard(site: site)
                }
                reportBanner
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = .report } label: { Label("Report", systemImage: "doc.richtext") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button { sheet = .edit } label: { Label("Edit Site", systemImage: "pencil") }
                    Button { sheet = .addFlag } label: { Label("Add Flag", systemImage: "flag") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Site", systemImage: "trash") }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Delete \(site.name) and all of its captures?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Site", role: .destructive) {
                context.delete(site)
                try? context.save()
                dismiss()
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .nameplate: NameplateCaptureView(site: site)
            case .roomScan: RoomScanFlowView(site: site)
            case .newRoof: NavigationStack { RoofSurveyView(survey: nil, site: site) }
            case .report: NavigationStack { ReportComposerView(site: site) }.presentationSizing(.page)
            case .edit: SiteEditorView(site: site)
            case .addFlag: FlagEditorView(site: site)
            case .runs: NavigationStack { RunProgressView(site: site).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { self.sheet = nil } } } }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(site.name).font(.title2.bold())
                    HStack(spacing: 10) {
                        Badge(text: site.discipline.rawValue, color: site.discipline.color, symbol: site.discipline.symbol)
                        if !site.address.isEmpty {
                            Label(site.address, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !site.client.isEmpty { Text(site.client).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                ProgressRing(value: site.progress, color: site.discipline.color, lineWidth: 7, label: "")
                    .frame(width: 64, height: 64)
                    .font(.caption)
            }
            HStack(spacing: 0) {
                stat("\(site.equipment.count)", "Equipment")
                stat("\(site.openFlags.count)", "Open flags", color: site.openFlags.isEmpty ? .primary : .red)
                stat("\(site.roomScans.count)", "Room scans")
                stat(site.buildingSqFt > 0 ? Units.number(site.buildingSqFt) : "—", "Sq ft")
            }
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var captureActions: some View {
        LazyVGrid(columns: ResponsiveColumns.make(sizeClass), spacing: 12) {
            actionButton("Nameplate", "Read labels & ratings", "text.viewfinder", .blue) { sheet = .nameplate }
            actionButton("Room Scan", RoomScanner.isSupported ? "LiDAR as-built" : "Enter dimensions", "cube.transparent", .indigo) { sheet = .roomScan }
            actionButton("Runs", "Conduit & tray progress", "point.topleft.down.to.point.bottomright.curvepath", .teal) { sheet = .runs }
            actionButton("Roof Survey", "Area & solar potential", "sun.max", .orange) { sheet = .newRoof }
        }
    }

    private func actionButton(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private var flagsCard: some View {
        Card {
            CardHeader(title: "Compliance Flags") {
                Button("Add") { sheet = .addFlag }.font(.subheadline)
            }
            ForEach(site.openFlags.sorted { $0.createdAt > $1.createdAt }) { flag in
                FlagRow(flag: flag)
            }
        }
    }

    private var equipmentCard: some View {
        Card {
            CardHeader(title: "Captured Equipment (\(site.equipment.count))") {
                Button { sheet = .nameplate } label: { Label("Capture", systemImage: "plus") }.font(.subheadline)
            }
            if site.equipment.isEmpty {
                Text("Scan a nameplate to add equipment. EnerVector reads the manufacturer, model, serial and ratings, and checks for an arc flash label.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(sortedEquipment) { item in
                NavigationLink(value: item) { EquipmentRow(equipment: item) }
                    .buttonStyle(.plain)
                if item.id != sortedEquipment.last?.id { Divider() }
            }
        }
    }

    private var scansCard: some View {
        Card {
            CardHeader(title: "As-Built Measurements") {
                Button { sheet = .roomScan } label: { Label("Scan", systemImage: "plus") }.font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(site.roomScans.sorted { $0.capturedAt > $1.capturedAt }) { scan in
                        NavigationLink(value: scan) {
                            VStack(alignment: .leading, spacing: 6) {
                                PlanImage(geometry: scan.geometry, height: 150).frame(width: 240)
                                Text(scan.name).font(.subheadline.weight(.semibold))
                                Text("\(Units.number(scan.floorAreaSqFt)) sq ft · \(Units.number(scan.ceilingHeightFt, digits: 1)) ft ceiling")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var runsCard: some View {
        Card {
            CardHeader(title: "Conduit & Cable Tray") {
                Button("Open") { sheet = .runs }.font(.subheadline)
            }
            if site.segments.isEmpty {
                Text("Track planned vs. installed footage for conduit, tray and busway. Measure installed runs with AR.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 20) {
                    ProgressRing(value: site.installedFeet / max(site.plannedFeet, 1), color: .green, lineWidth: 9)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueRow(key: "Installed", value: "\(Units.number(site.installedFeet)) ft")
                        KeyValueRow(key: "Planned", value: "\(Units.number(site.plannedFeet)) ft")
                        KeyValueRow(key: "Remaining", value: "\(Units.number(max(0, site.plannedFeet - site.installedFeet))) ft")
                        KeyValueRow(key: "Segments behind", value: "\(site.segments.filter { $0.statusLabel == "Behind" }.count)")
                    }
                }
            }
        }
    }

    private var roofCard: some View {
        Card {
            CardHeader(title: "Roof & Solar") {
                Button { sheet = .newRoof } label: { Label("Survey", systemImage: "plus") }.font(.subheadline)
            }
            ForEach(site.roofSurveys.sorted { $0.capturedAt > $1.capturedAt }) { roof in
                NavigationLink(value: roof) {
                    HStack(spacing: 14) {
                        RoofPlanImage(plan: roof.plan, height: 70).frame(width: 90)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(roof.name).font(.subheadline.weight(.semibold))
                            Text("\(Units.number(roof.usableAreaSqFt)) sq ft usable").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(Units.number(roof.capacityKW)) kW").font(.headline)
                            Text("est. capacity").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reportBanner: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "doc.richtext").font(.title).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to share your findings?").font(.headline)
                    Text("Generate a PDF report and email it to your client.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Build Report") { sheet = .report }.buttonStyle(.borderedProminent)
            }
        }
    }
}

struct EquipmentRow: View {
    let equipment: Equipment

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = equipment.photo, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: equipment.kind.symbol).foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(equipment.displayName).font(.subheadline.weight(.semibold))
                Text([equipment.kind.rawValue, equipment.manufacturer, equipment.ratingSummary].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if equipment.hasArcFlashLabel == false && equipment.kind.expectsArcFlashLabel {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill").foregroundStyle(.orange)
            }
            Badge(text: equipment.status.rawValue, color: equipment.status.color, symbol: equipment.status.symbol)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct FlagRow: View {
    @Bindable var flag: ComplianceFlag

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(flag.severity.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(flag.title).font(.subheadline.weight(.semibold))
                if !flag.detail.isEmpty { Text(flag.detail).font(.caption).foregroundStyle(.secondary) }
                if !flag.reference.isEmpty { Text(flag.reference).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Button("Resolve") {
                flag.resolved = true
                flag.resolvedAt = .now
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(flag.severity.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FlagEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let site: Site
    var equipmentTag = ""

    @State private var title = ""
    @State private var detail = ""
    @State private var severity: FlagSeverity = .warning
    @State private var reference = ""
    @State private var tag = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Severity", selection: $severity) {
                    ForEach(FlagSeverity.allCases, id: \.self) { Text($0.rawValue) }
                }
                TextField("Equipment tag", text: $tag)
                TextField("Code reference (e.g. NEC 110.26)", text: $reference)
                TextField("Details", text: $detail, axis: .vertical).lineLimit(3...8)
            }
            .navigationTitle("Add Flag")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { tag = equipmentTag }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let flag = ComplianceFlag(title: title, detail: detail, severity: severity, equipmentTag: tag, reference: reference)
                        context.insert(flag)
                        flag.site = site
                        if let item = site.equipment.first(where: { $0.tag == tag && !tag.isEmpty }) { item.status = .flagged }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

/// Rough connected-load estimate for energy audits: HVAC tonnage plus a lighting/plug density.
struct LoadEstimateCard: View {
    @Bindable var site: Site
    @AppStorage(AppSettings.kwPerTon) private var kwPerTon = 1.2
    @AppStorage(AppSettings.wattsPerSqFt) private var wattsPerSqFt = 3.0

    var body: some View {
        let est = LoadEstimate(site: site, kwPerTon: kwPerTon, wattsPerSqFt: wattsPerSqFt)
        Card {
            CardHeader("Load Estimate")
            HStack(alignment: .firstTextBaseline) {
                Text(Units.number(est.totalKW)).font(.system(size: 34, weight: .bold)).monospacedDigit()
                Text("kW connected (est.)").foregroundStyle(.secondary)
            }
            KeyValueRow(key: "HVAC (\(Units.number(est.tons, digits: 1)) tons × \(Units.number(kwPerTon, digits: 1)) kW/ton)", value: "\(Units.number(est.hvacKW)) kW")
            KeyValueRow(key: "Lighting & plug (\(Units.number(wattsPerSqFt, digits: 1)) W/sq ft)", value: "\(Units.number(est.densityKW)) kW")
            HStack {
                Text("Building area").foregroundStyle(.secondary)
                Spacer()
                TextField("sq ft", value: Binding(get: { site.buildingSqFt }, set: { site.buildingSqFtOverride = $0 > 0 ? $0 : nil }),
                          format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120)
                Text("sq ft").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Text(site.buildingSqFtOverride == nil && site.scannedSqFt > 0 ? "Area is the sum of LiDAR room scans. Enter a value to override." : "Assumptions can be changed in Settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LoadEstimate {
    let tons: Double
    let hvacKW: Double
    let densityKW: Double
    var totalKW: Double { hvacKW + densityKW }

    init(site: Site, kwPerTon: Double, wattsPerSqFt: Double) {
        tons = site.equipment.compactMap(\.tons).reduce(0, +)
        hvacKW = tons * kwPerTon
        densityKW = site.buildingSqFt * wattsPerSqFt / 1000
    }
}
