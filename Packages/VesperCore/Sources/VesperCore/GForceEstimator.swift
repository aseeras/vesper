import Foundation

/// Turns raw phone motion into car-frame g-forces without knowing how the phone is mounted.
///
/// Lateral g comes from yaw rate (gyro projected on gravity) times GPS speed, which is
/// independent of mount angle. Longitudinal g is the rest of the horizontal acceleration,
/// signed by whether GPS speed is rising or falling.
public enum GForceEstimator {
    public static let standardGravity = 9.80665

    /// - Parameters:
    ///   - speed: GPS speed in m/s.
    ///   - rotationRate: gyro rate in rad/s, phone frame.
    ///   - gravity: gravity direction in g, phone frame.
    ///   - userAcceleration: acceleration without gravity, in g, phone frame.
    ///   - speedTrend: recent change of GPS speed in m/s per second.
    public static func estimate(speed: Double, rotationRate: Vec3, gravity: Vec3,
                                userAcceleration: Vec3, speedTrend: Double) -> (lateral: Double, longitudinal: Double) {
        let down = gravity.normalized
        // Gravity points down, so a left (counter-clockwise from above) turn gives a negative dot product.
        let yawRate = -rotationRate.dot(down)
        let lateral = speed < 2 ? 0 : speed * yawRate / standardGravity
        let vertical = userAcceleration.dot(down)
        let horizontal = (userAcceleration - down * vertical).length
        let longitudinalMagnitude = max(0, horizontal * horizontal - lateral * lateral).squareRoot()
        return (lateral, speedTrend >= 0 ? longitudinalMagnitude : -longitudinalMagnitude)
    }
}

/// Exponential smoothing so the gauges don't jitter.
public struct Smoother: Sendable {
    public var alpha: Double
    public private(set) var value: Double?

    public init(alpha: Double) { self.alpha = alpha }

    public mutating func add(_ x: Double) -> Double {
        let v = value.map { $0 + alpha * (x - $0) } ?? x
        value = v
        return v
    }
}
