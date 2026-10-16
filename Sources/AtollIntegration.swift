import AppKit
import Observation
import BreakCore
import AtollRPC

@MainActor @Observable final class AtollIntegration {
    private(set) var enabled: Bool
    private(set) var status = "未启用"
    private(set) var connected = false
    var fullscreenEnabled: Bool {
        didSet { UserDefaults.standard.set(fullscreenEnabled, forKey: "fullscreenEnabled") }
    }
    var onReminderPresented: (() -> Void)?
    private let client = AtollRPCClient(bundleIdentifier: "app.mibreak.menu")
    private let activityID = "mi-break-presence"
    private var desired: NotchState?
    private var presented: NotchState?
    private var task: Task<Void, Never>?
    private var authorize = false
    private var nextAttempt = Date.distantPast
    private var completedAt: Date?
    private var dismissedPhase: String?
    private var stopping = false
    private var ownsActivity = false
    private var removing = false

    init() {
        enabled = UserDefaults.standard.bool(forKey: "atollEnabled")
        fullscreenEnabled = UserDefaults.standard.object(forKey: "fullscreenEnabled") as? Bool ?? true
        if enabled { status = "等待连接 Atoll" }
        client.onAtollLifecycleChange { [weak self] state in
            guard let self else { return }
            presented = nil; connected = false; nextAttempt = .distantPast
            if state == .idle { client.disconnect(); status = enabled ? "Atoll 未运行，原有监测继续" : "未启用" }
        }
        client.onAuthorizationChange { [weak self] allowed in
            guard let self else { return }
            if !allowed { presented = nil; connected = false; status = "请在 Atoll 中允许起身一下" }
        }
        client.onActivityDismiss(activityID: activityID) { [weak self] in
            guard let self, !removing, let presented else { return }
            dismissedPhase = presented.phase; self.presented = nil; ownsActivity = false
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "atollEnabled")
        authorize = value; nextAttempt = .distantPast; dismissedPhase = nil
        status = value ? "正在连接 Atoll…" : "正在关闭…"
        schedule()
    }
    func retryAuthorization() { authorize = true; nextAttempt = .distantPast; dismissedPhase = nil; schedule() }
    func update(engine: BreakEngine, now: Date) {
        let state = NotchState(engine: engine, now: now)
        if state?.phase != desired?.phase {
            dismissedPhase = nil
            completedAt = state?.phase == "complete" ? now : nil
        }
        desired = state
        schedule()
    }
    private func schedule() {
        guard !stopping, task == nil, Date() >= nextAttempt else { return }
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
            await synchronize()
        }
    }
    private func removeActivity() async throws {
        guard ownsActivity else { return }
        removing = true
        defer { removing = false }
        try await client.dismissLiveActivity(activityID: activityID)
        presented = nil; ownsActivity = false
    }
    private func synchronize() async {
        do {
            if !enabled {
                try await removeActivity(); client.disconnect(); connected = false; status = "未启用"; return
            }
            if !client.isConnected { presented = nil; try await client.connect() }
            let allowed: Bool
            if authorize { authorize = false; allowed = try await client.requestAuthorization() }
            else if !connected { allowed = try await client.checkAuthorization() }
            else { allowed = true }
            guard enabled, !stopping else { return }
            guard allowed else {
                connected = false; status = "请在 Atoll 扩展中允许起身一下"; nextAttempt = Date().addingTimeInterval(15); return
            }
            connected = true; status = "Atoll 已连接"
            guard let state = desired, state.phase != dismissedPhase,
                  !(state.phase == "complete" && Date().timeIntervalSince(completedAt ?? .distantPast) > 8) else {
                try await removeActivity(); return
            }
            guard state != presented else { return }
            let phaseChanged = state.phase != presented?.phase
            let color = AtollColorDescriptor(red: 0.88, green: 0.89, blue: 0.80)
            let descriptor = AtollLiveActivityDescriptor(
                id: activityID, bundleIdentifier: "app.mibreak.menu",
                priority: state.attention ? .high : .normal,
                title: state.title, subtitle: state.detail,
                leadingIcon: .symbol(name: state.icon),
                trailingContent: .text(state.compact, color: color), accentColor: color,
                allowsMusicCoexistence: true,
                sneakPeekConfig: AtollSneakPeekConfig(enabled: phaseChanged, duration: state.attention ? 8 : 3, style: .standard, showOnUpdate: phaseChanged),
                sneakPeekTitle: state.title, sneakPeekSubtitle: state.detail)
            // Atoll's update endpoint updates content only; present replaces the same ID
            // and evaluates showOnUpdate for phase transitions.
            if presented == nil || phaseChanged { try await client.presentLiveActivity(descriptor) }
            else { try await client.updateLiveActivity(descriptor) }
            presented = state; ownsActivity = true
            if phaseChanged && state.attention { onReminderPresented?() }
        } catch {
            connected = false; presented = nil; client.disconnect()
            status = enabled ? "Atoll 连接不可用，请检查扩展与 RPC 开关" : "未启用"
            nextAttempt = Date().addingTimeInterval(15)
        }
    }
    func disconnectForTermination() { client.disconnect() }
    func shutdown() async {
        stopping = true
        // Disconnect first to finish any pending SDK request, then remove our activity.
        client.disconnect()
        await task?.value
        if ownsActivity {
            do { try await client.connect(); try await client.dismissLiveActivity(activityID: activityID) } catch { }
        }
        client.disconnect()
    }
}
