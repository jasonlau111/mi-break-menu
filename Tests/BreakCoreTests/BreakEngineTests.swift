import Foundation
import Testing
@testable import BreakCore

let epoch = Date(timeIntervalSince1970: 1_800_000_000)
func elapse(_ engine: inout BreakEngine, _ state: Presence, from start: Date, seconds: Int) {
    engine.observe(state, at: start)
    for offset in stride(from: 15, through: seconds, by: 15) { engine.observe(state, at: start.addingTimeInterval(Double(offset))) }
    engine.observe(state, at: start.addingTimeInterval(Double(seconds)))
}

@Test func normalReminderShortBreakThenComplete() {
    var e = BreakEngine()
    elapse(&e, .seated, from: epoch, seconds: 2700)
    #expect(e.needsReminder(at: epoch.addingTimeInterval(2700)))
    elapse(&e, .away, from: epoch.addingTimeInterval(2700), seconds: 60)
    e.observe(.seated, at: epoch.addingTimeInterval(2760))
    #expect(e.seated == 2700)
    #expect(e.rest == 60)
    #expect(e.remainingRest == 240)
    #expect(e.shortReturn)
    #expect(e.needsReminder(at: epoch.addingTimeInterval(2760)))
    elapse(&e, .away, from: epoch.addingTimeInterval(2760), seconds: 240)
    #expect(e.seated == 0 && e.rest == 0)
    #expect(e.milestones.filter { $0.kind == "restCompleted" }.count == 1)
    elapse(&e, .away, from: epoch.addingTimeInterval(3000), seconds: 3600)
    #expect(e.seated == 0)
    #expect(e.milestones.filter { $0.kind == "restCompleted" }.count == 1)
    elapse(&e, .seated, from: epoch.addingTimeInterval(6600), seconds: 30)
    #expect(e.seated == 30)
}

@Test(arguments: [60, 90, 120]) func overtimeIsTotalLimitAndResets(minutes: Int) {
    var e = BreakEngine()
    elapse(&e, .seated, from: epoch, seconds: 2700)
    e.setOvertime(minutes, at: epoch.addingTimeInterval(2700))
    #expect(!e.due)
    let end = minutes * 60
    elapse(&e, .seated, from: epoch.addingTimeInterval(2700), seconds: end - 2700)
    #expect(e.due)
    e.setOvertime(minutes, at: epoch.addingTimeInterval(Double(end)))
    #expect(e.due) // Clicking the same mode does not add another hour.
    elapse(&e, .away, from: epoch.addingTimeInterval(Double(end)), seconds: 300)
    #expect(e.overtimeMinutes == nil && e.target == 2700)
}

@Test func unknownSleepAndRestartNeverGrantRest() {
    var e = BreakEngine()
    elapse(&e, .seated, from: epoch, seconds: 120)
    elapse(&e, .away, from: epoch.addingTimeInterval(120), seconds: 60)
    e.advance(to: epoch.addingTimeInterval(7200))
    #expect(e.presence == .unknown)
    #expect(e.seated == 120 && e.rest == 60)
    e.restored(at: epoch.addingTimeInterval(9000))
    #expect(e.presence == .unknown && e.rest == 60)
    #expect(e.milestones.isEmpty)
}

@Test func staleObservationExpiresAndClockReversalIsUnknown() {
    var e = BreakEngine()
    e.observe(.seated, at: epoch)
    for offset in 1...60 { e.advance(to: epoch.addingTimeInterval(Double(offset))) }
    #expect(e.presence == .unknown)
    #expect(e.seated == 45)
    e.advance(to: epoch.addingTimeInterval(-30))
    #expect(e.presence == .unknown)
}

@Test func snoozePauseAndResume() {
    var e = BreakEngine()
    elapse(&e, .seated, from: epoch, seconds: 2700)
    let due = epoch.addingTimeInterval(2700)
    e.snooze(at: due)
    #expect(!e.needsReminder(at: due.addingTimeInterval(299)))
    #expect(e.needsReminder(at: due.addingTimeInterval(300)))
    e.setPaused(true, at: due)
    elapse(&e, .seated, from: due, seconds: 600)
    #expect(e.seated == 2700)
    #expect(e.presence == .unknown)
    e.setPaused(false, at: due.addingTimeInterval(600))
    #expect(e.presence == .unknown)
}

@Test func dailySummarySplitsMidnightAndModes() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let midnight = cal.startOfDay(for: epoch)
    let start = midnight.addingTimeInterval(-120)
    var e = BreakEngine()
    elapse(&e, .seated, from: start, seconds: 60)
    e.setOvertime(90, at: start.addingTimeInterval(60))
    elapse(&e, .seated, from: start.addingTimeInterval(60), seconds: 180)
    let prior = e.summary(day: start, now: midnight.addingTimeInterval(120), calendar: cal)
    let today = e.summary(day: midnight, now: midnight.addingTimeInterval(120), calendar: cal)
    #expect(prior.seated == 120 && today.seated == 120)
    #expect(prior.longest == 120 && today.longest == 120)
    #expect(prior.overtime == 60 && today.overtime == 120)
}

@Test func snapshotRoundTripAndUnknownOnRestore() throws {
    var original = BreakEngine()
    elapse(&original, .seated, from: epoch, seconds: 120)
    original.setOvertime(120, at: epoch.addingTimeInterval(120))
    let data = try JSONEncoder().encode(original)
    var restored = try JSONDecoder().decode(BreakEngine.self, from: data)
    restored.restored(at: epoch.addingTimeInterval(300))
    #expect(restored.seated == 120 && restored.overtimeMinutes == 120)
    #expect(restored.presence == .unknown)
    #expect(restored.intervals.last?.presence == .unknown)
}
