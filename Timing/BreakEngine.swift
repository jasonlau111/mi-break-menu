import Foundation

nonisolated public enum Presence: String, Codable, Sendable { case seated, away, unknown }
nonisolated public struct Interval: Codable, Sendable {
    public var start: Date
    public var end: Date
    public var presence: Presence
    public var overtime: Bool
}
nonisolated public struct Milestone: Codable, Sendable {
    public var time: Date
    public var kind: String
    public var minutes: Int?
}
nonisolated public struct DaySummary: Sendable {
    public var seated: TimeInterval = 0
    public var away: TimeInterval = 0
    public var unknown: TimeInterval = 0
    public var longest: TimeInterval = 0
    public var overtime: TimeInterval = 0
    public var completed = 0
    public var intervals: [Interval] = []
    public var milestones: [Milestone] = []
}

/// All durations are observed time, never backfilled from an old cloud event.
/// Short absences accumulate toward this cycle's rest goal; unknown time never does.
nonisolated public struct BreakEngine: Codable, Sendable {
    public private(set) var presence: Presence = .unknown
    public private(set) var seated: TimeInterval = 0
    public private(set) var rest: TimeInterval = 0
    public private(set) var overtimeMinutes: Int? = nil
    public private(set) var shortReturn = false
    public private(set) var intervals: [Interval] = []
    public private(set) var milestones: [Milestone] = []
    public private(set) var lastTime: Date?
    public private(set) var lastObservation: Date?
    public private(set) var snoozedUntil: Date?
    public var workMinutes = 45
    public var restMinutes = 5
    public var paused = false
    public init() {}
    public var target: TimeInterval { Double(overtimeMinutes ?? workMinutes) * 60 }
    public var restTarget: TimeInterval { Double(restMinutes) * 60 }
    public var remainingRest: TimeInterval { max(0, restTarget - rest) }
    public var due: Bool { seated >= target }
    public func needsReminder(at now: Date) -> Bool {
        !paused && presence == .seated && (due || shortReturn) && (snoozedUntil == nil || now >= snoozedUntil!)
    }
    public mutating func observe(_ value: Presence, at now: Date) {
        advance(to: now)
        if value == .seated && presence == .away && rest > 0 && seated > 0 { shortReturn = true }
        if value == .away { shortReturn = false }
        presence = paused ? .unknown : value
        lastObservation = now
    }
    public mutating func invalidate(at now: Date) {
        advance(to: now)
        presence = .unknown
        lastObservation = nil
        shortReturn = false
    }
    public mutating func advance(to now: Date) {
        guard let previous = lastTime else { lastTime = now; return }
        guard now >= previous else { presence = .unknown; lastObservation = nil; lastTime = now; return }
        let elapsed = now.timeIntervalSince(previous)
        guard elapsed > 0 else { return }
        let stale = lastObservation.map { now.timeIntervalSince($0) > 45 } ?? true
        if elapsed > 45 || stale || paused { presence = .unknown }
        appendInterval(from: previous, to: now, state: presence)
        if presence == .seated { seated += elapsed }
        if presence == .away && seated > 0 {
            rest += elapsed
            if rest >= restTarget {
                milestones.append(Milestone(time: now, kind: "restCompleted", minutes: restMinutes))
                seated = 0; rest = 0; shortReturn = false; overtimeMinutes = nil; snoozedUntil = nil
            }
        }
        lastTime = now
    }
    private mutating func appendInterval(from start: Date, to end: Date, state: Presence) {
        if let last = intervals.last, last.presence == state, last.overtime == (overtimeMinutes != nil), last.end == start {
            intervals[intervals.count - 1].end = end
        } else {
            intervals.append(Interval(start: start, end: end, presence: state, overtime: overtimeMinutes != nil))
        }
    }
    public mutating func recordReminder(at now: Date) {
        milestones.append(Milestone(time: now, kind: rest > 0 ? "shortRestReminder" : "workReminder", minutes: nil))
    }
    public mutating func snooze(at now: Date) {
        advance(to: now); snoozedUntil = now.addingTimeInterval(300); shortReturn = false
        milestones.append(Milestone(time: now, kind: "snooze", minutes: 5))
    }
    public mutating func setOvertime(_ minutes: Int?, at now: Date) {
        advance(to: now)
        guard minutes == nil || [60, 90, 120].contains(minutes!) else { return }
        overtimeMinutes = minutes; shortReturn = false; snoozedUntil = nil
        milestones.append(Milestone(time: now, kind: minutes == nil ? "normal" : "overtime", minutes: minutes))
    }
    public mutating func setPaused(_ value: Bool, at now: Date) {
        invalidate(at: now); paused = value
        milestones.append(Milestone(time: now, kind: value ? "pause" : "resume", minutes: nil))
    }
    public mutating func restored(at now: Date) {
        // The period while the application was not running is explicitly unknown.
        if let lastTime, now > lastTime { appendInterval(from: lastTime, to: now, state: .unknown) }
        lastTime = now; lastObservation = nil; presence = .unknown; shortReturn = false; snoozedUntil = nil
    }
    public func summary(day: Date, now: Date, calendar: Calendar = .current) -> DaySummary {
        guard let range = calendar.dateInterval(of: .day, for: day) else { return DaySummary() }
        var result = DaySummary()
        var run: TimeInterval = 0
        var previousEnd: Date?
        for original in intervals where original.end > range.start && original.start < range.end {
            let start = max(original.start, range.start), end = min(original.end, range.end, now)
            guard end > start else { continue }
            let duration = end.timeIntervalSince(start)
            result.intervals.append(Interval(start: start, end: end, presence: original.presence, overtime: original.overtime))
            switch original.presence {
            case .seated:
                result.seated += duration
                run = (previousEnd == start ? run : 0) + duration
                result.longest = max(result.longest, run)
                if original.overtime { result.overtime += duration }
            case .away: result.away += duration; run = 0
            case .unknown: result.unknown += duration; run = 0
            }
            previousEnd = end
        }
        result.milestones = milestones.filter { range.contains($0.time) }
        result.completed = result.milestones.filter { $0.kind == "restCompleted" }.count
        return result
    }
}
