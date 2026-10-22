import Foundation
import IOKit.hid

/// Talks Logitech HID++ 2.0 to receivers (Lightspeed, Bolt, Unifying) and to
/// directly-connected Logitech devices to read their battery level.
final class LogitechBattery {
    private static let vendorID = 0x046d
    private static let longReport: UInt8 = 0x11
    private static let softwareID: UInt8 = 0x0a
    private static let timeout: CFTimeInterval = 0.5

    private enum Feature: UInt16 {
        case root = 0x0000
        case deviceName = 0x0005
        case batteryStatus = 0x1000
        case batteryVoltage = 0x1001
        case unifiedBattery = 0x1004
    }

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

    private func readBattery(_ hid: IOHIDDevice, index: UInt8) -> (percent: Int, charging: Bool)? {
        if let f = featureIndex(hid, index: index, feature: .unifiedBattery),
           let r = request(hid, index: index, feature: f, function: 1) {
            // [state of charge %, level flags, charging status, external power]
            let charging = (1...3).contains(r[2])
            if r[0] > 0 { return (Int(r[0]), charging) }
            // Devices without a percentage only report a coarse level.
            let coarse: Int = r[1] & 8 != 0 ? 100 : r[1] & 4 != 0 ? 50 : r[1] & 2 != 0 ? 20 : 5
            return (coarse, charging)
        }
        if let f = featureIndex(hid, index: index, feature: .batteryStatus),
           let r = request(hid, index: index, feature: f, function: 0) {
            // [level %, next level %, status]
            return (Int(r[0]), (1...4).contains(r[2]))
        }
        if let f = featureIndex(hid, index: index, feature: .batteryVoltage),
           let r = request(hid, index: index, feature: f, function: 0) {
            let millivolts = Int(r[0]) << 8 | Int(r[1])
            return (Self.percent(fromMillivolts: millivolts), r[2] & 0x80 != 0)
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
        let name = String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    private func readKind(_ hid: IOHIDDevice, index: UInt8) -> DeviceKind {
        guard let f = featureIndex(hid, index: index, feature: .deviceName),
              let r = request(hid, index: index, feature: f, function: 2)
        else { return .mouse }
        switch r[0] {
        case 0, 2: return .keyboard
        case 3, 4, 5: return .mouse
        case 8: return .headphones
        default: return .other
        }
    }

    private func featureIndex(_ hid: IOHIDDevice, index: UInt8, feature: Feature) -> UInt8? {
        let id = feature.rawValue
        guard let r = request(hid, index: index, feature: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xff)]),
              r[0] != 0 else { return nil }
        return r[0]
    }

    /// Sends a HID++ 2.0 long request and returns the 16 parameter bytes of the reply.
    private func request(_ hid: IOHIDDevice, index: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8]? {
        var report = [UInt8](repeating: 0, count: 20)
        report[0] = Self.longReport
        report[1] = index
        report[2] = feature
        report[3] = function << 4 | Self.softwareID
        for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }

        pending = (index, feature, report[3])
        response = nil
        guard IOHIDDeviceSetReport(hid, kIOHIDReportTypeOutput, CFIndex(Self.longReport), report, report.count) == kIOReturnSuccess
        else { return nil }

        let deadline = Date().addingTimeInterval(Self.timeout)
        while response == nil, Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        }
        pending = nil
        guard let r = response, r.count >= 20, r[2] != 0xff, r[2] != 0x8f else { return nil }
        return Array(r[4..<20])
    }

    private var pending: (index: UInt8, feature: UInt8, function: UInt8)?

    private func handle(_ report: [UInt8]) {
        guard let p = pending, report.count >= 5, report[1] == p.index else { return }
        let isReply = report[2] == p.feature && report[3] == p.function
        // Errors: HID++ 2.0 (0xff) or HID++ 1.0 (0x8f, e.g. no device paired at this index).
        let isError = (report[2] == 0xff || report[2] == 0x8f) && report[3] == p.feature && report[4] == p.function
        if isReply || isError { response = report.count >= 20 ? report : report + [UInt8](repeating: 0, count: 20 - report.count) }
    }

    /// Rough LiPo discharge curve used by devices that only report voltage.
    private static func percent(fromMillivolts mv: Int) -> Int {
        let curve: [(Int, Int)] = [(4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60),
                                   (3811, 50), (3778, 40), (3751, 30), (3717, 20), (3676, 10), (3500, 0)]
        guard mv < curve[0].0 else { return 100 }
        for i in 1..<curve.count where mv >= curve[i].0 {
            let (hiV, hiP) = curve[i - 1], (loV, loP) = curve[i]
            return loP + (mv - loV) * (hiP - loP) / (hiV - loV)
        }
        return 0
    }
}
