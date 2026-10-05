# mac-work-health · 精力挂件

原生 macOS 桌面健康打卡挂件：一个始终悬浮在所有桌面空间之上的深色毛玻璃小窗，提醒你按昼夜节律工作、休息、运动，并记录每天的体重、血压、睡眠，自动生成近 7 天趋势。

纯 Swift / SwiftUI / AppKit，**不需要 Xcode**，用 Swift Package Manager 即可构建。

## 功能

- **置顶悬浮面板**：NSPanel `floating` 级别，跟随所有桌面空间（含全屏），点按不抢焦点，无 Dock 图标，菜单栏 ⚡ 图标控制显示/隐藏
- **每日精力清单**：11 项按时间排列的习惯（起床、晨光、咖啡窗口、专注、午睡、运动、断电、上床），勾选持久化，0 点自动重置
- **到点提醒**：系统通知（UNUserNotificationCenter，每日重复触发器，已完成自动移除）+ 中文语音播报（NSSpeechSynthesizer）+ Glass 提示音 + 面板内横幅
- **每小时起身提醒**（9:00–21:00，可关）
- **今日测量**：体重 / 血压（高压·低压）/ 睡眠时长三项输入，实时判定达标状态（血压分级、睡眠 7–9h 目标）
- **近 7 天趋势**：体重、血压双线、睡眠（带 7–9h 目标区间底色）折线图，每日快照归档，最多保留 90 天
- **番茄钟**：25 / 5 / 15（每 4 个 🍅 进长休），状态持久化，退出重开倒计时继续；应用关闭期间到点会静默推进计数
- **4-7-8 呼吸**：即时回血小工具

## 要求

- macOS 13+
- Swift 5.9+（Xcode Command Line Tools 即可：`xcode-select --install`）

## 构建

```bash
# 1. 编译
swift build -c release

# 2. 组装 .app
rm -rf VitalityWidget.app
mkdir -p VitalityWidget.app/Contents/MacOS
cp .build/release/VitalityWidget VitalityWidget.app/Contents/MacOS/
cp Info.plist VitalityWidget.app/Contents/Info.plist

# 3. 签名并放入应用程序目录
codesign --force --sign - VitalityWidget.app
cp -R VitalityWidget.app /Applications/

# 4. 启动（首次会请求通知授权）
open /Applications/VitalityWidget.app
```

## 使用

- 挂件默认停靠在主屏右侧，可拖动到任意位置
- 首次启动点击「开启系统通知」，之后到点提醒走系统横幅，窗口被遮挡也能收到
- 点 ✕ 只是隐藏面板（从菜单栏 ⚡ 图标重新呼出），退出请走菜单栏 → 退出精力挂件
- 所有数据仅保存在本机（UserDefaults），清单与测量数据每天 0 点自动重置，历史趋势独立归档

## 结构

```
Sources/VitalityWidget/
├── main.swift         # 入口（附件模式，无 Dock 图标）
├── Models.swift       # 任务/测量/历史/番茄钟引擎 + 状态存储
├── AppDelegate.swift  # 悬浮面板、菜单栏、系统通知、提醒调度
└── ContentView.swift  # SwiftUI 界面（清单/测量/趋势/番茄钟/呼吸）
```
