import ARKit
import SceneKit
import SwiftUI
import UIKit

enum MeasureMode {
    /// Polyline — conduit / tray run length.
    case length
    /// Closed polygon — roof outline, obstruction, floor area.
    case area
}

struct MeasureResult {
    var points: [SIMD3<Float>]
    var mode: MeasureMode

    var lengthFt: Double { Units.feet(Geometry.polylineLength(points)) }
    var areaSqFt: Double { Units.sqFt(Geometry.polygonArea(points)) }
    var plan: [PlanPoint] { Geometry.topDown(points) }
}

enum ARMeasure {
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    static var hasLiDAR: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }
}

struct ARMeasureScreen: UIViewControllerRepresentable {
    var mode: MeasureMode
    var title: String
    var onFinish: (MeasureResult?) -> Void

    func makeUIViewController(context: Context) -> ARMeasureViewController {
        let vc = ARMeasureViewController()
        vc.mode = mode
        vc.titleText = title
        vc.onFinish = onFinish
        return vc
    }

    func updateUIViewController(_ vc: ARMeasureViewController, context: Context) {}
}

/// Aim the reticle, tap "Add Point". Points snap to the LiDAR mesh / detected planes via raycasting.
final class ARMeasureViewController: UIViewController, ARSCNViewDelegate {
    var mode: MeasureMode = .length
    var titleText = "Measure"
    var onFinish: ((MeasureResult?) -> Void)?

    private let sceneView = ARSCNView()
    private let readout = UILabel()
    private let hint = UILabel()
    private let reticle = UIImageView(image: UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .light)))
    private var points: [SIMD3<Float>] = []
    private var pointNodes: [SCNNode] = []
    private var lineNodes: [SCNNode] = []
    private var closingNode: SCNNode?

    override func viewDidLoad() {
        super.viewDidLoad()
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)

        reticle.tintColor = .white
        reticle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reticle)

        let top = UIStackView(arrangedSubviews: [readout, hint])
        top.axis = .vertical
        top.alignment = .center
        top.spacing = 4
        readout.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        readout.textColor = .white
        hint.font = .preferredFont(forTextStyle: .footnote)
        hint.textColor = .white.withAlphaComponent(0.85)
        hint.numberOfLines = 0
        hint.textAlignment = .center
        let topBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        topBackground.layer.cornerRadius = 16
        topBackground.clipsToBounds = true
        topBackground.translatesAutoresizingMaskIntoConstraints = false
        top.translatesAutoresizingMaskIntoConstraints = false
        topBackground.contentView.addSubview(top)
        view.addSubview(topBackground)

        let cancel = makeButton("Cancel", style: .bordered(), action: #selector(cancelTapped))
        let undo = makeButton("Undo", style: .bordered(), action: #selector(undoTapped))
        let add = makeButton("Add Point", style: .borderedProminent(), action: #selector(addTapped))
        let done = makeButton("Done", style: .borderedProminent(), action: #selector(doneTapped))
        done.configuration?.baseBackgroundColor = .systemGreen
        let bottom = UIStackView(arrangedSubviews: [cancel, undo, add, done])
        bottom.spacing = 10
        bottom.distribution = .fillProportionally
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)

        NSLayoutConstraint.activate([
            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            topBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            topBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topBackground.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
            top.topAnchor.constraint(equalTo: topBackground.topAnchor, constant: 10),
            top.bottomAnchor.constraint(equalTo: topBackground.bottomAnchor, constant: -10),
            top.leadingAnchor.constraint(equalTo: topBackground.leadingAnchor, constant: 18),
            top.trailingAnchor.constraint(equalTo: topBackground.trailingAnchor, constant: -18),
            bottom.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottom.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        updateReadout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        sceneView.session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    private func makeButton(_ title: String, style: UIButton.Configuration, action: Selector) -> UIButton {
        var config = style
        config.title = title
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: Actions

    @objc private func addTapped() {
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        guard let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any),
              let hit = sceneView.session.raycast(query).first else {
            hint.text = "No surface found — move the device slowly to map the area."
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let c = hit.worldTransform.columns.3
        let p = SIMD3<Float>(c.x, c.y, c.z)
        points.append(p)

        let dot = SCNNode(geometry: SCNSphere(radius: 0.012))
        dot.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
        dot.geometry?.firstMaterial?.lightingModel = .constant
        dot.simdPosition = p
        sceneView.scene.rootNode.addChildNode(dot)
        pointNodes.append(dot)

        if points.count > 1 {
            let line = Self.line(from: points[points.count - 2], to: p, color: .systemYellow)
            sceneView.scene.rootNode.addChildNode(line)
            lineNodes.append(line)
        }
        updateClosingLine()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateReadout()
    }

    @objc private func undoTapped() {
        guard !points.isEmpty else { return }
        points.removeLast()
        pointNodes.popLast()?.removeFromParentNode()
        if lineNodes.count > max(0, points.count - 1) { lineNodes.popLast()?.removeFromParentNode() }
        updateClosingLine()
        updateReadout()
    }

    @objc private func doneTapped() {
        let needed = mode == .area ? 3 : 2
        guard points.count >= needed else {
            hint.text = "Add at least \(needed) points."
            return
        }
        onFinish?(MeasureResult(points: points, mode: mode))
    }

    @objc private func cancelTapped() { onFinish?(nil) }

    // MARK: Drawing

    private func updateClosingLine() {
        closingNode?.removeFromParentNode()
        closingNode = nil
        guard mode == .area, points.count > 2, let first = points.first, let last = points.last else { return }
        let node = Self.line(from: last, to: first, color: UIColor.systemYellow.withAlphaComponent(0.5))
        sceneView.scene.rootNode.addChildNode(node)
        closingNode = node
    }

    private func updateReadout() {
        let result = MeasureResult(points: points, mode: mode)
        switch mode {
        case .length:
            readout.text = "\(Units.number(result.lengthFt, digits: 1)) ft"
            hint.text = points.isEmpty ? "\(titleText): aim at the start of the run and tap Add Point." : "\(points.count) points · add a point at each bend."
        case .area:
            readout.text = "\(Units.number(result.areaSqFt)) sq ft"
            hint.text = points.count < 3 ? "\(titleText): add a point at each corner (\(points.count)/3 min)." : "\(points.count) corners · shape closes automatically."
        }
    }

    static func line(from a: SIMD3<Float>, to b: SIMD3<Float>, color: UIColor) -> SCNNode {
        let length = simd_distance(a, b)
        let cylinder = SCNCylinder(radius: 0.004, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (a + b) / 2
        let up = SIMD3<Float>(0, 1, 0)
        let dir = simd_normalize(b - a)
        let axis = simd_cross(up, dir)
        let angle = acos(max(-1, min(1, simd_dot(up, dir))))
        if simd_length(axis) > 1e-5 {
            node.simdOrientation = simd_quatf(angle: angle, axis: simd_normalize(axis))
        } else if simd_dot(up, dir) < 0 {
            node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }
        return node
    }
}
