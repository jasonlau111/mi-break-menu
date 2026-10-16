import Foundation
import CoreGraphics

/// Reads only event ages; never installs an event tap or reads keys/coordinates.
nonisolated enum InputActivity {
    static func lastInput(at now: Date) -> Date? {
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown,
                                   .otherMouseDown, .mouseMoved, .leftMouseDragged,
                                   .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        let ages = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        guard let age = ages.filter({ $0.isFinite && $0 >= 0 }).min() else { return nil }
        return now.addingTimeInterval(-age)
    }
}
