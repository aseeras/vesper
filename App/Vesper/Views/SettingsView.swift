import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VesperCore

struct SettingsView: View {
    @Environment(DriverSettings.self) private var settings
    @Environment(GlassesManager.self) private var glasses
    @Environment(\.dismiss) private var dismiss
    @State private var logoItem: PhotosPickerItem?
    @State private var pickingMusic = false
    @State private var note: String?
    @State private var refresh = 0

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            Form {
                Section("Driver") {
                    TextField("Callsign", text: $s.callsign)
                    TextField("Car", text: $s.car)
                    Picker("Units", selection: $s.unit) { ForEach(SpeedUnit.allCases, id: \.self) { Text($0.label) } }
                }
                Section {
                    Stepper("Cylinders: \(s.cylinders)", value: $s.cylinders, in: 4...16, step: 2)
                    Stepper("Redline: \(Int(s.redline)) rpm", value: $s.redline, in: 4_000...9_000, step: 100)
                } header: { Text("Engine") } footer: {
                    Text("Vesper reads revs from the engine's sound. DB9: 12 cylinders.")
                }
                Section {
                    Stepper("Start above \(Int(s.autoStartSpeed)) \(s.unit.label)", value: $s.autoStartSpeed, in: 5...60, step: 5)
                    Stepper("End after parked \(Int(s.autoStopMinutes * 60)) s", value: $s.autoStopMinutes, in: 0.25...5, step: 0.25)
                    Toggle("Spoken call-outs", isOn: $s.voiceCallouts)
                    Toggle("Lens display (Ray-Ban Display)", isOn: $s.lensDisplay)
                    Toggle("Speedometer in grand tour films", isOn: $s.showSpeedOnRoad)
                    Stepper(String(format: "Glasses delay %.2f s", s.glassesLatency), value: $s.glassesLatency, in: 0...1, step: 0.05)
                } header: { Text("Hands-free") } footer: {
                    Text("If the gauges in your film run ahead of the picture, raise the glasses delay.")
                }
                Section {
                    PhotosPicker(selection: $logoItem, matching: .images) {
                        Label(BrandAssets.logo == nil ? "Add your logo" : "Replace logo", systemImage: "seal")
                    }
                    if BrandAssets.logo != nil {
                        Button("Remove logo", role: .destructive) {
                            try? FileManager.default.removeItem(at: BrandAssets.userLogoURL); refresh += 1
                        }
                    }
                    Button { pickingMusic = true } label: {
                        Label(BrandAssets.userMusicURL == nil ? "Use your own music" : "Replace music", systemImage: "music.note")
                    }
                    if BrandAssets.userMusicURL != nil {
                        Button("Back to Vesper's theme", role: .destructive) { BrandAssets.clearMusic(); refresh += 1 }
                    }
                    if let note { Text(note).font(.footnote) }
                } header: { Text("Your logo and soundtrack") } footer: {
                    Text("Shown in the title sequence and corner of every film. Use a PNG with a transparent background. Music must be a file you own, not an Apple Music stream.")
                }
                Section("Glasses") {
                    LabeledContent("Status", value: glasses.link.label)
                    if glasses.isRegistered {
                        Button("Unpair", role: .destructive) { Task { await glasses.unregister() } }
                    } else {
                        Button("Pair glasses") { Task { await glasses.register() } }
                    }
                }
            }
            .id(refresh)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: logoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let img = UIImage(data: data), let png = img.pngData() else { return }
                    try? png.write(to: BrandAssets.userLogoURL)
                    note = "Logo saved."; refresh += 1
                }
            }
            .fileImporter(isPresented: $pickingMusic, allowedContentTypes: [.audio]) { result in
                do { try BrandAssets.setMusic(from: result.get()); note = "Music saved."; refresh += 1 }
                catch { note = error.localizedDescription }
            }
        }
    }
}
