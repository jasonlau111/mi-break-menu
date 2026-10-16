import Foundation

/// Cloud presence is a sensor observation, not proof that someone resumed work.
nonisolated public struct PresenceResolver: Sendable {
    public private(set) var raw: Presence = .unknown
    public private(set) var observedAt: Date?
    public private(set) var effective: Presence = .unknown
    public private(set) var waitingForInput = false
    private var confirmed: Presence = .unknown
    private var awaySince: Date?
    public init() {}
    public mutating func observe(_ value: Presence, at now: Date) {
        raw = value; observedAt = now
    }
    public mutating func reset() { self = PresenceResolver() }
    public mutating func resolve(lastInput: Date?, at now: Date) -> Presence {
        waitingForInput = false
        guard let observedAt, now >= observedAt, now.timeIntervalSince(observedAt) <= 45, raw != .unknown else {
            effective = .unknown; return effective
        }
        if raw == .away {
            if confirmed != .away { awaySince = now }
            confirmed = .away; effective = .away
        } else if confirmed == .seated {
            // Reading/thinking without input does not turn work time into rest.
            effective = .seated
        } else {
            let recentInput = lastInput.map {
                $0 <= now && now.timeIntervalSince($0) <= 15 && (awaySince == nil || $0 > awaySince!)
            } ?? false
            if recentInput { confirmed = .seated; effective = .seated; awaySince = nil }
            else { effective = confirmed == .away ? .away : .unknown; waitingForInput = effective == .unknown }
        }
        return effective
    }
    public var restingWithoutInput: Bool { raw == .seated && effective == .away }
}
