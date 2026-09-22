import SwiftData
import SwiftUI

struct EquipmentDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var equipment: Equipment

    enum Sheet: String, Identifiable { case edit, label, schedule, flag; var id: String { rawValue } }
    @State private var sheet: Sheet?
    @State private var confirmDelete = false
    @State private var showRawText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        photoCard.frame(minWidth: 320)
                        dataCard.frame(width: 360)
                    }
                    VStack(spacing: 16) {
                        photoCard
                        dataCard
                    }
                }
                if !openFlags.isEmpty {
                    ForEach(openFlags) { FlagRow(flag: $0) }
                }
                arcFlashCard
                if equipment.kind.hasPanelSchedule || !equipment.circuits.isEmpty { scheduleCard }
                actions
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(equipment.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button { sheet = .edit } label: { Label("Edit", systemImage: "pencil") }
                Button { showRawText.toggle() } label: { Label("Show recognized text", systemImage: "text.alignleft") }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            } label: { Label("More", systemImage: "ellipsis.circle") }
        }
        .confirmationDialog("Delete \(equipment.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(equipment)
                try? context.save()
                dismiss()
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: EquipmentEditView(equipment: equipment)
            case .label: ArcFlashLabelCheckView(equipment: equipment)
            case .schedule: PanelScheduleCaptureView(equipment: equipment)
            case .flag: if let site = equipment.site { FlagEditorView(site: site, equipmentTag: equipment.tag) }
            }
        }
        .sheet(isPresented: $showRawText) {
            NavigationStack {
                ScrollView { Text(equipment.rawText.isEmpty ? "No recognized text." : equipment.rawText).font(.body.monospaced()).padding().textSelection(.enabled) }
                    .navigationTitle("Recognized Text")
                    .toolbar { Button("Done") { showRawText = false } }
            }
        }
    }

    private var openFlags: [ComplianceFlag] {
        (equipment.site?.openFlags ?? []).filter { !equipment.tag.isEmpty && $0.equipmentTag == equipment.tag }
    }

    private var photoCard: some View {
        Card(padding: 0) {
            ZStack {
                if let data = equipment.photo, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: equipment.kind.symbol).font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("No photo").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var dataCard: some View {
        Card {
            CardHeader(title: "Extracted Data") {
                Button { sheet = .edit } label: { Label("Edit", systemImage: "pencil") }.font(.subheadline)
            }
            KeyValueRow(key: "Tag", value: equipment.tag)
            KeyValueRow(key: "Type", value: equipment.kind.rawValue)
            KeyValueRow(key: "Manufacturer", value: equipment.manufacturer)
            KeyValueRow(key: "Model", value: equipment.model)
            KeyValueRow(key: "Serial", value: equipment.serial)
            KeyValueRow(key: "Voltage", value: equipment.voltage)
            KeyValueRow(key: "Amperage", value: equipment.amperage)
            KeyValueRow(key: "Phase", value: equipment.phase)
            if !equipment.kva.isEmpty { KeyValueRow(key: "kVA", value: equipment.kva) }
            if equipment.kind.isHVAC || !equipment.tonnage.isEmpty {
                KeyValueRow(key: "Tonnage", value: equipment.tonnage)
                KeyValueRow(key: "Refrigerant", value: equipment.refrigerant)
            }
            KeyValueRow(key: "Year / age", value: equipment.manufactureYear.map { "\($0) (\(equipment.age ?? 0) yrs)" } ?? "")
            KeyValueRow(key: "Location", value: equipment.location)
            if !equipment.notes.isEmpty { KeyValueRow(key: "Notes", value: equipment.notes) }
            HStack {
                Text("Status").foregroundStyle(.secondary).font(.subheadline)
                Spacer()
                Badge(text: equipment.status.rawValue, color: equipment.status.color, symbol: equipment.status.symbol)
            }
        }
    }

    private var arcFlashCard: some View {
        Card {
            CardHeader(title: "Arc Flash Label") {
                Button { sheet = .label } label: { Label("Check from photo", systemImage: "camera.viewfinder") }.font(.subheadline)
            }
            HStack(spacing: 12) {
                switch equipment.hasArcFlashLabel {
                case true?:
                    Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text("Label present").font(.subheadline.weight(.semibold))
                        if !equipment.arcFlashDetails.isEmpty { Text(equipment.arcFlashDetails).font(.caption).foregroundStyle(.secondary) }
                    }
                case false?:
                    Image(systemName: "exclamationmark.shield.fill").font(.title2).foregroundStyle(.red)
                    Text("No arc flash label found").font(.subheadline.weight(.semibold))
                case nil:
                    Image(systemName: "questionmark.circle").font(.title2).foregroundStyle(.secondary)
                    Text(equipment.kind.expectsArcFlashLabel ? "Not checked yet" : "Not typically required for this equipment")
                        .font(.subheadline)
                }
                Spacer()
                if let data = equipment.labelPhoto, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var scheduleCard: some View {
        Card {
            CardHeader(title: "Panel Schedule (\(equipment.circuits.count) circuits)") {
                Button { sheet = .schedule } label: { Label(equipment.circuits.isEmpty ? "Scan" : "Re-scan", systemImage: "doc.viewfinder") }
                    .font(.subheadline)
            }
            if equipment.circuits.isEmpty {
                Text("Photograph the panel directory card to digitize every circuit.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                CircuitTable(circuits: equipment.circuits)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                equipment.status = .confirmed
                try? context.save()
            } label: { Label("Confirm Data", systemImage: "checkmark").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .disabled(equipment.status == .confirmed)
            Button { sheet = .flag } label: { Label("Add Flag", systemImage: "flag").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .controlSize(.large)
    }
}

struct CircuitTable: View {
    let circuits: [Circuit]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Ckt"); Text("Description"); Text("Breaker").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Divider()
            ForEach(circuits) { c in
                GridRow {
                    Text("\(c.number)").monospacedDigit()
                    Text(c.description).lineLimit(1)
                    Text(c.breakerAmps.map { "\($0)A" + (c.poles.map { "/\($0)P" } ?? "") } ?? "—").monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(c.description.contains("SPARE") || c.description.contains("SPACE") ? .secondary : .primary)
            }
        }
    }
}

struct EquipmentEditView: View {
    @Environment(\.dismiss) private var dismiss
    let equipment: Equipment
    @State private var draft = EquipmentDraft()

    var body: some View {
        NavigationStack {
            Form {
                EquipmentFormFields(draft: $draft)
                Section("Arc flash") {
                    Picker("Arc flash label", selection: $draft.arcFlash) {
                        ForEach(ArcFlashChoice.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
            }
            .navigationTitle("Edit Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                var d = EquipmentDraft()
                d.tag = equipment.tag; d.kind = equipment.kind; d.manufacturer = equipment.manufacturer
                d.model = equipment.model; d.serial = equipment.serial; d.voltage = equipment.voltage
                d.amperage = equipment.amperage; d.phase = equipment.phase; d.kva = equipment.kva
                d.tonnage = equipment.tonnage; d.refrigerant = equipment.refrigerant
                d.year = equipment.manufactureYear.map(String.init) ?? ""; d.location = equipment.location
                d.notes = equipment.notes; d.arcFlash = ArcFlashChoice(equipment.hasArcFlashLabel)
                draft = d
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { draft.apply(to: equipment); dismiss() }
                }
            }
        }
    }
}

/// Photograph the arc flash label; OCR confirms it and pulls incident energy / PPE category.
struct ArcFlashLabelCheckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let equipment: Equipment

    @State private var image: UIImage?
    @State private var result: ArcFlashResult?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "bolt.shield").font(.system(size: 56)).foregroundStyle(.orange).padding(.top, 24)
                        Text("Photograph the arc flash label on \(equipment.displayName)").font(.title3.bold()).multilineTextAlignment(.center)
                        Text("If there is no label, take a photo of the enclosure front as evidence.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if working { ProgressView("Checking label…") }
                    if let result {
                        Card {
                            if result.detected {
                                Label("Arc flash label detected", systemImage: "checkmark.shield.fill").foregroundStyle(.green).font(.headline)
                                if !result.summary.isEmpty { Text(result.summary).font(.subheadline) }
                                Text("Found: " + result.matchedTerms.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Label("No arc flash label text found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.headline)
                                Text("If the label is present but unreadable (faded, glare), mark it present manually.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button { save(present: true) } label: { Text("Label Present").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).tint(.green)
                            Button { save(present: false) } label: { Text("Label Missing").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).tint(.red)
                        }
                        .controlSize(.large)
                    }
                    ImageSourceButtons(scanLabel: "Scan Label") { picked in
                        image = picked
                        working = true
                        Task {
                            let lines = (try? await TextRecognizer.recognize(picked)) ?? []
                            result = ArcFlashDetector.analyze(lines.map(\.text).joined(separator: "\n"))
                            working = false
                        }
                    }
                    .frame(maxWidth: 420)
                }
                .padding()
            }
            .navigationTitle("Arc Flash Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save(present: Bool) {
        equipment.hasArcFlashLabel = present
        equipment.labelPhoto = image?.storageJPEG()
        if present {
            equipment.arcFlashDetails = result?.summary ?? ""
            for flag in equipment.site?.openFlags ?? [] where flag.equipmentTag == equipment.tag && flag.title.localizedCaseInsensitiveContains("arc flash") {
                flag.resolved = true
                flag.resolvedAt = .now
            }
            if equipment.status == .flagged && (equipment.site?.openFlags.allSatisfy { $0.equipmentTag != equipment.tag } ?? true) {
                equipment.status = .captured
            }
        } else if let site = equipment.site,
                  !site.openFlags.contains(where: { $0.equipmentTag == equipment.tag && $0.title.localizedCaseInsensitiveContains("arc flash") }) {
            let flag = ComplianceFlag(title: "Missing arc flash label on \(equipment.displayName)",
                                      detail: "No arc flash warning label found on the \(equipment.kind.rawValue.lowercased()).",
                                      severity: .critical, equipmentTag: equipment.tag, reference: "NEC 110.16 / NFPA 70E 130.5(H)")
            context.insert(flag)
            flag.site = site
            equipment.status = .flagged
        }
        try? context.save()
        dismiss()
    }
}

struct PanelScheduleCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let equipment: Equipment

    @State private var circuits: [Circuit] = []
    @State private var working = false
    @State private var scanned = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ImageSourceButtons(scanLabel: "Scan Panel Directory") { picked in
                        working = true
                        Task {
                            let lines = (try? await TextRecognizer.recognize(picked)) ?? []
                            circuits = PanelScheduleParser.parse(lines)
                            scanned = true
                            working = false
                        }
                    }
                    .listRowBackground(Color.clear)
                    if working { ProgressView("Reading schedule…") }
                } footer: {
                    Text("Works best with the document scanner, square to the directory card. Two-column schedules (odd/even) are supported.")
                }

                if scanned || !circuits.isEmpty {
                    Section(circuits.isEmpty ? "No circuits recognized — add them manually" : "\(circuits.count) circuits — tap to correct") {
                        ForEach($circuits) { $c in
                            HStack {
                                TextField("#", value: $c.number, format: .number).keyboardType(.numberPad).frame(width: 36).monospacedDigit()
                                TextField("Description", text: $c.description).textInputAutocapitalization(.characters)
                                TextField("A", value: $c.breakerAmps, format: .number).keyboardType(.numberPad).frame(width: 50)
                                    .multilineTextAlignment(.trailing)
                                Text("A").foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { circuits.remove(atOffsets: $0) }
                        Button { circuits.append(Circuit(number: (circuits.map(\.number).max() ?? 0) + 1, description: "", breakerAmps: 20, poles: 1)) } label: {
                            Label("Add circuit", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle("Panel Schedule · \(equipment.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { circuits = equipment.circuits }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        equipment.circuits = circuits.sorted { $0.number < $1.number }
                        dismiss()
                    }
                }
            }
        }
    }
}
