import SwiftData
import SwiftUI

enum ArcFlashChoice: String, CaseIterable {
    case present = "Label present"
    case missing = "Label missing"
    case unchecked = "Not checked"

    init(_ value: Bool?) {
        switch value {
        case true?: self = .present
        case false?: self = .missing
        case nil: self = .unchecked
        }
    }

    var value: Bool? {
        switch self {
        case .present: true
        case .missing: false
        case .unchecked: nil
        }
    }
}

/// Capture → on-device OCR → review & correct → save. Raises an arc flash flag when a label is expected but missing.
struct NameplateCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let site: Site

    enum Step { case source, processing, review }
    @State private var step: Step = .source
    @State private var image: UIImage?
    @State private var result = NameplateResult()
    @State private var draft = EquipmentDraft()
    @State private var createFlag = true
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .source: sourceStep
                case .processing: ProgressView("Reading nameplate…").controlSize(.large)
                case .review: reviewStep
                }
            }
            .navigationTitle("Capture Nameplate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if step == .review {
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
                }
            }
        }
    }

    private var sourceStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "text.viewfinder").font(.system(size: 56)).foregroundStyle(Color.accentColor).padding(.top, 30)
                Text("Photograph the equipment nameplate").font(.title3.bold())
                Text("Fill the frame with the plate and avoid glare. FieldSight reads manufacturer, model, serial, voltage, amperage, kVA, tonnage and refrigerant on-device — nothing is uploaded. If the arc flash label is in the shot, it's checked too.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                ImageSourceButtons(scanLabel: "Scan Nameplate") { process($0) }
                    .frame(maxWidth: 420)
                Button("Enter manually instead") {
                    draft = EquipmentDraft()
                    step = .review
                }
                if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }
            }
            .padding()
        }
    }

    private var reviewStep: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240).frame(maxWidth: .infinity)
                    if !result.rawText.isEmpty {
                        Label("\(result.fieldCount) fields read from the photo — check them against the plate.",
                              systemImage: result.fieldCount >= 3 ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(result.fieldCount >= 3 ? .green : .orange)
                    }
                }
            }
            EquipmentFormFields(draft: $draft)

            Section {
                Picker("Arc flash label", selection: $draft.arcFlash) {
                    ForEach(ArcFlashChoice.allCases, id: \.self) { Text($0.rawValue) }
                }
                if result.arcFlash.detected {
                    Label("Arc flash label detected in photo" + (result.arcFlash.summary.isEmpty ? "" : ": \(result.arcFlash.summary)"),
                          systemImage: "checkmark.shield.fill").foregroundStyle(.green).font(.footnote)
                } else if draft.kind.expectsArcFlashLabel && image != nil {
                    Label("No arc flash label text found in this photo. Confirm on site — the label may be elsewhere on the enclosure.",
                          systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.footnote)
                }
                if draft.kind.expectsArcFlashLabel && draft.arcFlash == .missing {
                    Toggle("Create compliance flag", isOn: $createFlag)
                }
            } header: {
                Text("Arc flash")
            } footer: {
                if draft.kind.expectsArcFlashLabel {
                    Text("\(draft.kind.rawValue) equipment is expected to carry an arc flash warning label (NEC 110.16, NFPA 70E 130.5(H)).")
                }
            }

            if !result.rawText.isEmpty {
                Section("Recognized text") {
                    Text(result.rawText).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    private func process(_ picked: UIImage) {
        image = picked
        step = .processing
        errorText = nil
        Task {
            do {
                let lines = try await TextRecognizer.recognize(picked)
                let parsed = NameplateParser.parse(lines)
                result = parsed
                draft = EquipmentDraft(parsed)
                if parsed.arcFlash.detected { draft.arcFlash = .present }
                else if parsed.kind.expectsArcFlashLabel { draft.arcFlash = .missing }
                step = .review
            } catch {
                errorText = "Couldn't read that image: \(error.localizedDescription)"
                step = .source
            }
        }
    }

    private func save() {
        let e = Equipment()
        context.insert(e)
        draft.apply(to: e)
        e.rawText = result.rawText
        e.arcFlashDetails = result.arcFlash.summary
        e.photo = image?.storageJPEG()
        e.site = site
        if draft.kind.expectsArcFlashLabel && draft.arcFlash == .missing && createFlag {
            let flag = ComplianceFlag(title: "Missing arc flash label on \(e.displayName)",
                                      detail: "No arc flash warning label found on the \(e.kind.rawValue.lowercased()).",
                                      severity: .critical, equipmentTag: e.tag, reference: "NEC 110.16 / NFPA 70E 130.5(H)")
            context.insert(flag)
            flag.site = site
            e.status = .flagged
        }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

struct EquipmentDraft {
    var tag = ""
    var kind: EquipmentKind = .other
    var manufacturer = ""
    var model = ""
    var serial = ""
    var voltage = ""
    var amperage = ""
    var phase = ""
    var kva = ""
    var tonnage = ""
    var refrigerant = ""
    var year = ""
    var location = ""
    var notes = ""
    var arcFlash: ArcFlashChoice = .unchecked

    init() {}

    init(_ r: NameplateResult) {
        tag = r.tag; kind = r.kind; manufacturer = r.manufacturer; model = r.model; serial = r.serial
        voltage = r.voltage; amperage = r.amperage; phase = r.phase; kva = r.kva; tonnage = r.tonnage
        refrigerant = r.refrigerant; year = r.year.map(String.init) ?? ""
    }

    func apply(to e: Equipment) {
        e.tag = tag.uppercased()
        e.kind = kind
        e.manufacturer = manufacturer
        e.model = model
        e.serial = serial
        e.voltage = voltage
        e.amperage = amperage
        e.phase = phase
        e.kva = kva
        e.tonnage = tonnage
        e.refrigerant = refrigerant
        e.manufactureYear = Int(year)
        e.location = location
        e.notes = notes
        e.hasArcFlashLabel = arcFlash.value
    }
}

struct EquipmentFormFields: View {
    @Binding var draft: EquipmentDraft

    var body: some View {
        Section("Identification") {
            TextField("Tag (e.g. MDP-2, RTU-4)", text: $draft.tag).textInputAutocapitalization(.characters)
            Picker("Type", selection: $draft.kind) {
                ForEach(EquipmentKind.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            TextField("Location (e.g. Electrical Room 2B)", text: $draft.location)
        }
        Section("Nameplate") {
            LabeledContent("Manufacturer") { TextField("—", text: $draft.manufacturer).multilineTextAlignment(.trailing) }
            LabeledContent("Model") { TextField("—", text: $draft.model).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters) }
            LabeledContent("Serial") { TextField("—", text: $draft.serial).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters) }
            LabeledContent("Voltage") { TextField("—", text: $draft.voltage).multilineTextAlignment(.trailing) }
            LabeledContent("Amperage") { TextField("—", text: $draft.amperage).multilineTextAlignment(.trailing) }
            LabeledContent("Phase") { TextField("—", text: $draft.phase).multilineTextAlignment(.trailing).keyboardType(.numberPad) }
            if !draft.kind.isHVAC || !draft.kva.isEmpty {
                LabeledContent("kVA") { TextField("—", text: $draft.kva).multilineTextAlignment(.trailing) }
            }
            if draft.kind.isHVAC || !draft.tonnage.isEmpty {
                LabeledContent("Tonnage") { TextField("—", text: $draft.tonnage).multilineTextAlignment(.trailing) }
                LabeledContent("Refrigerant") { TextField("—", text: $draft.refrigerant).multilineTextAlignment(.trailing) }
            }
            LabeledContent("Year made") { TextField("—", text: $draft.year).multilineTextAlignment(.trailing).keyboardType(.numberPad) }
        }
        Section("Notes") {
            TextField("Condition, feeders, observations…", text: $draft.notes, axis: .vertical).lineLimit(2...6)
        }
    }
}
