import Foundation
import IOKit.ps

/// Reads battery levels of connected Bluetooth devices (headphones, AirPods, Apple
/// peripherals...) from `system_profiler`, which exposes the levels reported via HFP/AAP.
/// Devices it has no level for (e.g. Soundcore headphones) fall back to the accessory
/// power sources macOS keeps, the ones System Settings and `pmset -g accps` show.
enum BluetoothBattery {
    /// `connectedIDs` also includes connected devices that aren't reporting a level right
    /// now (some headphones, e.g. Soundcore, only report it intermittently).
    static func read() -> (devices: [BatteryDevice], connectedIDs: Set<String>) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return ([], []) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let controllers = json["SPBluetoothDataType"] as? [[String: Any]],
            let connected = controllers.first?["device_connected"] as? [[String: Any]]
        else { return ([], []) }

        let accessories = accessoryLevels()
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
    /// `IOPSCopyPowerSourcesByType` is private; the public `IOPSCopyPowerSourcesInfo`
    /// only lists the Mac's own battery.
    private static func accessoryLevels() -> [String: (percent: Int, charging: Bool)] {
        typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType"),
              let info = unsafeBitCast(symbol, to: CopyByType.self)(0)?.takeRetainedValue()
        else { return [:] }

        var levels: [String: (percent: Int, charging: Bool)] = [:]
        for source in IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray as [CFTypeRef] {
            guard
                let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                desc[kIOPSTransportTypeKey] as? String == "Bluetooth",
                let name = desc[kIOPSNameKey] as? String,
                let percent = desc[kIOPSCurrentCapacityKey] as? Int
            else { continue }
            levels[name] = (percent, desc[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return levels
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
