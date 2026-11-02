import SwiftUI

@main
struct VesperApp: App {
    @State private var model = AppModel.shared
    @State private var showIntro = true

    init() {
        GlassesManager.configureAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                HomeView()
                if showIntro {
                    ApertureIntroView { withAnimation(.easeOut(duration: 0.4)) { showIntro = false } }
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environment(model)
            .environment(model.glasses)
            .environment(model.store)
            .environment(model.settings)
            .preferredColorScheme(.dark)
            .tint(Theme.gold)
            .task { await model.glasses.observe() }
            .task { await model.glasses.observeDevices() }
            .onOpenURL { url in Task { await model.glasses.handle(url: url) } }
        }
    }
}
