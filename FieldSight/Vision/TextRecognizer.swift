import UIKit
import Vision

struct OCRLine: Hashable {
    let text: String
    /// Vision normalized coordinates (origin bottom-left).
    let box: CGRect
    let confidence: Float
}

enum TextRecognizer {
    /// On-device text recognition. Returns lines in reading order (top-to-bottom, left-to-right).
    static func recognize(_ image: UIImage) async throws -> [OCRLine] {
        guard let cgImage = image.normalized(maxDimension: 3000).cgImage else { return [] }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Serial and model numbers aren't dictionary words — correction mangles them.
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.008
            // Auto language detection can return Cyrillic look-alikes ("МСА" for "MCA") on all-caps plates.
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { obs -> OCRLine? in
                guard let top = obs.topCandidates(1).first else { return nil }
                return OCRLine(text: top.string.latinized, box: obs.boundingBox, confidence: top.confidence)
            }
            return lines.sorted {
                abs($0.box.midY - $1.box.midY) > 0.01 ? $0.box.midY > $1.box.midY : $0.box.minX < $1.box.minX
            }
        }.value
    }
}

/// Small regex helpers shared by the parsers.
enum Rx {
    static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespaces)
    }

    static func allMatches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > group, let r = Range(m.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]).trimmingCharacters(in: .whitespaces) }
        }
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        firstMatch("(\(pattern))", in: text) != nil
    }
}

extension String {
    /// Maps Cyrillic/Greek homoglyphs that OCR sometimes emits back to Latin letters.
    var latinized: String {
        let table: [Character: Character] = [
            "А": "A", "В": "B", "С": "C", "Е": "E", "Н": "H", "І": "I", "К": "K", "М": "M", "О": "O", "Р": "P",
            "Т": "T", "Х": "X", "У": "Y", "а": "a", "с": "c", "е": "e", "о": "o", "р": "p", "х": "x", "у": "y",
            "Α": "A", "Β": "B", "Ε": "E", "Η": "H", "Ι": "I", "Κ": "K", "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Χ": "X",
        ]
        return String(map { table[$0] ?? $0 })
    }
}
