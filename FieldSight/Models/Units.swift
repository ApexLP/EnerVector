import Foundation
import UIKit

enum Units {
    static let feetPerMeter = 3.28084
    static let sqFtPerSqM = 10.7639

    static func feet(_ meters: Double) -> Double { meters * feetPerMeter }
    static func sqFt(_ sqMeters: Double) -> Double { sqMeters * sqFtPerSqM }

    /// 3.76 m → 12' - 4"
    static func feetInches(_ meters: Double) -> String {
        let totalInches = Int((meters * 39.3701).rounded())
        return "\(totalInches / 12)' - \(totalInches % 12)\""
    }

    static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic))
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

enum AppSettings {
    static let technicianName = "technicianName"
    static let companyName = "companyName"
    static let defaultRecipient = "defaultRecipient"
    static let moduleWatts = "moduleWatts"
    static let moduleAreaSqFt = "moduleAreaSqFt"
    static let specificYield = "specificYield"
    static let kwPerTon = "kwPerTon"
    static let wattsPerSqFt = "wattsPerSqFt"
    static let didSeed = "didSeedSampleData"
}

extension Date {
    var relativeShort: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: self, relativeTo: .now)
    }
}

extension UIImage {
    /// Redraw with `.up` orientation, capped to `maxDimension` on the long edge.
    func normalized(maxDimension: CGFloat = 2400) -> UIImage {
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    func storageJPEG() -> Data? {
        normalized(maxDimension: 1600).jpegData(compressionQuality: 0.72)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }

    var fileSafe: String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
    }
}
