import Foundation

struct NameplateResult {
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
    var year: Int?
    var rawText = ""
    var arcFlash = ArcFlashResult()

    /// How many structured fields were found — used to tell the user how good the read was.
    var fieldCount: Int {
        [manufacturer, model, serial, voltage, amperage, phase, kva, tonnage, refrigerant].filter { !$0.isEmpty }.count
            + (year == nil ? 0 : 1)
    }
}

/// Turns OCR text from an equipment nameplate into structured fields.
/// Heuristic: labeled values first ("SERIAL NO: …"), then unit patterns ("480Y/277V", "2000A", "15 TONS").
enum NameplateParser {
    static let manufacturers: [(name: String, aliases: [String])] = [
        ("Square D", ["SQUARE D", "SQUARED", "SCHNEIDER"]),
        ("Eaton", ["EATON", "CUTLER-HAMMER", "CUTLER HAMMER", "WESTINGHOUSE"]),
        ("Siemens", ["SIEMENS", "ITE"]),
        ("GE", ["GENERAL ELECTRIC", "GE", "ABB"]),
        ("Vertiv", ["VERTIV", "LIEBERT"]),
        ("APC", ["APC"]),
        ("Hubbell", ["HUBBELL"]),
        ("ASCO", ["ASCO"]),
        ("Russelectric", ["RUSSELECTRIC"]),
        ("Caterpillar", ["CATERPILLAR", "CAT"]),
        ("Cummins", ["CUMMINS"]),
        ("Kohler", ["KOHLER"]),
        ("Generac", ["GENERAC"]),
        ("Itron", ["ITRON"]),
        ("Landis+Gyr", ["LANDIS", "GYR"]),
        ("Carrier", ["CARRIER", "BRYANT"]),
        ("Trane", ["TRANE"]),
        ("Lennox", ["LENNOX"]),
        ("York", ["YORK", "JOHNSON CONTROLS"]),
        ("Daikin", ["DAIKIN", "MCQUAY"]),
        ("Rheem", ["RHEEM", "RUUD"]),
        ("Goodman", ["GOODMAN", "AMANA"]),
        ("Mitsubishi", ["MITSUBISHI"]),
        ("AAON", ["AAON"]),
    ]

    static func parse(_ lines: [OCRLine]) -> NameplateResult {
        let textLines = lines.map { normalizeRatings($0.text.latinized).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let full = textLines.joined(separator: "\n")
        let upper = full.uppercased()
        var r = NameplateResult()
        r.rawText = full

        r.manufacturer = manufacturers.first { entry in
            entry.aliases.contains { Rx.contains("(?<![A-Z0-9])\(NSRegularExpression.escapedPattern(for: $0))(?![A-Z0-9])", in: upper) }
        }?.name ?? ""

        r.model = labeledValue(["MODEL NUMBER", "MODEL NO", "MOD NO", "MODEL", "M/N", "CATALOG NO", "CAT NO", "CATALOG"], in: textLines) ?? ""
        r.serial = labeledValue(["SERIAL NUMBER", "SERIAL NO", "SER NO", "SERIAL", "S/N", "SN"], in: textLines) ?? ""

        r.voltage = Rx.firstMatch(#"(?<![0-9])(\d{3}Y?\s*/\s*\d{3}\s*V?|\d{3}\s*(?:V|VAC|VOLTS?))(?![A-Z0-9])"#, in: upper)?
            .replacingOccurrences(of: " ", with: "") ?? ""
        if r.voltage.isEmpty, let v = labeledValue(["VOLTAGE", "VOLTS", "VOLT"], in: textLines), v.first?.isNumber == true {
            r.voltage = v.hasSuffix("V") ? v : v + "V"
        }
        if !r.voltage.isEmpty && !r.voltage.hasSuffix("V") && !r.voltage.uppercased().hasSuffix("VAC") && !r.voltage.uppercased().hasSuffix("VOLTS") {
            r.voltage += "V"
        }

        if let mca = Rx.firstMatch(#"(?:MCA|MIN\.?\s*CIRCUIT\s*AMP(?:ACITY|S)?)\s*[:=]?\s*(\d{1,3}(?:\.\d)?)"#, in: upper) {
            r.amperage = "MCA \(mca)A"
        } else {
            let amps = Rx.allMatches(#"(?<![0-9.A-Z\-])(\d{2,4})\s*(?:A|AMPS?|AMPERES)(?![A-Z0-9])"#, in: upper).compactMap(Int.init)
            if let top = amps.filter({ $0 >= 10 }).max() { r.amperage = "\(top)A" }
        }

        if let ph = Rx.firstMatch(#"(?<![0-9])([13])\s*(?:PH|PHASE|Ø|Φ)(?![A-Z])"#, in: upper)
            ?? Rx.firstMatch(#"(?:PHASE|PH)\s*[:=]?\s*([13])(?![0-9])"#, in: upper) {
            r.phase = ph
        }

        if let kva = Rx.firstMatch(#"(\d+(?:\.\d+)?)\s*KVA"#, in: upper) { r.kva = "\(kva) kVA" }

        if let tons = Rx.firstMatch(#"(\d+(?:\.\d+)?)\s*TONS?(?![A-Z])"#, in: upper) {
            r.tonnage = "\(tons) ton"
        } else if let btu = Rx.firstMatch(#"(\d{1,3}(?:,\d{3})+|\d{4,7})\s*(?:BTU|BTUH|BTU/H)"#, in: upper),
                  let value = Double(btu.replacingOccurrences(of: ",", with: "")), value >= 6000 {
            let tons = (value / 12000 * 2).rounded() / 2
            r.tonnage = "\(tons.formatted(.number.precision(.fractionLength(0...1)))) ton"
        }

        if let refrigerant = Rx.firstMatch(#"(R-?(?:22|32|410A|454B|407C|134A|404A|513A))"#, in: upper) {
            r.refrigerant = refrigerant.hasPrefix("R-") ? refrigerant : "R-" + refrigerant.dropFirst()
        }

        let yearPattern = #"((?:19[6-9]|20[0-4])\d)"#
        if let dateText = labeledValue(["MFG DATE", "MANUFACTURE DATE", "DATE OF MFG", "DATE MFD", "MFD", "MFG", "DATE"], in: textLines, rawRest: true),
           let y = Rx.firstMatch(yearPattern, in: dateText).flatMap(Int.init) {
            r.year = y
        } else if let y = Rx.firstMatch(#"(?<![0-9])\d{1,2}[/-]"# + yearPattern + #"(?![0-9])"#, in: upper).flatMap(Int.init) {
            r.year = y
        }

        r.tag = Rx.firstMatch(#"(?<![A-Z0-9])((?:MDP|MSB|SWBD|SWGR|DP|HDP|LDP|LP|PP|RP|MCC|ATS|UPS|PDU|XFMR|TX|GEN|RTU|AHU|CH|CU|HP)-\d{1,3}[A-Z]?)(?![A-Z0-9])"#, in: upper) ?? ""

        r.kind = guessKind(upper: upper, result: r)
        r.arcFlash = ArcFlashDetector.analyze(full)
        return r
    }

    /// OCR often reads the slash in "480Y/277V" as "|", "\\", "I" or "l"; put it back.
    static func normalizeRatings(_ text: String) -> String {
        text.replacingOccurrences(of: #"(\d{3}Y?)\s*[|\\Il]\s*(\d{3})(?=\s*V|\b)"#, with: "$1/$2", options: .regularExpression)
    }

    static func guessKind(upper: String, result r: NameplateResult) -> EquipmentKind {
        let rules: [(String, EquipmentKind)] = [
            ("SWITCHBOARD|SWITCHGEAR|SWBD|SWGR", .switchboard),
            ("MOTOR CONTROL|MCC", .mcc),
            ("PANELBOARD|LOAD CENTER|LOADCENTER", .panelboard),
            ("TRANSFER SWITCH|ATS", .ats),
            ("UNINTERRUPTIBLE|UPS", .ups),
            ("POWER DISTRIBUTION UNIT|PDU", .pdu),
            ("TRANSFORMER|XFMR", .transformer),
            ("GENERATOR|GENSET|ENGINE", .generator),
            ("SAFETY SWITCH|DISCONNECT|FUSIBLE", .disconnect),
            ("KWH|WATTHOUR|METER", .meter),
            ("CHILLER", .chiller),
            ("ROOFTOP|PACKAGED|RTU", .rtu),
            ("AIR HANDLER|AIR HANDLING|AHU", .ahu),
            ("HEAT PUMP|CONDENSING UNIT|SPLIT", .heatPump),
            ("BOILER|FURNACE", .boiler),
        ]
        for (pattern, kind) in rules where Rx.contains("(?<![A-Z])(?:\(pattern))(?![A-Z])", in: upper) {
            return kind
        }
        if !r.tonnage.isEmpty || !r.refrigerant.isEmpty { return .rtu }
        if !r.kva.isEmpty { return .transformer }
        if let tag = r.tag.split(separator: "-").first {
            switch tag {
            case "MDP", "MSB", "SWBD", "SWGR": return .switchboard
            case "LP", "PP", "RP", "DP", "HDP", "LDP": return .panelboard
            case "RTU": return .rtu
            case "AHU": return .ahu
            case "TX", "XFMR": return .transformer
            case "GEN": return .generator
            default: break
            }
        }
        return .other
    }

    /// Finds "LABEL: value" on one line, or a bare "LABEL" followed by the value on the next line.
    static func labeledValue(_ labels: [String], in lines: [String], rawRest: Bool = false) -> String? {
        for label in labels {
            let escaped = label.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\.?\s*"#)
            let pattern = #"(?<![A-Z0-9])"# + escaped + #"\.?(?![A-Z0-9])\s*[:#.\-=]*\s*(.*)$"#
            for (i, line) in lines.enumerated() {
                guard let rest = Rx.firstMatch(pattern, in: line.uppercased()) else { continue }
                let source = rest.isEmpty ? (i + 1 < lines.count ? lines[i + 1].uppercased() : "") : rest
                if rawRest { return source }
                if let token = Rx.firstMatch(#"^([A-Z0-9][A-Z0-9\-/.]{1,29})"#, in: source),
                   token.rangeOfCharacter(from: .decimalDigits) != nil || token.count >= 3 {
                    return token.trimmingCharacters(in: CharacterSet(charactersIn: ".-/"))
                }
            }
        }
        return nil
    }
}
