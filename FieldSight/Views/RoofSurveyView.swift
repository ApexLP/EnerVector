import SwiftData
import SwiftUI

/// Roof area & obstructions (AR-traced or entered) → usable area → module count, kW and annual kWh.
struct RoofSurveyView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let survey: RoofSurvey?
    var site: Site?

    @AppStorage(AppSettings.moduleWatts) private var defaultWatts = 450.0
    @AppStorage(AppSettings.moduleAreaSqFt) private var defaultModuleArea = 23.5
    @AppStorage(AppSettings.specificYield) private var defaultYield = 1250.0

    @State private var name = "Main Roof"
    @State private var total = 0.0
    @State private var obstruction = 0.0
    @State private var setback = 10.0
    @State private var watts = 450.0
    @State private var moduleArea = 23.5
    @State private var yield = 1250.0
    @State private var notes = ""
    @State private var plan = RoofPlan()
    @State private var loaded = false

    enum Tracing: Identifiable { case outline, obstruction; var id: Self { self } }
    @State private var tracing: Tracing?
    @State private var obstructionLabel = "HVAC"

    init(survey: RoofSurvey?, site: Site? = nil) {
        self.survey = survey
        self.site = site ?? survey?.site
    }

    private var usable: Double { max(0, (total - obstruction) * (1 - setback / 100)) }
    private var modules: Int { moduleArea > 0 ? Int(usable / moduleArea) : 0 }
    private var kw: Double { Double(modules) * watts / 1000 }

    var body: some View {
        Form {
            Section {
                TextField("Roof name", text: $name)
                RoofPlanImage(plan: plan, height: 220).listRowInsets(EdgeInsets())
            }

            Section {
                if ARMeasure.isSupported {
                    Button { tracing = .outline } label: { Label(plan.outline.isEmpty ? "Trace roof outline with AR" : "Re-trace roof outline", systemImage: "skew") }
                    HStack {
                        Button { tracing = .obstruction } label: { Label("Trace obstruction", systemImage: "square.dashed") }
                        Spacer()
                        Picker("", selection: $obstructionLabel) {
                            ForEach(["HVAC", "Skylight", "Vent", "Hatch", "Parapet", "Other"], id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                    }
                }
                NumberField(title: "Total roof area", value: $total, unit: "sq ft")
                NumberField(title: "Obstructions", value: $obstruction, unit: "sq ft")
                if !plan.obstructions.isEmpty {
                    ForEach(Array(plan.obstructions.enumerated()), id: \.offset) { i, obs in
                        KeyValueRow(key: "  \(obs.label) \(i + 1)", value: "\(Units.number(Units.sqFt(obs.area))) sq ft")
                    }
                    .onDelete { offsets in
                        plan.obstructions.remove(atOffsets: offsets)
                        obstruction = plan.obstructions.reduce(0) { $0 + Units.sqFt($1.area) }
                    }
                }
                NumberField(title: "Fire setback / spacing", value: $setback, unit: "%")
            } header: {
                Text("Measurements")
            } footer: {
                Text(ARMeasure.isSupported
                     ? "On the roof, drop a point at each corner. Areas use the true 3D surface, so pitched roofs aren't under-counted.\(ARMeasure.hasLiDAR ? " LiDAR improves accuracy at range." : "")"
                     : "AR tracing needs an ARKit device. Enter areas from drawings or aerial imagery.")
            }

            Section("Module assumptions") {
                NumberField(title: "Module rating", value: $watts, unit: "W")
                NumberField(title: "Module footprint", value: $moduleArea, unit: "sq ft")
                NumberField(title: "Specific yield", value: $yield, unit: "kWh/kWp")
            }

            Section("Solar summary") {
                summaryRow("Usable roof area", "\(Units.number(usable)) sq ft")
                summaryRow("Estimated modules", "\(modules)")
                summaryRow("Estimated capacity", "\(Units.number(kw, digits: 1)) kW")
                summaryRow("Annual production (est.)", "\(Units.number(kw * yield)) kWh")
            }

            Section("Notes") { TextField("Roof condition, access, shading…", text: $notes, axis: .vertical).lineLimit(2...6) }

            if survey != nil {
                Section {
                    Button("Delete Survey", role: .destructive) {
                        if let survey { context.delete(survey) }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(survey == nil ? "Roof Survey" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if survey == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(total <= 0) }
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $tracing) { mode in
            ARMeasureScreen(mode: .area, title: mode == .outline ? "Roof outline" : obstructionLabel) { result in
                tracing = nil
                guard let result else { return }
                switch mode {
                case .outline:
                    plan.outline = result.plan
                    total = result.areaSqFt
                case .obstruction:
                    plan.obstructions.append(PlanPolygon(label: obstructionLabel, points: result.plan))
                    obstruction += result.areaSqFt
                }
            }
            .ignoresSafeArea()
        }
    }

    private func summaryRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer()
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let s = survey {
            name = s.name; total = s.totalAreaSqFt; obstruction = s.obstructionAreaSqFt; setback = s.setbackPercent
            watts = s.moduleWatts; moduleArea = s.moduleAreaSqFt; yield = s.specificYield; notes = s.notes; plan = s.plan
        } else {
            watts = defaultWatts; moduleArea = defaultModuleArea; yield = defaultYield
        }
    }

    private func save() {
        let target = survey ?? RoofSurvey(name: name)
        if survey == nil {
            context.insert(target)
            target.site = site
        }
        target.name = name
        target.totalAreaSqFt = total
        target.obstructionAreaSqFt = obstruction
        target.setbackPercent = setback
        target.moduleWatts = watts
        target.moduleAreaSqFt = moduleArea
        target.specificYield = yield
        target.notes = notes
        target.plan = plan
        target.capturedAt = .now
        try? context.save()
        dismiss()
    }
}
