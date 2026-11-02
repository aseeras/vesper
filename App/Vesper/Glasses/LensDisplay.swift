import Foundation
import MWDATCore
import MWDATDisplay
import VesperCore

/// Drives the Meta Ray-Ban Display's in-lens screen (600×600).
///
/// Each `send` replaces the whole layout and travels over Bluetooth, so we only send when
/// the content changes (armed, lap completed, mission over), never on a timer.
/// SwiftUI is intentionally not imported: MWDATDisplay has its own `Text`.
@MainActor
final class LensDisplay {
    private var display: Display?
    private var token: AnyListenerToken?
    private var ready = false
    private var shown: LensHUD?
    private var latest: LensHUD?
    private var revertTask: Task<Void, Never>?

    func attach(to session: DeviceSession) {
        guard display == nil else { return }
        do {
            let display = try session.addDisplay()
            self.display = display
            token = display.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if case .started = state { self.ready = true } else { self.ready = false }
                    if self.ready, let latest = self.latest { await self.send(latest) }
                }
            }
            display.start()
        } catch {
            print("Lens display unavailable: \(error)")
        }
    }

    /// Show `hud`; if `revertTo` is given, switch to it after `seconds`.
    func show(_ hud: LensHUD, revertTo: LensHUD? = nil, after seconds: Double = 8) {
        revertTask?.cancel()
        Task { await send(hud) }
        guard let revertTo else { return }
        revertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.send(revertTo)
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
    }

    private func send(_ hud: LensHUD) async {
        latest = hud
        guard let display, ready, hud != shown else { return }
        // Fixed three-line layout so the headline never moves.
        let view = FlexBox(direction: .column, spacing: 10) {
            Text(hud.headline, style: .heading)
            Text(hud.detail ?? " ", style: .body)
            Text(hud.footnote ?? " ", style: .meta, color: .secondary)
        }
        do {
            try await display.send(view)
            shown = hud
        } catch {
            print("Lens display send failed: \(error)")
        }
    }
}
