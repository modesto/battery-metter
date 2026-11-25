import Foundation

public enum DeviceKind: String, Codable, Sendable {
    case headphones, mouse, keyboard, other

    public var symbolName: String {
        switch self {
        case .headphones: return "headphones"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

public struct BatteryDevice: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: DeviceKind
    public let percent: Int
    public let charging: Bool

    public init(id: String, name: String, kind: DeviceKind, percent: Int, charging: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.percent = percent
        self.charging = charging
    }
}

public struct BatteryReading: Equatable, Sendable {
    public let percent: Int
    public let charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }
}
