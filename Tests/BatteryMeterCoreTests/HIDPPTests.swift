import Testing
@testable import BatteryMeterCore

struct HIDPPTests {
    private func params(_ bytes: UInt8...) -> [UInt8] {
        bytes + [UInt8](repeating: 0, count: 16 - bytes.count)
    }

    @Test func rotatesSoftwareIDSkippingZero() {
        #expect(HIDPP.nextSoftwareID(after: 0) == 1)
        #expect(HIDPP.nextSoftwareID(after: 14) == 15)
        #expect(HIDPP.nextSoftwareID(after: 15) == 1)
    }

    @Test func buildsLongRequest() {
        let (report, pending) = HIDPP.request(index: 2, feature: 0x05, function: 1, softwareID: 3, params: [0x10, 0x04])

        #expect(report.count == 20)
        #expect(Array(report.prefix(6)) == [0x11, 2, 0x05, 0x13, 0x10, 0x04])
        #expect(pending == HIDPP.Pending(index: 2, feature: 0x05, function: 0x13))
    }

    @Test func acceptsMatchingReplyAndPadsIt() {
        let pending = HIDPP.Pending(index: 1, feature: 0x05, function: 0x13)

        let reply = HIDPP.reply([0x11, 1, 0x05, 0x13, 42], to: pending)

        #expect(reply?.count == 20)
        #expect(reply.flatMap(HIDPP.parameters)?.first == 42)
    }

    @Test func rejectsLateReplyToPreviousRequest() {
        let pending = HIDPP.Pending(index: 1, feature: 0x05, function: 0x14)

        #expect(HIDPP.reply([0x11, 1, 0x05, 0x13, 42], to: pending) == nil)
    }

    @Test func rejectsReplyFromAnotherDeviceIndex() {
        let pending = HIDPP.Pending(index: 1, feature: 0x05, function: 0x13)

        #expect(HIDPP.reply([0x11, 2, 0x05, 0x13, 42], to: pending) == nil)
    }

    @Test(arguments: [UInt8(0xff), 0x8f])
    func treatsErrorReplyAsAnsweredWithoutParameters(errorCode: UInt8) {
        let pending = HIDPP.Pending(index: 3, feature: 0x05, function: 0x13)

        let reply = HIDPP.reply([0x10, 3, errorCode, 0x05, 0x13, 0x09, 0], to: pending)

        #expect(reply != nil)
        #expect(reply.flatMap(HIDPP.parameters) == nil)
    }

    @Test func readsUnifiedBatteryPercentage() {
        #expect(HIDPP.unifiedBattery(params(36, 0, 0)) == BatteryReading(percent: 36, charging: false))
        #expect(HIDPP.unifiedBattery(params(80, 0, 1)) == BatteryReading(percent: 80, charging: true))
    }

    @Test(arguments: [(UInt8(8), 100), (4, 50), (2, 20), (1, 5)])
    func readsUnifiedBatteryCoarseLevel(flags: UInt8, percent: Int) {
        #expect(HIDPP.unifiedBattery(params(0, flags, 0))?.percent == percent)
    }

    @Test func readsBatteryStatus() {
        #expect(HIDPP.batteryStatus(params(50, 30, 0)) == BatteryReading(percent: 50, charging: false))
        #expect(HIDPP.batteryStatus(params(50, 30, 1)) == BatteryReading(percent: 50, charging: true))
    }

    @Test func readsBatteryVoltage() {
        #expect(HIDPP.batteryVoltage(params(0x0F, 0x50, 0x80)) == BatteryReading(percent: 69, charging: true))
    }

    @Test func rejectsTooShortBatteryParameters() {
        #expect(HIDPP.unifiedBattery([36, 0]) == nil)
        #expect(HIDPP.batteryStatus([50]) == nil)
        #expect(HIDPP.batteryVoltage([]) == nil)
    }

    @Test(arguments: [(4300, 100), (4186, 100), (3811, 50), (3900, 66), (3500, 0), (3000, 0)])
    func convertsMillivoltsToPercent(millivolts: Int, percent: Int) {
        #expect(HIDPP.percent(fromMillivolts: millivolts) == percent)
    }

    @Test(arguments: [(UInt8(0), DeviceKind.keyboard), (2, .keyboard), (3, .mouse), (5, .mouse), (8, .headphones), (7, .other)])
    func mapsDeviceTypeToKind(deviceType: UInt8, kind: DeviceKind) {
        #expect(HIDPP.kind(deviceType: deviceType) == kind)
    }

    @Test func decodesNameDroppingPadding() {
        #expect(HIDPP.name(Array("PRO X 2".utf8) + [0, 0]) == "PRO X 2")
        #expect(HIDPP.name([0, 0]) == nil)
    }
}
