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
    @State private var editingCar: Car?

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            Form {
                Section("Driver") {
                    TextField("Callsign", text: $s.callsign)
                    Picker("Units", selection: $s.unit) { ForEach(SpeedUnit.allCases, id: \.self) { Text($0.label) } }
                }
                Section {
                    ForEach(s.cars) { car in
                        HStack {
                            Button { s.activeCarID = car.id } label: {
                                HStack {
                                    Image(systemName: car.id == s.activeCarID ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Theme.gold)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(car.name).foregroundStyle(.white)
                                        Text("\(car.engineLabel) · redline \(Int(car.redline).formatted()) rpm")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            Button { editingCar = car } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).tint(Theme.gold)
                        }
                        .swipeActions {
                            if s.cars.count > 1 {
                                Button("Delete", role: .destructive) { s.removeCar(car) }
                            }
                        }
                    }
                    Button { editingCar = s.addCar() } label: { Label("Add a car", systemImage: "plus") }
                } header: { Text("Garage") } footer: {
                    Text("Tap a car to take it on your next drive. Vesper reads revs from the engine's sound, so set each car's cylinders correctly. Swipe left to delete.")
                }
                Section {
                    Stepper("Start above \(Int(s.autoStartSpeed)) \(s.unit.label)", value: $s.autoStartSpeed, in: 5...60, step: 5)
                    Stepper("End after parked \(Int(s.autoStopMinutes * 60)) s", value: $s.autoStopMinutes, in: 0.25...5, step: 0.25)
                    Toggle("Spoken call-outs", isOn: $s.voiceCallouts)
                    Toggle("Lens display (Ray-Ban Display)", isOn: $s.lensDisplay)
                    Toggle("Speedometer in grand tour films", isOn: $s.showSpeedOnRoad)
                    Toggle("Speed & red-light camera alerts", isOn: $s.cameraAlerts)
                    Stepper(String(format: "Glasses delay %.2f s", s.glassesLatency), value: $s.glassesLatency, in: 0...1, step: 0.05)
                } header: { Text("Hands-free") } footer: {
                    Text("If the gauges in your film run ahead of the picture, raise the glasses delay. Camera locations © OpenStreetMap contributors; coverage depends on what's been mapped locally, so always watch the posted limits.")
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
                Section {
                    Toggle("Voice commands", isOn: $s.voiceCommands)
                        .onChange(of: s.voiceCommands) { _, on in
                            if on { Task { await glasses.enableVoice() } } else { glasses.disableVoice() }
                        }
                    if s.voiceCommands {
                        LabeledContent("Status", value: glasses.voiceStatus)
                        if glasses.needsMicrophone {
                            Button("Allow the glasses microphone") { Task { await glasses.enableVoice() } }
                        }
                    }
                } header: { Text("Hey Meta") } footer: {
                    Text("Say \u{201C}Hey Meta, start Vesper\u{201D} to open Vesper, then talk to it by name: \u{201C}Vesper, track day\u{201D}, \u{201C}Vesper, grand tour\u{201D}, \u{201C}Vesper, end mission\u{201D}, \u{201C}Vesper, stand down\u{201D}, \u{201C}Vesper, next car\u{201D}, or a car\u{2019}s name such as \u{201C}Vesper, DB9\u{201D}. Anything said without \u{201C}Vesper\u{201D} is ignored, so the radio and passengers can\u{2019}t set it off.")
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
            .sheet(item: $editingCar) { car in
                CarEditor(car: car) { edited in
                    if let i = settings.cars.firstIndex(where: { $0.id == edited.id }) { settings.cars[i] = edited }
                }
            }
            .fileImporter(isPresented: $pickingMusic, allowedContentTypes: [.audio]) { result in
                do { try BrandAssets.setMusic(from: result.get()); note = "Music saved."; refresh += 1 }
                catch { note = error.localizedDescription }
            }
        }
    }
}

/// Name, engine and redline for one car in the garage.
struct CarEditor: View {
    @State var car: Car
    var save: (Car) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $car.name)
                Stepper("Cylinders: \(car.cylinders)", value: $car.cylinders, in: 2...16)
                Stepper("Redline: \(Int(car.redline).formatted()) rpm", value: $car.redline, in: 3_000...10_000, step: 100)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if car.name.trimmingCharacters(in: .whitespaces).isEmpty { car.name = "Car" }
                        save(car); dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
