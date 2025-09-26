import Foundation

class AudioFile: NSObject, NSCoding, Identifiable {
    let id = UUID()
    let fileId: UInt32
    let data: Data
    let fileSize: Int
    let timestamp: Date
    
    init(fileId: UInt32, data: Data, fileSize: Int, timestamp: Date) {
        self.fileId = fileId
        self.data = data
        self.fileSize = fileSize
        self.timestamp = timestamp
        super.init()
    }
    
    // NSCoding
    func encode(with coder: NSCoder) {
        coder.encode(fileId, forKey: "fileId")
        coder.encode(data, forKey: "data")
        coder.encode(fileSize, forKey: "fileSize")
        coder.encode(timestamp, forKey: "timestamp")
    }
    
    required init?(coder: NSCoder) {
        self.fileId = UInt32(coder.decodeInteger(forKey: "fileId"))
        self.data = coder.decodeObject(forKey: "data") as? Data ?? Data()
        self.fileSize = coder.decodeInteger(forKey: "fileSize")
        self.timestamp = coder.decodeObject(forKey: "timestamp") as? Date ?? Date()
        super.init()
    }
}
