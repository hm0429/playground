import Foundation
import CoreBluetooth

class BLECentralManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    
    // UUIDs from Peripheral
    private let serviceUUID = CBUUID(string: "98988A2A-64BE-45E1-8069-3F37EAF01611")
    private let characteristicUUID = CBUUID(string: "98988A2A-64BE-45E1-8069-3F37EAF01612")
    private let peripheralName = "PIYO_BLE_SERVER"
    
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var receivedValue: Int = 0
    @Published var statusText = "Not Connected"
    @Published var peripherals: [(peripheral: CBPeripheral, rssi: NSNumber)] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusText = "Bluetooth is not powered on"
            return
        }
        
        peripherals.removeAll()
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        isScanning = true
        statusText = "Scanning..."
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        statusText = "Scan stopped"
    }
    
    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        statusText = "Connecting..."
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func readValue() {
        guard let characteristic = characteristic else { return }
        peripheral?.readValue(for: characteristic)
    }
    
    func writeValue(_ value: Data) {
        guard let characteristic = characteristic else { return }
        peripheral?.writeValue(value, for: characteristic, type: .withResponse)
    }
}

extension BLECentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusText = "Bluetooth is powered on"
        case .poweredOff:
            statusText = "Bluetooth is powered off"
        case .resetting:
            statusText = "Bluetooth is resetting"
        case .unauthorized:
            statusText = "Bluetooth is unauthorized"
        case .unsupported:
            statusText = "Bluetooth is unsupported"
        case .unknown:
            statusText = "Bluetooth state is unknown"
        @unknown default:
            statusText = "Unknown Bluetooth state"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if we've already found this peripheral
        if !peripherals.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            peripherals.append((peripheral: peripheral, rssi: RSSI))
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusText = "Connected to \(peripheral.name ?? "Unknown")"
        stopScanning()
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusText = "Disconnected"
        self.peripheral = nil
        self.characteristic = nil
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        statusText = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
    }
}

extension BLECentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            statusText = "Error discovering services: \(error!.localizedDescription)"
            return
        }
        
        if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            statusText = "Error discovering characteristics: \(error!.localizedDescription)"
            return
        }
        
        if let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
            self.characteristic = characteristic
            
            // Subscribe to notifications
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            
            // Read initial value
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
            
            statusText = "Ready"
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            print("Error reading characteristic: \(error!.localizedDescription)")
            return
        }
        
        if let data = characteristic.value, !data.isEmpty {
            let value = Int8(bitPattern: data[0])
            receivedValue = Int(value)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if error == nil {
            if characteristic.isNotifying {
                statusText = "Notifications enabled"
            } else {
                statusText = "Notifications disabled"
            }
        }
    }
}
