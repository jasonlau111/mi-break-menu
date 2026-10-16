import BreakCore
import AppKit
import Observation

enum PanelPage { case overview, connection, history }

@MainActor @Observable final class Model {
    let atoll = AtollIntegration()
    var engine = BreakEngine()
    private var presenceResolver = PresenceResolver()
    var account: Account?
    var qr: NSImage?
    var candidates: [Sensor] = []
    var pendingSession: CloudSession?
    var region = "cn"
    var message = "扫码连接座位传感器，开始记录"
    var storageError: String?
    var pairing = false
    var busy = false
    var page: PanelPage = .overview
    var lastRead: Date?
    var selectedDay = Date()
    var now = Date()
    let preview: Bool
    private let bridge = Bridge()
    private var journal: Journal?
    private var pairTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var lastSaved = Date.distantPast
    private var lastAttempt = Date.distantPast
    private var generation = 0
    var onTick: (() -> Void)?

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            message = "界面预览 · 模拟数据，不读取米家或真实记录"
            let start = Date().addingTimeInterval(-2720)
            engine.observe(.seated, at: start)
            for s in stride(from: 15, through: 2700, by: 15) { engine.observe(.seated, at: start.addingTimeInterval(Double(s))) }
            engine.observe(.away, at: start.addingTimeInterval(2710))
            engine.observe(.seated, at: start.addingTimeInterval(2720))
            return
        }
        do { let store = try Journal(); journal = store; engine = try store.load(); engine.restored(at: now) }
        catch { storageError = error.localizedDescription }
        do { account = try Vault.load(); if account != nil { message = "正在读取米家状态" } }
        catch { message = error.localizedDescription }
    }
    func start() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
    }
    func tick() {
        now = Date()
        if !preview {
            if !engine.paused { resolvePresence(at: now) }
            else { engine.advance(to: now) }
            if account != nil && !pairing && !busy && !engine.paused && now.timeIntervalSince(lastAttempt) >= 15 { refresh() }
            if now.timeIntervalSince(lastSaved) >= 30 { save() }
        }
        onTick?()
    }
    private func resolvePresence(at time: Date) {
        let effective = presenceResolver.resolve(lastInput: InputActivity.lastInput(at: time), at: time)
        engine.observe(effective, at: time)
    }
    private func invalidatePresence(at time: Date) {
        presenceResolver.reset(); engine.invalidate(at: time)
    }
    var restingWithoutInput: Bool { presenceResolver.restingWithoutInput }
    var presenceExplanation: String {
        if engine.paused { return "监测已暂停" }
        if presenceResolver.restingWithoutInput { return "检测到附近有人，未操作电脑 · 继续休息" }
        if presenceResolver.waitingForInput { return "检测到有人 · 等待键鼠或触控板操作" }
        return engine.presence == .away ? "传感器无人 · 休息计时中" : engine.presence == .seated ? "已确认在座 · 人在＋电脑操作" : "等待有效传感器状态"
    }
    func save() {
        guard !preview else { return }
        do { guard let journal else { return }; try journal.save(engine); storageError = nil; lastSaved = Date() }
        catch { storageError = error.localizedDescription }
    }
    func stop() { timerTask?.cancel(); pairTask?.cancel(); readTask?.cancel(); bridge.cancel(); invalidatePresence(at: Date()); save() }
    func sleep() { generation += 1; readTask?.cancel(); bridge.cancel(); invalidatePresence(at: Date()); save(); onTick?() }
    func wake() { invalidatePresence(at: Date()); lastAttempt = .distantPast }
    func readRequest(_ account: Account) throws -> [String: Any] {
        let session = try JSONSerialization.jsonObject(with: JSONEncoder().encode(account.session))
        return ["op":"read", "session":session, "did":account.sensor.did, "model":account.sensor.model]
    }
    func refresh() {
        guard let account, !pairing, !busy, !preview else { return }
        busy = true; lastAttempt = Date()
        let version = generation
        readTask = Task {
            defer { busy = false }
            do {
                let reply = try await bridge.call(readRequest(account))
                guard version == generation else { return }
                guard let reading = reply.reading else { throw AppFailure.message("未返回传感器状态") }
                let receivedAt = Date()
                presenceResolver.observe(reading.presence, at: receivedAt)
                if !engine.paused { resolvePresence(at: receivedAt) }
                lastRead = receivedAt; message = reading.note
                if let name = reading.deviceName, !name.isEmpty, name != account.sensor.name {
                    let updated = Account(session: account.session, sensor: Sensor(name: name, model: account.sensor.model, did: account.sensor.did, supported: account.sensor.supported))
                    try Vault.save(updated); self.account = updated
                }
            } catch {
                guard version == generation else { return }
                invalidatePresence(at: Date()); message = error.localizedDescription
            }
            save(); onTick?()
        }
    }
    func pair() {
        guard !busy, !pairing, !preview else { return }
        pairing = true; candidates = []; pendingSession = nil; qr = nil; message = "正在生成二维码…"
        invalidatePresence(at: Date())
        pairTask = Task {
            defer { pairing = false; qr = nil }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mi-break-" + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: folder) }
                let file = folder.appendingPathComponent("login.png")
                let watcher = Task {
                    while !Task.isCancelled {
                        if let image = NSImage(contentsOf: file) { qr = image; message = "请用米家扫码，并在手机上确认登录"; break }
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                    }
                }
                defer { watcher.cancel() }
                let reply = try await bridge.call(["op":"pair", "region":region, "qr":file.path])
                pendingSession = reply.session
                candidates = reply.devices ?? []
                message = candidates.isEmpty ? "该地区未找到人在传感器，请核对米家地区" : "已登录，请选择座位传感器"
            } catch { message = error is CancellationError ? "已取消扫码" : error.localizedDescription }
        }
    }
    func cancelPair() { pairTask?.cancel(); bridge.cancel(); pendingSession = nil; candidates = [] }
    func choose(_ sensor: Sensor) {
        guard sensor.supported, let session = pendingSession, !busy else { return }
        let value = Account(session: session, sensor: sensor)
        do {
            try Vault.save(value)
            generation += 1; account = value; pendingSession = nil; candidates = []; page = .overview
            invalidatePresence(at: Date()); message = "已绑定，正在验证真实状态"; lastAttempt = .distantPast
            refresh()
        } catch { message = error.localizedDescription }
    }
    func forget() {
        guard !busy, !pairing else { return }
        do { try Vault.remove(); generation += 1; account = nil; pendingSession = nil; candidates = []; invalidatePresence(at: Date()); message = "已退出米家，本机历史记录保留"; save() }
        catch { message = error.localizedDescription }
    }
    func snooze() { engine.snooze(at: Date()); save(); onTick?() }
    func overtime(_ minutes: Int?) { engine.setOvertime(minutes, at: Date()); save(); onTick?() }
    func pause() { presenceResolver.reset(); engine.setPaused(!engine.paused, at: Date()); lastAttempt = .distantPast; save(); onTick?() }
    func configure(work: Int, rest: Int) { engine.workMinutes = work; engine.restMinutes = rest; save() }
    var summary: DaySummary { engine.summary(day: selectedDay, now: now) }
    var status: String {
        if engine.paused { return "已暂停" }
        return switch engine.presence { case .seated: "在座"; case .away: engine.seated == 0 ? "已休息 · 等待入座" : "离座休息中"; case .unknown: "等待有效状态" }
    }
}

func clockText(_ seconds: TimeInterval) -> String {
    let n = max(0, Int(seconds))
    return String(format: "%02d:%02d", n / 60, n % 60)
}
func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int(max(0, seconds)) / 60
    return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
}
