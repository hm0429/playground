import Foundation
import CoreBluetooth
import Combine
import CryptoKit

// Transfer status
struct ActiveTransfer {
    let fileId: UInt32
    let fileSize: UInt32
    let totalChunks: UInt16
    var receivedChunks: Int = 0
    var data: Data = Data()
    var expectedHash: Data?
    var lastSequenceNumber: UInt16?
    var receivedSequences: Set<UInt16> = []
    let startTime: Date = Date()
    var lastUpdateTime: Date = Date()
    var transferRate: Double = 0.0  // KB/s
}

class BLEManager: NSObject, ObservableObject {
    // BLE UUIDs
    private let serviceUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D0")
    private let controlUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D1")
    private let statusUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D2")
    private let dataTransferUUID = CBUUID(string: "572542C4-2198-4D1E-9820-1FEAEA1BB9D3")
    
    // Date formatter for File ID
    private let fileIdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
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
        print("🚀 Initializing BLEManager...")
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
    
    // Convert Unix timestamp to formatted string
    private func formatFileId(_ fileId: UInt32) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(fileId))
        return fileIdFormatter.string(from: date)
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
            let fileIdString = formatFileId(fileId)
            
            switch packet.type {
            case FILE_ADDED:
                print("File added on server: \(fileIdString)")
                if !availableFiles.contains(fileId) {
                    availableFiles.append(fileId)
                }
                // Auto transfer will be handled by server if enabled
                
            case FILE_DELETED:
                print("File deleted on server: \(fileIdString)")
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
                let expectedHash = payload.subdata(in: 8..<40)  // SHA256 hash is 32 bytes
                let totalChunks = payload.subdata(in: 264..<266).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
                
                var transfer = ActiveTransfer(
                    fileId: fileId,
                    fileSize: fileSize,
                    totalChunks: totalChunks
                )
                transfer.expectedHash = expectedHash
                transfer.lastSequenceNumber = packet.seq  // Should be totalChunks-1
                activeTransfer = transfer
                
                print("📥 Starting transfer: \(formatFileId(fileId))")
                print("  Size: \(fileSize) bytes, Chunks: \(totalChunks)")
                print("  Expected hash: \(expectedHash.map { String(format: "%02x", $0) }.prefix(8).joined())...")
                print("  Initial sequence: \(packet.seq) (expected: \(totalChunks - 1))")
            }
            
        case CONTINUE_TRANSFER_AUDIO_FILE, END_TRANSFER_AUDIO_FILE:
            if var transfer = activeTransfer {
                if let payload = packet.payload {
                    // Check sequence number
                    let expectedSeq = UInt16(transfer.totalChunks) - 1 - UInt16(transfer.receivedChunks)
                    if packet.seq != expectedSeq {
                        print("⚠️ Sequence mismatch! Expected: \(expectedSeq), Received: \(packet.seq)")
                        print("  Chunk \(transfer.receivedChunks + 1)/\(transfer.totalChunks)")
                    }
                    
                    // Check for duplicate sequences
                    if transfer.receivedSequences.contains(packet.seq) {
                        print("⚠️ Duplicate sequence detected: \(packet.seq)")
                    }
                    transfer.receivedSequences.insert(packet.seq)
                    
                    // Append data
                    transfer.data.append(payload)
                    transfer.receivedChunks += 1
                    transfer.lastSequenceNumber = packet.seq
                    
                    // Calculate transfer rate
                    let currentTime = Date()
                    let elapsedTime = currentTime.timeIntervalSince(transfer.startTime)
                    if elapsedTime > 0 {
                        let bytesPerSecond = Double(transfer.data.count) / elapsedTime
                        transfer.transferRate = bytesPerSecond / 1024.0  // Convert to KB/s
                    }
                    transfer.lastUpdateTime = currentTime
                    
                    activeTransfer = transfer
                    
                    // Log progress every 25%
                    let progress = Double(transfer.receivedChunks) / Double(transfer.totalChunks)
                    if transfer.receivedChunks % max(1, Int(transfer.totalChunks) / 4) == 0 {
                        print("  Progress: \(Int(progress * 100))% (\(transfer.receivedChunks)/\(transfer.totalChunks) chunks)")
                        print("  Speed: \(String(format: "%.1f", transfer.transferRate)) KB/s")
                        
                        // Estimate remaining time
                        if transfer.transferRate > 0 {
                            let remainingBytes = Int(transfer.fileSize) - transfer.data.count
                            let remainingSeconds = Double(remainingBytes) / (transfer.transferRate * 1024)
                            if remainingSeconds < 60 {
                                print("  ETA: \(Int(remainingSeconds)) seconds")
                            } else {
                                print("  ETA: \(String(format: "%.1f", remainingSeconds / 60)) minutes")
                            }
                        }
                    }
                    
                    if packet.type == END_TRANSFER_AUDIO_FILE {
                        // Calculate final transfer stats
                        let totalTime = Date().timeIntervalSince(transfer.startTime)
                        let avgSpeed = totalTime > 0 ? (Double(transfer.data.count) / totalTime / 1024.0) : 0
                        
                        // Verify data integrity
                        var integrityIssues: [String] = []
                        var hashVerified = true
                        
                        print("\n🔍 Verifying transfer integrity...")
                        print("📊 Transfer Statistics:")
                        print("  Duration: \(String(format: "%.1f", totalTime)) seconds")
                        print("  Average speed: \(String(format: "%.1f", avgSpeed)) KB/s")
                        if avgSpeed > 0 {
                            let throughput = avgSpeed * 8  // Convert to Kbps
                            print("  Throughput: \(String(format: "%.1f", throughput)) Kbps")
                        }
                        
                        // Check data size
                        let receivedSize = transfer.data.count
                        let expectedSize = Int(transfer.fileSize)
                        if receivedSize != expectedSize {
                            print("❌ Size mismatch! Expected: \(expectedSize), Received: \(receivedSize)")
                            print("  Difference: \(receivedSize - expectedSize) bytes")
                            integrityIssues.append("Size mismatch: \(receivedSize - expectedSize) bytes")
                        } else {
                            print("✅ Size match: \(receivedSize) bytes")
                        }
                        
                        // Verify hash if available
                        
                        if let expectedHash = transfer.expectedHash {
                            let receivedHash = SHA256.hash(data: transfer.data)
                            let receivedHashData = Data(receivedHash)
                            
                            if receivedHashData == expectedHash {
                                print("✅ Hash verification successful")
                            } else {
                                print("❌ Hash mismatch!")
                                print("  Expected: \(expectedHash.map { String(format: "%02x", $0) }.prefix(8).joined())...")
                                print("  Received: \(receivedHashData.map { String(format: "%02x", $0) }.prefix(8).joined())...")
                                hashVerified = false
                                integrityIssues.append("Hash mismatch")
                            }
                        }
                        
                        // Check sequence completeness
                        if transfer.receivedSequences.count != Int(transfer.totalChunks) {
                            print("⚠️ Missing chunks! Expected: \(transfer.totalChunks), Received unique: \(transfer.receivedSequences.count)")
                            let missingCount = Int(transfer.totalChunks) - transfer.receivedSequences.count
                            integrityIssues.append("Missing \(missingCount) chunks")
                            // Find missing sequences
                            for i in 0..<transfer.totalChunks {
                                if !transfer.receivedSequences.contains(i) {
                                    print("  Missing sequence: \(i)")
                                }
                            }
                        } else {
                            print("✅ All \(transfer.totalChunks) chunks received")
                        }
                        
                        // Create audio file
                        let audioFile = AudioFile(
                            fileId: transfer.fileId,
                            data: transfer.data,
                            fileSize: receivedSize,  // Use actual received size
                            timestamp: Date()
                        )
                        
                        // Set integrity status
                        if !integrityIssues.isEmpty {
                            audioFile.hasIntegrityIssue = true
                            audioFile.integrityMessage = integrityIssues.joined(separator: ", ")
                            print("⚠️ File has integrity issues: \(audioFile.integrityMessage ?? "")")
                        }
                        
                        // Check for duplicates before adding
                        if !audioFiles.contains(where: { $0.fileId == transfer.fileId }) {
                            audioFiles.append(audioFile)
                            audioFiles.sort { $0.fileId > $1.fileId } // Sort by newest first
                            saveFiles()
                            print("\n✅ Transfer complete: \(formatFileId(transfer.fileId))")
                        } else {
                            print("\n⚠️ Transfer complete but file already exists: \(formatFileId(transfer.fileId))")
                        }
                        
                        activeTransfer = nil
                        
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
    
    func saveFiles() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let archiveURL = documentsDirectory.appendingPathComponent("audioFiles.archive")
        
        do {
            // Create documents directory if it doesn't exist
            try FileManager.default.createDirectory(at: documentsDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let data = try NSKeyedArchiver.archivedData(withRootObject: audioFiles, requiringSecureCoding: false)
            try data.write(to: archiveURL, options: .atomic)  // Use atomic write for safety
            
            // Calculate total size using actual data size
            let totalSize = audioFiles.reduce(0) { $0 + $1.data.count }
            let sizeInMB = Double(totalSize) / 1024.0 / 1024.0
            
            print("✅ Saved \(audioFiles.count) audio files to persistent storage")
            print("  Path: \(archiveURL.path)")
            print("  Total size: \(String(format: "%.2f", sizeInMB)) MB (actual data)")
            
            // Log individual file sizes for debugging
            for file in audioFiles.prefix(3) {  // Show first 3 files
                let fileSizeKB = Double(file.data.count) / 1024.0
                print("  - \(formatFileId(file.fileId)): \(String(format: "%.2f", fileSizeKB)) KB")
            }
            if audioFiles.count > 3 {
                print("  ... and \(audioFiles.count - 3) more files")
            }
        } catch {
            print("❌ Failed to save files: \(error)")
            print("  Path: \(archiveURL.path)")
        }
    }
    
    private func loadSavedFiles() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let archiveURL = documentsDirectory.appendingPathComponent("audioFiles.archive")
        
        do {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                let data = try Data(contentsOf: archiveURL)
                if let files = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [AudioFile] {
                    audioFiles = files
                    audioFiles.sort { $0.fileId > $1.fileId } // Sort by newest first
                    
                    // Calculate total size and verify data integrity
                    var totalSize = 0
                    for file in audioFiles {
                        let actualDataSize = file.data.count
                        let storedSize = file.fileSize
                        totalSize += actualDataSize
                        
                        // Log any size mismatches
                        if actualDataSize != storedSize {
                            print("⚠️ Size mismatch for file \(formatFileId(file.fileId)):")
                            print("   Stored size: \(storedSize), Actual data size: \(actualDataSize)")
                        }
                    }
                    
                    let sizeInMB = Double(totalSize) / 1024.0 / 1024.0
                    
                    print("✅ Loaded \(audioFiles.count) audio files from persistent storage")
                    print("  Path: \(archiveURL.path)")
                    print("  Total size: \(String(format: "%.2f", sizeInMB)) MB (based on actual data)")
                } else {
                    print("⚠️ Failed to decode audio files from archive")
                    audioFiles = []
                }
            } else {
                print("ℹ️ No saved audio files found at: \(archiveURL.path)")
                audioFiles = []
            }
        } catch let error as NSError {
            print("❌ Error loading saved files: \(error)")
            print("  Path: \(archiveURL.path)")
            
            // If decoding failed due to format change, clear the old file
            if error.code == 4864 { // NSKeyedUnarchiveInvalidArchiveError
                print("🔄 Clearing corrupted archive file...")
                try? FileManager.default.removeItem(at: archiveURL)
                print("  Old archive removed. Starting with empty file list.")
            }
            
            audioFiles = []
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
