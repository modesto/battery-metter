import Foundation
import IOKit.ps

public enum BluetoothParsing {
    /// `connectedIDs` also includes connected devices that aren't reporting a level right
    /// now (some headphones, e.g. Soundcore, only report it intermittently).
    public static func devices(
        fromProfilerJSON data: Data,
        accessories: () -> [String: BatteryReading]
    ) -> (devices: [BatteryDevice], connectedIDs: Set<String>) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = json["SPBluetoothDataType"] as? [[String: Any]],
            let connected = controllers.first?["device_connected"] as? [[String: Any]]
        else { return ([], []) }

        let accessories = accessories()
        var devices: [BatteryDevice] = []
        var connectedIDs: Set<String> = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let id = "bt-\(info["device_address"] as? String ?? name)"
                connectedIDs.insert(id)
                let accessory = accessories[name]
                guard let percent = level(info) ?? accessory?.percent else { continue }
                devices.append(BatteryDevice(
                    id: id,
                    name: name,
                    kind: kind(info["device_minorType"] as? String),
                    percent: percent,
                    charging: accessory?.charging ?? false))
            }
        }
        return (devices, connectedIDs)
    }

    /// Bluetooth accessory power sources, keyed by name (they carry no device address).
    public static func accessoryLevels(_ descriptions: [[String: Any]]) -> [String: BatteryReading] {
        var levels: [String: BatteryReading] = [:]
        for desc in descriptions {
            guard
                (desc[kIOPSTransportTypeKey] as? String)?.hasPrefix("Bluetooth") == true,
                let name = desc[kIOPSNameKey] as? String,
                let percent = desc[kIOPSCurrentCapacityKey] as? Int
            else { continue }
            levels[name] = BatteryReading(percent: percent, charging: desc[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return levels
    }

    static func level(_ info: [String: Any]) -> Int? {
        func pct(_ key: String) -> Int? {
            (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
        }
        if let main = pct("device_batteryLevelMain") ?? pct("device_batteryLevel") { return main }
        // AirPods-style devices report each earbud separately; show the lowest one.
        let buds = [pct("device_batteryLevelLeft"), pct("device_batteryLevelRight")].compactMap { $0 }
        return buds.min()
    }

    static func kind(_ minorType: String?) -> DeviceKind {
        switch minorType?.lowercased() ?? "" {
        case let t where t.contains("head"): return .headphones
        case let t where t.contains("mouse") || t.contains("trackpad"): return .mouse
        case let t where t.contains("keyboard"): return .keyboard
        default: return .other
        }
    }
}
