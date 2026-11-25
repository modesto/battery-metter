import BatteryMeterCore
import Foundation
import IOKit.ps

/// Reads battery levels of connected Bluetooth devices (headphones, AirPods, Apple
/// peripherals...) from `system_profiler`, which exposes the levels reported via HFP/AAP.
/// Devices it has no level for (e.g. Soundcore headphones) fall back to the accessory
/// power sources macOS keeps, the ones System Settings and `pmset -g accps` show.
enum BluetoothBattery {
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

        return BluetoothParsing.devices(fromProfilerJSON: data) {
            BluetoothParsing.accessoryLevels(powerSourceDescriptions())
        }
    }

    /// `IOPSCopyPowerSourcesByType` is private; the public `IOPSCopyPowerSourcesInfo`
    /// only lists the Mac's own battery.
    private static func powerSourceDescriptions() -> [[String: Any]] {
        typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType"),
              let info = unsafeBitCast(symbol, to: CopyByType.self)(0)?.takeRetainedValue()
        else { return [] }

        return (IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray as [CFTypeRef]).compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
    }
}
