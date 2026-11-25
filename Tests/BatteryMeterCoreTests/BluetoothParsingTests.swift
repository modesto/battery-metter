import Foundation
import Testing
@testable import BatteryMeterCore

struct BluetoothParsingTests {
    private func profilerJSON(_ devices: [String: [String: String]]) -> Data {
        let connected = devices.map { [$0.key: $0.value] }
        let json: [String: Any] = ["SPBluetoothDataType": [["device_connected": connected]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func readsMainBatteryLevel() {
        let data = profilerJSON(["Keyboard": [
            "device_address": "AA:BB", "device_minorType": "Keyboard", "device_batteryLevelMain": "80%",
        ]])

        let result = BluetoothParsing.devices(fromProfilerJSON: data, accessories: { [:] })

        #expect(result.devices == [BatteryDevice(id: "bt-AA:BB", name: "Keyboard", kind: .keyboard, percent: 80, charging: false)])
        #expect(result.connectedIDs == ["bt-AA:BB"])
    }

    @Test func showsLowestEarbudWhenOnlyBudsReport() {
        #expect(BluetoothParsing.level(["device_batteryLevelLeft": "60%", "device_batteryLevelRight": "40%"]) == 40)
    }

    @Test func prefersMainLevelOverEarbuds() {
        #expect(BluetoothParsing.level(["device_batteryLevelMain": "90%", "device_batteryLevelLeft": "10%"]) == 90)
    }

    @Test func fallsBackToAccessoryLevelMatchedByName() {
        let data = profilerJSON(["soundcore Space One": ["device_address": "7C:E9", "device_minorType": "Headset"]])
        let accessories = ["soundcore Space One": BatteryReading(percent: 70, charging: true)]

        let result = BluetoothParsing.devices(fromProfilerJSON: data, accessories: { accessories })

        #expect(result.devices == [BatteryDevice(
            id: "bt-7C:E9", name: "soundcore Space One", kind: .headphones, percent: 70, charging: true)])
    }

    @Test func keepsConnectedDevicesWithoutLevelAsConnected() {
        let data = profilerJSON(["Headphones": ["device_address": "11:22", "device_minorType": "Headphones"]])

        let result = BluetoothParsing.devices(fromProfilerJSON: data, accessories: { [:] })

        #expect(result.devices.isEmpty)
        #expect(result.connectedIDs == ["bt-11:22"])
    }

    @Test func usesNameAsIDWhenAddressIsMissing() {
        let data = profilerJSON(["Mouse": ["device_batteryLevelMain": "50%"]])

        #expect(BluetoothParsing.devices(fromProfilerJSON: data, accessories: { [:] }).connectedIDs == ["bt-Mouse"])
    }

    @Test func returnsNothingForInvalidJSONWithoutReadingAccessories() {
        var readAccessories = false

        let result = BluetoothParsing.devices(fromProfilerJSON: Data("nope".utf8)) {
            readAccessories = true
            return [:]
        }

        #expect(result.devices.isEmpty)
        #expect(result.connectedIDs.isEmpty)
        #expect(!readAccessories)
    }

    @Test(arguments: [
        ("Headset", DeviceKind.headphones),
        ("Headphones", .headphones),
        ("Mouse", .mouse),
        ("Trackpad", .mouse),
        ("Keyboard", .keyboard),
        ("Speaker", .other),
    ])
    func mapsMinorTypeToKind(minorType: String, kind: DeviceKind) {
        #expect(BluetoothParsing.kind(minorType) == kind)
    }

    @Test func mapsMissingMinorTypeToOther() {
        #expect(BluetoothParsing.kind(nil) == .other)
    }

    @Test(arguments: ["Bluetooth", "Bluetooth LE"])
    func acceptsBluetoothAccessoryPowerSources(transport: String) {
        let levels = BluetoothParsing.accessoryLevels([[
            "Transport Type": transport, "Name": "soundcore Space One", "Current Capacity": 70, "Is Charging": false,
        ]])

        #expect(levels == ["soundcore Space One": BatteryReading(percent: 70, charging: false)])
    }

    @Test func ignoresNonBluetoothPowerSources() {
        let levels = BluetoothParsing.accessoryLevels([[
            "Transport Type": "Internal", "Name": "InternalBattery-0", "Current Capacity": 100,
        ]])

        #expect(levels.isEmpty)
    }
}
