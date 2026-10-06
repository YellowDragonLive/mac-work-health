import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: VitalityStore
    var onHide: () -> Void

    private let speechSynth = NSSpeechSynthesizer()

    private let WEEK = ["日", "一", "二", "三", "四", "五", "六"]

    // MARK: - Tab 架构
    enum AppTab: String, CaseIterable {
        case today, focus, record, settings
        var title: String {
            switch self {
            case .today: return "今天"
            case .focus: return "专注"
            case .record: return "记录"
            case .settings: return "设置"
            }
        }
        var icon: String {
            switch self {
            case .today: return "bolt.fill"
            case .focus: return "timer"
            case .record: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    @State private var activeTab: AppTab = .today

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(spacing: 0) {
                header(date: timeline.date)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 0.5)
                ScrollView {
                    tabContent
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                tabBar
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .overlay(alignment: .top) { bannerOverlay }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .today:
            VStack(spacing: 12) {
                nowCard
                checklistCard
            }
        case .focus:
            VStack(spacing: 12) {
                pomoCard
                if store.settings.cardBreath { breathCard }
            }
        case .record:
            VStack(spacing: 12) {
                metricsCard
                if store.settings.cardTrend { trendCard }
                if store.settings.cardCalendar { calendarCard }
            }
        case .settings:
            VStack(spacing: 12) {
                settingsCard
                customizeCard
                footer
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        .padding(.horizontal, 16)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isActive = activeTab == tab
        return Button(action: { activeTab = tab }) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                if tab == .focus && store.pomo.state.running {
                    // 运行中：专注 tab 的文字换成倒计时角标
                    Text(store.pomo.timeText())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.gold)
                } else {
                    Text(tab.title)
                        .font(.system(size: 9, weight: isActive ? .bold : .regular))
                }
            }
            .foregroundColor(isActive ? Color(hex: 0x1a1206) : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    isActive
                    ? AnyShapeStyle(LinearGradient(colors: [.gold, .amberC],
                                                   startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.clear)
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 头部（时钟 + 日期 + 时段 + 隐藏按钮）
    private func header(date: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clockText(date))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .gold, .amberC],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                let c = Calendar.current.dateComponents([.month, .day, .weekday], from: date)
                Text("\(c.month ?? 1)月\(c.day ?? 1)日 · 周\(WEEK[(c.weekday ?? 1) - 1])")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                let phase = store.phaseInfo(for: date)
                Text(phase.0)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(phase.1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().strokeBorder(phase.1.opacity(0.45))
                            .background(Capsule().fill(phase.1.opacity(0.08)))
                    )
                    .padding(.top, 4)
            }
            Spacer(minLength: 10)
            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("隐藏（从菜单栏 ⚡ 图标重新呼出）")
        }
    }

    private func clockText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: 现在该做
    private var nowCard: some View {
        let current = store.currentTask
        let isDone = current.map { store.done.contains($0.id) } ?? false

        return VStack(alignment: .leading, spacing: 7) {
            Text("现在该做")
                .font(.system(size: 10.5, weight: .bold))
                .kerning(3)
                .foregroundColor(.gold)

            HStack(alignment: .top, spacing: 10) {
                Text(current?.label ?? "清单从明天 07:00 开始，先睡好这一觉")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDone ? .secondary : .primary)
                    .strikethrough(isDone)
                Spacer(minLength: 8)
                if let t = current {
                    Button(action: { store.toggle(t.id) }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isDone ? Color(hex: 0x06231c) : .mintC)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isDone ? Color.mintC : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.mintC, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let next = store.nextTask, let mins = store.minutesToNext {
                Text("下一项 \(next.id) · 约 \(mins) 分钟后 — \(next.label)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("今日清单走完 🌙 早点休息")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.gold.opacity(0.25))
        )
    }

    // MARK: 清单
    private var checklistCard: some View {
        let currentId = store.currentTask?.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("⚡ 今日清单")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Text("\(store.done.count) / \(TASKS.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.mintC, .skyC], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * store.progress)
                }
            }
            .frame(height: 5)
            .padding(.vertical, 6)

            VStack(spacing: 0) {
                ForEach(TASKS) { t in
                    taskRow(t, current: currentId == t.id)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private func taskRow(_ t: VitalityTask, current: Bool) -> some View {
        let isDone = store.done.contains(t.id)
        return Button(action: { store.toggle(t.id) }) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.mintC, lineWidth: 1.5)
                        .frame(width: 17, height: 17)
                    if isDone {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.mintC)
                            .frame(width: 17, height: 17)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: 0x06231c))
                    }
                }
                Text(t.label)
                    .font(.system(size: 11.5, weight: current && !isDone ? .bold : .regular))
                    .foregroundColor(isDone ? .secondary : .primary)
                    .strikethrough(isDone)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(t.id)
                    .font(.system(size: 10))
                    .foregroundColor(current && !isDone ? .gold : .secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
                .padding(.horizontal, 2),
            alignment: .bottom
        )
    }

    // MARK: 今日测量（体重 / 血压 / 睡眠）
    private var metricsCard: some View {
        let m = store.metricsText.parsed
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("📊 今日测量")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                if let saved = store.metrics.savedAt {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(.mintC)
                        Text("已记录 \(epochText(saved))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mintC)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Text("当天记录 · 0 点重置")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: store.metrics.savedAt)

            // 体重
            HStack(spacing: 8) {
                Text("⚖️ 体重")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 62, alignment: .leading)
                MetricField(placeholder: "如 72.5", text: weightBinding, width: 88)
                Text("kg")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                if (m.weight ?? 0) > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.mintC)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("晨起空腹")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.white.opacity(0.25))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: m.weight)

            // 血压
            HStack(spacing: 8) {
                Text("🩺 血压")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 62, alignment: .leading)
                MetricField(placeholder: "高压", text: sysBinding, width: 48)
                Text("/")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                MetricField(placeholder: "低压", text: diaBinding, width: 48)
                if let st = m.bpStatus {
                    Text(st.0)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(st.1)
                } else {
                    Text("mmHg")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            // 睡眠
            HStack(spacing: 8) {
                Text("😴 睡眠")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(width: 62, alignment: .leading)
                MetricField(placeholder: "时", text: sleepHBinding, width: 42)
                Text("时")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                MetricField(placeholder: "分", text: sleepMBinding, width: 42)
                Text("分")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if let st = m.sleepStatus {
                    Text(st.0)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(st.1)
                }
                Spacer()
            }

            Text("血压建议静坐 5 分钟后测 · 睡眠按昨晚实际时长填")
                .font(.system(size: 9))
                .foregroundColor(Color.white.opacity(0.22))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private func epochText(_ epoch: Double) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: epoch))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // 输入清洗：只留 ASCII 数字，体重额外留一个小数点
    private func integers(_ s: String) -> String {
        String(s.filter { $0.isASCII && $0.isNumber }.prefix(3))
    }

    private func decimal(_ s: String) -> String {
        var seenDot = false
        var out = ""
        for ch in s {
            if ch.isASCII && ch.isNumber { out.append(ch) }
            else if ch == "." && !seenDot { out.append(ch); seenDot = true }
        }
        return String(out.prefix(6))
    }

    private var weightBinding: Binding<String> {
        Binding(get: { store.metricsText.weight },
                set: { v in store.setMetrics { $0.weight = decimal(v) } })
    }

    private var sysBinding: Binding<String> {
        Binding(get: { store.metricsText.sys },
                set: { v in store.setMetrics { $0.sys = integers(v) } })
    }

    private var diaBinding: Binding<String> {
        Binding(get: { store.metricsText.dia },
                set: { v in store.setMetrics { $0.dia = integers(v) } })
    }

    private var sleepHBinding: Binding<String> {
        Binding(get: { store.metricsText.sleepH },
                set: { v in store.setMetrics { $0.sleepH = String(integers(v).prefix(2)) } })
    }

    private var sleepMBinding: Binding<String> {
        Binding(get: { store.metricsText.sleepM },
                set: { v in store.setMetrics { $0.sleepM = String(integers(v).prefix(2)) } })
    }

    // 紧凑输入框
    private struct MetricField: View {
        let placeholder: String
        @Binding var text: String
        var width: CGFloat

        var body: some View {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: width, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.28)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.12)))
        }
    }

    // MARK: 近 7 天趋势
    private enum TrendMetric: CaseIterable {
        case weight, bp, sleep
        var title: String {
            switch self {
            case .weight: return "体重"
            case .bp: return "血压"
            case .sleep: return "睡眠"
            }
        }
    }

    @State private var trendMetric: TrendMetric = .weight

    private var historyMap: [String: HistoryDay] {
        Dictionary(store.history.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var last7Days: [(iso: String, label: String)] {
        (0..<7).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let c = Calendar.current.dateComponents([.month, .day], from: d)
            return (VitalityStore.isoKey(d), "\(c.month ?? 0)/\(c.day ?? 0)")
        }
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📈 近 7 天趋势")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Text("记录 ≥2 天出图")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(TrendMetric.allCases, id: \.self) { m in
                    Button(action: { trendMetric = m }) {
                        Text(m.title)
                            .font(.system(size: 10.5, weight: trendMetric == m ? .bold : .regular))
                            .foregroundColor(trendMetric == m ? Color(hex: 0x1a1206) : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(trendMetric == m
                                          ? AnyShapeStyle(LinearGradient(colors: [.gold, .amberC],
                                                                         startPoint: .leading, endPoint: .trailing))
                                          : AnyShapeStyle(Color.white.opacity(0.05)))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            trendChartBody
            trendStats
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private var trendChartBody: some View {
        let days = last7Days
        let map = historyMap
        switch trendMetric {
        case .weight:
            MultiLineChart(
                labels: days.map(\.label),
                series: [(color: .mintC, values: days.map { map[$0.iso]?.weight })],
                formatter: { String(format: "%.1f", $0) },
                legend: nil,
                band: nil
            )
        case .bp:
            MultiLineChart(
                labels: days.map(\.label),
                series: [
                    (color: .gold, values: days.map { map[$0.iso]?.sys.map(Double.init) }),
                    (color: .skyC, values: days.map { map[$0.iso]?.dia.map(Double.init) })
                ],
                formatter: { String(format: "%.0f", $0) },
                legend: [("高压", .gold), ("低压", .skyC)],
                band: nil
            )
        case .sleep:
            MultiLineChart(
                labels: days.map(\.label),
                series: [(color: .violetC, values: days.map { map[$0.iso]?.sleepMinutes.map { Double($0) / 60.0 } })],
                formatter: { String(format: "%.1f", $0) },
                legend: nil,
                band: 7.0...9.0
            )
        }
    }

    @ViewBuilder
    private var trendStats: some View {
        let days = last7Days
        let map = historyMap
        switch trendMetric {
        case .weight:
            let vals = days.compactMap { map[$0.iso]?.weight }
            if vals.count >= 2, let last = vals.last, let first = vals.first {
                let d = last - first
                Text("最新 \(String(format: "%.1f", last)) kg · 7 天 \(d >= 0 ? "+" : "")\(String(format: "%.1f", d))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.skyC)
            } else {
                trendPlaceholder
            }
        case .bp:
            let lastEntry = days.compactMap { map[$0.iso] }.last { $0.sys != nil && $0.dia != nil }
            if let e = lastEntry, let s = e.sys, let dd = e.dia {
                Text("最新 \(s)/\(dd) mmHg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.skyC)
            } else {
                trendPlaceholder
            }
        case .sleep:
            let vals = days.compactMap { map[$0.iso]?.sleepMinutes }
            if !vals.isEmpty {
                let avg = Double(vals.reduce(0, +)) / Double(vals.count) / 60.0
                Text("平均 \(String(format: "%.1f", avg)) 小时 · 目标 7–9h")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.skyC)
            } else {
                trendPlaceholder
            }
        }
    }

    private var trendPlaceholder: some View {
        Text("记录至少 2 天后显示趋势")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
    }

    // MARK: 折线图组件
    private struct MultiLineChart: View {
        let labels: [String]
        let series: [(color: Color, values: [Double?])]
        let formatter: (Double) -> String
        let legend: [(String, Color)]?
        var band: ClosedRange<Double>? = nil

        var body: some View {
            let flat = series.flatMap { $0.values.compactMap { $0 } }
            if flat.count < 2 {
                emptyView
            } else {
                chartView
            }
        }

        private var emptyView: some View {
            Text("记录至少 2 天后出现趋势图")
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.28))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        }

        private var chartView: some View {
            VStack(spacing: 6) {
                legendRow
                GeometryReader { geo in
                    chartZStack(geo)
                }
                .frame(height: 92)
                labelRow
            }
        }

        @ViewBuilder
        private var legendRow: some View {
            if let legend = legend {
                HStack(spacing: 12) {
                    ForEach(Array(legend.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 4) {
                            Circle().fill(item.1).frame(width: 5, height: 5)
                            Text(item.0).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var labelRow: some View {
            HStack(spacing: 0) {
                ForEach(labels, id: \.self) { l in
                    Text(l)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        private func xFor(_ i: Int, w: CGFloat) -> CGFloat {
            labels.count <= 1 ? w / 2 : w * CGFloat(i) / CGFloat(labels.count - 1)
        }

        private func yFor(_ v: Double, h: CGFloat, yLo: Double, yHi: Double) -> CGFloat {
            h * (1 - CGFloat((v - yLo) / (yHi - yLo)))
        }

        private func chartZStack(_ geo: GeometryProxy) -> some View {
            let w = geo.size.width
            let h = geo.size.height
            let flat = series.flatMap { $0.values.compactMap { $0 } }
            let lo = flat.min() ?? 0
            let hi = flat.max() ?? 1
            let span = max(hi - lo, abs(hi) * 0.08, 0.001)
            let yLo = lo - span * 0.2
            let yHi = hi + span * 0.2
            return ZStack {
                gridLines(h: h, w: w)
                bandRect(band, h: h, w: w, yLo: yLo, yHi: yHi)
                seriesLines(w: w, h: h, yLo: yLo, yHi: yHi)
                seriesDots(w: w, h: h, yLo: yLo, yHi: yHi)
            }
        }

        private func gridLines(h: CGFloat, w: CGFloat) -> some View {
            ForEach(0..<3, id: \.self) { g in
                let y = h * (0.25 + CGFloat(g) * 0.25)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            }
        }

        @ViewBuilder
        private func bandRect(_ band: ClosedRange<Double>?, h: CGFloat, w: CGFloat, yLo: Double, yHi: Double) -> some View {
            if let band = band {
                let yTop = h * (1 - CGFloat((band.upperBound - yLo) / (yHi - yLo)))
                let yBot = h * (1 - CGFloat((band.lowerBound - yLo) / (yHi - yLo)))
                Rectangle()
                    .fill(Color.mintC.opacity(0.08))
                    .frame(width: w, height: max(0, yBot - yTop))
                    .position(x: w / 2, y: (yTop + yBot) / 2)
            }
        }

        private func seriesLines(w: CGFloat, h: CGFloat, yLo: Double, yHi: Double) -> some View {
            ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                Path { p in
                    var lastPoint: CGPoint? = nil
                    for (i, v) in s.values.enumerated() {
                        guard let v = v else { lastPoint = nil; continue }
                        let c = CGPoint(x: xFor(i, w: w), y: yFor(v, h: h, yLo: yLo, yHi: yHi))
                        if lastPoint != nil { p.addLine(to: c) } else { p.move(to: c) }
                        lastPoint = c
                    }
                }
                .stroke(s.color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }

        private func seriesDots(w: CGFloat, h: CGFloat, yLo: Double, yHi: Double) -> some View {
            ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    if let v = v {
                        Circle().fill(s.color).frame(width: 4, height: 4)
                            .position(x: xFor(i, w: w), y: yFor(v, h: h, yLo: yLo, yHi: yHi))
                    }
                }
            }
        }
    }

    // MARK: 界面模块自定义（卡片显隐）
    private var customizeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🎨 界面模块")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Text("不用的模块直接隐藏")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            ToggleRow(
                icon: "📈",
                title: "近 7 天趋势",
                subtitle: "记录页折线图",
                isOn: Binding(
                    get: { store.settings.cardTrend },
                    set: { v in store.setSettings { $0.cardTrend = v } }
                )
            )
            ToggleRow(
                icon: "📅",
                title: "月历打卡",
                subtitle: "记录页日历",
                isOn: Binding(
                    get: { store.settings.cardCalendar },
                    set: { v in store.setSettings { $0.cardCalendar = v } }
                )
            )
            ToggleRow(
                icon: "🫁",
                title: "呼吸练习",
                subtitle: "专注页 4-7-8",
                isOn: Binding(
                    get: { store.settings.cardBreath },
                    set: { v in store.setSettings { $0.cardBreath = v } }
                )
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    // MARK: 月历打卡
    @State private var calAnchor = Date()
    @State private var selectedDate = Date()

    private var calendarCard: some View {
        let info = monthGrid(for: calAnchor)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: { moveMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(info.title)
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Button(action: { moveMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { w in
                    Text(w)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(info.grid.enumerated()), id: \.offset) { _, d in
                    calCell(d)
                }
            }

            dayDetail
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private func monthGrid(for anchor: Date) -> (title: String, grid: [Date?]) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: anchor)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else {
            return ("", [])
        }
        var grid: [Date?] = Array(repeating: nil, count: cal.component(.weekday, from: first) - 1)
        for day in range {
            if let d = cal.date(byAdding: .day, value: day - 1, to: first) { grid.append(d) }
        }
        while grid.count % 7 != 0 { grid.append(nil) }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy年M月"
        return (fmt.string(from: first), grid)
    }

    private func moveMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: calAnchor) {
            calAnchor = d
        }
    }

    private struct DayInfo {
        var metrics: Bool
        var checklist: Bool
        var tomatoes: Bool
        var doneCount: Int
        var tomatoCount: Int
        var metricsVal: VitalityMetrics
    }

    private func dayStatus(_ d: Date) -> DayInfo {
        if Calendar.current.isDateInToday(d) {
            let mv = store.metrics
            let hasM = mv.weight != nil || mv.sys != nil || mv.dia != nil || mv.sleepMinutes != nil
            let tc = store.pomo.state.todayTomatoes
            return DayInfo(metrics: hasM, checklist: !store.done.isEmpty, tomatoes: tc > 0,
                           doneCount: store.done.count, tomatoCount: tc, metricsVal: mv)
        }
        let h = historyMap[VitalityStore.isoKey(d)]
        let mv = VitalityMetrics(weight: h?.weight, sys: h?.sys, dia: h?.dia,
                                 sleepMinutes: h?.sleepMinutes, savedAt: nil)
        let hasM = mv.weight != nil || mv.sys != nil || mv.dia != nil || mv.sleepMinutes != nil
        let dc = h?.doneCount ?? 0
        let tc = h?.tomatoes ?? 0
        return DayInfo(metrics: hasM, checklist: dc > 0, tomatoes: tc > 0,
                       doneCount: dc, tomatoCount: tc, metricsVal: mv)
    }

    @ViewBuilder
    private func calCell(_ date: Date?) -> some View {
        if let d = date {
            let st = dayStatus(d)
            let isToday = Calendar.current.isDateInToday(d)
            let isFuture = d > Date() && !isToday
            let isSel = Calendar.current.isDate(selectedDate, inSameDayAs: d)
            Button(action: { if !isFuture { selectedDate = d } }) {
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: d))")
                        .font(.system(size: 10.5, weight: isToday || isSel ? .bold : .regular))
                        .foregroundColor(isFuture ? Color.white.opacity(0.18) : isSel ? .gold : .primary)
                    HStack(spacing: 2) {
                        if st.metrics { Circle().fill(Color.mintC).frame(width: 3, height: 3) }
                        if st.checklist { Circle().fill(Color.skyC).frame(width: 3, height: 3) }
                        if st.tomatoes { Circle().fill(Color.gold).frame(width: 3, height: 3) }
                    }
                    .frame(height: 3)
                }
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSel ? Color.gold.opacity(0.14) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isToday ? Color.mintC.opacity(0.7) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 30)
        }
    }

    @ViewBuilder
    private var dayDetail: some View {
        let st = dayStatus(selectedDate)
        let isToday = Calendar.current.isDateInToday(selectedDate)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "M月d日 EEE"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(fmt.string(from: selectedDate))
                    .font(.system(size: 11, weight: .bold))
                if isToday {
                    Text("今天")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(Color(hex: 0x06231c))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.mintC))
                }
                Spacer()
            }
            if st.metrics || st.checklist || st.tomatoes {
                detailRow("⚡", "清单", "\(st.doneCount) / \(TASKS.count)")
                if let w = st.metricsVal.weight {
                    detailRow("⚖️", "体重", String(format: "%.1f kg", w))
                }
                if let s = st.metricsVal.sys, let dd = st.metricsVal.dia {
                    detailRow("🩺", "血压", "\(s)/\(dd) mmHg")
                }
                if st.metricsVal.sleepText != nil {
                    detailRow("😴", "睡眠", st.metricsVal.sleepText ?? "")
                }
                if st.tomatoCount > 0 {
                    detailRow("🍅", "番茄", "\(st.tomatoCount) 个")
                }
            } else {
                Text("这一天没有记录")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.22)))
    }

    private func detailRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Text("\(icon) \(title)")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
        }
    }

    // MARK: 番茄钟
    private var pomoCard: some View {
        PomodoroCard(engine: store.pomo)
    }

    private struct PomodoroCard: View {
        @ObservedObject var engine: PomodoroEngine

        private var phaseColor: Color {
            switch engine.state.phase {
            case .focus: return .gold
            case .shortBreak: return .mintC
            case .longBreak: return .skyC
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🍅 番茄钟")
                        .font(.system(size: 12.5, weight: .bold))
                    Spacer()
                    Text("今日已收 \(engine.state.todayTomatoes) 个 🍅")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(engine.timeText())
                                .font(.system(size: 27, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    LinearGradient(colors: [phaseColor, Color.white.opacity(0.85)],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                            Spacer()
                            Text(engine.state.running ? "\(engine.state.phase.title)进行中" : "暂停 · \(engine.state.phase.title)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(phaseColor)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(phaseColor.opacity(0.85))
                                    .frame(width: geo.size.width * CGFloat(engine.progress))
                            }
                        }
                        .frame(height: 4)
                        HStack(spacing: 6) {
                            ForEach(0..<4, id: \.self) { i in
                                Image(systemName: i < min(engine.state.cycleIndex, 4) ? "circle.fill" : "circle")
                                    .font(.system(size: 7))
                                    .foregroundColor(i < min(engine.state.cycleIndex, 4) ? phaseColor : Color.white.opacity(0.2))
                            }
                            if engine.state.phase == .longBreak {
                                Text("长休后开启新周期")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(action: { engine.startPause() }) {
                        Text(engine.state.running ? "暂停" : "开始")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(Color(hex: 0x1a1206))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(LinearGradient(colors: [phaseColor, .amberC],
                                                         startPoint: .leading, endPoint: .trailing))
                            )
                    }
                    .buttonStyle(.plain)
                    pomoSmallButton("跳过", action: { engine.skip() })
                    pomoSmallButton("重置", action: { engine.resetPhase() })
                }

                Text("25 分钟专注 · 5 分钟小憩 · 每 4 个 🍅 长休 15 分钟")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.22))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
        }

        private func pomoSmallButton(_ title: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 提醒设置
    private var settingsCard: some View {
        VStack(spacing: 8) {
            if store.notifStatus == .authorized {
                Label("系统通知已开启 · 到点弹横幅", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.mintC)
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: { store.requestNotifications() }) {
                    Text(store.notifStatus == .denied
                         ? "🔔 通知被拒绝 · 点此重试（或去系统设置 → 通知）"
                         : "🔔 开启系统通知")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(Color(hex: 0x1a1206))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(LinearGradient(colors: [.gold, .amberC],
                                                     startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(.plain)
            }

            ToggleRow(
                icon: "🚀",
                title: "开机自动启动",
                subtitle: "登录 macOS 后自动出现挂件",
                isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { v in
                        store.setSettings { $0.launchAtLogin = v }
                        LoginItemManager.setEnabled(v)
                    }
                )
            )
            ToggleRow(
                icon: "🧍",
                title: "每小时起身提醒",
                subtitle: "9:00–21:00 整点",
                isOn: Binding(
                    get: { store.settings.hourly },
                    set: { v in store.setSettings { $0.hourly = v } }
                )
            )
            ToggleRow(
                icon: "🗣️",
                title: "语音播报",
                subtitle: "到点念出任务（中文）",
                isOn: Binding(
                    get: { store.settings.speech },
                    set: { v in
                        store.setSettings { $0.speech = v }
                        if v { speakTest() }
                    }
                )
            )
            ToggleRow(
                icon: "🔊",
                title: "提示音",
                subtitle: "到点播放一声轻响",
                isOn: Binding(
                    get: { store.settings.sound },
                    set: { v in
                        store.setSettings { $0.sound = v }
                        if v { AppDelegate.playGlass() }
                    }
                )
            )
            ToggleRow(
                icon: "🕰️",
                title: "番茄钟滴答声",
                subtitle: "专注运行中每秒一声",
                isOn: Binding(
                    get: { store.settings.pomoTick },
                    set: { v in store.setSettings { $0.pomoTick = v } }
                )
            )
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    private func speakTest() {
        let zhVoice = NSSpeechSynthesizer.availableVoices.first { $0.rawValue.contains(".zh-") }
        if let zhVoice = zhVoice { speechSynth.setVoice(zhVoice) }
        speechSynth.startSpeaking("语音播报已开启")
    }

    // MARK: 开关行
    private struct ToggleRow: View {
        let icon: String
        let title: String
        let subtitle: String
        @Binding var isOn: Bool

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(icon) \(title)")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Capsule()
                        .fill(isOn ? Color.mintC : Color.white.opacity(0.14))
                        .frame(width: 34, height: 19)
                    Circle()
                        .fill(isOn ? Color(hex: 0x06231c) : Color.white)
                        .frame(width: 13, height: 13)
                        .offset(x: isOn ? 7.5 : -7.5)
                }
                .animation(.spring(response: 0.25), value: isOn)
            }
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
        }
    }

    // MARK: 4-7-8 呼吸
    private struct BreathCard: View {
        @State private var running = false
        @State private var finished = false
        @State private var round = 1
        @State private var scale: CGFloat = 1
        @State private var text = "4-7-8\n呼吸"

        var body: some View {
            VStack(spacing: 10) {
                Text("即时回血 · 累了慌了来三轮")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.secondary)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(colors: [Color.mintC, Color(hex: 0x1d7d68)],
                                           center: .topLeading, startRadius: 10, endRadius: 120)
                        )
                        .frame(width: 86, height: 86)
                        .shadow(color: Color.mintC.opacity(0.35), radius: 24)
                    Text(text)
                        .font(.system(size: 12, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(hex: 0x06231c))
                }
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 1), value: scale)

                Button(action: { running ? stop() : start() }) {
                    Text(buttonLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
        }

        private var buttonLabel: String {
            if running { return "停止" }
            return finished ? "再来一轮" : "开始呼吸"
        }

        private func stop() {
            running = false
            scale = 1
            text = "4-7-8\n呼吸"
        }

        private func start() {
            running = true
            finished = false
            round = 1
            cycle()
        }

        private func cycle() {
            guard running else { return }
            if round > 3 {
                running = false
                finished = true
                text = "完成 ✓"
                scale = 1
                return
            }
            text = "吸气 4s\n第\(round)轮"
            withAnimation(.easeInOut(duration: 4)) { scale = 1.32 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                guard running else { return }
                text = "屏息 7s"
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                    guard running else { return }
                    text = "呼气 8s"
                    withAnimation(.easeInOut(duration: 8)) { scale = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                        round += 1
                        cycle()
                    }
                }
            }
        }
    }

    private var breathCard: some View { BreathCard() }

    // MARK: 底部说明
    private var footer: some View {
        VStack(spacing: 3) {
            Text("每天 0 点自动重置 · 数据仅存本机")
            Text("点 ✕ 隐藏 · 从菜单栏 ⚡ 图标呼出 · 全部桌面空间置顶悬浮")
        }
        .font(.system(size: 9.5))
        .foregroundColor(Color.white.opacity(0.28))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: 应用内横幅
    @ViewBuilder
    private var bannerOverlay: some View {
        if let msg = store.banner {
            VStack(alignment: .leading, spacing: 4) {
                Text("⚡ 今日精力")
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(2)
                    .foregroundColor(.gold)
                Text(msg)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: 0x20283a))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.gold.opacity(0.5))
            )
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.banner)
        }
    }
}
