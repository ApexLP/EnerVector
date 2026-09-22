import Foundation

/// Parses a photographed panel directory / schedule into circuits.
///
/// Panel schedules are usually two columns (odd circuits on the left, even on the right), so OCR
/// lines are grouped into rows by vertical position, then each half is parsed on its own.
enum PanelScheduleParser {
    static let breakerSizes: Set<Int> = [10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 110, 125, 150, 175,
                                         200, 225, 250, 300, 350, 400, 450, 500, 600, 800, 1000, 1200]

    static func parse(_ lines: [OCRLine]) -> [Circuit] {
        var byNumber: [Int: Circuit] = [:]

        for row in groupIntoRows(lines) {
            let left = row.filter { $0.box.midX < 0.5 }.map(\.text).joined(separator: " ")
            let right = row.filter { $0.box.midX >= 0.5 }.map(\.text).joined(separator: " ")
            var found = [parseSegment(left), parseSegment(right)].compactMap { $0 }
            if found.isEmpty {
                // Single-column schedules, or OCR merged the whole row into one line.
                found = row.compactMap { parseSegment($0.text) }
            }
            for c in found where byNumber[c.number] == nil { byNumber[c.number] = c }
        }
        return byNumber.values.sorted { $0.number < $1.number }
    }

    static func groupIntoRows(_ lines: [OCRLine]) -> [[OCRLine]] {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRLine]] = []
        for line in sorted {
            if let anchor = rows.last?.first,
               abs(anchor.box.midY - line.box.midY) < max(0.006, min(anchor.box.height, line.box.height) * 0.6) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    static func parseSegment(_ raw: String) -> Circuit? {
        let s = raw.latinized.uppercased()
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard s.count >= 3 else { return nil }

        let amps = #"(\d{2,4})\s*A?(?:\s*/\s*([123])\s*P?)?"#

        // "1 LIGHTING RM 101 20/1"  (circuit, description, breaker)
        if let g = Rx.groups(#"^(\d{1,3})\s+(.+?)\s+"# + amps + #"$"#, in: s), let c = circuit(g[1], g[2], g[3], g[4]) { return c }
        // "1 20A LIGHTING RM 101"  (circuit, breaker, description)
        if let g = Rx.groups(#"^(\d{1,3})\s+"# + amps + #"\s+(.+)$"#, in: s), let c = circuit(g[1], g[4], g[2], g[3]) { return c }
        // "20/1 RECEPT RM 102 2"  (right-hand column: breaker, description, circuit)
        if let g = Rx.groups(#"^"# + amps + #"\s+(.+?)\s+(\d{1,3})$"#, in: s), let c = circuit(g[4], g[3], g[1], g[2]) { return c }
        // "RECEPT RM 102 20 2"  (description, breaker, circuit)
        if let g = Rx.groups(#"^(.+?)\s+"# + amps + #"\s+(\d{1,3})$"#, in: s), let c = circuit(g[4], g[1], g[2], g[3]) { return c }
        // "5 SPARE" / "6 SPACE"
        if let g = Rx.groups(#"^(\d{1,3})\s+(SPARE|SPACE)\b"#, in: s), let n = g[1].flatMap(Int.init), (1...84).contains(n) {
            return Circuit(number: n, description: g[2] ?? "SPARE")
        }
        // "SPACE 8" (right-hand column)
        if let g = Rx.groups(#"^(SPARE|SPACE)\s+(\d{1,3})$"#, in: s), let n = g[2].flatMap(Int.init), (1...84).contains(n) {
            return Circuit(number: n, description: g[1] ?? "SPARE")
        }
        return nil
    }

    private static func circuit(_ number: String?, _ description: String?, _ amps: String?, _ poles: String?) -> Circuit? {
        guard let n = number.flatMap(Int.init), (1...84).contains(n),
              let a = amps.flatMap(Int.init), breakerSizes.contains(a),
              let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), d.count >= 2,
              d.rangeOfCharacter(from: .letters) != nil else { return nil }
        return Circuit(number: n, description: d, breakerAmps: a, poles: poles.flatMap(Int.init))
    }
}
