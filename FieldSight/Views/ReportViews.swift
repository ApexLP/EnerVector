import SwiftData
import SwiftUI

struct ReportsListView: View {
    @Query(sort: \Site.name) private var sites: [Site]
    @State private var composing: Site?

    var body: some View {
        List {
            Section {
                ForEach(sites) { site in
                    Button { composing = site } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .font(.title3)
                                .foregroundStyle(site.discipline.color)
                                .frame(width: 40, height: 40)
                                .background(site.discipline.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.name).font(.headline).foregroundStyle(.primary)
                                Text("\(ReportComposerView.defaultTitle(for: site)) · \(site.captureCount) captures · \(site.openFlags.count) open flags")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            } footer: {
                Text("Reports are generated on-device as PDF. Share them by email, AirDrop, Files, or any app on the share sheet.")
            }
        }
        .overlay {
            if sites.isEmpty { ContentUnavailableView("No sites", systemImage: "doc.richtext", description: Text("Create a site to build a report.")) }
        }
        .navigationTitle("Reports")
        .sheet(item: $composing) { site in NavigationStack { ReportComposerView(site: site) }.presentationSizing(.page) }
    }
}

struct ReportComposerView: View {
    @Environment(\.dismiss) private var dismiss
    let site: Site

    @AppStorage(AppSettings.technicianName) private var technician = ""
    @AppStorage(AppSettings.companyName) private var company = ""
    @AppStorage(AppSettings.kwPerTon) private var kwPerTon = 1.2
    @AppStorage(AppSettings.wattsPerSqFt) private var wattsPerSqFt = 3.0

    @State private var options = ReportOptions()
    @State private var generated: GeneratedReport?
    @State private var working = false

    static func defaultTitle(for site: Site) -> String {
        switch site.discipline {
        case .electrical: "Electrical Field Report"
        case .dataCenter: "Data Center Electrical As-Built"
        case .energyAudit: "Energy Audit Report"
        case .solarSurvey: "Solar Site Survey"
        }
    }

    var body: some View {
        Form {
            Section("Report") {
                LabeledContent("Title") { TextField("Title", text: $options.title).multilineTextAlignment(.trailing) }
                LabeledContent("Prepared for") { TextField("Client", text: $options.preparedFor).multilineTextAlignment(.trailing) }
                TextField("Summary / key findings", text: $options.summary, axis: .vertical).lineLimit(3...10)
            }
            Section("Include") {
                if !site.flags.isEmpty { Toggle("Compliance flags (\(site.flags.count))", isOn: $options.includeFlags) }
                if !site.equipment.isEmpty { Toggle("Equipment & nameplates (\(site.equipment.count))", isOn: $options.includeEquipment) }
                if site.equipment.contains(where: { !$0.circuits.isEmpty }) { Toggle("Panel schedules", isOn: $options.includeSchedules) }
                if !site.roomScans.isEmpty { Toggle("As-built floor plans (\(site.roomScans.count))", isOn: $options.includeRoomScans) }
                if !site.segments.isEmpty { Toggle("Conduit & tray progress", isOn: $options.includeRuns) }
                if !site.roofSurveys.isEmpty { Toggle("Roof & solar summary", isOn: $options.includeRoof) }
                if site.discipline == .energyAudit || site.equipment.contains(where: { $0.kind.isHVAC }) {
                    Toggle("Load estimate", isOn: $options.includeLoad)
                }
                if site.equipment.contains(where: { $0.photo != nil || $0.labelPhoto != nil }) { Toggle("Photo log", isOn: $options.includePhotos) }
            }
            if technician.isEmpty || company.isEmpty {
                Section {
                    Label("Add your name and company in Settings so they appear on the report.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Build Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if working { ProgressView() } else { Button("Generate PDF", action: generate).bold() }
            }
        }
        .onAppear {
            if options.title.isEmpty { options.title = Self.defaultTitle(for: site) }
            if options.preparedFor.isEmpty { options.preparedFor = site.client }
        }
        .navigationDestination(item: $generated) { ReportPreviewView(report: $0, site: site) }
    }

    private func generate() {
        working = true
        let author = ReportAuthor(technician: technician, company: company, kwPerTon: kwPerTon, wattsPerSqFt: wattsPerSqFt)
        let data = PDFReportBuilder.build(site: site, options: options, author: author)
        let name = "\(site.name) - \(options.title)".fileSafe
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pdfURL = dir.appendingPathComponent("\(name).pdf")
        try? data.write(to: pdfURL)

        var csvURL: URL?
        if !site.equipment.isEmpty {
            let url = dir.appendingPathComponent("\(site.name.fileSafe) - Equipment.csv")
            if (try? CSVExporter.equipment(site.equipment).write(to: url, atomically: true, encoding: .utf8)) != nil { csvURL = url }
        }
        generated = GeneratedReport(title: options.title, pdf: data, pdfURL: pdfURL, csvURL: csvURL)
        working = false
    }
}

struct GeneratedReport: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let pdf: Data
    let pdfURL: URL
    let csvURL: URL?
}

struct ReportPreviewView: View {
    let report: GeneratedReport
    let site: Site

    @AppStorage(AppSettings.defaultRecipient) private var defaultRecipient = ""
    @AppStorage(AppSettings.technicianName) private var technician = ""
    @AppStorage(AppSettings.companyName) private var company = ""
    @State private var showMail = false
    @State private var showShare = false
    @State private var status: String?

    var body: some View {
        PDFKitView(data: report.pdf)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(report.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { email() } label: { Label("Email", systemImage: "envelope") }
                    ShareLink(item: report.pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    if let csv = report.csvURL {
                        ShareLink(item: csv) { Label("Export CSV", systemImage: "tablecells") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { email() } label: { Label("Send to Client", systemImage: "paperplane.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    ShareLink(item: report.pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .overlay(alignment: .top) {
                if let status {
                    Text(status).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule()).padding(.top, 8)
                        .task { try? await Task.sleep(for: .seconds(2.5)); self.status = nil }
                }
            }
            .sheet(isPresented: $showMail) {
                MailComposeView(subject: "\(report.title) — \(site.name)",
                                recipients: [defaultRecipient],
                                body: emailBody,
                                attachments: attachments) { result in
                    showMail = false
                    if result == .sent { status = "Email sent" }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [report.pdfURL] + (report.csvURL.map { [$0] } ?? []))
                    .presentationDetents([.medium, .large])
            }
    }

    private var attachments: [MailAttachment] {
        var list = [MailAttachment(data: report.pdf, mimeType: "application/pdf", fileName: report.pdfURL.lastPathComponent)]
        if let csv = report.csvURL, let data = try? Data(contentsOf: csv) {
            list.append(MailAttachment(data: data, mimeType: "text/csv", fileName: csv.lastPathComponent))
        }
        return list
    }

    private var emailBody: String {
        var lines = ["Hello,", "", "Attached is the \(report.title.lowercased()) for \(site.name)."]
        let open = site.openFlags.count
        if open > 0 { lines.append("There \(open == 1 ? "is 1 open finding" : "are \(open) open findings") that need attention.") }
        lines += ["", "Thanks,"]
        let signature = [technician, company].filter { !$0.isEmpty }
        lines += signature.isEmpty ? [""] : signature
        return lines.joined(separator: "\n")
    }

    private func email() {
        if MailComposeView.canSend { showMail = true } else { showShare = true }
    }
}
