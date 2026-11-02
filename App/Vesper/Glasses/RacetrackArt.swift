import UIKit

/// An original, made-up circuit drawn for the lens welcome: a long main straight, a hairpin,
/// an esses section and a sweeping final corner, in gold on black. On the waveguide black is
/// see-through, so only the track glows.
enum RacetrackArt {
    /// Sized to sit above two lines of text on the 600×600 lens.
    @MainActor static let lensImage: UIImage = render(size: CGSize(width: 520, height: 300))

    /// Control points of the circuit, clockwise, in a unit box. Point 0 and 1 bound the main straight.
    private static let circuit: [CGPoint] = [
        CGPoint(x: 0.18, y: 0.86), CGPoint(x: 0.62, y: 0.88), CGPoint(x: 0.86, y: 0.84),
        CGPoint(x: 0.95, y: 0.66), CGPoint(x: 0.84, y: 0.52), CGPoint(x: 0.70, y: 0.58),
        CGPoint(x: 0.60, y: 0.44), CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.88, y: 0.18),
        CGPoint(x: 0.74, y: 0.07), CGPoint(x: 0.46, y: 0.12), CGPoint(x: 0.36, y: 0.30),
        CGPoint(x: 0.22, y: 0.24), CGPoint(x: 0.07, y: 0.38), CGPoint(x: 0.06, y: 0.66),
    ]

    static func render(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let inset: CGFloat = 18
            let box = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let pts = circuit.map { CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height) }
            let path = smoothClosedPath(through: pts)

            let gold = UIColor(red: 0.83, green: 0.69, blue: 0.36, alpha: 1)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)

            // Soft glow, then the tarmac band, then a bright racing line.
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: 14, color: gold.withAlphaComponent(0.8).cgColor)
            cg.addPath(path)
            cg.setStrokeColor(gold.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(16)
            cg.strokePath()
            cg.restoreGState()

            cg.addPath(path)
            cg.setStrokeColor(gold.cgColor)
            cg.setLineWidth(5)
            cg.strokePath()

            // Chequered start/finish line across the main straight.
            let a = pts[0], b = pts[1]
            let start = CGPoint(x: a.x + (b.x - a.x) * 0.55, y: a.y + (b.y - a.y) * 0.55)
            let squares = 4, sq: CGFloat = 5
            for row in 0..<squares {
                for col in 0..<2 {
                    ((row + col).isMultiple(of: 2) ? UIColor.white : UIColor.black).setFill()
                    cg.fill(CGRect(x: start.x - sq + CGFloat(col) * sq,
                                   y: start.y - CGFloat(squares) * sq / 2 + CGFloat(row) * sq,
                                   width: sq, height: sq))
                }
            }
        }
    }

    /// Closed Catmull-Rom spline through the points, as cubic Béziers.
    private static func smoothClosedPath(through p: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let n = p.count
        path.move(to: p[0])
        for i in 0..<n {
            let p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
