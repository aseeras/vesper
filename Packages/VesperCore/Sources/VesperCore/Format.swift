import Foundation

public enum SpeedUnit: String, Codable, CaseIterable, Sendable {
    case mph, kmh

    public var label: String { self == .mph ? "MPH" : "KM/H" }

    public func convert(_ metresPerSecond: Double) -> Double {
        self == .mph ? metresPerSecond * 2.236936 : metresPerSecond * 3.6
    }
}

public enum Format {
    /// 1:42.381
    public static func lapTime(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%d:%02d.%03d", ms / 60_000, (ms / 1000) % 60, ms % 1000)
    }

    /// "1 minute 42 point 3" for voice call-outs.
    public static func spokenLapTime(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded())
        let minutes = tenths / 600, secs = (tenths / 10) % 60, tenth = tenths % 10
        let head = minutes > 0 ? "\(minutes) \(minutes == 1 ? "minute" : "minutes") " : ""
        return "\(head)\(secs) point \(tenth)"
    }

    public static func speed(_ metresPerSecond: Double, _ unit: SpeedUnit) -> String {
        "\(Int(unit.convert(metresPerSecond).rounded())) \(unit.label)"
    }

    /// "42.3 MI" or "68.1 KM".
    public static func distance(_ metres: Double, _ unit: SpeedUnit) -> String {
        unit == .mph ? String(format: "%.1f MI", metres / 1609.344) : String(format: "%.1f KM", metres / 1000)
    }

    /// Short warning distances: "1,000 FT" (rounded to 100 ft) or "300 M" (rounded to 50 m).
    public static func shortDistance(_ metres: Double, _ unit: SpeedUnit) -> String {
        if unit == .mph {
            let feet = max(100, (metres * 3.28084 / 100).rounded() * 100)
            return "\(Int(feet).formatted(.number.grouping(.automatic))) FT"
        }
        return "\(Int(max(50, (metres / 50).rounded() * 50))) M"
    }

    /// "1H 24M" or "38M".
    public static func duration(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60)H \(m % 60)M" : "\(m)M"
    }

    public static func g(_ value: Double) -> String { String(format: "%.2f G", abs(value)) }

    /// Mission codename from a date, e.g. "OPERATION NIGHTSHADE".
    public static func codename(for date: Date) -> String {
        let words = ["NIGHTSHADE", "GOLDCREST", "SILVERFOX", "BLACKWATER", "KESTREL", "MONSOON",
                     "OBSIDIAN", "TEMPEST", "PHANTOM", "SOVEREIGN", "QUICKSILVER", "MIDNIGHT",
                     "ONYX", "LONGBOW", "HALCYON", "WILDFIRE"]
        let day = Int(date.timeIntervalSince1970 / 86_400)
        return "OPERATION " + words[abs(day) % words.count]
    }
}
