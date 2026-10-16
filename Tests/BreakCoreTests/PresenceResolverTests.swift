import Foundation
import Testing
@testable import BreakCore

@Test func passByWithoutInputContinuesRestButActualInputResumes() {
    var r = PresenceResolver()
    r.observe(.away, at: epoch)
    #expect(r.resolve(lastInput: epoch.addingTimeInterval(-1), at: epoch) == .away)
    r.observe(.seated, at: epoch.addingTimeInterval(15))
    #expect(r.resolve(lastInput: epoch, at: epoch.addingTimeInterval(15)) == .away)
    #expect(r.restingWithoutInput)
    for n in stride(from: 30, through: 300, by: 15) {
        let now = epoch.addingTimeInterval(Double(n))
        r.observe(.seated, at: now)
        #expect(r.resolve(lastInput: epoch, at: now) == .away)
    }
    #expect(r.resolve(lastInput: epoch.addingTimeInterval(301), at: epoch.addingTimeInterval(301)) == .seated)
    r.observe(.seated, at: epoch.addingTimeInterval(330))
    #expect(r.resolve(lastInput: epoch.addingTimeInterval(301), at: epoch.addingTimeInterval(330)) == .seated)
}

@Test func inputAloneNeverOverridesNoOneOrStaleSensor() {
    var r = PresenceResolver()
    r.observe(.away, at: epoch)
    #expect(r.resolve(lastInput: epoch, at: epoch) == .away)
    #expect(r.resolve(lastInput: epoch.addingTimeInterval(46), at: epoch.addingTimeInterval(46)) == .unknown)
    r.reset(); r.observe(.seated, at: epoch)
    #expect(r.resolve(lastInput: nil, at: epoch) == .unknown)
    #expect(r.waitingForInput)
    #expect(r.resolve(lastInput: epoch, at: epoch) == .seated)
    #expect(r.resolve(lastInput: epoch, at: epoch.addingTimeInterval(46)) == .unknown)
    #expect(!r.waitingForInput)
    r.reset()
    #expect(r.resolve(lastInput: epoch, at: epoch) == .unknown)
}

@Test func passByRestCompletesOnlyAtGoalAndEarlyWorkRetainsDebt() {
    var r = PresenceResolver(), e = BreakEngine()
    elapse(&e, .seated, from: epoch, seconds: 2700)
    let start = epoch.addingTimeInterval(2700)
    r.observe(.away, at: start)
    e.observe(r.resolve(lastInput: nil, at: start), at: start)
    for n in stride(from: 15, through: 60, by: 15) {
        let now = start.addingTimeInterval(Double(n))
        r.observe(.seated, at: now)
        e.observe(r.resolve(lastInput: nil, at: now), at: now)
    }
    #expect(e.rest == 60 && e.seated == 2700)
    let returned = start.addingTimeInterval(60)
    e.observe(r.resolve(lastInput: returned, at: returned), at: returned)
    #expect(e.shortReturn && e.remainingRest == 240 && e.seated == 2700)
}
