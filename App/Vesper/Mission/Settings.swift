import Foundation
import SwiftUI
import UIKit
import VesperCore

/// One car in the garage. Cylinders drive the engine-sound rev reading; redline sets the film's tach.
struct Car: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var cylinders: Int
    var redline: Double

    /// "V12", "V8", "6-CYL"… for film captions.
    var engineLabel: String { cylinders >= 6 && cylinders.isMultiple(of: 2) ? "V\(cylinders)" : "\(cylinders)-CYL" }

    static let db9 = Car(name: "DB9", cylinders: 12, redline: 6_800)
}

/// The driver's preferences. Defaults are tuned for a DB9: 12 cylinders, 7,000 rpm tach.
@MainActor
@Observable
final class DriverSettings {
    private let d = UserDefaults.standard

    var callsign: String { didSet { d.set(callsign, forKey: "callsign") } }
    /// Every car Alvin drives. Never empty.
    var cars: [Car] { didSet { saveGarage() } }
    var activeCarID: UUID { didSet { d.set(activeCarID.uuidString, forKey: "activeCarID") } }

    /// The car the next drive is in.
    var activeCar: Car {
        get { cars.first { $0.id == activeCarID } ?? cars[0] }
        set { if let i = cars.firstIndex(where: { $0.id == newValue.id }) { cars[i] = newValue } }
    }
    var car: String { activeCar.name }
    var cylinders: Int { activeCar.cylinders }
    var redline: Double { activeCar.redline }
    var unit: SpeedUnit { didSet { d.set(unit.rawValue, forKey: "unit") } }
    var autoStartSpeed: Double { didSet { d.set(autoStartSpeed, forKey: "autoStartSpeed") } }
    var autoStopMinutes: Double { didSet { d.set(autoStopMinutes, forKey: "autoStopMinutes") } }
    var voiceCallouts: Bool { didSet { d.set(voiceCallouts, forKey: "voiceCallouts") } }
    /// Seconds the glasses video lags real time over Bluetooth.
    var glassesLatency: Double { didSet { d.set(glassesLatency, forKey: "glassesLatency") } }
    var filmLength: Double { didSet { d.set(filmLength, forKey: "filmLength") } }
    /// Show lap info on the Ray-Ban Display's in-lens screen.
    var lensDisplay: Bool { didSet { d.set(lensDisplay, forKey: "lensDisplay") } }
    var lastMode: DriveMode { didSet { d.set(lastMode.rawValue, forKey: "lastMode") } }
    /// Grand tour films can leave the speedometer out.
    var showSpeedOnRoad: Bool { didSet { d.set(showSpeedOnRoad, forKey: "showSpeedOnRoad") } }
    /// Warn about speed and red-light cameras ahead, on the lens and by voice.
    var cameraAlerts: Bool { didSet { d.set(cameraAlerts, forKey: "cameraAlerts") } }

    init() {
        callsign = d.string(forKey: "callsign") ?? "ALVIN"
        // Garage; the first time, carry over the single car from earlier versions.
        let garage = d.data(forKey: "garage").flatMap { try? JSONDecoder().decode([Car].self, from: $0) } ?? []
        let cars = garage.isEmpty ? [Car(name: d.string(forKey: "car") ?? Car.db9.name,
                                         cylinders: d.object(forKey: "cylinders") as? Int ?? Car.db9.cylinders,
                                         redline: d.object(forKey: "redline") as? Double ?? Car.db9.redline)] : garage
        self.cars = cars
        activeCarID = d.string(forKey: "activeCarID").flatMap(UUID.init(uuidString:)).flatMap { id in
            cars.contains { $0.id == id } ? id : nil
        } ?? cars[0].id
        unit = SpeedUnit(rawValue: d.string(forKey: "unit") ?? "") ?? .mph
        autoStartSpeed = d.object(forKey: "autoStartSpeed") as? Double ?? 15
        autoStopMinutes = d.object(forKey: "autoStopMinutes") as? Double ?? 0.75
        voiceCallouts = d.object(forKey: "voiceCallouts") as? Bool ?? true
        glassesLatency = d.object(forKey: "glassesLatency") as? Double ?? 0.15
        filmLength = d.object(forKey: "filmLength") as? Double ?? 60
        lensDisplay = d.object(forKey: "lensDisplay") as? Bool ?? true
        lastMode = DriveMode(rawValue: d.string(forKey: "lastMode") ?? "") ?? .track
        showSpeedOnRoad = d.object(forKey: "showSpeedOnRoad") as? Bool ?? true
        cameraAlerts = d.object(forKey: "cameraAlerts") as? Bool ?? true
        // didSet doesn't run during init: store the migrated garage so its ids stay stable.
        if garage.isEmpty {
            saveGarage()
            d.set(activeCarID.uuidString, forKey: "activeCarID")
        }
    }

    func addCar() -> Car {
        let car = Car(name: "New car", cylinders: 8, redline: 7_000)
        cars.append(car)
        return car
    }

    func removeCar(_ car: Car) {
        guard cars.count > 1 else { return }
        cars.removeAll { $0.id == car.id }
        if activeCarID == car.id { activeCarID = cars[0].id }
    }

    private func saveGarage() {
        if let data = try? JSONEncoder().encode(cars) { d.set(data, forKey: "garage") }
    }

    /// Auto-record thresholds in the units the driver thinks in.
    func policy(for mode: DriveMode) -> AutoRecordPolicy {
        var p = AutoRecordPolicy()
        p.startSpeed = autoStartSpeed / unit.convert(1)
        // On the road, traffic lights and junctions shouldn't end the drive: wait at least 5 minutes.
        p.stopHold = mode == .road ? max(300, autoStopMinutes * 60) : autoStopMinutes * 60
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
