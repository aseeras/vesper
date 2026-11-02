import SwiftUI
import VesperCore

/// The dossier: glasses status, past missions, and the way into a new one.
struct HomeView: View {
    @Environment(GlassesManager.self) private var glasses
    @Environment(MissionStore.self) private var store
    @Environment(DriverSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var briefing = false
    @State private var showSettings = false
    @State private var path: [Mission] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    glassesCard
                    Button("Begin mission") { briefing = true }
                        .buttonStyle(GoldButtonStyle())
                    SectionRule(title: "Dossier")
                    if store.missions.isEmpty {
                        Text("No missions on file. Arm Vesper, drive, and your first film will be waiting here.")
                            .font(.footnote).foregroundStyle(Theme.silver.opacity(0.7))
                    }
                    ForEach(store.missions) { m in
                        NavigationLink(value: m) { MissionRow(mission: m, unit: settings.unit) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationDestination(for: Mission.self) { DebriefView(mission: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: Binding(get: { briefing || model.activeMission != nil },
                                                  set: { if !$0 { briefing = false } })) {
                BriefingView { finished in
                    briefing = false
                    model.close(finished: finished)
                }
            }
            .onChange(of: model.finishedMissionID) { _, id in
                if let id, let m = store.missions.first(where: { $0.id == id }) { path = [m] }
                model.finishedMissionID = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let logo = BrandAssets.logo {
                    Image(uiImage: logo).resizable().scaledToFit().frame(height: 34)
                }
                Text("VESPER").font(Theme.title(40)).foregroundStyle(Theme.gold).tracking(8)
            }
            Text("Eyes only · \(settings.callsign) · \(settings.car)").tracked(10)
        }
        .padding(.top, 8)
    }

    private var glassesCard: some View {
        DossierCard(stamp: glasses.isRegistered ? nil : "Action required") {
            HStack {
                Image(systemName: "eyeglasses").font(.title2).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glasses").tracked(10, Theme.gold)
                    Text(glasses.link.label).font(.headline).foregroundStyle(.white)
                }
                Spacer()
                if !glasses.isRegistered {
                    Button("Pair") { Task { await glasses.register() } }
                        .buttonStyle(GoldButtonStyle(prominent: false)).frame(width: 90)
                }
            }
        }
    }
}

struct MissionRow: View {
    var mission: Mission
    var unit: SpeedUnit

    var body: some View {
        DossierCard(stamp: mission.hasFilm ? "Film ready" : nil) {
            Text(mission.codename).tracked(10, Theme.gold)
            Text(mission.trackName).font(Theme.title(24)).foregroundStyle(.white)
            HStack(spacing: 16) {
                Label(mission.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                if let best = mission.bestLap { Label(Format.lapTime(best.duration), systemImage: "stopwatch") }
                Label("\(mission.laps.count) laps", systemImage: "flag.checkered")
            }
            .font(.caption).foregroundStyle(Theme.silver)
        }
    }
}
