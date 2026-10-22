import Foundation

enum DeviceKind {
    case headphones, mouse, keyboard, other

    var symbolName: String {
        switch self {
        case .headphones: return "headphones"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

struct BatteryDevice {
    let id: String
    let name: String
    let kind: DeviceKind
    let percent: Int
    let charging: Bool
}
