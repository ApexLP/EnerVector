import Foundation

struct ArcFlashResult {
    var detected = false
    var matchedTerms: [String] = []
    var incidentEnergy: String?
    var ppeCategory: String?
    var boundary: String?
    var workingDistance: String?

    var summary: String {
        var parts: [String] = []
        if let incidentEnergy { parts.append("Incident energy \(incidentEnergy) cal/cm²") }
        if let ppeCategory { parts.append("PPE \(ppeCategory)") }
        if let boundary { parts.append("Arc flash boundary \(boundary)") }
        if let workingDistance { parts.append("Working distance \(workingDistance)") }
        return parts.joined(separator: " · ")
    }
}

/// Detects an NFPA 70E-style arc flash warning label from OCR text.
///
/// This reads text, so a "not detected" result means the label wasn't legible in the photo —
/// the app always asks the technician to confirm before a flag is raised.
enum ArcFlashDetector {
    static let terms: [(label: String, pattern: String)] = [
        ("ARC FLASH", #"ARC\s*[-_ ]?\s*FLASH"#),
        ("INCIDENT ENERGY", #"INCIDENT\s+ENERGY"#),
        ("cal/cm²", #"CAL\s*/\s*CM"#),
        ("PPE", #"(?<![A-Z])PPE(?![A-Z])"#),
        ("FLASH HAZARD", #"FLASH\s+HAZARD"#),
        ("SHOCK HAZARD", #"SHOCK\s+HAZARD"#),
        ("LIMITED APPROACH", #"LIMITED\s+APPROACH"#),
        ("RESTRICTED APPROACH", #"RESTRICTED\s+APPROACH"#),
        ("WORKING DISTANCE", #"WORKING\s+DISTANCE"#),
    ]

    static func analyze(_ text: String) -> ArcFlashResult {
        let upper = text.latinized.uppercased().replacingOccurrences(of: "\n", with: " ")
        var r = ArcFlashResult()
        r.matchedTerms = terms.filter { Rx.contains($0.pattern, in: upper) }.map(\.label)

        r.incidentEnergy = Rx.firstMatch(#"(\d+(?:\.\d+)?)\s*CAL\s*/\s*CM"#, in: upper)
        r.ppeCategory = Rx.firstMatch(#"PPE\s*(?:CATEGORY|CAT\.?|LEVEL|HRC)?\s*[:#]?\s*([0-4])(?![0-9])"#, in: upper)
            .map { "Category \($0)" }
        r.boundary = Rx.firstMatch(#"(?:ARC\s*FLASH\s*)?BOUNDARY\s*[:#]?\s*(\d+(?:\.\d+)?\s*(?:FT|IN|MM|M|'|")(?:\s*\d+\s*(?:IN|"))?)"#, in: upper)
        r.workingDistance = Rx.firstMatch(#"WORKING\s+DISTANCE\s*[:#]?\s*(\d+(?:\.\d+)?\s*(?:FT|IN|MM|M|'|"))"#, in: upper)

        let hasCore = r.matchedTerms.contains("ARC FLASH") || r.incidentEnergy != nil
        let hasSupporting = r.matchedTerms.count >= 2 && Rx.contains(#"WARNING|DANGER"#, in: upper)
        r.detected = hasCore || hasSupporting
        return r
    }
}
