import Foundation
import Combine
import SwiftUI

// MARK: - 颜色
extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
    static let gold    = Color(hex: 0xf5c96b)
    static let amberC = Color(hex: 0xff9d5c)
    static let mintC  = Color(hex: 0x6ee7c8)
    static let skyC    = Color(hex: 0x7dd3fc)
    static let roseC   = Color(hex: 0xfda4af)
    static let violetC = Color(hex: 0xa78bfa)
}

// MARK: - 任务模型（合并两份手册的每日节律）
struct VitalityTask: Identifiable {
    let id: String      // "07:30"
    let label: String
    let speech: String

    var minutes: Int {
        let p = id.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return 0 }
        return p[0] * 60 + p[1]
    }
}

let TASKS: [VitalityTask] = [
    .init(id: "07:00", label: "固定起床 · 先喝 300ml 温水",    speech: "到点了，固定起床，先喝三百毫升温水。"),
    .init(id: "07:30", label: "晨光下散步 / 拉伸 10 分钟",       speech: "去晒十分钟晨光，散步或拉伸都可以。"),
    .init(id: "08:30", label: "起床 90 分钟后 · 第一杯咖啡",    speech: "现在可以喝今天第一杯咖啡了。"),
    .init(id: "09:00", label: "黄金时段 · 攻最难的一件事",      speech: "黄金时段开始，去处理最难的那件事。"),
    .init(id: "12:30", label: "午餐七分饱 · 饭后走 10 分钟",     speech: "午餐七分饱，饭后走十分钟。"),
    .init(id: "13:00", label: "小睡 20 分钟（别超 30）",         speech: "午间小睡二十分钟，别超过三十分钟。"),
    .init(id: "14:00", label: "咖啡因停杯",                      speech: "下午两点了，咖啡因到此为止。"),
    .init(id: "15:00", label: "起身活动 3 分钟 · 补水",          speech: "起来活动三分钟，喝点水。"),
    .init(id: "18:00", label: "30 分钟有氧 / 力量训练",          speech: "运动三十分钟，有氧或力量都行。"),
    .init(id: "21:30", label: "屏幕断电 · 睡前仪式",             speech: "屏幕该断电了，进入睡前仪式。"),
    .init(id: "22:30", label: "上床 · 保证 7–9 小时睡眠",        speech: "该上床了，晚安。")
]

// MARK: - 设置
struct VitalitySettings: Codable, Equatable {
    var sound = true
    var speech = false
    var hourly = false
    var launchAtLogin = false
    var notificationsAsked = false
}

enum NotifStatus {
    case unknown
    case authorized
    case denied
}

// MARK: - 当日测量记录（体重 / 血压 / 睡眠）
struct VitalityMetrics: Codable, Equatable {
    var weight: Double?       // kg
    var sys: Int?              // 收缩压（高压）
    var dia: Int?              // 舒张压（低压）
    var sleepMinutes: Int?     // 昨晚睡眠分钟数
    var savedAt: Double? = nil // 最近一次记录的时刻（epoch 秒），用于“已记录”反馈

    var bpStatus: (String, Color)? {
        guard let s = sys, let d = dia, s > 0, d > 0 else { return nil }
        if s >= 140 || d >= 90 { return ("偏高 ⚠️", .roseC) }
        if s >= 130 || d >= 85 { return ("偏高", .amberC) }
        if s >= 120 || d >= 80 { return ("正常高值", .amberC) }
        return ("正常", .mintC)
    }

    var sleepStatus: (String, Color)? {
        guard let m = sleepMinutes, m > 0 else { return nil }
        if m >= 420 && m <= 540 { return ("达标 · 7–9h", .mintC) }
        if m < 420 { return ("不足", .roseC) }
        return ("偏多", .amberC)
    }

    var sleepText: String? {
        guard let m = sleepMinutes, m > 0 else { return nil }
        let h = m / 60, mm = m % 60
        return mm == 0 ? "\(h) 小时" : "\(h) 小时 \(mm) 分"
    }
}

struct MetricsText: Equatable {
    var weight = ""
    var sys = ""
    var dia = ""
    var sleepH = ""
    var sleepM = ""

    var parsed: VitalityMetrics {
        let w = Double(weight)
        let s = Int(sys)
        let d = Int(dia)
        let h = Int(sleepH)
        let m = Int(sleepM)
        let sleep = (h == nil && m == nil) ? nil : (h ?? 0) * 60 + (m ?? 0)
        return VitalityMetrics(weight: w, sys: s, dia: d, sleepMinutes: sleep)
    }

    static func from(_ m: VitalityMetrics) -> MetricsText {
        var t = MetricsText()
        if let w = m.weight { t.weight = w == w.rounded() ? String(Int(w)) : String(w) }
        if let s = m.sys { t.sys = String(s) }
        if let d = m.dia { t.dia = String(d) }
        if let sl = m.sleepMinutes {
            t.sleepH = String(sl / 60)
            if sl % 60 != 0 { t.sleepM = String(sl % 60) }
        }
        return t
    }
}

// MARK: - 历史记录（每天一份快照，用于趋势图与月历打卡）
struct HistoryDay: Codable, Equatable {
    let date: String          // "2025-03-05"
    var weight: Double?
    var sys: Int?
    var dia: Int?
    var sleepMinutes: Int?
    var doneCount: Int?        // 当天完成清单数
    var tomatoes: Int?         // 当天完成番茄数
}

// MARK: - 全局状态存储（本机持久化，跨天自动重置）
final class VitalityStore: ObservableObject {
    struct PersistedState: Codable {
        let day: String
        let done: [String]
        var metrics: VitalityMetrics?
    }

    @Published var dayKey: String
    @Published var done: Set<String>
    @Published var settings: VitalitySettings
    @Published var banner: String?
    @Published var notifStatus: NotifStatus = .unknown
    @Published var metricsText = MetricsText()
    @Published private(set) var history: [HistoryDay] = []
    private(set) var metrics = VitalityMetrics()

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoKey(_ date: Date = Date()) -> String {
        isoFmt.string(from: date)
    }

    private(set) var fired: Set<String> = []   // 今日已触发过的提醒（内存即可）
    var onReschedule: (() -> Void)?
    var onRequestNotifications: (() -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        let today = VitalityStore.todayKey()

        if let raw = defaults.string(forKey: "vitality.state"),
           let data = raw.data(using: .utf8),
           let s = try? JSONDecoder().decode(PersistedState.self, from: data),
           s.day == today {
            dayKey = today
            done = Set(s.done)
            if let m = s.metrics {
                metrics = m
                metricsText = MetricsText.from(m)
            }
        } else {
            dayKey = today
            done = []
        }

        if let raw = defaults.string(forKey: "vitality.settings"),
           let data = raw.data(using: .utf8),
           let s = try? JSONDecoder().decode(VitalitySettings.self, from: data) {
            settings = s
        } else {
            settings = VitalitySettings()
        }

        if let raw = defaults.string(forKey: "vitality.history"),
           let data = raw.data(using: .utf8),
           let h = try? JSONDecoder().decode([HistoryDay].self, from: data) {
            history = h
        }

        markFarPastAsFired()
    }

    static func todayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func persistState() {
        syncHistoryToday()
        let s = PersistedState(day: dayKey, done: Array(done), metrics: metrics)
        if let data = try? JSONEncoder().encode(s), let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: "vitality.state")
        }
        persistHistory()
    }

    /// 把当天的测量与打卡写入历史（同一天覆盖，最多留 90 天）
    private func syncHistoryToday() {
        let key = VitalityStore.isoKey()
        let entry = HistoryDay(
            date: key,
            weight: metrics.weight,
            sys: metrics.sys,
            dia: metrics.dia,
            sleepMinutes: metrics.sleepMinutes,
            doneCount: done.count,
            tomatoes: pomo.state.todayTomatoes
        )
        if let i = history.firstIndex(where: { $0.date == key }) {
            history[i] = entry
        } else {
            history.append(entry)
            history.sort { $0.date < $1.date }
            if history.count > 90 { history.removeFirst(history.count - 90) }
        }
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history), let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: "vitality.history")
        }
    }

    func setMetrics(_ mutate: (inout MetricsText) -> Void) {
        mutate(&metricsText)
        var m = metricsText.parsed
        let hasAny = m.weight != nil || m.sys != nil || m.dia != nil || m.sleepMinutes != nil
        m.savedAt = hasAny ? Date().timeIntervalSince1970 : nil
        metrics = m
        persistState()
    }

    func persistSettings() {
        if let data = try? JSONEncoder().encode(settings), let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: "vitality.settings")
        }
    }

    func setSettings(_ mutate: (inout VitalitySettings) -> Void) {
        mutate(&settings)
        persistSettings()
        onReschedule?()
    }

    func toggle(_ id: String) {
        if done.contains(id) { done.remove(id) } else { done.insert(id) }
        persistState()
        onReschedule?()
    }

    // MARK: 节律计算
    func nowMinutes(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 启动时把早已过期的任务标记为已触发，避免一打开就连环轰炸
    private func markFarPastAsFired() {
        let n = nowMinutes()
        for t in TASKS where t.minutes + 30 <= n { fired.insert(t.id) }
    }

    func rollDayIfNeeded() -> Bool {
        let today = VitalityStore.todayKey()
        guard today != dayKey else { return false }
        dayKey = today
        done = []
        fired = []
        metrics = VitalityMetrics()
        metricsText = MetricsText()
        markFarPastAsFired()
        persistState()
        return true
    }

    /// 到点 30 分钟内、未完成、未提醒过 → 触发（由 AppDelegate 每 30 秒轮询）
    func dueReminders() -> [String] {
        var out: [String] = []
        let n = nowMinutes()

        for t in TASKS where !done.contains(t.id) && !fired.contains(t.id) {
            if n >= t.minutes && n < t.minutes + 30 {
                fired.insert(t.id)
                out.append("\(t.id) · \(t.label)")
            }
        }

        if settings.hourly {
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            if let h = c.hour, (9...21).contains(h), (c.minute ?? 60) < 5 {
                let key = "hour-\(h)"
                if !fired.contains(key) {
                    fired.insert(key)
                    out.append("整点提醒 · 起身活动 2 分钟，顺便喝水 🧍")
                }
            }
        }

        if !done.isEmpty && TASKS.allSatisfy({ done.contains($0.id) }) && !fired.contains("all-done") {
            fired.insert("all-done")
            out.append("今日精力清单全部完成 🎉 保持住这个节奏！")
        }
        return out
    }

    var progress: Double { Double(done.count) / Double(TASKS.count) }

    var currentTask: VitalityTask? {
        let n = nowMinutes()
        return TASKS.last(where: { $0.minutes <= n })
    }

    var nextTask: VitalityTask? {
        let n = nowMinutes()
        return TASKS.first(where: { $0.minutes > n })
    }

    var minutesToNext: Int? {
        guard let nx = nextTask else { return nil }
        return nx.minutes - nowMinutes()
    }

    func phaseInfo(for date: Date = Date()) -> (String, Color) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
        switch h {
        case 6.5..<9:     return ("开机 · 晨光充电", .mintC)
        case 9..<11.5:    return ("黄金时段 · 最强大脑", .gold)
        case 11.5..<14:   return ("午餐 · 恢复窗口", .skyC)
        case 14..<16:     return ("午后低谷 · 别硬扛", .amberC)
        case 16..<18.5:   return ("第二高峰 · 创造协作", .gold)
        case 18.5..<21.5: return ("运动 · 制造精力", .mintC)
        case 21.5...:     return ("关机 · 降温程序", .roseC)
        default:          return ("睡眠充电中 😴", .violetC)
        }
    }

    func showBanner(_ text: String) {
        banner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            if self?.banner == text { self?.banner = nil }
        }
    }

    func requestNotifications() {
        onRequestNotifications?()
    }

    // 番茄钟引擎（独立持久化，重启后继续）
    let pomo = PomodoroEngine()
}

// MARK: - 番茄钟
enum PomoPhase: Int, Codable {
    case focus = 0
    case shortBreak = 1
    case longBreak = 2

    var minutes: Int {
        switch self {
        case .focus: return 25
        case .shortBreak: return 5
        case .longBreak: return 15
        }
    }

    var title: String {
        switch self {
        case .focus: return "专注"
        case .shortBreak: return "小憩"
        case .longBreak: return "长休"
        }
    }
}

struct PomoState: Codable, Equatable {
    var phase: PomoPhase = .focus
    var remaining: Double = 25 * 60   // 暂停时剩余秒数
    var endAt: Double = 0             // 运行时的结束时刻（epoch 秒）
    var running: Bool = false
    var cycleIndex: Int = 0           // 本周期已完成的专注数（0–4）
    var todayKey: String = ""
    var todayTomatoes: Int = 0        // 今日累计完成的 🍅
}

final class PomodoroEngine: ObservableObject {
    @Published private(set) var state: PomoState
    var onFinish: ((PomoPhase, Int) -> Void)?   // (刚结束的阶段, 今日累计番茄数)

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    init() {
        if let raw = defaults.string(forKey: "vitality.pomo"),
           let data = raw.data(using: .utf8),
           let s = try? JSONDecoder().decode(PomoState.self, from: data) {
            state = s
        } else {
            state = PomoState()
        }
        state.todayKey = state.todayKey == "" ? VitalityStore.todayKey() : state.todayKey
        rollDayIfNeeded()
        catchUpIfMissed()
        persist()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func now() -> Double { Date().timeIntervalSince1970 }

    private func duration(of phase: PomoPhase) -> Double { Double(phase.minutes) * 60 }

    private func persist() {
        if let data = try? JSONEncoder().encode(state), let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: "vitality.pomo")
        }
    }

    private func rollDayIfEmpty() -> Bool {
        let today = VitalityStore.todayKey()
        guard state.todayKey != today || state.todayKey == "" else { return false }
        state.todayKey = today
        state.todayTomatoes = 0
        state.cycleIndex = 0
        state.phase = .focus
        state.running = false
        state.remaining = duration(of: .focus)
        state.endAt = 0
        return true
    }

    /// 跨天重置（幂等，AppDelegate 轮询与引擎自身时钟都会调）
    func rollDayIfNeeded() {
        if rollDayIfEmpty() { persist() }
    }

    /// 应用退出期间到点：静默推进（番茄照样计数，但不打扰）
    private func catchUpIfMissed() {
        if state.running, state.endAt > 0, now() >= state.endAt {
            completePhase(alert: false, counts: true)
        }
    }

    private func tick() {
        rollDayIfNeeded()
        guard state.running else { return }
        if now() >= state.endAt {
            completePhase(alert: true, counts: true)
        }
    }

    private func completePhase(alert: Bool, counts: Bool) {
        let ended = state.phase
        state.running = false
        state.endAt = 0
        switch ended {
        case .focus:
            if counts {
                state.todayTomatoes += 1
                state.cycleIndex += 1
                state.phase = state.cycleIndex >= 4 ? .longBreak : .shortBreak
            } else {
                state.phase = .shortBreak
            }
        case .shortBreak:
            state.phase = .focus
        case .longBreak:
            state.cycleIndex = 0
            state.phase = .focus
        }
        state.remaining = duration(of: state.phase)
        persist()
        if alert, let cb = onFinish { cb(ended, state.todayTomatoes) }
    }

    // MARK: 对外操作
    func startPause() {
        if state.running {
            state.remaining = max(0, state.endAt - now())
            state.running = false
        } else {
            if state.remaining <= 1 { state.remaining = duration(of: state.phase) }
            state.endAt = now() + state.remaining
            state.running = true
        }
        persist()
    }

    /// 跳过当前阶段（专注被跳过不计数）
    func skip() {
        completePhase(alert: false, counts: false)
    }

    func resetPhase() {
        state.running = false
        state.endAt = 0
        state.remaining = duration(of: state.phase)
        persist()
    }

    // MARK: 显示
    var displayRemaining: Double {
        state.running ? max(0, state.endAt - now()) : state.remaining
    }

    var progress: Double {
        min(1, max(0, 1 - displayRemaining / duration(of: state.phase)))
    }

    func timeText() -> String {
        let t = Int(displayRemaining.rounded())
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
