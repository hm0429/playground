# BLE Central Example iOS App

This is a simple iOS app that acts as a BLE Central device and connects to the BLE Peripheral example in the `../Peripheral` directory.

## Features

- Scans for BLE peripherals with the specific service UUID
- Connects to the "PIYO_BLE_SERVER" peripheral
- Displays the counter value received via notifications
- Allows reading the current counter value
- Allows sending data to the peripheral

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Physical iOS device (BLE doesn't work on the simulator)

## Setup

1. Open `BLECentralExample.xcodeproj` in Xcode
2. Select your development team in the project settings
3. Connect your iOS device
4. Build and run the app on your device

## Usage

1. First, make sure the Peripheral is running:
   ```bash
   cd ../Peripheral
   npm install
   sudo node index.js
   ```

2. Run the iOS app on your device

3. Tap "Start Scan" to search for BLE peripherals

4. When "PIYO_BLE_SERVER" appears in the list, tap "Connect"

5. Once connected, you will see:
   - The counter value updating every second via notifications
   - "Read Value" button to manually read the current counter
   - Text field and "Send" button to write data to the peripheral

## BLE Service Details

- **Service UUID**: `98988A2A-64BE-45E1-8069-3F37EAF01611`
- **Characteristic UUID**: `98988A2A-64BE-45E1-8069-3F37EAF01612`
- **Properties**: Read, Write, Notify

## Project Structure

- `BLECentralExampleApp.swift` - App entry point
- `ContentView.swift` - Main UI using SwiftUI
- `BLECentralManager.swift` - BLE Central logic using CoreBluetooth
- `Info.plist` - App configuration including Bluetooth permissions

## Permissions

The app requires Bluetooth permission. The following keys are configured in Info.plist:
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`
