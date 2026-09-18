import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    static var statusLabel: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "已开启"
        case .notRegistered: return "未开启"
        case .notFound: return "不可用"
        case .requiresApproval: return "需在系统设置中批准"
        @unknown default: return "未知"
        }
    }
}
