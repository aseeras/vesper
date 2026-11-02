import Foundation

/// When to start and stop filming without the driver touching anything.
public struct AutoRecordPolicy: Codable, Hashable, Sendable {
    /// Start once speed stays above this (m/s) for `startHold` seconds.
    public var startSpeed: Double = 20 / 3.6
    public var startHold: Double = 2
    /// Finish once speed stays below this (m/s) for `stopHold` seconds.
    public var stopSpeed: Double = 5 / 3.6
    public var stopHold: Double = 45

    public init() {}
}

public enum AutoRecordEvent: Equatable, Sendable {
    case startRecording
    case finishMission
}

public struct AutoRecordController: Sendable {
    public enum State: Equatable, Sendable {
        case armed(fastSince: Double?)
        case rolling(slowSince: Double?)
        case finished
    }

    public var policy: AutoRecordPolicy
    public private(set) var state: State = .armed(fastSince: nil)

    public init(policy: AutoRecordPolicy = AutoRecordPolicy()) { self.policy = policy }

    public var isRolling: Bool { if case .rolling = state { return true } else { return false } }

    public mutating func update(speed: Double, at t: Double) -> AutoRecordEvent? {
        switch state {
        case .armed(let fastSince):
            guard speed >= policy.startSpeed else { state = .armed(fastSince: nil); return nil }
            let since = fastSince ?? t
            if t - since >= policy.startHold { state = .rolling(slowSince: nil); return .startRecording }
            state = .armed(fastSince: since)
        case .rolling(let slowSince):
            guard speed < policy.stopSpeed else { state = .rolling(slowSince: nil); return nil }
            let since = slowSince ?? t
            if t - since >= policy.stopHold { state = .finished; return .finishMission }
            state = .rolling(slowSince: since)
        case .finished:
            break
        }
        return nil
    }

    /// Manual start, e.g. a voice command or the pit-lane button.
    public mutating func forceStart() -> AutoRecordEvent? {
        guard case .armed = state else { return nil }
        state = .rolling(slowSince: nil)
        return .startRecording
    }

    public mutating func forceFinish() -> AutoRecordEvent? {
        guard state != .finished else { return nil }
        state = .finished
        return .finishMission
    }
}
