//
//  AudioFile.swift
//  TMSBLEClient
//
//  Audio file model for TMS BLE Client
//

import Foundation
import CryptoKit

class AudioFile: Identifiable, ObservableObject {
    private(set) var id: UInt32
    private(set) var fileName: String
    @Published var fileSize: Int = 0
    @Published var fileData: Data?
    @Published var fileHash: Data?
    @Published var transferProgress: Double = 0.0
    @Published var isTransferring: Bool = false
    @Published var isTransferComplete: Bool = false
    @Published var isPlaying: Bool = false
    
    private var expectedChunks: Int = 0
    private var receivedChunks: [Int: Data] = [:]
    
    init(id: UInt32) {
        self.id = id
        // Convert Unix timestamp to readable filename
        if id > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(id))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            self.fileName = "\(formatter.string(from: date)).mp3"
        } else {
            // Placeholder file
            self.fileName = "pending.mp3"
        }
    }
    
    func updateFileId(_ newId: UInt32) {
        self.id = newId
        // Update filename based on new ID
        let date = Date(timeIntervalSince1970: TimeInterval(newId))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        self.fileName = "\(formatter.string(from: date)).mp3"
    }
    
    func setMetadata(size: Int, hash: Data, totalChunks: Int) {
        self.fileSize = size
        self.fileHash = hash
        self.expectedChunks = totalChunks
        self.receivedChunks = [:]
        self.fileData = nil
        self.transferProgress = 0.0
    }
    
    func addChunk(_ chunkNumber: Int, data: Data) {
        receivedChunks[chunkNumber] = data
        transferProgress = Double(receivedChunks.count) / Double(expectedChunks)
    }
    
    func assembleFile() -> Bool {
        guard receivedChunks.count == expectedChunks else {
            print("[AudioFile] Missing chunks: \(receivedChunks.count)/\(expectedChunks)")
            return false
        }
        
        // Assemble all chunks in order
        var assembledData = Data()
        for i in 0..<expectedChunks {
            guard let chunk = receivedChunks[i] else {
                print("[AudioFile] Missing chunk \(i)")
                return false
            }
            assembledData.append(chunk)
        }
        
        // Verify hash
        if let expectedHash = fileHash {
            let computedHash = Data(SHA256.hash(data: assembledData))
            if computedHash.prefix(32) != expectedHash {
                print("[AudioFile] Hash mismatch!")
                return false
            }
        }
        
        self.fileData = assembledData
        self.isTransferComplete = true
        self.transferProgress = 1.0
        
        // Save to documents directory
        saveToDocuments()
        
        return true
    }
    
    private func saveToDocuments() {
        guard let data = fileData else { return }
        
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let filePath = documentsPath.appendingPathComponent(fileName)
            try data.write(to: filePath)
            print("[AudioFile] Saved to: \(filePath)")
        } catch {
            print("[AudioFile] Failed to save file: \(error)")
        }
    }
    
    func getFileURL() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filePath = documentsPath.appendingPathComponent(fileName)
        
        // Check if file exists
        if FileManager.default.fileExists(atPath: filePath.path) {
            return filePath
        }
        
        // If not saved yet but we have data, save it first
        if fileData != nil {
            saveToDocuments()
            return filePath
        }
        
        return nil
    }
    
    func deleteFile() {
        // Delete from documents directory
        if let url = getFileURL() {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Clear data
        fileData = nil
        receivedChunks.removeAll()
        transferProgress = 0.0
        isTransferComplete = false
    }
}