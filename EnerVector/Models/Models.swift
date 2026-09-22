import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums

enum Discipline: String, CaseIterable, Identifiable, Codable {
    case electrical = "Electrical"
    case dataCenter = "Data Center"
    case energyAudit = "Energy Audit"
    case solarSurvey = "Solar Survey"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .electrical: .blue
        case .dataCenter: .indigo
        case .energyAudit: .green
        case .solarSurvey: .orange
        }
    }

    var symbol: String {
        switch self {
        case .electrical: "bolt.fill"
        case .dataCenter: "server.rack"
        case .energyAudit: "leaf.fill"
        case .solarSurvey: "sun.max.fill"
        }
    }
}

enum EquipmentKind: String, CaseIterable, Identifiable, Codable {
    case panelboard = "Panelboard"
    case switchboard = "Switchboard / Switchgear"
    case mcc = "Motor Control Center"
    case disconnect = "Disconnect"
    case transformer = "Transformer"
    case ups = "UPS"
    case pdu = "PDU"
    case ats = "Transfer Switch"
    case generator = "Generator"
    case meter = "Meter"
    case rtu = "Rooftop Unit"
    case ahu = "Air Handler"
    case chiller = "Chiller"
    case boiler = "Boiler / Furnace"
    case heatPump = "Heat Pump / Split"
    case other = "Other"

    var id: String { rawValue }

    /// Equipment that NEC 110.16 / NFPA 70E 130.5(H) expects to carry an arc flash label.
    var expectsArcFlashLabel: Bool {
        switch self {
        case .panelboard, .switchboard, .mcc, .disconnect, .transformer, .ups, .pdu, .ats, .meter: true
        default: false
        }
    }

    var isHVAC: Bool {
        switch self {
        case .rtu, .ahu, .chiller, .boiler, .heatPump: true
        default: false
        }
    }

    var hasPanelSchedule: Bool {
        switch self {
        case .panelboard, .switchboard, .pdu, .mcc: true
        default: false
        }
    }

    var symbol: String {
        switch self {
        case .panelboard, .switchboard, .mcc, .disconnect: "square.grid.3x3.square"
        case .transformer: "bolt.horizontal.fill"
        case .ups: "battery.100.bolt"
        case .pdu: "powerplug.fill"
        case .ats: "arrow.triangle.swap"
        case .generator: "engine.combustion.fill"
        case .meter: "gauge.with.dots.needle.67percent"
        case .rtu, .ahu, .heatPump: "fan.fill"
        case .chiller: "snowflake"
        case .boiler: "flame.fill"
        case .other: "shippingbox.fill"
        }
    }
}

enum EquipmentStatus: String, CaseIterable, Codable {
    case captured = "Captured"
    case confirmed = "Confirmed"
    case flagged = "Flagged"

    var color: Color {
        switch self {
        case .captured: .blue
        case .confirmed: .green
        case .flagged: .red
        }
    }

    var symbol: String {
        switch self {
        case .captured: "camera.fill"
        case .confirmed: "checkmark.circle.fill"
        case .flagged: "exclamationmark.triangle.fill"
        }
    }
}

enum FlagSeverity: String, CaseIterable, Codable {
    case critical = "Critical"
    case warning = "Warning"
    case info = "Info"

    var color: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        }
    }
}

enum RunType: String, CaseIterable, Identifiable, Codable {
    case conduit = "Conduit"
    case cableTray = "Cable Tray"
    case busway = "Busway"
    case cable = "Cable Pull"

    var id: String { rawValue }
}

// MARK: - Codable value types

struct Circuit: Codable, Hashable, Identifiable {
    var id = UUID()
    var number: Int
    var description: String
    var breakerAmps: Int?
    var poles: Int?
}

// MARK: - Models

@Model
final class Site {
    var name: String
    var client: String
    var address: String
    var disciplineRaw: String
    var createdAt: Date
    var buildingSqFtOverride: Double?
    var notes: String
    var isSample = false
    @Attribute(.externalStorage) var coverPhoto: Data?

    @Relationship(deleteRule: .cascade, inverse: \Equipment.site) var equipment: [Equipment] = []
    @Relationship(deleteRule: .cascade, inverse: \ComplianceFlag.site) var flags: [ComplianceFlag] = []
    @Relationship(deleteRule: .cascade, inverse: \RoomScan.site) var roomScans: [RoomScan] = []
    @Relationship(deleteRule: .cascade, inverse: \RunSegment.site) var segments: [RunSegment] = []
    @Relationship(deleteRule: .cascade, inverse: \RoofSurvey.site) var roofSurveys: [RoofSurvey] = []

    init(name: String, client: String = "", address: String = "", discipline: Discipline, createdAt: Date = .now, notes: String = "") {
        self.name = name
        self.client = client
        self.address = address
        self.disciplineRaw = discipline.rawValue
        self.createdAt = createdAt
        self.notes = notes
    }

    var discipline: Discipline {
        get { Discipline(rawValue: disciplineRaw) ?? .electrical }
        set { disciplineRaw = newValue.rawValue }
    }

    var openFlags: [ComplianceFlag] { flags.filter { !$0.resolved } }

    var plannedFeet: Double { segments.reduce(0) { $0 + $1.plannedFt } }
    var installedFeet: Double { segments.reduce(0) { $0 + min($1.installedFt, $1.plannedFt) } }

    /// Install progress if runs are tracked; otherwise the share of captured equipment that is confirmed.
    var progress: Double {
        if plannedFeet > 0 { return installedFeet / plannedFeet }
        guard !equipment.isEmpty else { return roofSurveys.isEmpty && roomScans.isEmpty ? 0 : 1 }
        return Double(equipment.filter { $0.status == .confirmed }.count) / Double(equipment.count)
    }

    var scannedSqFt: Double { roomScans.reduce(0) { $0 + $1.floorAreaSqFt } }
    var buildingSqFt: Double { buildingSqFtOverride ?? scannedSqFt }

    var lastActivity: Date? {
        let dates = equipment.map(\.capturedAt) + roomScans.map(\.capturedAt)
            + segments.map(\.updatedAt) + roofSurveys.map(\.capturedAt) + flags.map(\.createdAt)
        return dates.max()
    }

    var captureCount: Int { equipment.count + roomScans.count + roofSurveys.count }
}

@Model
final class Equipment {
    var tag: String
    var kindRaw: String
    var manufacturer: String
    var model: String
    var serial: String
    var voltage: String
    var amperage: String
    var phase: String
    var kva: String
    var tonnage: String
    var refrigerant: String
    var manufactureYear: Int?
    var location: String
    var notes: String
    var rawText: String
    /// nil = not checked, true = label detected, false = no label detected
    var hasArcFlashLabel: Bool?
    var arcFlashDetails: String
    var statusRaw: String
    var capturedAt: Date
    @Attribute(.externalStorage) var photo: Data?
    @Attribute(.externalStorage) var labelPhoto: Data?
    var circuitsData: Data?
    var site: Site?

    init(tag: String = "", kind: EquipmentKind = .other, manufacturer: String = "", model: String = "", serial: String = "",
         voltage: String = "", amperage: String = "", phase: String = "", kva: String = "", tonnage: String = "",
         refrigerant: String = "", manufactureYear: Int? = nil, location: String = "", notes: String = "", rawText: String = "",
         hasArcFlashLabel: Bool? = nil, arcFlashDetails: String = "", status: EquipmentStatus = .captured, capturedAt: Date = .now) {
        self.tag = tag
        self.kindRaw = kind.rawValue
        self.manufacturer = manufacturer
        self.model = model
        self.serial = serial
        self.voltage = voltage
        self.amperage = amperage
        self.phase = phase
        self.kva = kva
        self.tonnage = tonnage
        self.refrigerant = refrigerant
        self.manufactureYear = manufactureYear
        self.location = location
        self.notes = notes
        self.rawText = rawText
        self.hasArcFlashLabel = hasArcFlashLabel
        self.arcFlashDetails = arcFlashDetails
        self.statusRaw = status.rawValue
        self.capturedAt = capturedAt
    }

    var kind: EquipmentKind {
        get { EquipmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var status: EquipmentStatus {
        get { EquipmentStatus(rawValue: statusRaw) ?? .captured }
        set { statusRaw = newValue.rawValue }
    }

    var circuits: [Circuit] {
        get { circuitsData.flatMap { try? JSONDecoder().decode([Circuit].self, from: $0) } ?? [] }
        set { circuitsData = try? JSONEncoder().encode(newValue) }
    }

    var displayName: String { tag.isEmpty ? kind.rawValue : tag }

    var ratingSummary: String {
        [amperage.isEmpty ? nil : amperage, voltage.isEmpty ? nil : voltage, kva.isEmpty ? nil : kva,
         tonnage.isEmpty ? nil : tonnage].compactMap { $0 }.joined(separator: " · ")
    }

    var age: Int? {
        guard let manufactureYear else { return nil }
        return Calendar.current.component(.year, from: .now) - manufactureYear
    }

    var tons: Double? {
        Double(tonnage.lowercased().replacingOccurrences(of: "tons", with: "").replacingOccurrences(of: "ton", with: "")
            .trimmingCharacters(in: .whitespaces))
    }
}

@Model
final class ComplianceFlag {
    var title: String
    var detail: String
    var severityRaw: String
    var equipmentTag: String
    var reference: String
    var createdAt: Date
    var resolved: Bool
    var resolvedAt: Date?
    var site: Site?

    init(title: String, detail: String = "", severity: FlagSeverity = .warning, equipmentTag: String = "",
         reference: String = "", createdAt: Date = .now) {
        self.title = title
        self.detail = detail
        self.severityRaw = severity.rawValue
        self.equipmentTag = equipmentTag
        self.reference = reference
        self.createdAt = createdAt
        self.resolved = false
    }

    var severity: FlagSeverity {
        get { FlagSeverity(rawValue: severityRaw) ?? .warning }
        set { severityRaw = newValue.rawValue }
    }
}

@Model
final class RoomScan {
    var name: String
    var level: String
    var capturedAt: Date
    var floorAreaSqFt: Double
    var ceilingHeightFt: Double
    var notes: String
    var fromLiDAR: Bool
    var geometryData: Data?
    @Attribute(.externalStorage) var usdzData: Data?
    var site: Site?

    init(name: String, level: String = "", capturedAt: Date = .now, floorAreaSqFt: Double = 0, ceilingHeightFt: Double = 0,
         notes: String = "", fromLiDAR: Bool = false, geometry: RoomGeometry = RoomGeometry()) {
        self.name = name
        self.level = level
        self.capturedAt = capturedAt
        self.floorAreaSqFt = floorAreaSqFt
        self.ceilingHeightFt = ceilingHeightFt
        self.notes = notes
        self.fromLiDAR = fromLiDAR
        self.geometryData = try? JSONEncoder().encode(geometry)
    }

    var geometry: RoomGeometry {
        get { geometryData.flatMap { try? JSONDecoder().decode(RoomGeometry.self, from: $0) } ?? RoomGeometry() }
        set { geometryData = try? JSONEncoder().encode(newValue) }
    }
}

@Model
final class RunSegment {
    var name: String
    var typeRaw: String
    var area: String
    var plannedFt: Double
    var installedFt: Double
    var notes: String
    var updatedAt: Date
    var site: Site?

    init(name: String, type: RunType = .conduit, area: String = "", plannedFt: Double, installedFt: Double = 0,
         notes: String = "", updatedAt: Date = .now) {
        self.name = name
        self.typeRaw = type.rawValue
        self.area = area
        self.plannedFt = plannedFt
        self.installedFt = installedFt
        self.notes = notes
        self.updatedAt = updatedAt
    }

    var type: RunType {
        get { RunType(rawValue: typeRaw) ?? .conduit }
        set { typeRaw = newValue.rawValue }
    }

    var progress: Double { plannedFt > 0 ? min(installedFt / plannedFt, 1) : 0 }
    var variance: Double { installedFt - plannedFt }

    var statusLabel: String {
        if installedFt >= plannedFt && plannedFt > 0 { return "Complete" }
        if installedFt == 0 { return "Not Started" }
        return progress < 0.5 ? "Behind" : "In Progress"
    }

    var statusColor: Color {
        switch statusLabel {
        case "Complete": .green
        case "Behind": .red
        case "Not Started": .gray
        default: .blue
        }
    }
}

@Model
final class RoofSurvey {
    var name: String
    var capturedAt: Date
    var totalAreaSqFt: Double
    var obstructionAreaSqFt: Double
    var setbackPercent: Double
    var moduleWatts: Double
    var moduleAreaSqFt: Double
    var specificYield: Double
    var notes: String
    var outlineData: Data?
    var site: Site?

    init(name: String, capturedAt: Date = .now, totalAreaSqFt: Double = 0, obstructionAreaSqFt: Double = 0,
         setbackPercent: Double = 10, moduleWatts: Double = 450, moduleAreaSqFt: Double = 23.5, specificYield: Double = 1250,
         notes: String = "", plan: RoofPlan = RoofPlan()) {
        self.name = name
        self.capturedAt = capturedAt
        self.totalAreaSqFt = totalAreaSqFt
        self.obstructionAreaSqFt = obstructionAreaSqFt
        self.setbackPercent = setbackPercent
        self.moduleWatts = moduleWatts
        self.moduleAreaSqFt = moduleAreaSqFt
        self.specificYield = specificYield
        self.notes = notes
        self.outlineData = try? JSONEncoder().encode(plan)
    }

    var plan: RoofPlan {
        get { outlineData.flatMap { try? JSONDecoder().decode(RoofPlan.self, from: $0) } ?? RoofPlan() }
        set { outlineData = try? JSONEncoder().encode(newValue) }
    }

    var usableAreaSqFt: Double { max(0, (totalAreaSqFt - obstructionAreaSqFt) * (1 - setbackPercent / 100)) }
    var moduleCount: Int { moduleAreaSqFt > 0 ? Int(usableAreaSqFt / moduleAreaSqFt) : 0 }
    var capacityKW: Double { Double(moduleCount) * moduleWatts / 1000 }
    var annualKWh: Double { capacityKW * specificYield }
}
