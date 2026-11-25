# BatteryMeter

A tiny macOS menu bar app that shows the battery level of your wireless peripherals: Bluetooth headphones and Logitech mice and keyboards.

## Features

- Battery level of connected Bluetooth devices (headphones, AirPods, Apple peripherals, …), with charging indicator.
- Battery level of Logitech devices behind a Lightspeed, Bolt or Unifying receiver, or connected directly, via HID++ 2.0.
- Keeps showing the last known level of devices that disconnect or fall asleep, dimmed, also across app and Mac restarts.
- Red when a device is at 20% or less and not charging.
- Refreshes every minute, on wake, and as soon as a Bluetooth device connects or disconnects.
- Optional launch at login.

## Requirements

- macOS 14 or later, Apple silicon.
- Xcode Command Line Tools (`xcode-select --install`).

## Build and install

```sh
./build.sh            # builds build/BatteryMeter.app
./build.sh --install  # also copies it to ~/Applications and launches it
```

The app is ad-hoc signed. On first launch macOS asks for Bluetooth permission, used to refresh when devices connect or disconnect.

## How it works

- **Bluetooth:** reads levels from `system_profiler SPBluetoothDataType`. For devices it has no level for (e.g. some Soundcore headphones), it falls back to the accessory power sources macOS keeps, the same ones System Settings and `pmset -g accps` show.
- **Logitech:** talks HID++ 2.0 over IOKit HID and reads the Unified Battery, Battery Status or Battery Voltage feature, whichever the device supports.

## Limitations

- The Bluetooth fallback uses a private IOKit function (`IOPSCopyPowerSourcesByType`), so a macOS update may break it.
- Only devices that report their battery to macOS, or Logitech devices speaking HID++ 2.0, are shown.

## License

[MIT](LICENSE)
