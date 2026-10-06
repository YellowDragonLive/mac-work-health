import AppKit
import SwiftUI
import UserNotifications

// MARK: - 置顶悬浮面板（所有桌面空间保持悬浮，点按不抢焦点）
final class VitalityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var store: VitalityStore!
    private var panel: VitalityPanel?
    private var statusItem: NSStatusItem?
    private let synthesizer = NSSpeechSynthesizer()
    private var tickSound: NSSound?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = VitalityStore()
        store.onReschedule = { [weak self] in self?.rescheduleNotifications() }
        store.onRequestNotifications = { [weak self] in self?.requestNotifications() }
        store.pomo.onFinish = { [weak self] ended, _ in
            self?.pomoDidFinish(ended)
        }

        // 自愈：偏好里开了自启动但系统注册丢了（如应用重装/更新），启动时补注册
        if store.settings.launchAtLogin, !LoginItemManager.isEnabled {
            LoginItemManager.setEnabled(true)
        }

        makePanel()
        makeStatusItem()

        UNUserNotificationCenter.current().delegate = self
        refreshNotifStatus()

        if !store.settings.notificationsAsked {
            requestNotifications()
        }

        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()

        // 番茄钟滴答声：运行时合成一个短促的秒针音
        tickSound = Self.makeTickSound()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickTick()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - 面板
    private func makePanel() {
        let size = NSSize(width: 344, height: 820)
        let rect = NSRect(origin: .zero, size: size)

        let p = VitalityPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false

        // 深色毛玻璃背景
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: ContentView(
            store: store,
            onHide: { [weak self] in self?.panel?.orderOut(nil) }
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        p.contentView = effect

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor)
        ])

        // 默认停靠在主屏右侧
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(
                x: screen.frame.maxX - size.width - 24,
                y: screen.frame.midY - size.height / 2
            ))
        } else {
            p.center()
        }
        p.orderFrontRegardless()
        panel = p
    }

    // MARK: - 菜单栏图标
    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "精力挂件")

        let menu = NSMenu()
        let mi = menu.addItem(withTitle: "显示 / 隐藏挂件", action: #selector(togglePanelVisible), keyEquivalent: "")
        mi.target = self
        menu.addItem(NSMenuItem.separator())
        let qi = menu.addItem(withTitle: "退出精力挂件", action: #selector(quitApp), keyEquivalent: "q")
        qi.target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanelVisible() {
        guard let panel = panel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - 轮询：跨天重置 + 到点提醒
    private func tick() {
        // 先滚番茄钟再滚清单，避免跨天瞬间把昨天的番茄数写进新一天的历史
        store.pomo.rollDayIfNeeded()
        if store.rollDayIfNeeded() {
            rescheduleNotifications()
        }
        for msg in store.dueReminders() {
            deliverInApp(msg)
        }
        refreshNotifStatus()
    }

    private func deliverInApp(_ msg: String) {
        store.showBanner(msg)
        if store.settings.speech {
            speakZH(msg)
        }
        // 系统通知授权过时横幅自带声音，此时不再叠加应用内提示音
        if store.settings.sound && store.notifStatus != .authorized {
            AppDelegate.playGlass()
        }
    }

    // MARK: - 声音 / 语音
    static func playSound(named name: String) {
        if let s = NSSound(named: name) { s.play() } else { NSSound.beep() }
    }

    static func playGlass() {
        playSound(named: "Glass")
    }

    /// 合成 40ms 的机械秒针滴答声（2.6kHz 正弦 + 快速衰减），写入临时 wav
    static func makeTickSound() -> NSSound? {
        let sampleRate = 44100
        let count = Int(0.04 * Double(sampleRate))
        var data = Data()

        func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }

        data.append("RIFF".data(using: .ascii)!)
        le32(UInt32(36 + count * 2))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        le32(16); le16(1); le16(1)
        le32(UInt32(sampleRate)); le32(UInt32(sampleRate * 2)); le16(2); le16(16)
        data.append("data".data(using: .ascii)!)
        le32(UInt32(count * 2))

        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let env = exp(-t * 160)
            let v = sin(2 * .pi * 2600 * t) * env * 0.22
            le16(UInt16(bitPattern: Int16(v * Double(Int16.max))))
        }

        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vitality-tick.wav")
        do {
            try data.write(to: url)
            return NSSound(contentsOf: url, byReference: false)
        } catch {
            return nil
        }
    }

    private func tickTick() {
        let s = store.pomo.state
        guard s.running, s.phase == .focus, store.settings.pomoTick else { return }
        if let t = tickSound {
            t.play()
        } else {
            NSSound.beep()
        }
    }

    private func speakZH(_ text: String) {
        // 语音名形如 com.apple.voice.compact.zh-CN.Tingting
        let zhVoice = NSSpeechSynthesizer.availableVoices.first { $0.rawValue.contains(".zh-") }
        if let zhVoice = zhVoice { synthesizer.setVoice(zhVoice) }
        synthesizer.startSpeaking(text)
    }

    // MARK: - 番茄钟到点
    private func pomoDidFinish(_ ended: PomoPhase) {
        let msg: String
        switch ended {
        case .focus:
            msg = store.pomo.state.phase == .longBreak
                 ? "🍅 专注完成！4 个 🍅 收齐，去长休 15 分钟"
                 : "🍅 专注完成！去小憩 5 分钟"
        case .shortBreak:
            msg = "⏰ 小憩结束，回到专注"
        case .longBreak:
            msg = "🌅 长休结束，新周期开始"
        }
        store.showBanner(msg)
        if store.settings.sound {
            switch ended {
            case .focus:
                AppDelegate.playSound(named: "Glass")   // 专注结束：清脆玻璃声
            case .shortBreak, .longBreak:
                AppDelegate.playSound(named: "Hero")    // 休息结束：开工号角
            }
        }
        if store.settings.speech { speakZH(msg) }
        postPomoNotification(msg)
    }

    private func postPomoNotification(_ msg: String) {
        guard store.notifStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "⚡ 番茄钟"
        content.body = msg
        if store.settings.sound { content.sound = .default }
        let req = UNNotificationRequest(
            identifier: "vital.pomo.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - 系统通知
    private func requestNotifications() {
        store.setSettings { $0.notificationsAsked = true }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshNotifStatus()
            }
        }
    }

    private func refreshNotifStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let wasAuth = self.store.notifStatus == .authorized
                switch s.authorizationStatus {
                case .authorized, .provisional: self.store.notifStatus = .authorized
                case .denied:                  self.store.notifStatus = .denied
                default:                       self.store.notifStatus = .unknown
                }
                // 从未授权 → 已授权 的瞬间需要重建全部每日触发器
                if self.store.notifStatus == .authorized && !wasAuth {
                    self.rescheduleNotifications()
                }
            }
        }
    }

    /// 为每个未完成任务建立每日重复的日历触发器；已完成的不打扰
    private func rescheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                guard let self = self, s.authorizationStatus == .authorized else { return }

                for t in TASKS where !self.store.done.contains(t.id) {
                    let content = UNMutableNotificationContent()
                    content.title = "⚡ 今日精力"
                    content.body = "\(t.id) · \(t.label)"
                    if self.store.settings.sound { content.sound = .default }

                    var comps = DateComponents()
                    let p = t.id.split(separator: ":").compactMap { Int($0) }
                    comps.hour = p.first ?? 0
                    comps.minute = p.count > 1 ? p[1] : 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                    center.add(UNNotificationRequest(identifier: "vital.\(t.id)", content: content, trigger: trigger))
                }

                if self.store.settings.hourly {
                    for h in 9...21 {
                        let content = UNMutableNotificationContent()
                        content.title = "⚡ 今日精力"
                        content.body = "整点提醒 · 起身活动 2 分钟，顺便喝水 🧍"
                        if self.store.settings.sound { content.sound = .default }
                        var comps = DateComponents()
                        comps.hour = h
                        comps.minute = 0
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                        center.add(UNNotificationRequest(identifier: "vital.hour.\(h)", content: content, trigger: trigger))
                    }
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    // 点击横幅 = 标记完成并呼出挂件
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        if id.hasPrefix("vital.") {
            let taskId = String(id.dropFirst("vital.".count))
            if !taskId.hasPrefix("hour.") {
                DispatchQueue.main.async {
                    self.store.toggle(taskId)
                    self.panel?.orderFrontRegardless()
                }
            }
        }
        completionHandler()
    }
}
