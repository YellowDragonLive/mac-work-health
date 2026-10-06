import Foundation
import AppKit
import ServiceManagement

// MARK: - 开机自启动管理
// 真实注册走 SMAppService（系统设置可见、无权限弹窗）；
// 失败时降级为 System Events 登录项（需一次自动化授权，且先去重防重复启动）。
enum LoginItemManager {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                return true
            } catch {
                // 注册失败（如临时签名限制），降级走传统登录项
            }
        }
        return setEnabledLegacy(on)
    }

    private static func setEnabledLegacy(_ on: Bool) -> Bool {
        let path = Bundle.main.bundlePath
        var err: NSDictionary?

        // 无论开关，先清掉同名旧登录项，防止重复
        NSAppleScript(
            source: "tell application \"System Events\" to delete login item \"VitalityWidget\""
        )?.executeAndReturnError(&err)

        if on {
            NSAppleScript(
                source: "tell application \"System Events\" to make login item at end with properties {path:\"\(path)\", hidden:false}"
            )?.executeAndReturnError(&err)
        }
        return err == nil
    }
}
