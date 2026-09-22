import SwiftData
import SwiftUI

@main
struct EnerVectorApp: App {
    let container: ModelContainer = {
        let schema = Schema([Site.self, Equipment.self, ComplianceFlag.self, RoomScan.self, RunSegment.self, RoofSurvey.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        UserDefaults.standard.register(defaults: [
            AppSettings.moduleWatts: 450.0,
            AppSettings.moduleAreaSqFt: 23.5,
            AppSettings.specificYield: 1250.0,
            AppSettings.kwPerTon: 1.2,
            AppSettings.wattsPerSqFt: 3.0,
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task { SampleData.seedIfNeeded(container.mainContext) }
        }
        .modelContainer(container)
    }
}

enum AppTab: Hashable {
    case dashboard, sites, captures, reports, settings
}

struct RootView: View {
    @State private var selection: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "square.grid.2x2", value: AppTab.dashboard) {
                NavigationStack { DashboardView().withAppDestinations() }
            }
            Tab("Sites", systemImage: "building.2", value: AppTab.sites) {
                NavigationStack { SitesListView().withAppDestinations() }
            }
            Tab("Captures", systemImage: "camera.viewfinder", value: AppTab.captures) {
                NavigationStack { CapturesView().withAppDestinations() }
            }
            Tab("Reports", systemImage: "doc.richtext", value: AppTab.reports) {
                NavigationStack { ReportsListView().withAppDestinations() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

extension View {
    func withAppDestinations() -> some View {
        navigationDestination(for: Site.self) { SiteDetailView(site: $0) }
            .navigationDestination(for: Equipment.self) { EquipmentDetailView(equipment: $0) }
            .navigationDestination(for: RoomScan.self) { RoomScanDetailView(scan: $0) }
            .navigationDestination(for: RoofSurvey.self) { RoofSurveyView(survey: $0) }
    }
}
