import Foundation
import CoreBluetooth
import AVFoundation

// MARK: - Protocol Constants
struct TMSBLEProtocol {
    static let serviceUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D0")
    static let controlUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D1")
    static let statusUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D2")
    static let dataTransferUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D3")
    
    enum ControlType: UInt8 {
        case startTransferAudioFile = 0x01
        case completeTransferAudioFile = 0x02
        case beginTransferAudioFile = 0x21
        case endTransferAudioFile = 0x22
    }
    
    enum StatusType: UInt8 {
        case fileAdded = 0x40
        case fileDeleted = 0x41
    }
    
    enum DataTransferType: UInt8 {
        case transferAudioFile = 0x80
    }
}

// MARK: - Audio File Model
struct AudioFile: Identifiable {
    let id = UUID()
    let fileId: UInt32
    let filename: String
    let data: Data
    let receivedAt: Date
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: Double(fileId)))
    }
}

// MARK: - Transfer State
class TransferState {
    var fileId: UInt32 = 0
    var fileSize: UInt32 = 0
    var fileHash: Data = Data()
    var totalChunks: UInt16 = 0
    var receivedChunks: UInt16 = 0
    var fileData: Data = Data()
    var messageId: UInt16 = 0
    
    func reset() {
        fileId = 0
        fileSize = 0
        fileHash = Data()
        totalChunks = 0
        receivedChunks = 0
        fileData = Data()
        messageId = 0
    }
}

// MARK: - BLE Manager
class BLEManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var dataTransferCharacteristic: CBCharacteristic?
    
    private var currentTransfer = TransferState()
    private var pendingFileQueue: [UInt32] = []
    private var isTransferring = false
    
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var connectionStatus = "Not Connected"
    @Published var transferStatus = ""
    @Published var transferProgress: Double = 0.0
    @Published var audioFiles: [AudioFile] = []
    @Published var autoDownload = false {
        didSet {
            if autoDownload {
                processPendingQueue()
            }
        }
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth is not powered on"
            return
        }
        
        print("[BLE] Starting scan for TMS BLE Server")
        centralManager.scanForPeripherals(withServices: [TMSBLEProtocol.serviceUUID], options: nil)
        isScanning = true
        connectionStatus = "Scanning..."
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        connectionStatus = "Scan stopped"
        print("[BLE] Scan stopped")
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func requestOldestFile() {
        guard isConnected, let characteristic = controlCharacteristic, !isTransferring else {
            print("[BLE] Cannot request file: not ready or transfer in progress")
            return
        }
        
        print("[BLE] Requesting oldest file")
        let packet = createControlPacket(type: .startTransferAudioFile, fileId: nil)
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        isTransferring = true
    }
    
    func deleteAudioFile(_ file: AudioFile) {
        audioFiles.removeAll { $0.id == file.id }
    }
    
    // MARK: - Protocol Helpers
    private func createControlPacket(type: TMSBLEProtocol.ControlType, fileId: UInt32?) -> Data {
        var packet = Data()
        packet.append(type.rawValue)
        packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Array($0) }) // Message ID
        packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Array($0) }) // SEQ
        
        if let fileId = fileId {
            packet.append(contentsOf: withUnsafeBytes(of: UInt16(4).bigEndian) { Array($0) }) // Length
            packet.append(contentsOf: withUnsafeBytes(of: fileId.bigEndian) { Array($0) })
        } else {
            packet.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Array($0) }) // Length
        }
        
        return packet
    }
    
    private func parsePacket(_ data: Data) -> (type: UInt8, messageId: UInt16, seq: UInt16, payload: Data)? {
        guard data.count >= 7 else { return nil }
        
        let type = data[0]
        let messageId = data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let seq = data.subdata(in: 3..<5).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let length = data.subdata(in: 5..<7).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let payload = data.subdata(in: 7..<min(7 + Int(length), data.count))
        
        return (type, messageId, seq, payload)
    }
    
    private func handleControlIndication(_ data: Data) {
        guard let packet = parsePacket(data) else { return }
        
        if packet.type == TMSBLEProtocol.ControlType.beginTransferAudioFile.rawValue {
            handleBeginTransfer(packet.payload)
        } else if packet.type == TMSBLEProtocol.ControlType.endTransferAudioFile.rawValue {
            handleEndTransfer(packet.payload)
        }
    }
    
    private func handleBeginTransfer(_ payload: Data) {
        guard payload.count >= 42 else { return }
        
        currentTransfer.reset()
        currentTransfer.fileId = payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        currentTransfer.fileSize = payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        currentTransfer.fileHash = payload.subdata(in: 8..<40)
        currentTransfer.totalChunks = payload.subdata(in: 40..<42).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        
        print("[Control] BEGIN_TRANSFER - File ID: \(currentTransfer.fileId), Size: \(currentTransfer.fileSize), Chunks: \(currentTransfer.totalChunks)")
        
        transferStatus = "Receiving file..."
        transferProgress = 0.0
    }
    
    private func handleEndTransfer(_ payload: Data) {
        guard payload.count >= 4 else { return }
        
        let fileId = payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        print("[Control] END_TRANSFER - File ID: \(fileId)")
        
        // Create audio file
        let filename = getFilenameFromFileId(fileId)
        let audioFile = AudioFile(
            fileId: fileId,
            filename: filename,
            data: currentTransfer.fileData,
            receivedAt: Date()
        )
        
        DispatchQueue.main.async {
            self.audioFiles.append(audioFile)
            self.transferStatus = "Transfer complete"
            self.transferProgress = 1.0
        }
        
        // Send completion acknowledgment
        if let characteristic = controlCharacteristic {
            let packet = createControlPacket(type: .completeTransferAudioFile, fileId: fileId)
            peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        }
        
        isTransferring = false
        
        // Process pending queue
        processPendingQueue()
    }
    
    private func handleDataTransfer(_ data: Data) {
        guard let packet = parsePacket(data) else { return }
        
        if packet.type == TMSBLEProtocol.DataTransferType.transferAudioFile.rawValue {
            currentTransfer.fileData.append(packet.payload)
            currentTransfer.receivedChunks += 1
            
            let progress = Double(currentTransfer.receivedChunks) / Double(currentTransfer.totalChunks)
            DispatchQueue.main.async {
                self.transferProgress = progress
                self.transferStatus = "Receiving: \(self.currentTransfer.receivedChunks)/\(self.currentTransfer.totalChunks) chunks"
            }
            
            print("[DataTransfer] Received chunk \(currentTransfer.receivedChunks)/\(currentTransfer.totalChunks)")
        }
    }
    
    private func handleStatusNotification(_ data: Data) {
        guard let packet = parsePacket(data) else { return }
        
        if packet.type == TMSBLEProtocol.StatusType.fileAdded.rawValue {
            guard packet.payload.count >= 4 else { return }
            let fileId = packet.payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            print("[Status] FILE_ADDED - File ID: \(fileId)")
            
            if autoDownload {
                pendingFileQueue.append(fileId)
                processPendingQueue()
            }
        } else if packet.type == TMSBLEProtocol.StatusType.fileDeleted.rawValue {
            guard packet.payload.count >= 4 else { return }
            let fileId = packet.payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            print("[Status] FILE_DELETED - File ID: \(fileId)")
        }
    }
    
    private func processPendingQueue() {
        guard autoDownload, !isTransferring, !pendingFileQueue.isEmpty, isConnected,
              let characteristic = controlCharacteristic else { return }
        
        let fileId = pendingFileQueue.removeFirst()
        print("[BLE] Auto-downloading file ID: \(fileId)")
        
        let packet = createControlPacket(type: .startTransferAudioFile, fileId: fileId)
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        isTransferring = true
    }
    
    private func getFilenameFromFileId(_ fileId: UInt32) -> String {
        let date = Date(timeIntervalSince1970: Double(fileId))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        return "\(formatter.string(from: date)).mp3"
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionStatus = "Bluetooth is powered on"
        case .poweredOff:
            connectionStatus = "Bluetooth is powered off"
        case .resetting:
            connectionStatus = "Bluetooth is resetting"
        case .unauthorized:
            connectionStatus = "Bluetooth is unauthorized"
        case .unsupported:
            connectionStatus = "Bluetooth is unsupported"
        case .unknown:
            connectionStatus = "Bluetooth state is unknown"
        @unknown default:
            connectionStatus = "Unknown Bluetooth state"
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                       advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("[BLE] Discovered peripheral: \(peripheral.name ?? "Unknown")")
        
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        stopScanning()
        connectionStatus = "Connecting..."
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLE] Connected to peripheral")
        isConnected = true
        connectionStatus = "Connected"
        peripheral.discoverServices([TMSBLEProtocol.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Disconnected from peripheral")
        isConnected = false
        connectionStatus = "Disconnected"
        self.peripheral = nil
        controlCharacteristic = nil
        statusCharacteristic = nil
        dataTransferCharacteristic = nil
        currentTransfer.reset()
        pendingFileQueue.removeAll()
        isTransferring = false
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = "Failed to connect"
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            print("[BLE] Error discovering services: \(error!)")
            return
        }
        
        if let service = peripheral.services?.first(where: { $0.uuid == TMSBLEProtocol.serviceUUID }) {
            print("[BLE] Found TMS service")
            peripheral.discoverCharacteristics([
                TMSBLEProtocol.controlUUID,
                TMSBLEProtocol.statusUUID,
                TMSBLEProtocol.dataTransferUUID
            ], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            print("[BLE] Error discovering characteristics: \(error!)")
            return
        }
        
        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case TMSBLEProtocol.controlUUID:
                controlCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BLE] Found CONTROL characteristic")
                
            case TMSBLEProtocol.statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BLE] Found STATUS characteristic")
                
            case TMSBLEProtocol.dataTransferUUID:
                dataTransferCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BLE] Found DATA_TRANSFER characteristic")
                
            default:
                break
            }
        }
        
        connectionStatus = "Ready"
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        
        switch characteristic.uuid {
        case TMSBLEProtocol.controlUUID:
            handleControlIndication(data)
        case TMSBLEProtocol.statusUUID:
            handleStatusNotification(data)
        case TMSBLEProtocol.dataTransferUUID:
            handleDataTransfer(data)
        default:
            break
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLE] Write error: \(error)")
        } else {
            print("[BLE] Write successful")
        }
    }
}
