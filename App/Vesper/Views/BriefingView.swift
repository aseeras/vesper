import SwiftUI
import VesperCore

/// Pre-drive: name the circuit, check the kit, arm. Then hands off to the mission screen.
struct BriefingView: View {
    var dismiss: (UUID?) -> Void
    @Environment(GlassesManager.self) private var glasses
    @Environment(MissionStore.self) private var store
    @Environment(DriverSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var trackName = ""

    var body: some View {
        Group {
            if let controller = model.activeMission {
                MissionView(controller: controller) { id in dismiss(id) }
            } else {
                form
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var lastTrack: String? { store.missions.first?.trackName }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Briefing").font(Theme.title(34)).foregroundStyle(Theme.gold)
                    Spacer()
                    Button { dismiss(nil) } label: { Image(systemName: "xmark").foregroundStyle(Theme.silver) }
                }
                Text(Format.codename(for: .now)).tracked(11, Theme.gold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Circuit").tracked(10)
                    TextField("e.g. Thunderhill East", text: $trackName)
                        .textFieldStyle(.plain).font(.title3).foregroundStyle(.white)
                        .padding(12).overlay(Rectangle().stroke(Theme.gold.opacity(0.5)))
                    if let lastTrack, trackName.isEmpty {
                        Button("Same as last time: \(lastTrack)") { trackName = lastTrack }.font(.footnote)
                    }
                }

                SectionRule(title: "Checklist")
                check("Glasses", glasses.link.label, ok: glasses.link == .ready || glasses.link == .streaming)
                check("Phone", "Mount it or leave it in the console. Screen stays on, you won't need to touch it.", ok: true)
                check("Recording", "Starts by itself above \(Int(settings.autoStartSpeed)) \(settings.unit.label). Ends after you park.", ok: true)
                check("Lap timing", "Start line is found automatically after your first full lap.", ok: true)
                if settings.lensDisplay {
                    check("Lens display", "Lap time, gap to best and speed. Nothing else.", ok: true)
                }

                Text("Track use only. Keep your eyes on the road; Vesper speaks to you so you never need to look down.")
                    .font(.footnote).foregroundStyle(Theme.silver.opacity(0.7))

                Button("Arm Vesper") { Task { await model.arm(trackName: trackName) } }
                .buttonStyle(GoldButtonStyle())
            }
            .padding(20)
        }
    }

    private func check(_ title: String, _ detail: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Theme.gold : Theme.signalRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).tracked(10, Theme.gold)
                Text(detail).font(.subheadline).foregroundStyle(.white)
            }
        }
    }
}
