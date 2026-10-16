import BreakCore
import AppKit
import SwiftUI

let mint = Color(red: 0.88, green: 0.89, blue: 0.80)
let muted = Color(red: 0.60, green: 0.61, blue: 0.57)
let ink = Color(white: 0.045)
let panelBackground = LinearGradient(colors: [Color(white: 0.065), Color(white: 0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)

struct QuietPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .scaleEffect(reduced ? 1 : configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(reduced ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A quiet desk vignette, drawn locally with shapes rather than a camera image.
struct SeatIllustration: View {
    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.8)).frame(width: 225, height: 20).blur(radius: 10).offset(y: 51)
            Path { p in
                p.move(to: CGPoint(x: 95, y: 65)); p.addLine(to: CGPoint(x: 95, y: 108))
                p.move(to: CGPoint(x: 95, y: 100)); p.addLine(to: CGPoint(x: 65, y: 113))
                p.move(to: CGPoint(x: 95, y: 100)); p.addLine(to: CGPoint(x: 122, y: 113))
            }.stroke(Color(white: 0.42), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(white: 0.83), Color(white: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 58).rotationEffect(.degrees(-9)).offset(x: -45, y: -22)
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1).frame(width: 38, height: 46).rotationEffect(.degrees(-9)).offset(x: -45, y: -22) }
            RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.40)], startPoint: .top, endPoint: .bottom))
                .frame(width: 66, height: 17).rotationEffect(.degrees(-3)).offset(x: -38, y: 13)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.35)).frame(width: 5, height: 58).offset(x: 65, y: 24)
            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [mint, Color(white: 0.5)], startPoint: .top, endPoint: .bottom)).frame(width: 110, height: 7).offset(x: 66, y: -8)
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.18)).frame(width: 46, height: 31).rotationEffect(.degrees(-8)).offset(x: 71, y: -29)
                .overlay { RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [mint.opacity(0.24), .black], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 40, height: 25).rotationEffect(.degrees(-8)).offset(x: 71, y: -29) }
            Capsule().fill(Color(white: 0.48)).frame(width: 58, height: 3).offset(x: 67, y: -12)
        }.frame(width: 270, height: 124).accessibilityHidden(true)
    }
}

struct Dashboard: View {
    @Bindable var model: Model
    var startRest: () -> Void
    var previewReminder: () -> Void
    var quit: () -> Void
    var panelHeight: CGFloat = 560
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var changingAccount = false
    private var away: Bool { model.engine.presence == .away && !model.engine.paused }
    private var known: Bool { model.engine.presence != .unknown && !model.engine.paused }
    private var ready: Bool { away && model.engine.seated == 0 }
    private var shownTime: TimeInterval { away ? model.engine.rest : model.engine.seated }
    private var remaining: Int { Int(ceil(max(0, model.engine.target - model.engine.seated) / 60)) }
    var body: some View {
        ScrollView {
            switch model.page {
            case .overview: overview
            case .connection: setup
            case .history: HistoryView(model: model)
            }
        }.id(model.page).padding(24).frame(width: 430, height: panelHeight, alignment: .top).clipped()
            .background(panelBackground).foregroundStyle(mint).preferredColorScheme(.dark).tint(mint)
            .animation(reduced ? nil : .easeOut(duration: 0.16), value: model.page)
            .onChange(of: model.page) { _, page in if page != .connection && !model.pairing { changingAccount = false } }
            .onChange(of: model.pendingSession == nil) { _, cleared in if cleared && model.account != nil && !model.pairing { changingAccount = false } }
    }
    var overview: some View {
        VStack(spacing: 17) {
            HStack(spacing: 8) {
                Image(systemName: "figure.seated.side").foregroundStyle(muted)
                Text("起身一下").font(.system(size: 13, weight: .medium))
                Spacer()
                Button { model.pause() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.engine.paused ? "play.fill" : "pause.fill").font(.system(size: 11, weight: .medium))
                        Text(model.engine.paused ? "继续" : "暂停").font(.system(size: 12, weight: .medium))
                    }.padding(.horizontal, 13).frame(height: 36).background(Capsule().fill(mint.opacity(0.09)))
                }.buttonStyle(QuietPressStyle()).help(model.engine.paused ? "继续监测" : "暂停监测")
                    .accessibilityLabel(model.engine.paused ? "继续监测" : "暂停监测")
            }
            SeatIllustration()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ready ? "休息完成" : away ? "本轮已休息" : known ? "本轮已坐" : "上次累计在座").font(.system(size: 12)).foregroundStyle(muted)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(ready ? "就绪" : String(format: "%02d", Int(shownTime / 60))).font(.system(size: 58, weight: .medium, design: .rounded)).tracking(-2).monospacedDigit()
                        if !ready { Text("分").font(.system(size: 19)); Text(String(format: "%02d秒", Int(shownTime) % 60)).font(.system(size: 14)).foregroundStyle(muted).monospacedDigit() }
                    }.accessibilityElement(children: .combine)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(ready ? "下次入座" : away ? "距离休息完成" : "距离起身提醒").font(.system(size: 11)).foregroundStyle(muted)
                    Text(ready ? "重新计时" : !known ? "计时暂停" : away ? "还差 \(Int(ceil(model.engine.remainingRest / 60))) 分钟" : remaining == 0 ? "现在该休息" : "还有 \(remaining) 分钟").font(.system(size: 14, weight: .medium))
                }.padding(.bottom, 10)
            }
            VStack(spacing: 9) {
                GeometryReader { g in
                    let ratio = away ? (ready ? 1 : model.engine.rest / model.engine.restTarget) : model.engine.seated / model.engine.target
                    Capsule().fill(.white.opacity(0.065)).overlay(alignment: .leading) {
                        Capsule().fill(mint.opacity(0.72)).frame(width: max(0, g.size.width * min(1, max(0, ratio))))
                    }
                }.frame(height: 5)
                HStack {
                    Text(away ? "累计离座 \(model.engine.restMinutes) 分钟后清零" : "坐满 \(Int(model.engine.target / 60)) 分钟提醒")
                    Spacer()
                    if !away { Text("休息目标 \(model.engine.restMinutes) 分钟") }
                }.font(.system(size: 10)).foregroundStyle(muted)
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach([30, 45, 50, 60], id: \.self) { n in Button("坐 \(n) 分钟后提醒") { model.configure(work: n, rest: model.engine.restMinutes) } }
                } label: { tile("timer", "普通模式", "\(model.engine.workMinutes) 分钟", arrow: true) }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                Menu {
                    ForEach([3, 5, 10], id: \.self) { n in Button("本轮累计休息 \(n) 分钟") { model.configure(work: model.engine.workMinutes, rest: n) } }
                } label: { tile("leaf", "休息时长", "\(model.engine.restMinutes) 分钟", arrow: true) }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                Menu {
                    Button("恢复普通模式") { model.overtime(nil) }
                    Divider()
                    ForEach([60, 90, 120], id: \.self) { n in Button("本轮加班 · \(n) 分钟") { model.overtime(n) } }
                } label: { tile("moon", "临时加班", model.engine.overtimeMinutes.map { "\($0) 分钟" } ?? "未开启", arrow: true) }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                Button { model.page = .history } label: { tile("chart.bar.xaxis", "按天记录", "查看", arrow: false) }.buttonStyle(QuietPressStyle())
            }
            if model.account == nil && !model.preview {
                Button("连接米家传感器") { model.page = .connection }.buttonStyle(.borderedProminent).foregroundStyle(.black).controlSize(.large)
            } else {
                HStack {
                    Text(ready ? "已归零，等待下次入座" : !away && model.engine.rest > 0 ? "还需休息 \(clockText(model.engine.remainingRest))" : "本轮已离座 \(clockText(model.engine.rest))")
                    Spacer()
                    Button(action: startRest) {
                        Label(ready ? "休息完成" : away ? "查看休息" : "去休息", systemImage: "figure.walk")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink).padding(.horizontal, 13).padding(.vertical, 7)
                            .background(mint, in: Capsule())
                    }.buttonStyle(QuietPressStyle()).disabled(!known || ready)
                        .help("打开正式休息页，确认离座后开始累计休息")
                }.font(.system(size: 11)).foregroundStyle(muted)
            }
            HStack(spacing: 7) {
                Circle().fill(known ? Color(red: 0.61, green: 0.73, blue: 0.51) : muted).frame(width: 5, height: 5)
                Text(model.preview ? "界面预览 · 示例数据" : model.engine.paused ? "监测已暂停" : model.presenceExplanation).font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
                Spacer(minLength: 4)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy || model.account == nil || model.engine.paused).help("刷新状态")
                Button { model.page = .connection } label: { Image(systemName: "slider.horizontal.3") }.help("米家账号与连接")
            }.buttonStyle(.plain)
            if let error = model.storageError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    func tile(_ icon: String, _ title: String, _ value: String, arrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Image(systemName: icon).font(.system(size: 20, weight: .light)); Spacer(); if arrow { Image(systemName: "chevron.down").font(.system(size: 8)) } }.foregroundStyle(muted)
            Text(title).font(.system(size: 10)).foregroundStyle(muted)
            Text(value).font(.system(size: 13, weight: .medium))
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
    var setup: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("连接与提醒").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button { model.page = .overview } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(QuietPressStyle()).help("返回主面板")
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Atoll 刘海显示", isOn: Binding(get: { model.atoll.enabled }, set: { model.atoll.setEnabled($0) }))
                Text(model.atoll.status).font(.system(size: 11)).foregroundStyle(muted)
                if model.atoll.enabled && !model.atoll.connected {
                    Button("连接并授权 Atoll") { model.atoll.retryAuthorization() }.buttonStyle(.bordered)
                    Text("在 Atoll 设置中开启扩展与 RPC 服务，再允许起身一下。仅同步本机计时状态。").font(.system(size: 10)).foregroundStyle(muted)
                }
                Toggle("同时使用全屏提醒", isOn: Binding(get: { model.atoll.fullscreenEnabled }, set: { model.atoll.fullscreenEnabled = $0 }))
            }.font(.system(size: 12)).toggleStyle(.switch)
            Divider()
            connection
            Text(model.message).font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            if let last = model.lastRead { Text("最近同步 \(last.formatted(date: .omitted, time: .standard))").font(.system(size: 10)).foregroundStyle(muted) }
            Divider()
            HStack { Button("预览全屏提醒", action: previewReminder); Spacer(); Button("退出应用", action: quit) }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(muted)
        }
    }
    @ViewBuilder var connection: some View {
        if let account = model.account, !changingAccount {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 35, weight: .light)).foregroundStyle(muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("米家已登录").font(.system(size: 15, weight: .semibold))
                        Text("小米账号 ···" + String(account.session.user.suffix(4))).font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(mint.opacity(0.7))
                }
                VStack(spacing: 12) {
                    infoRow("登录地区", regionName(account.session.region))
                    infoRow("座位传感器", account.sensor.name)
                    infoRow("当前状态", model.status)
                }.font(.system(size: 12))
                HStack {
                    Button(model.busy ? "正在同步…" : "同步状态") { model.refresh() }.disabled(model.busy || model.pairing)
                    Spacer()
                    Button("切换账号") { changingAccount = true; model.region = account.session.region }.disabled(model.busy || model.pairing)
                    Button("退出登录") { model.forget() }.disabled(model.busy || model.pairing)
                }.font(.system(size: 11)).buttonStyle(.plain)
            }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        } else {
            login
        }
    }
    func infoRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(muted); Spacer(); Text(value).lineLimit(2).multilineTextAlignment(.trailing) }
    }
    func regionName(_ key: String) -> String {
        ["cn": "中国大陆", "tw": "中国台湾", "sg": "新加坡", "de": "欧洲", "us": "美国", "ru": "俄罗斯", "in": "印度", "i2": "印度二区"][key] ?? key
    }
    var login: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.account == nil ? "连接米家" : "切换米家账号").font(.headline)
                Spacer()
                Picker("地区", selection: $model.region) {
                    Text("中国大陆").tag("cn"); Text("台湾").tag("tw"); Text("新加坡").tag("sg"); Text("欧洲").tag("de"); Text("美国").tag("us")
                }.labelsHidden().frame(width: 125).disabled(model.pairing)
            }
            if let qr = model.qr {
                Image(nsImage: qr).resizable().interpolation(.none).scaledToFit().frame(width: 190, height: 190).padding(10).background(.white, in: RoundedRectangle(cornerRadius: 12)).frame(maxWidth: .infinity)
            }
            HStack {
                if model.pairing { ProgressView().controlSize(.small); Button("取消扫码") { model.cancelPair() } }
                else { Button("用米家 App 扫码登录") { model.pair() }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(model.busy || model.preview) }
                if model.account != nil { Button("取消切换") { model.cancelPair(); changingAccount = false } }
            }
            ForEach(model.candidates) { device in
                Button { model.choose(device) } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(device.name); Text(device.model).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(device.supported ? "连接" : "暂未适配").font(.caption)
                    }.padding(8)
                }.disabled(!device.supported || model.busy)
            }
            Text("登录会话保存在本机钥匙串；只读取传感器，不修改米家设备。云端状态可能有上报延迟。").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ReminderView: View {
    @Bindable var model: Model
    let isPreview: Bool
    let dismiss: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: model.engine.presence == .away ? "leaf" : "figure.walk").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(mint)
            if isPreview { Text("全屏提醒预览").font(.subheadline).foregroundStyle(.secondary) }
            Text(title).font(.system(size: 48, weight: .medium)).multilineTextAlignment(.center)
            Text(detail).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
            Text(clockText(model.engine.remainingRest)).font(.system(size: 88, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(mint)
            Text(model.engine.presence == .away ? "正在累计离座时间" : "休息计时已暂停 · 等待确认离座").font(.subheadline).foregroundStyle(.secondary)
            if !isPreview {
                Text("\(model.presenceExplanation) · 最近读取 \(model.lastRead?.formatted(date: .omitted, time: .standard) ?? "暂无")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button(isPreview ? "关闭预览" : "稍后 5 分钟") { if !isPreview { model.snooze() }; dismiss() }.keyboardShortcut(.cancelAction)
                if !isPreview {
                    Menu("这轮需要加班") {
                        ForEach([60, 90, 120], id: \.self) { n in Button("本轮总时限 \(n) 分钟") { model.overtime(n); dismiss() } }
                    }
                }
            }.controlSize(.large)
            Text("起身走动、倒杯水，或做一些舒展。\n离座满额后自动结束提醒；Esc 可稍后提醒。").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Spacer()
            Text("起身一下 · \(model.preview ? "模拟数据" : "按座位传感器状态计时")").font(.caption).foregroundStyle(.secondary).padding(.bottom, 32)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(panelBackground).foregroundStyle(mint).preferredColorScheme(.dark).tint(mint)
    }
    var title: String {
        if model.engine.presence == .unknown { return "暂时无法确认座位状态" }
        if model.engine.presence == .away { return "很好，继续休息一会儿" }
        return model.engine.rest > 0 ? "再活动一会儿吧" : "该起来活动一下了"
    }
    var detail: String {
        if model.engine.presence == .unknown { return "检测恢复前，休息计时暂停。" }
        if model.engine.presence == .away && model.restingWithoutInput { return "附近检测到人，但没有电脑操作。\n继续累计本轮休息，操作电脑后确认回座。" }
        if model.engine.presence == .away { return "已确认离座，正在累计休息。\n达到本轮目标后会自动关闭提醒。" }
        if model.engine.rest > 0 { return "已离座 \(clockText(model.engine.rest))，还差 \(clockText(model.engine.remainingRest)) 达到本轮目标。\n短暂活动也有价值，再给自己一点时间。" }
        return "这一轮已在座 \(durationText(model.engine.seated))。\n传感器仍报告有人；确认无人后开始累计休息。"
    }
}

struct HistoryView: View {
    @Bindable var model: Model
    var body: some View {
        let day = model.summary
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("按天记录").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button { model.page = .overview } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.buttonStyle(QuietPressStyle()).help("返回主面板")
            }
            HStack {
                Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28) }.help("前一天")
                DatePicker("日期", selection: $model.selectedDay, in: ...Date(), displayedComponents: .date).labelsHidden().datePickerStyle(.field).font(.system(size: 12))
                Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 28) }.disabled(Calendar.current.isDateInToday(model.selectedDay)).help("后一天")
                Spacer()
                Button("今天") { model.selectedDay = Date() }.font(.system(size: 11))
            }.buttonStyle(QuietPressStyle())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                stat("累计在座", durationText(day.seated), icon: "figure.seated.side")
                stat("最长连续在座", durationText(day.longest), icon: "timer")
                stat("离座时长", durationText(day.away), icon: "figure.walk")
                stat("完成休息", "\(day.completed) 次", icon: "checkmark.circle")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("加班在座 \(durationText(day.overtime)) · 未知 / 暂停 \(durationText(day.unknown))")
                Text("仅记录本机监测到的时间；离座不等于运动。")
            }.font(.system(size: 10)).foregroundStyle(muted)
            Divider().opacity(0.6)
            if day.intervals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar").font(.system(size: 28, weight: .light))
                    Text("这一天还没有记录").font(.system(size: 13))
                    Text("连接传感器后自动记录").font(.system(size: 11)).foregroundStyle(muted)
                }.frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                Text("时间轴").font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                LazyVStack(spacing: 0) {
                    ForEach(Array(day.intervals.reversed().enumerated()), id: \.offset) { _, segment in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(segment.presence == .seated ? mint : segment.presence == .away ? Color(red: 0.61, green: 0.73, blue: 0.51) : muted.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(segment.presence == .seated ? "在座" : segment.presence == .away ? "离座" : "未知 / 暂停").font(.system(size: 12, weight: .medium))
                                    if segment.overtime && segment.presence == .seated { Text("加班").font(.system(size: 10)).foregroundStyle(muted) }
                                }
                                Text(segment.start.formatted(date: .omitted, time: .standard) + " — " + segment.end.formatted(date: .omitted, time: .standard)).font(.system(size: 10)).monospacedDigit().foregroundStyle(muted)
                            }
                            Spacer()
                            Text(clockText(segment.end.timeIntervalSince(segment.start))).font(.system(size: 12)).monospacedDigit().foregroundStyle(muted)
                        }.padding(.vertical, 11)
                        Divider().opacity(0.3)
                    }
                }
            }
            if !day.milestones.isEmpty {
                Text("提醒与模式").font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                ForEach(Array(day.milestones.reversed().enumerated()), id: \.offset) { _, event in
                    HStack(alignment: .top, spacing: 10) {
                        Text(event.time.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(muted)
                        Text(eventName(event))
                        Spacer()
                    }.font(.system(size: 11))
                }
            }
        }
    }
    func moveDay(_ offset: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: offset, to: model.selectedDay) else { return }
        model.selectedDay = min(next, Date())
    }
    func stat(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.system(size: 10)).foregroundStyle(muted)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
    func eventName(_ event: Milestone) -> String {
        switch event.kind { case "restCompleted": "完成 \(event.minutes ?? 5) 分钟休息"; case "overtime": "加班模式：本轮 \(event.minutes ?? 60) 分钟"; case "normal": "恢复普通模式"; case "snooze": "稍后 5 分钟提醒"; case "pause": "暂停监测"; case "resume": "继续监测"; case "workReminder": "起身提醒"; case "shortRestReminder": "休息不足提醒"; default: event.kind }
    }
}
