import AVFoundation

/// Short spoken call-outs in a British voice, played through the glasses' speakers,
/// so the driver never has to look at the phone.
@MainActor
final class Announcer {
    private let synth = AVSpeechSynthesizer()
    var enabled = true

    private lazy var voice: AVSpeechSynthesisVoice? = {
        let british = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-GB" }
        return british.first { $0.quality == .premium }
            ?? british.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-GB")
    }()

    var isSpeaking: Bool { synth.isSpeaking }

    func say(_ text: String) {
        guard enabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = 0.5
        u.pitchMultiplier = 0.9
        u.postUtteranceDelay = 0.1
        synth.speak(u)
    }
}
