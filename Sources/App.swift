import BreakCore
import AppKit
import SwiftUI

@MainActor final class ReminderWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model(preview: CommandLine.arguments.contains("--preview"))
    var statusItem: NSStatusItem?
    let popover = NSPopover()
    var panelHeight: CGFloat = 560
    var overlays: [NSWindow] = []
    var overlayPreview = false
    var terminationReplied = false
    var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.image = NSImage(systemSymbolName: "figure.seated.side", accessibilityDescription: "久坐提醒")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self; item.button?.action = #selector(togglePanel)
        panelHeight = min(560, max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 40))
        popover.behavior = .transient
        let host = NSHostingController(rootView: Dashboard(model: model, previewReminder: { [weak self] in self?.showReminder(preview: true) }, quit: { NSApp.terminate(nil) }, panelHeight: panelHeight))
        host.sizingOptions = []
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 430, height: panelHeight)
        model.onTick = { [weak self] in self?.update() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.sleep(); self?.closeReminder() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.wake() } })
        model.atoll.onReminderPresented = { [weak self] in
            guard let self, !model.atoll.fullscreenEnabled else { return }
            model.engine.recordReminder(at: Date()); model.save()
        }
        model.start(); showPanel()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.stop()
        Task {
            await model.atoll.shutdown()
            finishTermination(sender)
        }
        Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            model.atoll.disconnectForTermination()
            finishTermination(sender)
        }
        return .terminateLater
    }
    private func finishTermination(_ sender: NSApplication) {
        guard !terminationReplied else { return }
        terminationReplied = true
        sender.reply(toApplicationShouldTerminate: true)
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop(); for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }
    func showPanel() {
        guard !popover.isShown, let button = statusItem?.button else { return }
        if !model.pairing && model.pendingSession == nil { model.page = .overview }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
    func update() {
        if !model.preview { model.atoll.update(engine: model.engine, now: Date()) }
        let text: String
        if model.engine.paused { text = "已暂停" }
        else if model.account == nil && !model.preview { text = "未连接" }
        else {
            text = switch model.engine.presence {
            case .unknown: "状态未知"
            case .away: model.engine.seated == 0 ? "休息完成" : "休息中"
            case .seated: model.engine.seated < 60 ? "已坐不足1分钟" : "已坐 \(Int(model.engine.seated / 60)) 分钟"
            }
        }
        let notchConnected = model.atoll.enabled && model.atoll.connected && !model.preview
        statusItem?.button?.title = notchConnected ? "" : " \(text)"
        statusItem?.button?.toolTip = "起身一下 · \(model.status) · 本轮已坐 \(durationText(model.engine.seated))，\(Int(model.engine.target / 60)) 分钟提醒"
        if !overlays.isEmpty && !overlayPreview {
            if model.engine.paused || model.engine.presence == .unknown || model.engine.seated == 0 { closeReminder() }
        }
        if (model.atoll.fullscreenEnabled || !model.atoll.enabled || !model.atoll.connected) && !model.preview && overlays.isEmpty && model.engine.needsReminder(at: Date()) { showReminder(preview: false) }
    }
    func showReminder(preview: Bool) {
        guard overlays.isEmpty else { return }
        popover.performClose(nil)
        if !preview { model.engine.recordReminder(at: Date()); model.save() }
        overlayPreview = preview
        for screen in NSScreen.screens {
            let window = ReminderWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ReminderView(model: model, isPreview: preview, dismiss: { [weak self] in self?.closeReminder() }))
            window.setFrame(screen.frame, display: true); window.orderFrontRegardless(); overlays.append(window)
        }
        NSApp.activate(ignoringOtherApps: true); overlays.first?.makeKey()
    }
    func closeReminder() { overlays.forEach { $0.close() }; overlays = []; overlayPreview = false }
}

@main enum Entry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
