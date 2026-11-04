import Foundation

/// Something the driver said to Vesper through the glasses' microphone.
public enum VoiceCommand: Equatable, Sendable {
    /// Arm a drive. `nil` means the last mode used.
    case start(DriveMode?)
    /// Finish the drive in progress and save it.
    case end
    /// Cancel an armed drive before it records anything.
    case standDown
    case nextCar
    /// Index into the garage.
    case selectCar(Int)
}

/// Turns a transcript into a command. A phrase only counts when it contains the wake word
/// ("Vesper, track day"), so passengers, the radio and phone calls can't start or end a drive.
public enum VoiceCommandParser {
    /// How speech recognisers tend to hear "Vesper".
    public static let wakeWords: Set<String> = ["vesper", "vespa", "vesta", "vespers"]

    public static func parse(_ transcript: String, cars: [String]) -> VoiceCommand? {
        let words = normalize(transcript)
        guard let wake = words.lastIndex(where: { wakeWords.contains($0) }) else { return nil }
        let after = Array(words[(wake + 1)...])
        guard !after.isEmpty else { return nil }
        let phrase = " " + after.joined(separator: " ") + " "
        func has(_ s: String) -> Bool { phrase.contains(" " + s + " ") }

        if has("stand down") || has("cancel") || has("abort") { return .standDown }
        if has("end") || has("stop") || has("finish") || has("done") || has("box box") { return .end }
        if has("next car") || has("switch car") || has("change car") || has("other car") { return .nextCar }
        if let i = carIndex(in: after, cars: cars) { return .selectCar(i) }
        if has("track") || has("track day") || has("circuit") { return .start(.track) }
        if has("grand tour") || has("tour") || has("road") || has("cruise") { return .start(.road) }
        if has("start") || has("go") || has("arm") || has("begin") || has("mission") { return .start(nil) }
        return nil
    }

    /// The garage car whose name appears in the words, matched with spaces removed so
    /// "DB 9", "DB9" and "DB nine" all find the DB9. The longest name wins.
    static func carIndex(in words: [String], cars: [String]) -> Int? {
        let compact = words.joined()
        var best: (index: Int, length: Int)?
        for (i, name) in cars.enumerated() {
            let key = normalize(name).joined()
            guard key.count >= 2, compact.contains(key) else { continue }
            if best == nil || key.count > best!.length { best = (i, key.count) }
        }
        return best?.index
    }

    /// Lowercased words with punctuation dropped and number words turned into digits.
    static func normalize(_ s: String) -> [String] {
        let cleaned = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").map { numbers[String($0)] ?? String($0) }
    }

    private static let numbers: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12",
    ]
}
