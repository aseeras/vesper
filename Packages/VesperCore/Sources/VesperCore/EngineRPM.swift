import Foundation

/// Estimates engine RPM from cabin audio by finding the firing frequency.
///
/// A four-stroke engine fires `cylinders / 2` times per revolution, so a V12 at 6,000 rpm
/// hums at 600 Hz. We find that pitch with the YIN method and keep it continuous over time
/// so octave slips don't make the needle jump.
public struct EngineRPMEstimator: Sendable {
    public var cylinders: Int
    public var sampleRate: Double
    public var minRPM: Double
    public var maxRPM: Double
    /// YIN threshold; lower is stricter.
    public var threshold: Double = 0.2
    public private(set) var lastRPM: Double?

    public init(cylinders: Int = 12, sampleRate: Double = 44_100, minRPM: Double = 700, maxRPM: Double = 7_500) {
        self.cylinders = cylinders; self.sampleRate = sampleRate; self.minRPM = minRPM; self.maxRPM = maxRPM
    }

    private var firingsPerRev: Double { Double(cylinders) / 2 }

    public func frequency(forRPM rpm: Double) -> Double { rpm / 60 * firingsPerRev }
    public func rpm(forFrequency hz: Double) -> Double { hz / firingsPerRev * 60 }

    /// Feed a window of mono samples (about 2,048). Returns RPM, or nil when the engine isn't clear.
    public mutating func estimate(_ samples: [Float]) -> Double? {
        let minLag = max(2, Int(sampleRate / frequency(forRPM: maxRPM)))
        let maxLag = Int(sampleRate / frequency(forRPM: minRPM))
        let n = samples.count - maxLag - 1
        guard n > 64, minLag < maxLag else { return nil }

        // Cumulative mean normalised difference (YIN steps 2 and 3).
        var d = [Double](repeating: 1, count: maxLag + 2)
        var running = 0.0
        for lag in 1...maxLag + 1 {
            var sum = 0.0
            for i in 0..<n {
                let diff = Double(samples[i] - samples[i + lag])
                sum += diff * diff
            }
            running += sum
            d[lag] = running > 0 ? sum * Double(lag) / running : 1
        }

        // First dip below the threshold, then walk to its local minimum.
        var lag = -1
        var l = minLag
        while l <= maxLag {
            if d[l] < threshold {
                while l + 1 <= maxLag, d[l + 1] < d[l] { l += 1 }
                lag = l
                break
            }
            l += 1
        }
        guard lag > 0 else { return nil }

        // Parabolic interpolation for sub-sample precision.
        let a = d[lag - 1], b = d[lag], c = d[lag + 1]
        let denom = a - 2 * b + c
        let refined = Double(lag) + (abs(denom) > 1e-12 ? 0.5 * (a - c) / denom : 0)
        var rpm = rpm(forFrequency: sampleRate / refined)

        // Fold octave slips back toward the previous reading.
        if let last = lastRPM {
            for candidate in [rpm * 2, rpm / 2] where abs(candidate - last) < abs(rpm - last) * 0.5 {
                rpm = candidate
            }
        }
        guard rpm >= minRPM * 0.9, rpm <= maxRPM * 1.1 else { return nil }
        lastRPM = rpm
        return rpm
    }
}
