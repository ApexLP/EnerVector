import UIKit
import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

struct Badge: View {
    let text: String
    var color: Color = .accentColor
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct LinearProgress: View {
    let value: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

struct ProgressRing: View {
    let value: Double
    var color: Color = .green
    var lineWidth: CGFloat = 14
    var label: String = "Complete"

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(Units.percent(value)).font(.title.bold()).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.3)
                if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5) }
            }
            .padding(lineWidth * 1.4)
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var color: Color = .accentColor

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(.title2.bold()).monospacedDigit()
                    Text(label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

struct DisciplineThumbnail: View {
    let site: Site

    var body: some View {
        ZStack {
            if let data = site.coverPhoto, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [site.discipline.color.opacity(0.85), site.discipline.color.opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: site.discipline.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .clipped()
    }
}

struct PlanImage: View {
    let geometry: RoomGeometry
    var height: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: PlanRenderer.image(geometry, size: CGSize(width: max(geo.size.width, 50), height: height)))
                .resizable()
                .scaledToFit()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct RoofPlanImage: View {
    let plan: RoofPlan
    var height: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: PlanRenderer.roofImage(plan, size: CGSize(width: max(geo.size.width, 50), height: height)))
                .resizable()
                .scaledToFit()
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Decimal text field bound to a Double.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
        }
    }
}

/// Equal-width grid columns: `regular` count on iPad / landscape, `compact` on iPhone portrait.
struct ResponsiveColumns {
    static func make(_ sizeClass: UserInterfaceSizeClass?, regular: Int = 4, compact: Int = 2, spacing: CGFloat = 12) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: sizeClass == .compact ? compact : regular)
    }
}


extension View {
    /// Lets a downward swipe close the keyboard (number pads have no return key).
    func keyboardDoneButton() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}

/// Closes the keyboard when the user taps anywhere outside a text field, app-wide.
enum KeyboardDismisser {
    private final class Handler: NSObject, UIGestureRecognizerDelegate {
        @objc func tapped(_ g: UITapGestureRecognizer) { g.view?.endEditing(true) }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view {  // Taps inside a text field keep the keyboard up.
                if v is UITextField || v is UITextView { return false }
                view = v.superview
            }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
    private static let handler = Handler()

    @MainActor static func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0.name == "dismissKeyboard" }) {
                let tap = UITapGestureRecognizer(target: handler, action: #selector(Handler.tapped))
                tap.name = "dismissKeyboard"
                tap.cancelsTouchesInView = false
                tap.delegate = handler
                window.addGestureRecognizer(tap)
            }
        }
    }
}
