import CarPlay
import VesperCore

/// Vesper on the car's screen: a CarPlay "driving task" app.
///
/// Shows mission status and lap times in large type, with Arm and End buttons that only
/// work while the car is stopped. Needs Apple's CarPlay Driving Task entitlement
/// (see README); without it this scene simply never connects.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var template: CPInformationTemplate?
    private var refresh: Timer?

    private var model: AppModel { AppModel.shared }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let t = CPInformationTemplate(title: "Vesper", layout: .twoColumn, items: [], actions: [])
        template = t
        update()
        interfaceController.setRootTemplate(t, animated: false, completion: nil)
        refresh = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        refresh?.invalidate()
        refresh = nil
        template = nil
        self.interfaceController = nil
    }

    private func update() {
        guard let template else { return }
        let unit = model.settings.unit
        var items: [CPInformationItem] = []
        var actions: [CPTextButton] = []

        if let m = model.activeMission {
            switch m.phase {
            case .idle, .armed:
                items.append(CPInformationItem(title: "Status", detail: "Armed. Recording starts when you drive."))
                items.append(CPInformationItem(title: "Glasses", detail: model.glasses.link.label))
                if m.isStationary {
                    actions.append(CPTextButton(title: "Stand down", textStyle: .cancel) { [weak self] _ in
                        m.abort(); self?.model.close(finished: nil); self?.update()
                    })
                }
            case .rolling:
                if m.mode == .road {
                    items.append(CPInformationItem(title: "Grand tour", detail: Format.speed(m.speed, unit)))
                    items.append(CPInformationItem(title: "Trip", detail: Format.distance(m.tripDistance, unit)))
                } else {
                    items.append(CPInformationItem(title: m.lapCount > 0 ? "Lap \(m.lapCount + 1)" : "Out lap",
                                                   detail: Format.speed(m.speed, unit)))
                }
                if let last = m.lastLap { items.append(CPInformationItem(title: "Last lap", detail: Format.lapTime(last.duration))) }
                if let best = m.bestLap { items.append(CPInformationItem(title: "Best lap", detail: Format.lapTime(best.duration))) }
                if m.isStationary {
                    actions.append(CPTextButton(title: "End mission", textStyle: .confirm) { _ in m.finishNow() })
                }
            case .saving:
                items.append(CPInformationItem(title: "Status", detail: "Saving footage…"))
            case .done(let id):
                items.append(CPInformationItem(title: "Mission complete", detail: "Debrief ready on your phone"))
                if let best = m.bestLap { items.append(CPInformationItem(title: "Best lap", detail: Format.lapTime(best.duration))) }
                actions.append(CPTextButton(title: "Done", textStyle: .confirm) { [weak self] _ in
                    self?.model.close(finished: id); self?.update()
                })
            }
        } else {
            items.append(CPInformationItem(title: "Glasses", detail: model.glasses.link.label))
            if let last = model.store.missions.first {
                items.append(CPInformationItem(title: "Last mission", detail: last.trackName))
                if let best = last.bestLap { items.append(CPInformationItem(title: "Best lap", detail: Format.lapTime(best.duration))) }
            }
            actions.append(CPTextButton(title: "Track day", textStyle: .confirm) { [weak self] _ in
                Task { await self?.model.arm(trackName: "", mode: .track); self?.update() }
            })
            actions.append(CPTextButton(title: "Grand tour", textStyle: .normal) { [weak self] _ in
                Task { await self?.model.arm(trackName: "", mode: .road); self?.update() }
            })
        }
        template.items = items
        template.actions = actions
    }
}
