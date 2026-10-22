import Foundation

/// Reads battery levels of connected Bluetooth devices (headphones, AirPods, Apple
/// peripherals...) from `system_profiler`, which exposes the levels reported via HFP/AAP.
enum BluetoothBattery {
    static func read() -> [BatteryDevice] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = json["SPBluetoothDataType"] as? [[String: Any]],
            let connected = controllers.first?["device_connected"] as? [[String: Any]]
        else { return [] }

        var devices: [BatteryDevice] = []
        for entry in connected {
            for (name, value) in entry {
                guard let info = value as? [String: Any], let percent = level(info) else { continue }
                devices.append(BatteryDevice(
                    id: "bt-\(info["device_address"] as? String ?? name)",
                    name: name,
                    kind: kind(info["device_minorType"] as? String),
                    percent: percent,
                    charging: false))
            }
        }
        return devices
    }

    private static func level(_ info: [String: Any]) -> Int? {
        func pct(_ key: String) -> Int? {
            (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
        }
        if let main = pct("device_batteryLevelMain") ?? pct("device_batteryLevel") { return main }
        // AirPods-style devices report each earbud separately; show the lowest one.
        let buds = [pct("device_batteryLevelLeft"), pct("device_batteryLevelRight")].compactMap { $0 }
        return buds.min()
    }

    private static func kind(_ minorType: String?) -> DeviceKind {
        switch minorType?.lowercased() ?? "" {
        case let t where t.contains("head"): return .headphones
        case let t where t.contains("mouse") || t.contains("trackpad"): return .mouse
        case let t where t.contains("keyboard"): return .keyboard
        default: return .other
        }
    }
}
