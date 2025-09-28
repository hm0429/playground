//
//  TransferManager.swift
//  TMSBLEClient
//
//  Manages file transfer state for TMS BLE Client
//

import Foundation

class TransferManager: ObservableObject {
    @Published var currentTransfer: AudioFile?
    @Published var pendingFileIds: Set<UInt32> = []
    @Published var completedTransfers: [UInt32] = []
    
    private var messageIdCounters: [String: UInt16] = [
        "CONTROL": 1,
        "STATUS": 1,
        "DATA_TRANSFER": 1
    ]
    
    private let fragmentManager = FragmentManager()
    
    func getNextMessageId(for characteristic: String) -> UInt16 {
        let id = messageIdCounters[characteristic] ?? 1
        messageIdCounters[characteristic] = id &+ 1  // Use overflow operator for automatic wrapping
        return id
    }
    
    func addPendingFile(_ fileId: UInt32) {
        pendingFileIds.insert(fileId)
        print("[TransferManager] Added pending file: \(fileId)")
    }
    
    func removePendingFile(_ fileId: UInt32) {
        pendingFileIds.remove(fileId)
        print("[TransferManager] Removed pending file: \(fileId)")
    }
    
    func startTransfer(for file: AudioFile) {
        currentTransfer = file
        file.isTransferring = true
        file.transferProgress = 0.0
        fragmentManager.reset()
        print("[TransferManager] Started transfer for file: \(file.id)")
    }
    
    func handleBeginTransfer(packet: Packet) -> Bool {
        guard packet.payload.count >= 42 else {
            print("[TransferManager] Invalid BEGIN_TRANSFER packet")
            return false
        }
        
        let fileId = packet.payload.readUInt32BE(at: 0)
        let fileSize = packet.payload.readUInt32BE(at: 4)
        let fileHash = packet.payload.subdata(in: 8..<40)
        let totalChunks = packet.payload.readUInt16BE(at: 40)
        
        // Check if we have a current transfer
        guard let current = currentTransfer else {
            print("[TransferManager] No active transfer for BEGIN_TRANSFER")
            return false
        }
        
        // If the current transfer has ID 0 (placeholder for oldest file request),
        // update it with the actual file ID from the server
        if current.id == 0 {
            // Update the placeholder with actual file ID
            current.updateFileId(fileId)
            print("[TransferManager] Updated placeholder file with actual ID: \(fileId)")
        } else if current.id != fileId {
            // If not a placeholder and IDs don't match, that's an error
            print("[TransferManager] Unexpected file ID in BEGIN_TRANSFER: \(fileId), expected: \(current.id)")
            return false
        }
        
        current.setMetadata(size: Int(fileSize), hash: fileHash, totalChunks: Int(totalChunks))
        
        print("[TransferManager] Begin transfer - File: \(fileId), Size: \(fileSize), Chunks: \(totalChunks)")
        return true
    }
    
    func handleDataChunk(packet: Packet) -> Bool {
        guard let current = currentTransfer else {
            print("[TransferManager] No active transfer")
            return false
        }
        
        let chunkNumber = Int(packet.seq)
        current.addChunk(chunkNumber, data: packet.payload)
        
        print("[TransferManager] Received chunk \(chunkNumber + 1), progress: \(Int(current.transferProgress * 100))%")
        return true
    }
    
    func handleEndTransfer() -> Bool {
        guard let current = currentTransfer else {
            print("[TransferManager] No active transfer to end")
            return false
        }
        
        // Assemble the file
        if current.assembleFile() {
            print("[TransferManager] File assembled successfully: \(current.fileName)")
            current.isTransferring = false
            completedTransfers.append(current.id)
            removePendingFile(current.id)
            currentTransfer = nil
            return true
        } else {
            print("[TransferManager] Failed to assemble file")
            current.isTransferring = false
            currentTransfer = nil
            return false
        }
    }
    
    func cancelCurrentTransfer() {
        if let current = currentTransfer {
            current.isTransferring = false
            current.transferProgress = 0.0
            currentTransfer = nil
            print("[TransferManager] Cancelled transfer for file: \(current.id)")
        }
    }
    
    func handleFragmentedPacket(_ packet: Packet) -> Data? {
        return fragmentManager.addFragment(packet)
    }
    
    func reset() {
        cancelCurrentTransfer()
        pendingFileIds.removeAll()
        completedTransfers.removeAll()
        fragmentManager.reset()
        
        // Reset message ID counters
        messageIdCounters = [
            "CONTROL": 1,
            "STATUS": 1,
            "DATA_TRANSFER": 1
        ]
    }
    
    func getNextPendingFileId() -> UInt32? {
        // Get the oldest file (smallest ID)
        return pendingFileIds.min()
    }
}
