import Foundation
import Testing
@testable import BreakCore

@Test func notchNeverTreatsUnknownOrPausedAsRest() {
    var engine = BreakEngine()
    let now = Date()
    #expect(NotchState(engine: engine, now: now) == nil)
    engine.observe(.seated, at: now)
    #expect(NotchState(engine: engine, now: now)?.compact == "已坐 <1 分")
    engine.setPaused(true, at: now)
    #expect(NotchState(engine: engine, now: now) == nil)
}

@Test func notchReflectsShortRestCompletionAndSnooze() {
    var engine = BreakEngine()
    let now = Date()
    engine.observe(.seated, at: now)
    for second in stride(from: 15, through: 2700, by: 15) { engine.observe(.seated, at: now.addingTimeInterval(Double(second))) }
    #expect(NotchState(engine: engine, now: now.addingTimeInterval(2700))?.phase == "due")
    engine.snooze(at: now.addingTimeInterval(2700))
    #expect(NotchState(engine: engine, now: now.addingTimeInterval(2700))?.attention == false)
    engine.observe(.away, at: now.addingTimeInterval(2700))
    for second in stride(from: 2715, through: 2760, by: 15) { engine.observe(.away, at: now.addingTimeInterval(Double(second))) }
    #expect(NotchState(engine: engine, now: now.addingTimeInterval(2760))?.compact == "还差 04:00")
    engine.observe(.seated, at: now.addingTimeInterval(2760))
    // Snooze is respected even after returning early.
    #expect(NotchState(engine: engine, now: now.addingTimeInterval(2760))?.attention == false)
    engine.observe(.away, at: now.addingTimeInterval(2760))
    for second in stride(from: 2775, through: 3000, by: 15) { engine.observe(.away, at: now.addingTimeInterval(Double(second))) }
    #expect(NotchState(engine: engine, now: now.addingTimeInterval(3000))?.phase == "complete")
    engine.observe(.seated, at: now.addingTimeInterval(3000))
    engine.setOvertime(90, at: now.addingTimeInterval(3000))
    #expect(NotchState(engine: engine, now: now.addingTimeInterval(3000))?.phase == "overtime")
}
