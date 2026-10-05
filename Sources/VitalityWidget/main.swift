import AppKit

// 入口：附件模式运行（无 Dock 图标），悬浮面板 + 菜单栏由 AppDelegate 搭建
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
