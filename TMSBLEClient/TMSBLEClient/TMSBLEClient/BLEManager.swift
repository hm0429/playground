import Foundation
import CoreBluetooth
import Combine

// Transfer status
struct ActiveTransfer {
    let fileId: UInt32
    let fileSize: UInt32
    let totalChunks: UInt16
    var receivedChunks: Int = 0
    var data: Data = Data()
}

class BLEManager: NSObject, ObservableObject {
    // BLE UUIDs
    private let serviceUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D0")
    private let controlUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D1")
    private let statusUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D2")
    private let dataTransferUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D3")
    
    // Command codes
    private let START_TRANSFER_AUDIO_FILE: UInt8 = 0x01
    private let START_TRANSFER_AUDIO_FILE_AUTO: UInt8 = 0x02
    private let STOP_TRANSFER_AUDIO_FILE_AUTO: UInt8 = 0x03
    private let COMPLETE_TRANSFER_AUDIO_FILE: UInt8 = 0x04
    
    // Status codes
    private let FILE_ADDED: UInt8 = 0x10
    private let FILE_DELETED: UInt8 = 0x11
    
    // Transfer flags
    private let BEGIN_TRANSFER_AUDIO_FILE: UInt8 = 0x20
    private let CONTINUE_TRANSFER_AUDIO_FILE: UInt8 = 0x21
    private let END_TRANSFER_AUDIO_FILE: UInt8 = 0x22
    
    // BLE properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var dataTransferCharacteristic: CBCharacteristic?
    
    // Published properties
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var isAutoTransferEnabled = false
    @Published var audioFiles: [AudioFile] = []
    @Published var activeTransfer: ActiveTransfer?
    @Published var connectionError: String?
    @Published var availableFiles: [UInt32] = []
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadSavedFiles()
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionError = "Bluetooth is not available"
            return
        }
        
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        
        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.isScanning == true {
                self?.stopScanning()
                self?.connectionError = "No TMS BLE Server found"
            }
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func toggleAutoTransfer() {
        guard let characteristic = controlCharacteristic else { return }
        
        let command = isAutoTransferEnabled ? STOP_TRANSFER_AUDIO_FILE_AUTO : START_TRANSFER_AUDIO_FILE_AUTO
        let packet = createPacket(type: command, id: 0, seq: 0, payload: nil)
        
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        isAutoTransferEnabled.toggle()
    }
    
    func requestFileTransfer(fileId: UInt32) {
        guard let characteristic = controlCharacteristic else { return }
        
        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: fileId.bigEndian) { Array($0) })
        
        let packet = createPacket(type: START_TRANSFER_AUDIO_FILE, id: 0, seq: 0, payload: payload)
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
    }
    
    private func createPacket(type: UInt8, id: UInt32, seq: UInt16, payload: Data?) -> Data {
        var packet = Data()
        packet.append(type)
        packet.append(contentsOf: withUnsafeBytes(of: id.bigEndian) { Array($0) })
        packet.append(contentsOf: withUnsafeBytes(of: seq.bigEndian) { Array($0) })
        
        let payloadLength = UInt16(payload?.count ?? 0)
        packet.append(contentsOf: withUnsafeBytes(of: payloadLength.bigEndian) { Array($0) })
        
        if let payload = payload {
            packet.append(payload)
        }
        
        return packet
    }
    
    private func parsePacket(_ data: Data) -> (type: UInt8, id: UInt32, seq: UInt16, payload: Data?) {
        guard data.count >= 9 else {
            return (0, 0, 0, nil)
        }
        
        let type = data[0]
        let id = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let seq = data.subdata(in: 5..<7).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let payloadLength = data.subdata(in: 7..<9).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        var payload: Data?
        if payloadLength > 0 && data.count >= 9 + Int(payloadLength) {
            payload = data.subdata(in: 9..<(9 + Int(payloadLength)))
        }
        
        return (type, id, seq, payload)
    }
    
    private func handleStatusNotification(_ data: Data) {
        let packet = parsePacket(data)
        
        if let payload = packet.payload, payload.count >= 4 {
            let fileId = payload.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            switch packet.type {
            case FILE_ADDED:
                print("File added on server: \(fileId)")
                if !availableFiles.contains(fileId) {
                    availableFiles.append(fileId)
                }
                // Auto transfer will be handled by server if enabled
                
            case FILE_DELETED:
                print("File deleted on server: \(fileId)")
                availableFiles.removeAll { $0 == fileId }
                
            default:
                break
            }
        }
    }
    
    private func handleDataTransferNotification(_ data: Data) {
        let packet = parsePacket(data)
        
        switch packet.type {
        case BEGIN_TRANSFER_AUDIO_FILE:
            if let payload = packet.payload, payload.count >= 266 {
                let fileId = payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let fileSize = payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                let totalChunks = payload.subdata(in: 264..<266).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                
                activeTransfer = ActiveTransfer(
                    fileId: fileId,
                    fileSize: fileSize,
                    totalChunks: totalChunks
                )
                
                print("Starting transfer: fileId=\(fileId), size=\(fileSize), chunks=\(totalChunks)")
            }
            
        case CONTINUE_TRANSFER_AUDIO_FILE, END_TRANSFER_AUDIO_FILE:
            if var transfer = activeTransfer {
                if let payload = packet.payload {
                    transfer.data.append(payload)
                    transfer.receivedChunks += 1
                    activeTransfer = transfer
                    
                    if packet.type == END_TRANSFER_AUDIO_FILE {
                        // Transfer complete
                        let audioFile = AudioFile(
                            fileId: transfer.fileId,
                            data: transfer.data,
                            fileSize: Int(transfer.fileSize),
                            timestamp: Date()
                        )
                        
                        audioFiles.append(audioFile)
                        saveFiles()
                        activeTransfer = nil
                        
                        print("Transfer complete: \(transfer.fileId)")
                        
                        // Send completion acknowledgment
                        requestFileCompletion(fileId: transfer.fileId)
                    }
                }
            }
            
        default:
            break
        }
    }
    
    private func requestFileCompletion(fileId: UInt32) {
        guard let characteristic = controlCharacteristic else { return }
        
        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: fileId.bigEndian) { Array($0) })
        
        let packet = createPacket(type: COMPLETE_TRANSFER_AUDIO_FILE, id: 0, seq: 0, payload: payload)
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
    }
    
    private func saveFiles() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let archiveURL = documentsDirectory.appendingPathComponent("audioFiles.archive")
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: audioFiles, requiringSecureCoding: false)
            try data.write(to: archiveURL)
        } catch {
            print("Failed to save files: \(error)")
        }
    }
    
    private func loadSavedFiles() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let archiveURL = documentsDirectory.appendingPathComponent("audioFiles.archive")
        
        if let data = try? Data(contentsOf: archiveURL),
           let files = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [AudioFile] {
            audioFiles = files
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            connectionError = "Bluetooth is powered off"
        case .unauthorized:
            connectionError = "Bluetooth permission denied"
        case .unsupported:
            connectionError = "Bluetooth is not supported"
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        stopScanning()
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionError = error?.localizedDescription ?? "Failed to connect"
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        isAutoTransferEnabled = false
        self.peripheral = nil
        controlCharacteristic = nil
        statusCharacteristic = nil
        dataTransferCharacteristic = nil
        activeTransfer = nil
        
        if let error = error {
            connectionError = "Disconnected: \(error.localizedDescription)"
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([controlUUID, statusUUID, dataTransferUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case controlUUID:
                controlCharacteristic = characteristic
                print("Found CONTROL characteristic")
                
            case statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("Found STATUS characteristic")
                
            case dataTransferUUID:
                dataTransferCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("Found DATA_TRANSFER characteristic")
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case statusUUID:
            handleStatusNotification(data)
            
        case dataTransferUUID:
            handleDataTransferNotification(data)
            
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Write error: \(error.localizedDescription)")
        } else {
            print("Write successful")
        }
    }
}
