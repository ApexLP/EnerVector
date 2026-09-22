import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Site.createdAt, order: .reverse) private var sites: [Site]
    @Query private var equipment: [Equipment]
    @Query private var flags: [ComplianceFlag]
    @Query private var scans: [RoomScan]
    @Query private var roofs: [RoofSurvey]
    @AppStorage(AppSettings.technicianName) private var technician = ""
    @State private var showNewSite = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let first = technician.split(separator: " ").first.map(String.init)
        return first.map { "\(part), \($0)" } ?? part
    }

    private var avgComplete: Double {
        guard !sites.isEmpty else { return 0 }
        return sites.map(\.progress).reduce(0, +) / Double(sites.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let layout = sizeClass == .compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(.largeTitle.bold())
                        Text("Here's what's happening across your projects.").foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).month().day().year())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: ResponsiveColumns.make(sizeClass), spacing: 12) {
                    StatTile(value: "\(sites.count)", label: "Active Sites", symbol: "building.2.fill")
                    StatTile(value: "\(flags.filter { !$0.resolved }.count)", label: "Open Flags", symbol: "flag.fill", color: .red)
                    StatTile(value: "\(equipment.count + scans.count + roofs.count)", label: "Captures", symbol: "camera.fill", color: .indigo)
                    StatTile(value: Units.percent(avgComplete), label: "Avg Complete", symbol: "chart.bar.fill", color: .green)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        siteGrid.frame(minWidth: 520, maxWidth: .infinity)
                        activity.frame(width: 320)
                    }
                    VStack(spacing: 16) {
                        siteGrid
                        activity
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { showNewSite = true } label: { Label("New Site", systemImage: "plus") }
        }
        .sheet(isPresented: $showNewSite) { SiteEditorView() }
    }

    private var siteGrid: some View {
        Group {
            if sites.isEmpty {
                Card {
                    ContentUnavailableView {
                        Label("No sites yet", systemImage: "building.2")
                    } description: {
                        Text("Create a site to start capturing nameplates, rooms and runs.")
                    } actions: {
                        Button("New Site") { showNewSite = true }.buttonStyle(.borderedProminent)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(sites) { site in
                        NavigationLink(value: site) { SiteCard(site: site) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var activity: some View {
        Card {
            CardHeader("Recent Activity")
            let items = ActivityItem.feed(equipment: equipment, flags: flags, scans: scans, roofs: roofs).prefix(8)
            if items.isEmpty {
                Text("Captures and flags will show up here.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(items)) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(item.color)
                        .frame(width: 30, height: 30)
                        .background(item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.date.relativeShort).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SiteCard: View {
    let site: Site

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisciplineThumbnail(site: site).frame(height: 110)
            VStack(alignment: .leading, spacing: 8) {
                Text(site.name).font(.headline).lineLimit(1)
                Badge(text: site.discipline.rawValue, color: site.discipline.color)
                HStack {
                    Label(site.address.isEmpty ? "No address" : site.address, systemImage: "mappin.and.ellipse")
                        .lineLimit(1)
                    Spacer()
                    Text(Units.percent(site.progress)).bold().foregroundStyle(.primary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                LinearProgress(value: site.progress, color: site.discipline.color)
                HStack {
                    Text(site.lastActivity.map { "Last capture \($0.relativeShort)" } ?? "No captures yet")
                    Spacer()
                    if !site.openFlags.isEmpty {
                        Label("\(site.openFlags.count)", systemImage: "flag.fill").foregroundStyle(.red)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let date: Date
    let symbol: String
    let color: Color

    static func feed(equipment: [Equipment], flags: [ComplianceFlag], scans: [RoomScan], roofs: [RoofSurvey]) -> [ActivityItem] {
        var items: [ActivityItem] = []
        items += equipment.map {
            ActivityItem(title: $0.kind.isHVAC ? "Nameplate captured" : "\($0.kind.rawValue) captured",
                         subtitle: "\($0.displayName) · \($0.site?.name ?? "")", date: $0.capturedAt, symbol: "camera.viewfinder", color: .blue)
        }
        items += flags.map {
            ActivityItem(title: $0.title, subtitle: $0.site?.name ?? "", date: $0.resolvedAt ?? $0.createdAt,
                         symbol: $0.resolved ? "checkmark.seal.fill" : "flag.fill", color: $0.resolved ? .green : .red)
        }
        items += scans.map {
            ActivityItem(title: "Room scanned", subtitle: "\($0.name) · \($0.site?.name ?? "")", date: $0.capturedAt,
                         symbol: "cube.transparent", color: .indigo)
        }
        items += roofs.map {
            ActivityItem(title: "Roof surveyed", subtitle: "\($0.name) · \($0.site?.name ?? "")", date: $0.capturedAt,
                         symbol: "sun.max.fill", color: .orange)
        }
        return items.sorted { $0.date > $1.date }
    }
}
