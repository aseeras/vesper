import Foundation
import Observation
import UIKit
import MWDATCore
import MWDATDisplay
import VesperCore

/// Drives the Meta Ray-Ban Display's in-lens screen (600×600).
///
/// Each `send` replaces the whole layout and travels over Bluetooth, so live gauges are
/// rounded, de-duplicated and capped at a few refreshes a second. Lap cards hold the
/// screen for a few seconds before the live gauges come back.
/// SwiftUI is intentionally not imported: MWDATDisplay has its own `Text`.
@MainActor
@Observable
final class LensDisplay {
    /// Shown on the phone so a blank lens can be explained at a glance.
    private(set) var status = "Lens off"

    @ObservationIgnored private var display: Display?
    @ObservationIgnored private var token: AnyListenerToken?
    @ObservationIgnored private var ready = false
    /// What can be on the lens: text cards and gauges, or the racetrack welcome.
    private enum Content: Equatable { case hud(LensHUD), welcome }

    @ObservationIgnored private var shown: Content?
    @ObservationIgnored private var latest: Content?
    @ObservationIgnored private var revertTask: Task<Void, Never>?
    @ObservationIgnored private var holdUntil = Date.distantPast
    @ObservationIgnored private var lastSend = Date.distantPast
    /// Minimum gap between live refreshes.
    private let liveInterval: TimeInterval = 0.4

    func attach(to session: DeviceSession) {
        guard display == nil else { return }
        status = "Lens connecting…"
        do {
            let display = try session.addDisplay()
            self.display = display
            token = display.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if case .started = state { self.ready = true } else { self.ready = false }
                    self.status = self.ready ? "Lens live" : "Lens: \(state)"
                    if self.ready, let latest = self.latest { await self.send(latest) }
                }
            }
            display.start()
        } catch {
            print("Lens display unavailable: \(error)")
            status = "Lens unavailable: \(error.localizedDescription)"
        }
    }

    /// Live speed and revs. Dropped while a lap card is up or if the last refresh was too recent;
    /// the next reading catches up, so nothing stale lingers.
    func live(_ hud: LensHUD) {
        let now = Date()
        guard now >= holdUntil, now.timeIntervalSince(lastSend) >= liveInterval else { return }
        lastSend = now
        Task { await send(.hud(hud)) }
    }

    /// The racetrack welcome, shown from app launch until a drive is armed. Sent as soon as
    /// the lens is ready if it isn't yet.
    func showWelcome() {
        revertTask?.cancel()
        holdUntil = .distantPast
        Task { await send(.welcome) }
    }

    /// Show a card (lap complete, armed, finished). With `hold`, live updates pause that long.
    func show(_ hud: LensHUD, hold seconds: Double = 0, revertTo: LensHUD? = nil) {
        revertTask?.cancel()
        holdUntil = Date().addingTimeInterval(seconds)
        Task { await send(.hud(hud)) }
        guard let revertTo else { return }
        revertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(seconds, 1)))
            guard !Task.isCancelled else { return }
            await self?.send(.hud(revertTo))
        }
    }

    func detach() {
        revertTask?.cancel()
        display?.stop()
        token = nil
        display = nil
        ready = false
        shown = nil
        latest = nil
        status = "Lens off"
    }

    private func send(_ content: Content) async {
        latest = content
        guard let display, ready, content != shown else { return }
        do {
            switch content {
            case .hud(let hud):
                // Fixed three-line layout so the headline never moves.
                try await display.send(FlexBox(direction: .column, spacing: 10) {
                    Text(hud.headline, style: .heading)
                    Text(hud.detail ?? " ", style: .body)
                    Text(hud.footnote ?? " ", style: .meta, color: .secondary)
                })
            case .welcome:
                try await display.send(FlexBox(direction: .column, spacing: 8) {
                    Image(image: RacetrackArt.lensImage)
                    Text("VESPER", style: .heading)
                    Text("Ready when you are", style: .meta, color: .secondary)
                })
            }
            shown = content
        } catch {
            print("Lens display send failed: \(error)")
            status = "Lens send failed: \(error.localizedDescription)"
        }
    }
}
