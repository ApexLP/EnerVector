import Foundation
import SwiftData

/// Demo content so the app is explorable on first launch (and in the Simulator, which has no camera or LiDAR).
/// Settings → "Remove sample data" clears it.
enum SampleData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppSettings.didSeed) else { return }
        defaults.set(true, forKey: AppSettings.didSeed)
        let count = (try? context.fetchCount(FetchDescriptor<Site>())) ?? 0
        guard count == 0 else { return }
        insert(into: context)
    }

    @MainActor
    static func removeAll(from context: ModelContext) {
        let sites = (try? context.fetch(FetchDescriptor<Site>())) ?? []
        for site in sites where site.isSample { context.delete(site) }
        try? context.save()
    }

    private static func ago(hours: Double) -> Date { Date.now.addingTimeInterval(-hours * 3600) }

    @MainActor
    static func insert(into context: ModelContext) {
        // 1. Data center electrical room
        let dc = Site(name: "Ashburn DC3", client: "Hyperscale Campus", address: "Ashburn, VA",
                      discipline: .dataCenter, createdAt: ago(hours: 400))
        context.insert(dc)
        dc.isSample = true

        let mdp = Equipment(tag: "MDP-2", kind: .switchboard, manufacturer: "Square D", model: "QED-2", serial: "SD-88213",
                            voltage: "480Y/277V", amperage: "2000A", phase: "3", location: "Electrical Room 2B",
                            notes: "Fed from utility main", hasArcFlashLabel: false, status: .flagged, capturedAt: ago(hours: 2))
        mdp.circuits = [
            Circuit(number: 1, description: "LP-3A FEEDER", breakerAmps: 225, poles: 3),
            Circuit(number: 2, description: "PP-2 FEEDER", breakerAmps: 400, poles: 3),
            Circuit(number: 3, description: "TX-1 PRIMARY", breakerAmps: 150, poles: 3),
            Circuit(number: 4, description: "SPARE", breakerAmps: 225, poles: 3),
        ]
        let items: [Equipment] = [
            mdp,
            Equipment(tag: "LP-3A", kind: .panelboard, manufacturer: "Square D", model: "NQ442L2C", serial: "SD-90117",
                      voltage: "208Y/120V", amperage: "225A", phase: "3", location: "Electrical Room 2B",
                      hasArcFlashLabel: true, arcFlashDetails: "Incident energy 1.2 cal/cm² · PPE 1", status: .confirmed, capturedAt: ago(hours: 5)),
            Equipment(tag: "TX-1", kind: .transformer, manufacturer: "Eaton", model: "V48M28T75EE", serial: "EA-44120",
                      voltage: "480V / 208Y/120V", phase: "3", kva: "75 kVA", location: "Electrical Room 2B",
                      hasArcFlashLabel: true, status: .confirmed, capturedAt: ago(hours: 6)),
            Equipment(tag: "PP-2", kind: .panelboard, manufacturer: "Siemens", model: "P1C42ML400CTS", serial: "SI-10442",
                      voltage: "480Y/277V", amperage: "400A", phase: "3", location: "Electrical Room 2B",
                      hasArcFlashLabel: true, status: .confirmed, capturedAt: ago(hours: 7)),
            Equipment(tag: "GEN-1", kind: .generator, manufacturer: "Caterpillar", model: "C32", serial: "CAT-7781",
                      voltage: "480V", amperage: "1500A", phase: "3", kva: "1250 kVA", location: "Generator Yard",
                      status: .confirmed, capturedAt: ago(hours: 30)),
        ]
        for e in items { context.insert(e); e.site = dc }
        let lp = items[1]
        lp.circuits = (1...12).map { n in
            Circuit(number: n, description: n % 5 == 0 ? "SPARE" : (n.isMultiple(of: 2) ? "RECEPT RM 2\(n)" : "LIGHTING ZONE \(n)"),
                    breakerAmps: 20, poles: 1)
        }

        let flag = ComplianceFlag(title: "Missing arc flash label on MDP-2", detail: "No arc flash warning label detected on the switchboard front.",
                                  severity: .critical, equipmentTag: "MDP-2", reference: "NEC 110.16 / NFPA 70E 130.5(H)", createdAt: ago(hours: 2))
        context.insert(flag); flag.site = dc

        var room = RoomGeometry.rectangle(width: 7.2, depth: 4.6, doorOnWall: false)
        room.openings.append(PlanSegment(a: PlanPoint(x: 7.2, y: 1.4), b: PlanPoint(x: 7.2, y: 2.5), kind: .door))
        room.objects = [
            PlanObject(label: "MDP-2", center: PlanPoint(x: 2.6, y: 0.35), width: 3.76, depth: 0.6, angle: 0),
            PlanObject(label: "LP-3A", center: PlanPoint(x: 5.6, y: 0.2), width: 0.6, depth: 0.25, angle: 0),
            PlanObject(label: "TX-1", center: PlanPoint(x: 0.6, y: 3.7), width: 0.9, depth: 0.9, angle: 0),
            PlanObject(label: "PP-2", center: PlanPoint(x: 3.2, y: 4.4), width: 0.6, depth: 0.25, angle: 0),
        ]
        let scan = RoomScan(name: "Electrical Room 2B", level: "Level 1", capturedAt: ago(hours: 3),
                            floorAreaSqFt: Units.sqFt(7.2 * 4.6), ceilingHeightFt: 12, fromLiDAR: true, geometry: room)
        context.insert(scan); scan.site = dc

        // 2. Conduit progress
        let loudoun = Site(name: "Loudoun Hyperscale Phase 2", client: "Riverside Electric", address: "Leesburg, VA",
                           discipline: .electrical, createdAt: ago(hours: 300))
        context.insert(loudoun)
        loudoun.isSample = true
        let runs: [RunSegment] = [
            RunSegment(name: "C-12", type: .conduit, area: "Elec Room 2A", plannedFt: 220, installedFt: 60, updatedAt: ago(hours: 3)),
            RunSegment(name: "Tray Run A", type: .cableTray, area: "Elec Room 2B", plannedFt: 500, installedFt: 420, updatedAt: ago(hours: 5)),
            RunSegment(name: "Tray Run B", type: .cableTray, area: "Elec Room 2B", plannedFt: 180, installedFt: 180, updatedAt: ago(hours: 28)),
            RunSegment(name: "C-13", type: .conduit, area: "Elec Room 2C", plannedFt: 310, installedFt: 310, updatedAt: ago(hours: 50)),
            RunSegment(name: "C-14", type: .conduit, area: "Elec Room 2C", plannedFt: 275, installedFt: 190, updatedAt: ago(hours: 70)),
        ]
        for r in runs { context.insert(r); r.site = loudoun }

        // 3. Energy audit
        let fairfax = Site(name: "Fairfax Corp HQ", client: "Fairfax Corp", address: "Fairfax, VA",
                           discipline: .energyAudit, createdAt: ago(hours: 200))
        context.insert(fairfax)
        fairfax.isSample = true
        fairfax.buildingSqFtOverride = 48_000
        let rtus: [(String, String, String, String, Int, Double)] = [
            ("RTU-1", "Carrier", "48TC", "20 ton", 2019, 50), ("RTU-2", "Trane", "Voyager", "12.5 ton", 2017, 48),
            ("RTU-3", "Carrier", "48TC", "15 ton", 2015, 30), ("RTU-4", "Trane", "YSC", "15 ton", 2014, 26),
            ("RTU-5", "Daikin", "Rebel", "10 ton", 2018, 24),
        ]
        for (tag, mfg, model, tons, year, hrs) in rtus {
            let e = Equipment(tag: tag, kind: .rtu, manufacturer: mfg, model: model, serial: "\(mfg.prefix(2).uppercased())-\(year)\(tag.suffix(1))0",
                              voltage: "460V", phase: "3", tonnage: tons, refrigerant: "R-410A", manufactureYear: year,
                              location: "Roof", status: .confirmed, capturedAt: ago(hours: hrs))
            context.insert(e); e.site = fairfax
        }
        let meter = Equipment(tag: "M-1", kind: .meter, manufacturer: "Itron", model: "CENTRON", serial: "IT-5530021",
                              voltage: "480V", amperage: "Class 20", phase: "3", location: "Main Electrical",
                              hasArcFlashLabel: true, status: .confirmed, capturedAt: ago(hours: 52))
        context.insert(meter); meter.site = fairfax

        // 4. Solar survey
        let solar = Site(name: "Regency Tower Solar Survey", client: "Regency Properties", address: "Arlington, VA",
                         discipline: .solarSurvey, createdAt: ago(hours: 150))
        context.insert(solar)
        solar.isSample = true
        let outline = [PlanPoint(x: 0, y: 0), PlanPoint(x: 52, y: 0), PlanPoint(x: 52, y: 43), PlanPoint(x: 0, y: 43)]
        let obstructions = [
            PlanPolygon(label: "HVAC", points: [PlanPoint(x: 8, y: 8), PlanPoint(x: 14, y: 8), PlanPoint(x: 14, y: 13), PlanPoint(x: 8, y: 13)]),
            PlanPolygon(label: "HVAC", points: [PlanPoint(x: 30, y: 20), PlanPoint(x: 37, y: 20), PlanPoint(x: 37, y: 26), PlanPoint(x: 30, y: 26)]),
            PlanPolygon(label: "Skylight", points: [PlanPoint(x: 40, y: 32), PlanPoint(x: 46, y: 32), PlanPoint(x: 46, y: 38), PlanPoint(x: 40, y: 38)]),
        ]
        let roof = RoofSurvey(name: "Main Roof", capturedAt: ago(hours: 1), totalAreaSqFt: 24_600, obstructionAreaSqFt: 6_200,
                              plan: RoofPlan(outline: outline, obstructions: obstructions))
        context.insert(roof); roof.site = solar

        // 5. Panel retrofit
        let gng = Site(name: "GNG Panel Retrofit", client: "GNG Electric", address: "Manassas, VA",
                       discipline: .electrical, createdAt: ago(hours: 100))
        context.insert(gng)
        gng.isSample = true
        let old = Equipment(tag: "LP-1", kind: .panelboard, manufacturer: "GE", model: "AQ", voltage: "208Y/120V",
                            amperage: "100A", phase: "3", manufactureYear: 1994, location: "Basement",
                            hasArcFlashLabel: false, status: .flagged, capturedAt: ago(hours: 24))
        context.insert(old); old.site = gng
        let flag2 = ComplianceFlag(title: "Panel cover issue on LP-1", detail: "Dead front has missing knockout filler plates.",
                                   severity: .warning, equipmentTag: "LP-1", reference: "NEC 408.7", createdAt: ago(hours: 24))
        context.insert(flag2); flag2.site = gng

        try? context.save()
    }
}
