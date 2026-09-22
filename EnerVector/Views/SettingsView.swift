import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettings.technicianName) private var technician = ""
    @AppStorage(AppSettings.companyName) private var company = ""
    @AppStorage(AppSettings.defaultRecipient) private var recipient = ""
    @AppStorage(AppSettings.moduleWatts) private var moduleWatts = 450.0
    @AppStorage(AppSettings.moduleAreaSqFt) private var moduleArea = 23.5
    @AppStorage(AppSettings.specificYield) private var specificYield = 1250.0
    @AppStorage(AppSettings.kwPerTon) private var kwPerTon = 1.2
    @AppStorage(AppSettings.wattsPerSqFt) private var wattsPerSqFt = 3.0
    @Query private var sites: [Site]
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $technician).textContentType(.name)
                TextField("Company", text: $company).textContentType(.organizationName)
                TextField("Default report recipient", text: $recipient)
                    .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            } header: {
                Text("Report author")
            } footer: {
                Text("Shown on every PDF report and pre-filled when emailing reports.")
            }

            Section("Solar defaults") {
                NumberField(title: "Module rating", value: $moduleWatts, unit: "W")
                NumberField(title: "Module footprint", value: $moduleArea, unit: "sq ft")
                NumberField(title: "Specific yield", value: $specificYield, unit: "kWh/kWp")
            }

            Section {
                NumberField(title: "HVAC", value: $kwPerTon, unit: "kW/ton")
                NumberField(title: "Lighting & plug", value: $wattsPerSqFt, unit: "W/sq ft")
            } header: {
                Text("Load estimate")
            } footer: {
                Text("Planning-level assumptions used for the connected-load estimate on energy audits.")
            }

            Section("Device capabilities") {
                capability("LiDAR room scanning (RoomPlan)", RoomScanner.isSupported)
                capability("AR measuring (ARKit)", ARMeasure.isSupported)
                capability("LiDAR depth for AR", ARMeasure.hasLiDAR)
                capability("Mail app configured", MailComposeView.canSend)
            }

            Section {
                if sites.contains(where: \.isSample) {
                    Button("Remove sample data", role: .destructive) { confirmRemove = true }
                } else {
                    Button("Load sample data") { SampleData.insert(into: context) }
                }
            } footer: {
                Text("All captures are stored on this device. Text recognition and measurements run on-device.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Remove the sample sites and all of their captures?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove sample data", role: .destructive) { SampleData.removeAll(from: context) }
        }
    }

    private func capability(_ label: String, _ available: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}
