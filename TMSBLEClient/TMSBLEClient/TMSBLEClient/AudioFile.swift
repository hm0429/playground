import Foundation

class AudioFile: NSObject, NSCoding, Identifiable {
    let id = UUID()
    let fileId: UInt32
    let data: Data
    let fileSize: Int
    let timestamp: Date
    var hasIntegrityIssue: Bool = false
    var integrityMessage: String? = nil
    
    init(fileId: UInt32, data: Data, fileSize: Int, timestamp: Date) {
        self.fileId = fileId
        self.data = data
        self.fileSize = fileSize
        self.timestamp = timestamp
        super.init()
    }
    
    // NSCoding - Using more robust encoding/decoding
    func encode(with coder: NSCoder) {
        // Encode UInt32 as NSNumber to avoid type issues
        coder.encode(NSNumber(value: fileId), forKey: "fileId")
        coder.encode(data, forKey: "data")
        coder.encode(NSNumber(value: fileSize), forKey: "fileSize")
        coder.encode(timestamp, forKey: "timestamp")
        coder.encode(hasIntegrityIssue, forKey: "hasIntegrityIssue")
        if let message = integrityMessage {
            coder.encode(message, forKey: "integrityMessage")
        }
    }
    
    required init?(coder: NSCoder) {
        // Decode using NSNumber for better compatibility
        if let fileIdNumber = coder.decodeObject(forKey: "fileId") as? NSNumber {
            self.fileId = fileIdNumber.uint32Value
        } else {
            self.fileId = 0
        }
        
        // Decode data first
        self.data = coder.decodeObject(forKey: "data") as? Data ?? Data()
        
        // Try to decode fileSize, fallback to actual data size
        if let fileSizeNumber = coder.decodeObject(forKey: "fileSize") as? NSNumber {
            let decodedSize = fileSizeNumber.intValue
            // Use actual data size if decoded size is 0 or doesn't match
            self.fileSize = (decodedSize > 0) ? decodedSize : self.data.count
        } else {
            // If no fileSize stored, use actual data size
            self.fileSize = self.data.count
        }
        
        self.timestamp = coder.decodeObject(forKey: "timestamp") as? Date ?? Date()
        self.hasIntegrityIssue = coder.decodeBool(forKey: "hasIntegrityIssue")
        self.integrityMessage = coder.decodeObject(forKey: "integrityMessage") as? String
        super.init()
    }
}