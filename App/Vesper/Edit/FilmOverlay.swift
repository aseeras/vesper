import CoreImage
import UIKit
import VesperCore

/// Draws everything that sits on top of the footage, one frame at a time:
/// the aperture title sequence, grand-tourer gauges, captions and the closing card.
///
/// The gauges nod to the DB9's instrument cluster: a jewel-like speedometer on the left
/// and a counter-rotating tachometer on the right whose needle sweeps anticlockwise.
struct FilmOverlay: @unchecked Sendable {
    struct Style {
        var callsign: String
        var car: String
        /// "V12", "V8"… shown next to the car's name.
        var engine = "V12"
        var codename: String
        var trackName: String
        var date: Date
        var unit: SpeedUnit
        var redline: Double
        var logo: UIImage?
        var mode: DriveMode = .track
        var showSpeed = true
    }

    let plan: HighlightPlan
    let track: TelemetryTrack
    let laps: [Lap]
    let style: Style
    let size: CGSize
    let introDuration: Double
    let outroDuration: Double

    private var total: Double { plan.totalDuration }

    private let gold = UIColor(red: 0.79, green: 0.66, blue: 0.29, alpha: 1)
    private let silver = UIColor(red: 0.84, green: 0.86, blue: 0.88, alpha: 1)
    private let red = UIColor(red: 0.85, green: 0.12, blue: 0.12, alpha: 1)

    func image(at outputTime: Double) -> CIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(in: ctx.cgContext, t: outputTime)
        }
        return CIImage(image: img) ?? CIImage.empty()
    }

    // MARK: Composition of layers

    private func draw(in c: CGContext, t: Double) {
        let w = size.width, h = size.height
        cinematicBars(c, w: w, h: h)
        guard let hit = plan.source(atOutput: t) else { return }
        let inIntro = t < introDuration
        let inOutro = t > total - outroDuration

        if !inIntro && !inOutro {
            gauges(c, w: w, h: h, missionTime: hit.missionTime)
            if style.mode == .track { lapClock(c, w: w, h: h, missionTime: hit.missionTime) }
            caption(c, w: w, h: h, t: t, index: hit.index)
        }
        brandMark(c, w: w, h: h, faded: inIntro)
        if inIntro { intro(c, w: w, h: h, t: t) }
        if inOutro { outro(c, w: w, h: h, t: t - (total - outroDuration)) }
    }

    private func cinematicBars(_ c: CGContext, w: CGFloat, h: CGFloat) {
        let colors = [UIColor.black.withAlphaComponent(0.75).cgColor, UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: h * 0.14), options: [])
        c.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.68), options: [])
    }

    // MARK: Gauges

    private func gauges(_ c: CGContext, w: CGFloat, h: CGFloat, missionTime: Double) {
        let r = w * 0.19
        let y = h - r - h * 0.05
        let speed = style.unit.convert(track.speed(at: missionTime))
        let maxSpeed: Double = style.unit == .mph ? 200 : 320
        let step: Double = style.unit == .mph ? 20 : 40

        // Speedometer: clockwise, 0 at lower left. Optional on grand tours.
        if style.showSpeed {
            dial(c, center: CGPoint(x: w * 0.24, y: y), radius: r, value: speed, max: maxSpeed, step: step,
                 clockwise: true, redFrom: nil, label: style.unit.label, readout: "\(Int(speed.rounded()))")
        }

        // Tachometer: anticlockwise, 0 at lower right, like the DB9's.
        let rpm = track.rpm(at: missionTime)
        dial(c, center: CGPoint(x: w * 0.76, y: y), radius: r, value: (rpm ?? 0) / 1000, max: 8, step: 1,
             clockwise: false, redFrom: style.redline / 1000, label: "RPM ×1000",
             readout: rpm.map { "\(Int(($0 / 100).rounded()) * 100)" } ?? "—")

        gBall(c, center: CGPoint(x: w * 0.5, y: y + r * 0.35), radius: r * 0.42, g: track.gforce(at: missionTime))
    }

    /// A round gauge sweeping 270°. Angles are in screen space (y down).
    private func dial(_ c: CGContext, center: CGPoint, radius r: CGFloat, value: Double, max: Double, step: Double,
                      clockwise: Bool, redFrom: Double?, label: String, readout: String) {
        let start = clockwise ? 135.0 : 45.0   // degrees, 0 = east, increasing clockwise on screen
        let sweep = 270.0
        func angle(_ v: Double) -> CGFloat {
            let f = min(Swift.max(v / max, 0), 1)
            let deg = clockwise ? start + sweep * f : start - sweep * f
            return CGFloat(deg * .pi / 180)
        }
        func point(_ a: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius)
        }

        c.saveGState()
        // Smoked-glass face with a polished bezel.
        c.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        c.setStrokeColor(silver.withAlphaComponent(0.85).cgColor)
        c.setLineWidth(r * 0.035)
        c.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))

        if let redFrom {
            c.setStrokeColor(red.cgColor)
            c.setLineWidth(r * 0.07)
            c.addArc(center: center, radius: r * 0.86, startAngle: angle(redFrom), endAngle: angle(max), clockwise: !clockwise)
            c.strokePath()
        }

        // Ticks and numerals.
        var v = 0.0
        while v <= max + 0.001 {
            let a = angle(v)
            c.setStrokeColor(silver.cgColor)
            c.setLineWidth(r * 0.025)
            c.move(to: point(a, r * 0.78)); c.addLine(to: point(a, r * 0.92)); c.strokePath()
            let numeral = step >= 10 ? "\(Int(v))" : "\(Int(v))"
            text(numeral, at: point(a, r * 0.62), size: r * 0.13, color: silver, weight: .medium, center: true)
            let half = v + step / 2
            if half < max {
                c.setLineWidth(r * 0.012)
                c.move(to: point(angle(half), r * 0.84)); c.addLine(to: point(angle(half), r * 0.92)); c.strokePath()
            }
            v += step
        }

        // Needle.
        let a = angle(value)
        c.setStrokeColor(gold.cgColor)
        c.setLineWidth(r * 0.045)
        c.setLineCap(.round)
        c.move(to: point(a + .pi, r * 0.12)); c.addLine(to: point(a, r * 0.9)); c.strokePath()
        c.setFillColor(gold.cgColor)
        c.fillEllipse(in: CGRect(x: center.x - r * 0.07, y: center.y - r * 0.07, width: r * 0.14, height: r * 0.14))

        text(readout, at: CGPoint(x: center.x, y: center.y + r * 0.42), size: r * 0.22, color: .white, mono: true, center: true)
        text(label, at: CGPoint(x: center.x, y: center.y + r * 0.66), size: r * 0.09, color: gold, kern: 2, center: true)
        c.restoreGState()
    }

    /// Friction circle: where the car's weight is going.
    private func gBall(_ c: CGContext, center: CGPoint, radius r: CGFloat, g: GForceSample) {
        c.saveGState()
        c.setStrokeColor(silver.withAlphaComponent(0.6).cgColor)
        c.setLineWidth(1.5)
        for k in [1.0, 0.5] {
            let rr = r * k
            c.strokeEllipse(in: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr))
        }
        c.move(to: CGPoint(x: center.x - r, y: center.y)); c.addLine(to: CGPoint(x: center.x + r, y: center.y))
        c.move(to: CGPoint(x: center.x, y: center.y - r)); c.addLine(to: CGPoint(x: center.x, y: center.y + r))
        c.strokePath()
        let scale = r / 1.5
        // Cornering left pushes you right; braking pushes you forward (up).
        let dot = CGPoint(x: center.x - CGFloat(g.lateral) * scale, y: center.y + CGFloat(g.longitudinal) * scale)
        c.setFillColor(gold.cgColor)
        c.fillEllipse(in: CGRect(x: dot.x - r * 0.12, y: dot.y - r * 0.12, width: r * 0.24, height: r * 0.24))
        text(String(format: "%.2f G", g.combined), at: CGPoint(x: center.x, y: center.y - r - r * 0.35),
             size: r * 0.26, color: .white, mono: true, center: true)
        c.restoreGState()
    }

    private func lapClock(_ c: CGContext, w: CGFloat, h: CGFloat, missionTime: Double) {
        guard let lap = laps.first(where: { missionTime >= $0.start && missionTime < $0.end }) else { return }
        let x = w - w * 0.05
        text("LAP \(lap.number)", at: CGPoint(x: x, y: h * 0.045), size: w * 0.03, color: gold, kern: 3, right: true)
        text(Format.lapTime(missionTime - lap.start), at: CGPoint(x: x, y: h * 0.07), size: w * 0.055,
             color: .white, mono: true, right: true)
    }

    // MARK: Captions

    private func caption(_ c: CGContext, w: CGFloat, h: CGFloat, t: Double, index: Int) {
        let seg = plan.segments[index]
        guard let text = seg.caption else { return }
        // A caption spans the run of neighbouring segments that share it.
        var first = index, last = index
        while first > 0, plan.segments[first - 1].caption == text { first -= 1 }
        while last + 1 < plan.segments.count, plan.segments[last + 1].caption == text { last += 1 }
        let start = plan.outputStart(ofSegment: first)
        let end = plan.outputStart(ofSegment: last) + plan.segments[last].outputDuration
        let alpha = CGFloat(min(1, (t - start) / 0.3, (end - t) / 0.3, 1))
        guard alpha > 0 else { return }

        let y = h * 0.6
        c.saveGState()
        c.setAlpha(alpha)
        let reveal = CGFloat(min(1, (t - start) / 0.5))
        c.setFillColor(gold.cgColor)
        c.fill(CGRect(x: w / 2 - w * 0.3 * reveal, y: y - h * 0.012, width: w * 0.6 * reveal, height: 1.5))
        self.text(text, at: CGPoint(x: w / 2, y: y + h * 0.01), size: w * 0.055, color: silver, weight: .semibold, kern: 6, center: true)
        if seg.role == .slowMotion {
            self.text("½ SPEED", at: CGPoint(x: w / 2, y: y + h * 0.06), size: w * 0.028, color: gold, kern: 4, center: true)
        }
        c.restoreGState()
    }

    private func brandMark(_ c: CGContext, w: CGFloat, h: CGFloat, faded: Bool) {
        guard !faded else { return }
        if let logo = style.logo {
            let height = h * 0.035
            let width = height * logo.size.width / Swift.max(logo.size.height, 1)
            logo.draw(in: CGRect(x: w * 0.05, y: h * 0.04, width: width, height: height), blendMode: .normal, alpha: 0.9)
        } else {
            text("VESPER", at: CGPoint(x: w * 0.05, y: h * 0.045), size: w * 0.032, color: gold, kern: 8)
            text(style.car.uppercased() + " · " + style.engine, at: CGPoint(x: w * 0.05, y: h * 0.07), size: w * 0.022, color: silver, kern: 3)
        }
    }

    // MARK: Titles

    /// Dots race across a black screen, settle into an aperture, and the aperture opens onto the drive.
    private func intro(_ c: CGContext, w: CGFloat, h: CGFloat, t: Double) {
        let center = CGPoint(x: w / 2, y: h * 0.45)
        let full = (w * w + h * h).squareRoot()
        let openStart = introDuration - 0.9
        let small = w * 0.22
        let radius: CGFloat
        if t < 1.4 { radius = 0 }
        else if t < openStart { radius = small * CGFloat(min(1, (t - 1.4) / 0.35)) }
        else { radius = small + (full - small) * CGFloat(pow(min(1, (t - openStart) / 0.9), 2)) }

        c.saveGState()
        c.setFillColor(UIColor.black.cgColor)
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if radius > 0 {
            c.setBlendMode(.clear)
            c.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            c.setBlendMode(.normal)
            // Rifled gold ring around the aperture.
            c.setStrokeColor(gold.cgColor)
            c.setLineWidth(3)
            c.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            for k in 0..<12 {
                let a = CGFloat(k) / 12 * 2 * .pi + CGFloat(t) * 0.6
                c.setStrokeColor(gold.withAlphaComponent(0.35).cgColor)
                c.setLineWidth(1)
                c.move(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
                c.addLine(to: CGPoint(x: center.x + cos(a + 0.4) * radius * 1.12, y: center.y + sin(a + 0.4) * radius * 1.12))
                c.strokePath()
            }
        }

        // The opening run of white dots.
        if t < 1.6 {
            for k in 0..<6 {
                let local = t - Double(k) * 0.12
                guard local > 0 else { continue }
                let x = -w * 0.1 + CGFloat(local / 1.0) * w * 0.7
                let dot = w * 0.045
                c.setFillColor(UIColor.white.withAlphaComponent(CGFloat(max(0, 1 - local / 1.4))).cgColor)
                c.fillEllipse(in: CGRect(x: x - dot / 2, y: center.y - dot / 2, width: dot, height: dot))
            }
        }

        // Title card while the aperture is small.
        if t > 1.5 && t < openStart + 0.3 {
            let a = CGFloat(min(1, (t - 1.5) / 0.4, (openStart + 0.3 - t) / 0.3))
            c.setAlpha(a)
            text(style.codename, at: CGPoint(x: w / 2, y: h * 0.2), size: w * 0.045, color: gold, kern: 7, center: true)
            if let logo = style.logo {
                let lh = h * 0.05
                let lw = lh * logo.size.width / Swift.max(logo.size.height, 1)
                logo.draw(in: CGRect(x: w / 2 - lw / 2, y: h * 0.11, width: lw, height: lh))
            }
            text(style.trackName.uppercased(), at: CGPoint(x: w / 2, y: h * 0.66), size: w * 0.06, color: .white,
                 serif: true, center: true)
            let date = style.date.formatted(date: .long, time: .omitted).uppercased()
            text("\(style.callsign.uppercased()) · \(style.car.uppercased()) · \(date)", at: CGPoint(x: w / 2, y: h * 0.71),
                 size: w * 0.025, color: silver, kern: 3, center: true)
        }
        c.restoreGState()
    }

    private func outro(_ c: CGContext, w: CGFloat, h: CGFloat, t: Double) {
        let a = CGFloat(min(1, t / 0.6))
        c.saveGState()
        c.setFillColor(UIColor.black.withAlphaComponent(0.88 * a).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setAlpha(a)
        if let logo = style.logo {
            let lh = h * 0.07
            let lw = lh * logo.size.width / Swift.max(logo.size.height, 1)
            logo.draw(in: CGRect(x: w / 2 - lw / 2, y: h * 0.3, width: lw, height: lh))
        }
        text("\(style.callsign.uppercased()) WILL RETURN", at: CGPoint(x: w / 2, y: h * 0.44), size: w * 0.07,
             color: gold, serif: true, center: true)
        var stats: [String]
        if style.mode == .road {
            stats = ["\(Format.distance(track.distance, style.unit)) · \(Format.duration(track.duration))",
                     "BEST BEND \(Format.g(track.peakLateralG))"]
        } else {
            stats = ["V-MAX \(Format.speed(track.maxSpeed, style.unit))", "PEAK \(Format.g(track.peakLateralG))"]
            if let best = laps.min(by: { $0.duration < $1.duration }) { stats.append("BEST LAP \(Format.lapTime(best.duration))") }
        }
        for (i, s) in stats.enumerated() {
            text(s, at: CGPoint(x: w / 2, y: h * 0.52 + CGFloat(i) * h * 0.035), size: w * 0.032, color: silver, kern: 4, center: true)
        }
        text(style.codename, at: CGPoint(x: w / 2, y: h * 0.86), size: w * 0.025, color: gold.withAlphaComponent(0.7), kern: 6, center: true)
        c.restoreGState()
    }

    // MARK: Text

    private func text(_ string: String, at p: CGPoint, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular,
                      mono: Bool = false, serif: Bool = false, kern: CGFloat = 0, center: Bool = false, right: Bool = false) {
        let font: UIFont
        if serif { font = UIFont(name: "Didot-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold) }
        else if mono { font = .monospacedSystemFont(ofSize: size, weight: .medium) }
        else { font = .systemFont(ofSize: size, weight: weight) }
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.8)
        shadow.shadowBlurRadius = size * 0.15
        let attr = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: color, .kern: kern, .shadow: shadow,
        ])
        let s = attr.size()
        var origin = CGPoint(x: p.x, y: p.y - s.height / 2)
        if center { origin.x -= s.width / 2 }
        if right { origin.x -= s.width }
        attr.draw(at: origin)
    }
}
