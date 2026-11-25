import BatteryMeterCore
import Foundation
import IOKit.hid

/// Talks Logitech HID++ 2.0 to receivers (Lightspeed, Bolt, Unifying) and to
/// directly-connected Logitech devices to read their battery level.
final class LogitechBattery {
    private static let vendorID = 0x046d
    /// A sleeping mouse can take over a second to answer the first request after waking.
    private static let timeout: CFTimeInterval = 2

    private var response: [UInt8]?
    private var inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    deinit { inputBuffer.deallocate() }

    /// Must be called from a thread whose run loop can be spun (not the main thread).
    func read() -> [BatteryDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [0xFF00, 0xFF43].map {
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDPrimaryUsagePageKey: $0] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return [] }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let hidDevices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        var result: [BatteryDevice] = []
        for hid in hidDevices {
            // Only the interface that accepts 20-byte long reports speaks HID++ 2.0.
            let maxInput = IOHIDDeviceGetProperty(hid, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
            guard maxInput >= 20 else { continue }
            let product = IOHIDDeviceGetProperty(hid, kIOHIDProductKey as CFString) as? String ?? ""
            let isReceiver = product.localizedCaseInsensitiveContains("receiver")

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(hid, inputBuffer, 64, { context, _, _, _, _, report, length in
                guard let context else { return }
                let me = Unmanaged<LogitechBattery>.fromOpaque(context).takeUnretainedValue()
                me.handle(Array(UnsafeBufferPointer(start: report, count: length)))
            }, context)
            IOHIDDeviceScheduleWithRunLoop(hid, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

            let indexes: [UInt8] = isReceiver ? Array(1...6) : [0xff]
            for index in indexes {
                if let device = readDevice(hid, index: index, fallbackName: product) {
                    result.append(device)
                }
            }

            IOHIDDeviceUnscheduleFromRunLoop(hid, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(hid, inputBuffer, 64, nil, nil)
        }
        return result
    }

    private func readDevice(_ hid: IOHIDDevice, index: UInt8, fallbackName: String) -> BatteryDevice? {
        guard let battery = readBattery(hid, index: index) else { return nil }
        let name = readName(hid, index: index) ?? fallbackName
        return BatteryDevice(
            id: "logi-\(name)",
            name: name,
            kind: readKind(hid, index: index),
            percent: battery.percent,
            charging: battery.charging)
    }

    private func readBattery(_ hid: IOHIDDevice, index: UInt8) -> BatteryReading? {
        if let f = featureIndex(hid, index: index, feature: .unifiedBattery),
           let r = request(hid, index: index, feature: f, function: 1) {
            return HIDPP.unifiedBattery(r)
        }
        if let f = featureIndex(hid, index: index, feature: .batteryStatus),
           let r = request(hid, index: index, feature: f, function: 0) {
            return HIDPP.batteryStatus(r)
        }
        if let f = featureIndex(hid, index: index, feature: .batteryVoltage),
           let r = request(hid, index: index, feature: f, function: 0) {
            return HIDPP.batteryVoltage(r)
        }
        return nil
    }

    private func readName(_ hid: IOHIDDevice, index: UInt8) -> String? {
        guard let f = featureIndex(hid, index: index, feature: .deviceName),
              let count = request(hid, index: index, feature: f, function: 0)?[0], count > 0
        else { return nil }
        var bytes: [UInt8] = []
        while bytes.count < Int(count) {
            guard let chunk = request(hid, index: index, feature: f, function: 1, params: [UInt8(bytes.count)]) else { break }
            bytes += chunk.prefix(Int(count) - bytes.count)
        }
        return HIDPP.name(bytes)
    }

    private func readKind(_ hid: IOHIDDevice, index: UInt8) -> DeviceKind {
        guard let f = featureIndex(hid, index: index, feature: .deviceName),
              let r = request(hid, index: index, feature: f, function: 2)
        else { return .mouse }
        return HIDPP.kind(deviceType: r[0])
    }

    private func featureIndex(_ hid: IOHIDDevice, index: UInt8, feature: HIDPP.Feature) -> UInt8? {
        let id = feature.rawValue
        guard let r = request(hid, index: index, feature: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xff)]),
              r[0] != 0 else { return nil }
        return r[0]
    }

    /// Sends a HID++ 2.0 long request and returns the 16 parameter bytes of the reply.
    private func request(_ hid: IOHIDDevice, index: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8]? {
        softwareID = HIDPP.nextSoftwareID(after: softwareID)
        let (report, pending) = HIDPP.request(
            index: index, feature: feature, function: function, softwareID: softwareID, params: params)
        self.pending = pending
        response = nil
        guard IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, CFIndex(HIDPP.longReport), report, report.count) == kIOReturnSuccess
        else { return nil }

        let deadline = Date().addingTimeInterval(Self.timeout)
        while response == nil, Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        self.pending = nil
        return response.flatMap(HIDPP.parameters)
    }

    private var pending: HIDPP.Pending?
    private var softwareID: UInt8 = 0

    private func handle(_ report: [UInt8]) {
        guard let pending, let reply = HIDPP.reply(report, to: pending) else { return }
        response = reply
    }
}
