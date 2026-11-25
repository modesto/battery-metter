import Foundation

public enum HIDPP {
    public static let longReport: UInt8 = 0x11
    public static let reportLength = 20

    public enum Feature: UInt16, Sendable {
        case root = 0x0000
        case deviceName = 0x0005
        case batteryStatus = 0x1000
        case batteryVoltage = 0x1001
        case unifiedBattery = 0x1004
    }

    public struct Pending: Equatable, Sendable {
        public let index: UInt8
        public let feature: UInt8
        public let function: UInt8
    }

    // Rotate the software ID (1...15; 0 is reserved for notifications) so a late reply
    // to a timed-out request is never mistaken for the reply to the next one.
    public static func nextSoftwareID(after id: UInt8) -> UInt8 {
        id % 15 + 1
    }

    public static func request(
        index: UInt8, feature: UInt8, function: UInt8, softwareID: UInt8, params: [UInt8] = []
    ) -> (report: [UInt8], pending: Pending) {
        var report = [UInt8](repeating: 0, count: reportLength)
        report[0] = longReport
        report[1] = index
        report[2] = feature
        report[3] = function << 4 | softwareID
        for (i, p) in params.prefix(16).enumerated() { report[4 + i] = p }
        return (report, Pending(index: index, feature: feature, function: report[3]))
    }

    public static func reply(_ report: [UInt8], to pending: Pending) -> [UInt8]? {
        guard report.count >= 5, report[1] == pending.index else { return nil }
        let isReply = report[2] == pending.feature && report[3] == pending.function
        // Errors: HID++ 2.0 (0xff) or HID++ 1.0 (0x8f, e.g. no device paired at this index).
        let isError = (report[2] == 0xff || report[2] == 0x8f) && report[3] == pending.feature && report[4] == pending.function
        guard isReply || isError else { return nil }
        return report.count >= reportLength ? report : report + [UInt8](repeating: 0, count: reportLength - report.count)
    }

    public static func parameters(_ reply: [UInt8]) -> [UInt8]? {
        guard reply.count >= reportLength, reply[2] != 0xff, reply[2] != 0x8f else { return nil }
        return Array(reply[4..<reportLength])
    }

    /// [state of charge %, level flags, charging status, external power]
    public static func unifiedBattery(_ r: [UInt8]) -> BatteryReading? {
        guard r.count >= 3 else { return nil }
        let charging = (1...3).contains(r[2])
        if r[0] > 0 { return BatteryReading(percent: Int(r[0]), charging: charging) }
        // Devices without a percentage only report a coarse level.
        let coarse: Int = r[1] & 8 != 0 ? 100 : r[1] & 4 != 0 ? 50 : r[1] & 2 != 0 ? 20 : 5
        return BatteryReading(percent: coarse, charging: charging)
    }

    /// [level %, next level %, status]
    public static func batteryStatus(_ r: [UInt8]) -> BatteryReading? {
        guard r.count >= 3 else { return nil }
        return BatteryReading(percent: Int(r[0]), charging: (1...4).contains(r[2]))
    }

    public static func batteryVoltage(_ r: [UInt8]) -> BatteryReading? {
        guard r.count >= 3 else { return nil }
        let millivolts = Int(r[0]) << 8 | Int(r[1])
        return BatteryReading(percent: percent(fromMillivolts: millivolts), charging: r[2] & 0x80 != 0)
    }

    public static func kind(deviceType: UInt8) -> DeviceKind {
        switch deviceType {
        case 0, 2: return .keyboard
        case 3, 4, 5: return .mouse
        case 8: return .headphones
        default: return .other
        }
    }

    public static func name(_ bytes: [UInt8]) -> String? {
        let name = String(decoding: bytes.filter { $0 != 0 }, as: UTF8.self)
        return name.isEmpty ? nil : name
    }

    /// Rough LiPo discharge curve used by devices that only report voltage.
    public static func percent(fromMillivolts mv: Int) -> Int {
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
