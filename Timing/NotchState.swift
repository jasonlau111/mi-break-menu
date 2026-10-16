import Foundation

/// Only display information leaves the timing domain; no account or device data.
nonisolated public struct NotchState: Equatable, Sendable {
    public let phase: String
    public let title: String
    public let detail: String
    public let compact: String
    public let icon: String
    public let attention: Bool
    public init?(engine: BreakEngine, now: Date) {
        guard !engine.paused, engine.presence != .unknown else { return nil }
        let minutes = Int(engine.seated / 60)
        attention = engine.needsReminder(at: now)
        if engine.presence == .away {
            if engine.seated == 0 {
                phase = "complete"; title = "休息完成"; detail = "下次入座重新计时"; compact = "已休息"; icon = "checkmark.circle"
            } else {
                phase = "rest"; title = "离座休息中"; detail = "本轮累计休息 \(engine.restMinutes) 分钟后归零"
                let n = Int(ceil(engine.remainingRest))
                compact = String(format: "还差 %02d:%02d", n / 60, n % 60); icon = "figure.walk"
            }
        } else if attention {
            phase = engine.shortReturn ? "short" : "due"
            title = engine.shortReturn ? "休息还不够" : "起来活动一下"
            detail = "已坐 \(minutes) 分钟，再休息 \(Int(ceil(engine.remainingRest / 60))) 分钟"
            compact = "该休息了"; icon = "figure.walk"
        } else {
            phase = engine.overtimeMinutes == nil ? "seated" : "overtime"
            title = engine.overtimeMinutes == nil ? "起身一下" : "临时加班中"
            detail = "距离起身提醒还有 \(Int(ceil(max(0, engine.target - engine.seated) / 60))) 分钟"
            compact = minutes == 0 ? "已坐 <1 分" : "已坐 \(minutes) 分"
            icon = engine.overtimeMinutes == nil ? "figure.seated.side" : "moon"
        }
    }
}
