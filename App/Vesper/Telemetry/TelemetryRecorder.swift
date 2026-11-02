import CoreLocation
import CoreMotion
import Foundation
import VesperCore

/// GPS and motion on one clock (phone uptime minus mission start).
final class TelemetryRecorder: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let location = CLLocationManager()
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let lock = NSLock()
    private var lateral = Smoother(alpha: 0.25)
    private var longitudinal = Smoother(alpha: 0.25)
    private var lastSpeed: Double = 0
    private var speedTrend: Double = 0
    private var lastFixTime: Double?

    private(set) var missionStartUptime: TimeInterval = 0
    private var fixes: [GPSFix] = []
    private var gforces: [GForceSample] = []

    /// Called on the main queue with each GPS fix.
    var onFix: ((GPSFix) -> Void)?
    /// Called on the main queue ~10× a second with the latest g-force.
    var onGForce: ((GForceSample) -> Void)?

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        location.activityType = .automotiveNavigation
        location.distanceFilter = kCLDistanceFilterNone
        location.pausesLocationUpdatesAutomatically = false
        motionQueue.maxConcurrentOperationCount = 1
    }

    func requestPermission() { location.requestWhenInUseAuthorization() }

    func start(missionStartUptime: TimeInterval) {
        self.missionStartUptime = missionStartUptime
        lock.withLock { fixes.removeAll(); gforces.removeAll() }
        location.allowsBackgroundLocationUpdates = true
        location.startUpdatingLocation()

        motion.deviceMotionUpdateInterval = 1.0 / 50
        var tick = 0
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] m, _ in
            guard let self, let m else { return }
            let r = m.rotationRate, g = m.gravity, a = m.userAcceleration
            let (lat, lon) = self.lock.withLock { () -> (Double, Double) in
                GForceEstimator.estimate(speed: self.lastSpeed,
                                         rotationRate: Vec3(x: r.x, y: r.y, z: r.z),
                                         gravity: Vec3(x: g.x, y: g.y, z: g.z),
                                         userAcceleration: Vec3(x: a.x, y: a.y, z: a.z),
                                         speedTrend: self.speedTrend)
            }
            let sample = self.lock.withLock { () -> GForceSample in
                let s = GForceSample(t: m.timestamp - self.missionStartUptime,
                                     lateral: self.lateral.add(lat), longitudinal: self.longitudinal.add(lon))
                self.gforces.append(s)
                return s
            }
            tick += 1
            if tick % 5 == 0 { DispatchQueue.main.async { self.onGForce?(sample) } }
        }
    }

    func stop() -> TelemetryTrack {
        location.stopUpdatingLocation()
        motion.stopDeviceMotionUpdates()
        return lock.withLock { TelemetryTrack(fixes: fixes, gforces: gforces) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let nowUptime = ProcessInfo.processInfo.systemUptime
        for loc in locations where loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 50 {
            let uptime = nowUptime - Date().timeIntervalSince(loc.timestamp)
            let fix = GPSFix(t: uptime - missionStartUptime,
                             point: GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude),
                             speed: loc.speed, course: loc.course, accuracy: loc.horizontalAccuracy)
            lock.withLock {
                if let last = lastFixTime, fix.t > last, fix.speed >= 0 {
                    speedTrend = 0.5 * speedTrend + 0.5 * (fix.speed - lastSpeed) / (fix.t - last)
                }
                if fix.speed >= 0 { lastSpeed = fix.speed }
                lastFixTime = fix.t
                fixes.append(fix)
            }
            onFix?(fix)
        }
    }
}
