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
    let short: String   // 打卡矩阵用的短名

    var minutes: Int {
        let p = id.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return 0 }
        return p[0] * 60 + p[1]
    }
}

let TASKS: [VitalityTask] = [
    .init(id: "07:00", label: "固定起床 · 先喝 300ml 温水",    speech: "到点了，固定起床，先喝三百毫升温水。", short: "起床喝水"),
    .init(id: "07:30", label: "晨光下散步 / 拉伸 10 分钟",       speech: "去晒十分钟晨光，散步或拉伸都可以。", short: "晨光"),
    .init(id: "08:30", label: "起床 90 分钟后 · 第一杯咖啡",    speech: "现在可以喝今天第一杯咖啡了。", short: "咖啡"),
    .init(id: "09:00", label: "黄金时段 · 攻最难的一件事",      speech: "黄金时段开始，去处理最难的那件事。", short: "深度工作"),
    .init(id: "12:30", label: "午餐七分饱 · 饭后走 10 分钟",     speech: "午餐七分饱，饭后走十分钟。", short: "午餐"),
    .init(id: "13:00", label: "小睡 20 分钟（别超 30）",         speech: "午间小睡二十分钟，别超过三十分钟。", short: "午睡"),
    .init(id: "14:00", label: "咖啡因停杯",                      speech: "下午两点了，咖啡因到此为止。", short: "停咖啡"),
    .init(id: "15:00", label: "起身活动 3 分钟 · 补水",          speech: "起来活动三分钟，喝点水。", short: "起身"),
    .init(id: "18:00", label: "30 分钟有氧 / 力量训练",          speech: "运动三十分钟，有氧或力量都行。", short: "运动"),
    .init(id: "21:30", label: "屏幕断电 · 睡前仪式",             speech: "屏幕该断电了，进入睡前仪式。", short: "断电"),
    .init(id: "22:30", label: "上床 · 保证 7–9 小时睡眠",        speech: "该上床了，晚安。", short: "上床")
]

// MARK: - 设置
struct VitalitySettings: Equatable {
    var sound = true
    var speech = false
    var hourly = false
    var launchAtLogin = false
    var notificationsAsked = false
    var pomoTick = true         // 番茄钟专注运行中的滴答声
    var cardTrend = true        // 卡片显隐：近 7 天趋势
    var cardCalendar = true     // 卡片显隐：月历打卡
    var cardBreath = true       // 卡片显隐：呼吸练习
    var dndUntil: Double? = nil // 免打扰截止时刻（epoch 秒），期间暂停任务/整点提醒
}

// 自定义解码 + 自动编码；老配置缺新字段时用默认值，而不是整个重置
extension VitalitySettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case sound, speech, hourly, launchAtLogin, notificationsAsked
        case pomoTick, cardTrend, cardCalendar, cardBreath, dndUntil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        speech = try c.decodeIfPresent(Bool.self, forKey: .speech) ?? false
        hourly = try c.decodeIfPresent(Bool.self, forKey: .hourly) ?? false
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        notificationsAsked = try c.decodeIfPresent(Bool.self, forKey: .notificationsAsked) ?? false
        pomoTick = try c.decodeIfPresent(Bool.self, forKey: .pomoTick) ?? true
        cardTrend = try c.decodeIfPresent(Bool.self, forKey: .cardTrend) ?? true
        cardCalendar = try c.decodeIfPresent(Bool.self, forKey: .cardCalendar) ?? true
        cardBreath = try c.decodeIfPresent(Bool.self, forKey: .cardBreath) ?? true
        dndUntil = try c.decodeIfPresent(Double.self, forKey: .dndUntil) ?? nil
    }
}

enum NotifStatus {
    case unknown
    case authorized
    case denied
}

// MARK: - 当日测量记录（体重 / 血压 / 睡眠）
// 血压一天内波动大（晨峰 vs 午后），用多次读数而非单一值
struct BPReading: Codable, Equatable, Identifiable {
    var timestamp: Double   // epoch 秒
    var sys: Int
    var dia: Int
    var id: String { String(format: "%.0f", timestamp * 1000) }

    var timeText: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: timestamp))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    var status: (String, Color) {
        if sys >= 140 || dia >= 90 { return ("偏高 ⚠️", .roseC) }
        if sys >= 130 || dia >= 85 { return ("偏高", .amberC) }
        if sys >= 120 || dia >= 80 { return ("正常高值", .amberC) }
        return ("正常", .mintC)
    }
}

// 每个任务打卡带完成时间戳（几点完成的）
struct DoneRecord: Codable, Equatable, Identifiable {
    let taskId: String
    let timestamp: Double   // epoch 秒
    var id: String { taskId }
    var timeText: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: timestamp))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

struct VitalityMetrics: Codable, Equatable {
    var weight: Double?       // kg
    var bpReadings: [BPReading] = []   // 一天多次血压读数
    var sleepMinutes: Int?     // 昨晚睡眠分钟数
    var savedAt: Double? = nil // 最近一次记录时刻（epoch 秒）

    var latestBP: BPReading? { bpReadings.max(by: { $0.timestamp < $1.timestamp }) }

    var bpStatus: (String, Color)? { latestBP?.status }

    private enum CodingKeys: String, CodingKey {
        case weight, bpReadings, sleepMinutes, savedAt
        case sysLegacy = "sys", diaLegacy = "dia"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        sleepMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepMinutes)
        savedAt = try c.decodeIfPresent(Double.self, forKey: .savedAt)
        if let readings = try c.decodeIfPresent([BPReading].self, forKey: .bpReadings) {
            bpReadings = readings
        } else if let s = try c.decodeIfPresent(Int.self, forKey: .sysLegacy),
                  let d = try c.decodeIfPresent(Int.self, forKey: .diaLegacy) {
            bpReadings = [BPReading(timestamp: savedAt ?? Date().timeIntervalSince1970, sys: s, dia: d)]
        } else {
            bpReadings = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(sleepMinutes, forKey: .sleepMinutes)
        try c.encodeIfPresent(savedAt, forKey: .savedAt)
        if !bpReadings.isEmpty { try c.encode(bpReadings, forKey: .bpReadings) }
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
    var sleepH = ""
    var sleepM = ""

    var parsed: VitalityMetrics {
        let w = Double(weight)
        let h = Int(sleepH)
        let m = Int(sleepM)
        let sleep = (h == nil && m == nil) ? nil : (h ?? 0) * 60 + (m ?? 0)
        var v = VitalityMetrics()
        v.weight = w
        v.sleepMinutes = sleep
        return v
    }

    static func from(_ m: VitalityMetrics) -> MetricsText {
        var t = MetricsText()
        if let w = m.weight { t.weight = w == w.rounded() ? String(Int(w)) : String(w) }
        if let sl = m.sleepMinutes {
            t.sleepH = String(sl / 60)
            if sl % 60 != 0 { t.sleepM = String(sl % 60) }
        }
        return t
    }
}

// MARK: - 历史记录（每天一份快照，用于趋势图与月历打卡）
struct HistoryDay: Codable, Equatable {
    let date: String
    var weight: Double?
    var bpReadings: [BPReading]?
    var sleepMinutes: Int?
    var doneCount: Int?
    var tomatoes: Int?
    var waterGlasses: Int?
    var doneRecords: [DoneRecord]?    // 带时间戳的完成记录

    /// 旧字段兼容（只有 id 数组、无时间戳）
    private enum CodingKeys: String, CodingKey {
        case date, weight, bpReadings, sleepMinutes, doneCount, tomatoes, waterGlasses, doneRecords
        case doneIdsLegacy = "doneIds"
        case sysLegacy = "sys", diaLegacy = "dia"
    }

    init(date: String, weight: Double?, bpReadings: [BPReading]?, sleepMinutes: Int?,
         doneCount: Int?, tomatoes: Int?, waterGlasses: Int?, doneRecords: [DoneRecord]?) {
        self.date = date
        self.weight = weight
        self.bpReadings = bpReadings
        self.sleepMinutes = sleepMinutes
        self.doneCount = doneCount
        self.tomatoes = tomatoes
        self.waterGlasses = waterGlasses
        self.doneRecords = doneRecords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        if let r = try c.decodeIfPresent([BPReading].self, forKey: .bpReadings) {
            bpReadings = r
        } else if let s = try c.decodeIfPresent(Int.self, forKey: .sysLegacy),
                  let d = try c.decodeIfPresent(Int.self, forKey: .diaLegacy) {
            bpReadings = [BPReading(timestamp: Date().timeIntervalSince1970, sys: s, dia: d)]
        } else {
            bpReadings = nil
        }
        sleepMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepMinutes)
        doneCount = try c.decodeIfPresent(Int.self, forKey: .doneCount)
        tomatoes = try c.decodeIfPresent(Int.self, forKey: .tomatoes)
        waterGlasses = try c.decodeIfPresent(Int.self, forKey: .waterGlasses)
        if let recs = try c.decodeIfPresent([DoneRecord].self, forKey: .doneRecords) {
            doneRecords = recs
        } else if let ids = try c.decodeIfPresent([String].self, forKey: .doneIdsLegacy) {
            // 旧格式迁移：id 数组 → DoneRecord（用任务计划时间作近似）
            doneRecords = ids.map { id in
                DoneRecord(taskId: id, timestamp: Self.scheduledTimestamp(dayKey: date, taskId: id))
            }
        } else {
            doneRecords = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(weight, forKey: .weight)
        if let r = bpReadings, !r.isEmpty { try c.encode(r, forKey: .bpReadings) }
        try c.encodeIfPresent(sleepMinutes, forKey: .sleepMinutes)
        try c.encodeIfPresent(doneCount, forKey: .doneCount)
        try c.encodeIfPresent(tomatoes, forKey: .tomatoes)
        try c.encodeIfPresent(waterGlasses, forKey: .waterGlasses)
        if let recs = doneRecords, !recs.isEmpty { try c.encode(recs, forKey: .doneRecords) }
    }

    /// 旧数据迁移用：把任务计划时间（"07:00"）落到指定日期，作为完成时刻的近似
    static func scheduledTimestamp(dayKey: String, taskId: String) -> Double {
        let dp = dayKey.split(separator: "-").compactMap { Int($0) }
        guard dp.count == 3 else { return Date().timeIntervalSince1970 }
        var c = DateComponents(); c.year = dp[0]; c.month = dp[1]; c.day = dp[2]
        guard let day = Calendar.current.date(from: c) else { return Date().timeIntervalSince1970 }
        let tp = taskId.split(separator: ":").compactMap { Int($0) }
        guard tp.count == 2 else { return day.timeIntervalSince1970 }
        return day.addingTimeInterval(Double(tp[0]) * 3600 + Double(tp[1]) * 60).timeIntervalSince1970
    }

    var doneSet: Set<String> { Set((doneRecords ?? []).map { $0.taskId }) }
}

// MARK: - 整点起身提醒轮换的拉伸动作库
let STRETCH_TIPS = [
    "颈部：缓慢左右转头各 5 次",
    "肩部环绕 10 次，顺便喝口水",
    "靠墙静蹲 30 秒",
    "远眺窗外 20 秒 + 用力眨眼 10 次",
    "双手上举，向两侧弯腰各 10 秒",
    "走楼梯或快走 2 分钟，唤醒下肢"
]

// MARK: - 全局状态存储（本机持久化，跨天自动重置）
final class VitalityStore: ObservableObject {
    struct PersistedState: Codable {
        let day: String
        var doneRecords: [DoneRecord]?
        var metrics: VitalityMetrics?
        var waterGlasses: Int?

        private enum CodingKeys: String, CodingKey {
            case day, doneRecords, metrics, waterGlasses
            case doneLegacy = "done"
        }

        init(day: String, doneRecords: [DoneRecord]?, metrics: VitalityMetrics?, waterGlasses: Int?) {
            self.day = day
            self.doneRecords = doneRecords
            self.metrics = metrics
            self.waterGlasses = waterGlasses
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = try c.decode(String.self, forKey: .day)
            metrics = try c.decodeIfPresent(VitalityMetrics.self, forKey: .metrics)
            waterGlasses = try c.decodeIfPresent(Int.self, forKey: .waterGlasses)
            if let recs = try c.decodeIfPresent([DoneRecord].self, forKey: .doneRecords) {
                doneRecords = recs
            } else if let ids = try c.decodeIfPresent([String].self, forKey: .doneLegacy) {
                // 旧格式迁移：只存了任务 id，用该任务的计划时间作为完成时刻近似
                doneRecords = ids.map { id in
                    DoneRecord(taskId: id, timestamp: HistoryDay.scheduledTimestamp(dayKey: day, taskId: id))
                }
            } else {
                doneRecords = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(day, forKey: .day)
            if let r = doneRecords, !r.isEmpty { try c.encode(r, forKey: .doneRecords) }
            try c.encodeIfPresent(metrics, forKey: .metrics)
            try c.encodeIfPresent(waterGlasses, forKey: .waterGlasses)
        }
    }

    @Published var dayKey: String
    @Published var doneRecords: [DoneRecord] = []
    @Published var settings: VitalitySettings
    @Published var banner: String?
    @Published var notifStatus: NotifStatus = .unknown
    @Published var metricsText = MetricsText()
    @Published var waterGlasses = 0
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
            doneRecords = s.doneRecords ?? []
            waterGlasses = s.waterGlasses ?? 0
            if let m = s.metrics {
                metrics = m
                metricsText = MetricsText.from(m)
            }
        } else {
            dayKey = today
            doneRecords = []
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

    /// 当前已完成任务的 id 集合（便利属性）
    var done: Set<String> { Set(doneRecords.map { $0.taskId }) }

    func isDone(_ id: String) -> Bool { done.contains(id) }

    func doneTimestamp(_ id: String) -> Double? {
        doneRecords.first { $0.taskId == id }?.timestamp
    }

    private func persistState() {
        syncHistoryToday()
        let s = PersistedState(day: dayKey, doneRecords: doneRecords, metrics: metrics, waterGlasses: waterGlasses)
        if let data = try? JSONEncoder().encode(s), let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: "vitality.state")
        }
        persistHistory()
    }

    /// 供外部（如番茄钟完成回调）把当天快照落盘，保证 streak 不漏记
    func syncTodaySnapshot() {
        persistState()
    }

    /// 把当天的测量与打卡写入历史（同一天覆盖，最多留 90 天）
    private func syncHistoryToday() {
        let key = VitalityStore.isoKey()
        let entry = HistoryDay(
            date: key,
            weight: metrics.weight,
            bpReadings: metrics.bpReadings.isEmpty ? nil : metrics.bpReadings,
            sleepMinutes: metrics.sleepMinutes,
            doneCount: done.count,
            tomatoes: pomo.state.todayTomatoes,
            waterGlasses: waterGlasses,
            doneRecords: doneRecords.isEmpty ? nil : doneRecords
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
        m.bpReadings = metrics.bpReadings   // 血压不经过文本，保留已有读数
        let hasAny = m.weight != nil || !m.bpReadings.isEmpty || m.sleepMinutes != nil
        m.savedAt = hasAny ? Date().timeIntervalSince1970 : nil
        metrics = m
        persistState()
    }

    /// 新增一次血压读数（时间取当前）
    func addBPReading(sys: Int, dia: Int) {
        let r = BPReading(timestamp: Date().timeIntervalSince1970, sys: sys, dia: dia)
        metrics.bpReadings.append(r)
        metrics.savedAt = Date().timeIntervalSince1970
        persistState()
    }

    func removeBPReading(_ id: String) {
        metrics.bpReadings.removeAll { $0.id == id }
        if metrics.bpReadings.isEmpty && metrics.weight == nil && metrics.sleepMinutes == nil {
            metrics.savedAt = nil
        }
        persistState()
    }

    /// 某天最新血压读数（趋势图用）
    func latestBP(on iso: String) -> BPReading? {
        if iso == VitalityStore.isoKey() { return metrics.latestBP }
        return history.first { $0.date == iso }?.bpReadings?.max(by: { $0.timestamp < $1.timestamp })
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
        if let i = doneRecords.firstIndex(where: { $0.taskId == id }) {
            doneRecords.remove(at: i)
        } else {
            doneRecords.append(DoneRecord(taskId: id, timestamp: Date().timeIntervalSince1970))
        }
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
        doneRecords = []
        fired = []
        metrics = VitalityMetrics()
        metricsText = MetricsText()
        waterGlasses = 0
        markFarPastAsFired()
        persistState()
        return true
    }

    // MARK: 饮水
    func addWater(_ delta: Int) {
        waterGlasses = max(0, min(20, waterGlasses + delta))
        persistState()
    }

    /// 每杯按 250ml；有体重时按 35ml/kg 自动算目标，否则默认 8 杯
    var waterGoalGlasses: Int {
        if let w = metrics.weight, w > 30 {
            return max(6, min(14, Int((w * 35.0 / 250.0).rounded(.up))))
        }
        return 8
    }

    // MARK: 连续打卡 streak
    private func hasActivityOn(offsetDays offset: Int) -> Bool {
        guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return false }
        if offset == 0 {
            return !done.isEmpty || waterGlasses > 0 || pomo.state.todayTomatoes > 0
                || metrics.weight != nil || !metrics.bpReadings.isEmpty || metrics.sleepMinutes != nil
        }
        let iso = VitalityStore.isoKey(d)
        guard let h = history.first(where: { $0.date == iso }) else { return false }
        return (h.doneCount ?? 0) > 0 || (h.tomatoes ?? 0) > 0 || (h.waterGlasses ?? 0) > 0
            || h.weight != nil || !(h.bpReadings ?? []).isEmpty || h.sleepMinutes != nil
    }

    /// 今天有活动算今天；没活动则从昨天起算——streak 只有隔一整天空窗才断
    func computeStreak() -> Int {
        var streak = 0
        if hasActivityOn(offsetDays: 0) { streak += 1 }
        var offset = 1
        while hasActivityOn(offsetDays: offset) {
            streak += 1
            offset += 1
        }
        return streak
    }

    /// 补卡：切换某个历史日期某任务的完成状态（带当天午夜兜底时间戳）
    func toggleHistoryDone(_ isoDate: String, taskId: String) {
        guard isoDate != VitalityStore.isoKey() else { return }
        let baseTs = HistoryDay.scheduledTimestamp(dayKey: isoDate, taskId: taskId)
        if let i = history.firstIndex(where: { $0.date == isoDate }) {
            var recs = history[i].doneRecords ?? []
            if let j = recs.firstIndex(where: { $0.taskId == taskId }) {
                recs.remove(at: j)
            } else {
                recs.append(DoneRecord(taskId: taskId, timestamp: baseTs))
            }
            history[i].doneRecords = recs.isEmpty ? nil : recs
            history[i].doneCount = recs.count
        } else {
            history.append(HistoryDay(date: isoDate, weight: nil, bpReadings: nil,
                                       sleepMinutes: nil, doneCount: 1, tomatoes: 0,
                                       waterGlasses: 0, doneRecords: [DoneRecord(taskId: taskId, timestamp: baseTs)]))
            history.sort { $0.date < $1.date }
        }
        persistHistory()
    }

    /// 某任务截至今天（或昨天）的连续完成天数
    func taskStreak(_ taskId: String) -> Int {
        var streak = 0
        if done.contains(taskId) { streak += 1 }
        var offset = 1
        while offset <= 90 {
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let iso = VitalityStore.isoKey(d)
            if let h = history.first(where: { $0.date == iso }), h.doneSet.contains(taskId) {
                streak += 1
                offset += 1
            } else {
                break
            }
        }
        return streak
    }

    /// 某天清单完成率（0–1），今天取实时
    func dayDoneRatio(_ d: Date) -> Double {
        let total = TASKS.count
        guard total > 0 else { return 0 }
        let cnt: Int
        if Calendar.current.isDateInToday(d) {
            cnt = done.count
        } else if let h = history.first(where: { $0.date == VitalityStore.isoKey(d) }) {
            cnt = h.doneCount ?? h.doneSet.count
        } else {
            cnt = 0
        }
        return Double(cnt) / Double(total)
    }

    // MARK: 免打扰
    var dndActive: Bool {
        if let u = settings.dndUntil { return Date().timeIntervalSince1970 < u }
        return false
    }

    var dndRemainingMin: Int {
        if let u = settings.dndUntil { return max(0, Int(ceil((u - Date().timeIntervalSince1970) / 60))) }
        return 0
    }

    func setDND(seconds: Double) {
        settings.dndUntil = Date().timeIntervalSince1970 + seconds
        persistSettings()
        onReschedule?()
    }

    func clearDND() {
        settings.dndUntil = nil
        persistSettings()
        onReschedule?()
    }

    /// 到点 30 分钟内、未完成、未提醒过 → 触发（由 AppDelegate 每 30 秒轮询）；免打扰期间静音
    func dueReminders() -> [String] {
        var out: [String] = []
        let n = nowMinutes()

        if !dndActive {
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
                        out.append("整点提醒 · 起身：" + STRETCH_TIPS[h % STRETCH_TIPS.count])
                    }
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
