import Foundation
import simd

/// Top-down plan coordinates, in meters.
struct PlanPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct PlanSegment: Codable, Hashable {
    enum Kind: String, Codable { case wall, door, window, opening }
    var a: PlanPoint
    var b: PlanPoint
    var kind: Kind

    var length: Double { hypot(b.x - a.x, b.y - a.y) }
}

struct PlanObject: Codable, Hashable {
    var label: String
    var center: PlanPoint
    var width: Double
    var depth: Double
    /// Rotation in radians, counter-clockwise.
    var angle: Double

    var corners: [PlanPoint] {
        let c = cos(angle), s = sin(angle)
        let hw = width / 2, hd = depth / 2
        return [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { dx, dy in
            PlanPoint(x: center.x + dx * c - dy * s, y: center.y + dx * s + dy * c)
        }
    }
}

struct RoomGeometry: Codable, Hashable {
    var walls: [PlanSegment] = []
    var openings: [PlanSegment] = []
    var objects: [PlanObject] = []

    var isEmpty: Bool { walls.isEmpty && objects.isEmpty }

    var allPoints: [PlanPoint] {
        walls.flatMap { [$0.a, $0.b] } + openings.flatMap { [$0.a, $0.b] } + objects.flatMap(\.corners)
    }

    /// Axis-aligned extents in meters.
    var extents: (width: Double, depth: Double) {
        let pts = allPoints
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return (0, 0) }
        return (maxX - minX, maxY - minY)
    }

    /// A simple rectangular room, used for manual entry when LiDAR isn't available.
    static func rectangle(width: Double, depth: Double, doorOnWall: Bool = true) -> RoomGeometry {
        let p = [PlanPoint(x: 0, y: 0), PlanPoint(x: width, y: 0), PlanPoint(x: width, y: depth), PlanPoint(x: 0, y: depth)]
        var g = RoomGeometry()
        for i in 0..<4 { g.walls.append(PlanSegment(a: p[i], b: p[(i + 1) % 4], kind: .wall)) }
        if doorOnWall && width > 1.5 {
            g.openings.append(PlanSegment(a: PlanPoint(x: 0.4, y: depth), b: PlanPoint(x: 1.3, y: depth), kind: .door))
        }
        return g
    }
}

struct PlanPolygon: Codable, Hashable {
    var label: String
    var points: [PlanPoint]

    var area: Double { Geometry.shoelaceArea(points) }
}

struct RoofPlan: Codable, Hashable {
    var outline: [PlanPoint] = []
    var obstructions: [PlanPolygon] = []
}

enum Geometry {
    static func shoelaceArea(_ pts: [PlanPoint]) -> Double {
        guard pts.count > 2 else { return 0 }
        var sum = 0.0
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    static func polylineLength(_ pts: [SIMD3<Float>]) -> Double {
        guard pts.count > 1 else { return 0 }
        return zip(pts, pts.dropFirst()).reduce(0) { $0 + Double(simd_distance($1.0, $1.1)) }
    }

    /// True surface area of a planar (or near-planar) 3D polygon — Newell's method.
    /// Works for sloped roofs, where a top-down projection would under-count.
    static func polygonArea(_ pts: [SIMD3<Float>]) -> Double {
        guard pts.count > 2 else { return 0 }
        var n = SIMD3<Float>(repeating: 0)
        for i in pts.indices {
            n += simd_cross(pts[i], pts[(i + 1) % pts.count])
        }
        return Double(simd_length(n)) / 2
    }

    /// Project world points onto the floor (x/z) for plan drawings.
    static func topDown(_ pts: [SIMD3<Float>]) -> [PlanPoint] {
        pts.map { PlanPoint(x: Double($0.x), y: Double($0.z)) }
    }
}
