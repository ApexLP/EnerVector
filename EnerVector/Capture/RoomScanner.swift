import RoomPlan
import SwiftUI
import UIKit
import simd

/// Result of a LiDAR room scan, flattened to what EnerVector stores.
struct RoomScanResult {
    var geometry: RoomGeometry
    var floorAreaSqFt: Double
    var ceilingHeightFt: Double
    var usdz: Data?
}

enum RoomScanner {
    static var isSupported: Bool { RoomCaptureSession.isSupported }

    static func convert(_ room: CapturedRoom) -> RoomScanResult {
        var g = RoomGeometry()
        g.walls = room.walls.map { segment(for: $0, kind: .wall) }
        g.openings = room.doors.map { segment(for: $0, kind: .door) }
            + room.windows.map { segment(for: $0, kind: .window) }
            + room.openings.map { segment(for: $0, kind: .opening) }
        g.objects = room.objects.map { object in
            let t = object.transform
            return PlanObject(label: String(describing: object.category).capitalized,
                              center: PlanPoint(x: Double(t.columns.3.x), y: Double(t.columns.3.z)),
                              width: Double(object.dimensions.x), depth: Double(object.dimensions.z),
                              angle: Double(atan2(t.columns.0.z, t.columns.0.x)))
        }

        var areaM2 = 0.0
        for floor in room.floors {
            let corners = floor.polygonCorners
            if corners.count > 2 {
                areaM2 += Geometry.shoelaceArea(corners.map { PlanPoint(x: Double($0.x), y: Double($0.y)) })
            } else {
                areaM2 += Double(floor.dimensions.x * floor.dimensions.y)
            }
        }
        if areaM2 == 0 {
            let e = g.extents
            areaM2 = e.width * e.depth
        }
        let height = room.walls.map { Double($0.dimensions.y) }.max() ?? 0

        var usdz: Data?
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString).usdz")
        if (try? room.export(to: url)) != nil {
            usdz = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
        }
        return RoomScanResult(geometry: g, floorAreaSqFt: Units.sqFt(areaM2), ceilingHeightFt: Units.feet(height), usdz: usdz)
    }

    private static func segment(for surface: CapturedRoom.Surface, kind: PlanSegment.Kind) -> PlanSegment {
        let t = surface.transform
        let center = SIMD2<Double>(Double(t.columns.3.x), Double(t.columns.3.z))
        var dir = SIMD2<Double>(Double(t.columns.0.x), Double(t.columns.0.z))
        if simd_length(dir) > 0 { dir = simd_normalize(dir) }
        let half = Double(surface.dimensions.x) / 2
        let a = center - dir * half, b = center + dir * half
        return PlanSegment(a: PlanPoint(x: a.x, y: a.y), b: PlanPoint(x: b.x, y: b.y), kind: kind)
    }
}

/// Full-screen RoomPlan capture. Tap Done to stop scanning, review the model, then Save.
struct RoomCaptureScreen: UIViewControllerRepresentable {
    var onFinish: (CapturedRoom?) -> Void

    func makeUIViewController(context: Context) -> RoomCaptureViewController {
        let vc = RoomCaptureViewController()
        vc.onFinish = onFinish
        return vc
    }

    func updateUIViewController(_ vc: RoomCaptureViewController, context: Context) {}
}

final class RoomCaptureViewController: UIViewController, RoomCaptureViewDelegate {
    var onFinish: ((CapturedRoom?) -> Void)?

    private var captureView: RoomCaptureView!
    private var result: CapturedRoom?
    private var isScanning = false
    private let primaryButton = UIButton(configuration: .borderedProminent())
    private let cancelButton = UIButton(configuration: .bordered())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.delegate = self
        view.addSubview(captureView)

        primaryButton.configuration?.title = "Done"
        primaryButton.configuration?.cornerStyle = .capsule
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        cancelButton.configuration?.title = "Cancel"
        cancelButton.configuration?.cornerStyle = .capsule
        cancelButton.configuration?.baseForegroundColor = .white
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [cancelButton, UIView(), primaryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !isScanning, result == nil else { return }
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        isScanning = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isScanning { captureView.captureSession.stop() }
    }

    @objc private func primaryTapped() {
        if isScanning {
            captureView.captureSession.stop()
            isScanning = false
            primaryButton.configuration?.title = "Processing…"
            primaryButton.isEnabled = false
        } else if let result {
            onFinish?(result)
        }
    }

    @objc private func cancelTapped() {
        if isScanning { captureView.captureSession.stop(); isScanning = false }
        onFinish?(nil)
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        result = processedResult
        primaryButton.configuration?.title = "Save Scan"
        primaryButton.isEnabled = true
    }
}
