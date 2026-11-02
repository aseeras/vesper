import Foundation
import SwiftUI
import UIKit
import VesperCore

/// The driver's preferences. Defaults are tuned for a DB9: 12 cylinders, 7,000 rpm tach.
@MainActor
@Observable
final class DriverSettings {
    private let d = UserDefaults.standard

    var callsign: String { didSet { d.set(callsign, forKey: "callsign") } }
    var car: String { didSet { d.set(car, forKey: "car") } }
    var cylinders: Int { didSet { d.set(cylinders, forKey: "cylinders") } }
    var redline: Double { didSet { d.set(redline, forKey: "redline") } }
    var unit: SpeedUnit { didSet { d.set(unit.rawValue, forKey: "unit") } }
    var autoStartSpeed: Double { didSet { d.set(autoStartSpeed, forKey: "autoStartSpeed") } }
    var autoStopMinutes: Double { didSet { d.set(autoStopMinutes, forKey: "autoStopMinutes") } }
    var voiceCallouts: Bool { didSet { d.set(voiceCallouts, forKey: "voiceCallouts") } }
    /// Seconds the glasses video lags real time over Bluetooth.
    var glassesLatency: Double { didSet { d.set(glassesLatency, forKey: "glassesLatency") } }
    var filmLength: Double { didSet { d.set(filmLength, forKey: "filmLength") } }
    /// Show lap info on the Ray-Ban Display's in-lens screen.
    var lensDisplay: Bool { didSet { d.set(lensDisplay, forKey: "lensDisplay") } }

    init() {
        callsign = d.string(forKey: "callsign") ?? "ALVIN"
        car = d.string(forKey: "car") ?? "DB9"
        cylinders = d.object(forKey: "cylinders") as? Int ?? 12
        redline = d.object(forKey: "redline") as? Double ?? 6_800
        unit = SpeedUnit(rawValue: d.string(forKey: "unit") ?? "") ?? .mph
        autoStartSpeed = d.object(forKey: "autoStartSpeed") as? Double ?? 15
        autoStopMinutes = d.object(forKey: "autoStopMinutes") as? Double ?? 0.75
        voiceCallouts = d.object(forKey: "voiceCallouts") as? Bool ?? true
        glassesLatency = d.object(forKey: "glassesLatency") as? Double ?? 0.15
        filmLength = d.object(forKey: "filmLength") as? Double ?? 60
        lensDisplay = d.object(forKey: "lensDisplay") as? Bool ?? true
    }

    /// Auto-record thresholds in the units the driver thinks in.
    var policy: AutoRecordPolicy {
        var p = AutoRecordPolicy()
        p.startSpeed = autoStartSpeed / unit.convert(1)
        p.stopHold = autoStopMinutes * 60
        return p
    }
}

/// Drop-in slots for the driver's own logo and soundtrack.
///
/// Checked in order: files chosen in Settings (Documents/Brand), then files dropped into
/// the app bundle's Custom folder before building, then Vesper's original theme.
enum BrandAssets {
    static let folder: URL = {
        let url = URL.documentsDirectory.appending(path: "Brand", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var userLogoURL: URL { folder.appending(path: "logo.png") }

    static var logo: UIImage? {
        if let img = UIImage(contentsOfFile: userLogoURL.path) { return img }
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png", subdirectory: "Custom") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    static var userMusicURL: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == "music" }
    }

    static var music: URL? {
        if let url = userMusicURL { return url }
        for ext in ["m4a", "mp3", "wav", "aiff"] {
            if let url = Bundle.main.url(forResource: "music", withExtension: ext, subdirectory: "Custom") { return url }
        }
        return Bundle.main.url(forResource: "vesper_theme", withExtension: "m4a")
    }

    static func setMusic(from source: URL) throws {
        if let old = userMusicURL { try? FileManager.default.removeItem(at: old) }
        let dest = folder.appending(path: "music.\(source.pathExtension.lowercased())")
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)
    }

    static func clearMusic() { if let url = userMusicURL { try? FileManager.default.removeItem(at: url) } }
}
