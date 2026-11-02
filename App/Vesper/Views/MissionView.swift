import AVFoundation
import SwiftUI
import VesperCore

/// What the phone shows while driving: almost nothing, on purpose.
///
/// Once the car is moving the camera preview disappears and the only thing left is a large
/// lap clock that can be read at a glance. Buttons only work when the car is stopped.
struct MissionView: View {
    @Bindable var controller: MissionController
    var dismiss: (UUID?) -> Void
    @Environment(DriverSettings.self) private var settings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch controller.phase {
            case .idle, .armed: armed
            case .rolling: rolling
            case .saving: saving
            case .done(let id): done(id)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private var armed: some View {
        VStack(spacing: 18) {
            Text("Armed").font(Theme.title(40)).foregroundStyle(Theme.gold)
            Text(controller.glasses.link.label).tracked(11)
            if controller.glasses.link == .streaming, controller.isStationary {
                GlassesPreview(layer: controller.glasses.previewLayer)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .frame(maxHeight: 360)
                    .overlay(Rectangle().stroke(Theme.gold.opacity(0.6)))
                Text("Glasses view. Check it's level, then drive.").font(.footnote).foregroundStyle(Theme.silver)
            }
            if let e = controller.error { Text(e).font(.footnote).foregroundStyle(Theme.signalRed) }
            Spacer()
            Text("Recording starts on its own once you're moving.").font(.footnote).foregroundStyle(Theme.silver)
            HStack(spacing: 12) {
                Button("Stand down") { controller.abort(); dismiss(nil) }
                    .buttonStyle(GoldButtonStyle(prominent: false))
                Button("Roll now") { controller.startNow() }
                    .buttonStyle(GoldButtonStyle())
            }
            .disabled(!controller.isStationary)
        }
        .padding(24)
    }

    private var rolling: some View {
        VStack(spacing: 10) {
            HStack {
                Circle().fill(Theme.signalRed).frame(width: 10, height: 10)
                Text("Rec").tracked(11, Theme.signalRed)
                Spacer()
                Text(controller.lapCount > 0 ? "Lap \(controller.lapCount + 1)" : "Out lap").tracked(11, Theme.gold)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Text(Format.lapTime(controller.currentLapStart.map { controller.missionTime - $0 } ?? controller.missionTime))
                    .font(.system(size: 76, weight: .light, design: .monospaced))
                    .foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            }
            if let best = controller.bestLap {
                Text("Best \(Format.lapTime(best.duration))").font(Theme.mono(22)).foregroundStyle(Theme.gold)
            }
            Spacer()
            Text(Format.speed(controller.speed, settings.unit)).font(Theme.mono(18)).foregroundStyle(Theme.silver)
            // Only usable once parked, and needs a deliberate hold.
            Text(controller.isStationary ? "Hold to end mission" : " ")
                .tracked(10).padding(.vertical, 18).frame(maxWidth: .infinity)
                .overlay(Rectangle().stroke(Theme.gold.opacity(controller.isStationary ? 0.6 : 0)))
                .onLongPressGesture(minimumDuration: 1.5) { if controller.isStationary { controller.finishNow() } }
        }
        .padding(24)
    }

    private var saving: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Theme.gold)
            Text("Securing the footage").tracked(11, Theme.gold)
        }
    }

    private func done(_ id: UUID) -> some View {
        VStack(spacing: 18) {
            Text("Mission complete").font(Theme.title(34)).foregroundStyle(Theme.gold)
            if let best = controller.bestLap {
                Text("Best lap \(Format.lapTime(best.duration))").font(Theme.mono(20)).foregroundStyle(.white)
            }
            Button("Open debrief") { dismiss(id) }.buttonStyle(GoldButtonStyle())
        }
        .padding(24)
    }
}

/// Hosts the glasses' live HEVC preview layer.
struct GlassesPreview: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerHost { LayerHost(hosted: layer) }
    func updateUIView(_ view: LayerHost, context: Context) {}

    final class LayerHost: UIView {
        let hosted: CALayer
        init(hosted: CALayer) {
            self.hosted = hosted
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(hosted)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            hosted.frame = bounds
        }
    }
}
