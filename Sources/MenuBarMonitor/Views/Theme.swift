import SwiftUI

enum Palette {
    static let cpu = Color(hex: 0x7F77DD)
    static let memory = Color(hex: 0x1D9E75)
    static let download = Color(hex: 0xD85A30)
    static let upload = Color(hex: 0x888780)
    static let warning = Color(hex: 0xEF9F27)
    static let critical = Color(hex: 0xE24B4A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Warning colours shared by the menu bar label and the dropdown.
@MainActor
struct Severity {
    let store: MetricsStore
    let settings: AppSettings

    var cpuIsHot: Bool {
        settings.colorWarnings && store.cpu.total > MetricsStore.cpuHotThreshold
    }
    var cpuColor: Color { cpuIsHot ? Palette.critical : Palette.cpu }

    var memoryWarningColor: Color? {
        guard settings.colorWarnings else { return nil }
        switch store.memory.pressure {
        case .normal: return nil
        case .warning: return Palette.warning
        case .critical: return Palette.critical
        }
    }
    var memoryColor: Color { memoryWarningColor ?? Palette.memory }
}
