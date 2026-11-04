import AVKit
import MapKit
import Photos
import SwiftUI
import VesperCore

/// After the drive: the circuit, the numbers, and the button that makes the film.
struct DebriefView: View {
    @State var mission: Mission
    @Environment(MissionStore.self) private var store
    @Environment(DriverSettings.self) private var settings
    @State private var track = TelemetryTrack()
    @State private var rendering = false
    @State private var progress = 0.0
    @State private var player: AVPlayer?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("\(mission.mode.title) · \(mission.codename)").tracked(11, Theme.gold)
                Text(mission.trackName).font(Theme.title(32)).foregroundStyle(.white)
                Text("\(mission.car) · \(mission.date.formatted(date: .long, time: .shortened))").tracked(10)

                if track.fixes.count > 1 { circuitMap }
                stats
                if !mission.laps.isEmpty { lapTable }
                SectionRule(title: "The film")
                film
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            track = store.telemetry(for: mission)
            if mission.hasFilm { player = AVPlayer(url: MissionStore.filmURL(mission.id)) }
        }
    }

    private var circuitMap: some View {
        let coords = track.fixes.map { CLLocationCoordinate2D(latitude: $0.point.latitude, longitude: $0.point.longitude) }
        return Map {
            MapPolyline(coordinates: coords).stroke(Theme.gold, lineWidth: 3)
            if let gate = mission.gate {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: gate.center.latitude, longitude: gate.center.longitude)) {
                    Image(systemName: "flag.checkered").foregroundStyle(.white).padding(4).background(Theme.racingGreen)
                }
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .frame(height: 240)
        .overlay(Rectangle().stroke(Theme.gold.opacity(0.4)))
    }

    @ViewBuilder private var stats: some View {
        if mission.mode == .road {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    stat("Distance", Format.distance(track.distance, mission.unit))
                    stat("Time", Format.duration(track.duration))
                }
                GridRow {
                    stat("Best bend", Format.g(track.peakLateralG))
                    stat("Peak revs", track.rpm.map(\.rpm).max().map { "\(Int($0 / 100) * 100) rpm" } ?? "—")
                }
            }
        } else {
            trackStats
        }
    }

    private var trackStats: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                stat("V-max", Format.speed(track.maxSpeed, mission.unit))
                stat("Peak lateral", Format.g(track.peakLateralG))
            }
            GridRow {
                stat("Hardest braking", Format.g(track.peakBrakingG))
                stat("Best lap", mission.bestLap.map { Format.lapTime($0.duration) } ?? "—")
            }
            if let top = track.rpm.map(\.rpm).max() {
                GridRow {
                    stat("Peak revs", "\(Int(top / 100) * 100) rpm")
                    stat("Laps", "\(mission.laps.count)")
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        DossierCard {
            Text(label).tracked(9, Theme.gold)
            Text(value).font(Theme.mono(20)).foregroundStyle(.white)
        }
    }

    private var lapTable: some View {
        let best = mission.bestLap?.number
        return VStack(spacing: 0) {
            ForEach(mission.laps) { lap in
                HStack {
                    Text("Lap \(lap.number)").tracked(10)
                    Spacer()
                    Text(Format.speed(lap.topSpeed, mission.unit)).font(Theme.mono(13)).foregroundStyle(Theme.silver)
                    Text(Format.lapTime(lap.duration)).font(Theme.mono(17))
                        .foregroundStyle(lap.number == best ? Theme.gold : .white)
                        .frame(width: 110, alignment: .trailing)
                }
                .padding(.vertical, 8)
                Divider().background(Theme.gold.opacity(0.3))
            }
        }
    }

    @ViewBuilder private var film: some View {
        if !mission.hasVideo {
            Text("No glasses footage was recorded on this mission.").foregroundStyle(Theme.silver)
        } else {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(Rectangle().stroke(Theme.gold.opacity(0.5)))
                HStack(spacing: 12) {
                    ShareLink(item: MissionStore.filmURL(mission.id)) { Text("Share") }
                        .buttonStyle(GoldButtonStyle(prominent: false))
                    Button("Save to Photos") { Task { await saveToPhotos() } }
                        .buttonStyle(GoldButtonStyle(prominent: false))
                }
            }
            @Bindable var settings = settings
            Picker("Length", selection: $settings.filmLength) {
                Text("30 s").tag(30.0); Text("60 s").tag(60.0); Text("90 s").tag(90.0); Text("3 min").tag(180.0)
            }
            .pickerStyle(.segmented)
            if rendering {
                ProgressView(value: progress).tint(Theme.gold)
                Text("Cutting the film… \(Int(progress * 100))%").tracked(10)
            } else {
                Button(mission.hasFilm ? "Recut the film" : "Make the film") { Task { await makeFilm() } }
                    .buttonStyle(GoldButtonStyle())
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.silver) }
        }
    }

    private func makeFilm() async {
        rendering = true; message = nil; progress = 0
        player = nil
        var options = HighlightOptions()
        options.targetDuration = settings.filmLength
        options.unit = mission.unit
        options.mode = mission.mode
        // The car this drive was in: its own engine and redline, not whichever car is selected now.
        let garageCar = settings.cars.first { $0.name == mission.car }
        let cylinders = mission.carCylinders ?? garageCar?.cylinders ?? Car.db9.cylinders
        let engine = Car(name: mission.car, cylinders: cylinders, redline: 0).engineLabel
        let style = FilmOverlay.Style(callsign: settings.callsign, car: mission.car, engine: engine, codename: mission.codename,
                                      trackName: mission.trackName, date: mission.date, unit: mission.unit,
                                      redline: mission.carRedline ?? garageCar?.redline ?? settings.redline, logo: BrandAssets.logo, mode: mission.mode,
                                      showSpeed: mission.mode == .track || settings.showSpeedOnRoad)
        let input = HighlightComposer.Input(mission: mission, track: track, options: options, style: style,
                                            music: BrandAssets.music)
        do {
            let url = try await HighlightComposer.render(input) { p in Task { @MainActor in progress = p } }
            mission.hasFilm = true
            store.save(mission)
            player = AVPlayer(url: url)
        } catch {
            message = error.localizedDescription
        }
        rendering = false
    }

    private func saveToPhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { message = "Photos access was declined."; return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: MissionStore.filmURL(mission.id))
            }
            message = "Saved to Photos."
        } catch { message = error.localizedDescription }
    }
}
