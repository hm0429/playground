//
//  BLEManager.swift
//  TMSBLEClient
//
//  BLE communication manager for TMS BLE Client
//

import Foundation
import CoreBluetooth
import Combine

class BLEManager: NSObject, ObservableObject {
    // Published properties for UI binding
    @Published var isScanning = false
    @Published var isConnected = false
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var connectionStatus = "Disconnected"
    @Published var audioFiles: [AudioFile] = []
    @Published var autoDownloadEnabled = UserDefaults.standard.bool(forKey: "AutoDownloadEnabled") {
        didSet {
            UserDefaults.standard.set(autoDownloadEnabled, forKey: "AutoDownloadEnabled")
        }
    }
    
    // Core Bluetooth properties
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    // Characteristics
    private var controlCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var dataTransferCharacteristic: CBCharacteristic?
    
    // Transfer management
    let transferManager = TransferManager()
    
    // UUIDs
    private let serviceUUID = CBUUID(string: ProtocolConstants.serviceUUID)
    private let controlUUID = CBUUID(string: ProtocolConstants.controlUUID)
    private let statusUUID = CBUUID(string: ProtocolConstants.statusUUID)
    private let dataTransferUUID = CBUUID(string: ProtocolConstants.dataTransferUUID)
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[BLEManager] Bluetooth is not powered on")
            return
        }
        
        discoveredPeripherals.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        connectionStatus = "Scanning..."
        print("[BLEManager] Started scanning for TMS BLE Server")
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        connectionStatus = isConnected ? "Connected" : "Disconnected"
        print("[BLEManager] Stopped scanning")
    }
    
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        self.peripheral = peripheral
        centralManager.connect(peripheral, options: nil)
        connectionStatus = "Connecting..."
        print("[BLEManager] Connecting to: \(peripheral.name ?? "Unknown")")
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }
    
    func requestTransfer(for fileId: UInt32? = nil) {
        guard let characteristic = controlCharacteristic else {
            print("[BLEManager] Control characteristic not available")
            return
        }
        
        // Use provided fileId or get next pending one
        let targetFileId = fileId ?? transferManager.getNextPendingFileId()
        
        guard let targetFileId = targetFileId else {
            print("[BLEManager] No pending files to transfer")
            return
        }
        
        // Find or create audio file object
        var audioFile = audioFiles.first(where: { $0.id == targetFileId })
        if audioFile == nil {
            audioFile = AudioFile(id: targetFileId)
            audioFiles.append(audioFile!)
        }
        
        // Start transfer tracking
        transferManager.startTransfer(for: audioFile!)
        
        // Create START_TRANSFER_AUDIO_FILE packet
        var payload = Data()
        payload.appendUInt32BE(targetFileId)
        
        let messageId = transferManager.getNextMessageId(for: "CONTROL")
        let packet = Packet.createPacket(
            type: ControlType.startTransferAudioFile.rawValue,
            id: messageId,
            seq: 0,
            payload: payload,
            hasMore: false
        )
        
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        print("[BLEManager] Requested transfer for file: \(targetFileId)")
    }
    
    func requestOldestFileTransfer() {
        guard let characteristic = controlCharacteristic else {
            print("[BLEManager] Control characteristic not available")
            return
        }
        
        // Remove any existing placeholder files (ID = 0)
        audioFiles.removeAll { $0.id == 0 }
        
        // We don't know the file ID yet, but we need to prepare for the transfer
        // The server will tell us the file ID in the BEGIN_TRANSFER packet
        // For now, create a temporary placeholder with ID 0, which will be updated
        let placeholderFile = AudioFile(id: 0)
        audioFiles.append(placeholderFile)
        transferManager.startTransfer(for: placeholderFile)
        
        // Send START_TRANSFER_AUDIO_FILE with empty payload for oldest file
        let messageId = transferManager.getNextMessageId(for: "CONTROL")
        let packet = Packet.createPacket(
            type: ControlType.startTransferAudioFile.rawValue,
            id: messageId,
            seq: 0,
            payload: Data(),
            hasMore: false
        )
        
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        print("[BLEManager] Requested oldest file transfer")
    }
    
    private func sendTransferComplete(for fileId: UInt32) {
        guard let characteristic = controlCharacteristic else {
            print("[BLEManager] Control characteristic not available")
            return
        }
        
        // Create COMPLETE_TRANSFER_AUDIO_FILE packet
        var payload = Data()
        payload.appendUInt32BE(fileId)
        
        let messageId = transferManager.getNextMessageId(for: "CONTROL")
        let packet = Packet.createPacket(
            type: ControlType.completeTransferAudioFile.rawValue,
            id: messageId,
            seq: 0,
            payload: payload,
            hasMore: false
        )
        
        peripheral?.writeValue(packet, for: characteristic, type: .withResponse)
        print("[BLEManager] Sent transfer complete for file: \(fileId)")
    }
    
    func requestAllPendingTransfers() {
        // Request transfer for all pending files
        while let nextFileId = transferManager.getNextPendingFileId() {
            requestTransfer(for: nextFileId)
            // Add delay to avoid overwhelming the connection
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    // MARK: - Private Methods
    
    private func cleanup() {
        controlCharacteristic = nil
        statusCharacteristic = nil
        dataTransferCharacteristic = nil
        peripheral = nil
        connectedPeripheral = nil
        isConnected = false
        connectionStatus = "Disconnected"
        transferManager.reset()
    }
    
    private func handleStatusPacket(_ packet: Packet) {
        guard let statusType = StatusType(rawValue: packet.type) else {
            print("[BLEManager] Unknown status type: 0x\(String(format: "%02X", packet.type))")
            return
        }
        
        switch statusType {
        case .fileAdded:
            if packet.payload.count >= 4 {
                let fileId = packet.payload.readUInt32BE(at: 0)
                transferManager.addPendingFile(fileId)
                
                // Auto-request transfer only if auto-download is enabled and no current transfer
                if autoDownloadEnabled && transferManager.currentTransfer == nil {
                    requestTransfer(for: fileId)
                    print("[BLEManager] Auto-downloading file: \(fileId)")
                } else if autoDownloadEnabled {
                    print("[BLEManager] File added to queue: \(fileId) (transfer in progress)")
                } else {
                    print("[BLEManager] File added notification: \(fileId) (auto-download disabled)")
                }
            }
            
        case .fileDeleted:
            if packet.payload.count >= 4 {
                let fileId = packet.payload.readUInt32BE(at: 0)
                transferManager.removePendingFile(fileId)
                
                // Remove from audio files list
                audioFiles.removeAll { $0.id == fileId }
                
                print("[BLEManager] File deleted notification: \(fileId)")
            }
        }
    }
    
    private func handleDataTransferPacket(_ packet: Packet) {
        guard let transferType = DataTransferType(rawValue: packet.type) else {
            print("[BLEManager] Unknown transfer type: 0x\(String(format: "%02X", packet.type))")
            return
        }
        
        switch transferType {
        case .beginTransferAudioFile:
            if transferManager.handleBeginTransfer(packet: packet) {
                print("[BLEManager] Transfer begun successfully")
            }
            
        case .transferAudioFile:
            if transferManager.handleDataChunk(packet: packet) {
                // Progress is updated in the transfer manager
            }
            
        case .endTransferAudioFile:
            if transferManager.handleEndTransfer() {
                print("[BLEManager] Transfer completed successfully")
                
                // Send completion acknowledgment
                if let fileId = transferManager.completedTransfers.last {
                    sendTransferComplete(for: fileId)
                    
                    // Check for more pending files (only if auto-download is enabled)
                    if autoDownloadEnabled, let nextFileId = transferManager.getNextPendingFileId() {
                        // Small delay before requesting next file
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.requestTransfer(for: nextFileId)
                            print("[BLEManager] Auto-downloading next file: \(nextFileId)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BLEManager] Bluetooth powered on")
            startScanning()
        case .poweredOff:
            print("[BLEManager] Bluetooth powered off")
            connectionStatus = "Bluetooth Off"
        case .unauthorized:
            print("[BLEManager] Bluetooth unauthorized")
            connectionStatus = "Bluetooth Unauthorized"
        default:
            print("[BLEManager] Bluetooth state: \(central.state)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            print("[BLEManager] Discovered: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BLEManager] Connected to: \(peripheral.name ?? "Unknown")")
        isConnected = true
        connectedPeripheral = peripheral
        connectionStatus = "Connected"
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BLEManager] Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        cleanup()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BLEManager] Disconnected: \(error?.localizedDescription ?? "User disconnected")")
        cleanup()
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            print("[BLEManager] Error discovering services: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        for service in services {
            if service.uuid == serviceUUID {
                print("[BLEManager] Found TMS BLE service")
                peripheral.discoverCharacteristics([controlUUID, statusUUID, dataTransferUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            print("[BLEManager] Error discovering characteristics: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case controlUUID:
                controlCharacteristic = characteristic
                print("[BLEManager] Found CONTROL characteristic")
                
            case statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BLEManager] Found STATUS characteristic, enabling notifications")
                
            case dataTransferUUID:
                dataTransferCharacteristic = characteristic
                // Enable both notify and indicate for DATA_TRANSFER characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BLEManager] Found DATA_TRANSFER characteristic, enabling notifications")
                
            default:
                break
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLEManager] Error updating notification state: \(error.localizedDescription)")
            return
        }
        
        print("[BLEManager] Notification state updated for: \(characteristic.uuid)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            print("[BLEManager] Error receiving data: \(error?.localizedDescription ?? "Unknown")")
            return
        }
        
        guard let packet = Packet(from: data) else {
            print("[BLEManager] Failed to parse packet")
            return
        }
        
        // Handle packet based on characteristic
        switch characteristic.uuid {
        case statusUUID:
            handleStatusPacket(packet)
            
        case dataTransferUUID:
            handleDataTransferPacket(packet)
            
        default:
            print("[BLEManager] Received data on unknown characteristic")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("[BLEManager] Error writing value: \(error.localizedDescription)")
        } else {
            print("[BLEManager] Successfully wrote value to characteristic")
        }
    }
}
