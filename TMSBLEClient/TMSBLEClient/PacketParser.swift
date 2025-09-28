//
//  PacketParser.swift
//  TMSBLEClient
//
//  Packet parsing utilities for TMS BLE Protocol
//

import Foundation

// Protocol constants
enum ProtocolConstants {
    // Service and Characteristics
    static let serviceUUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D0"
    static let controlUUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D1"
    static let statusUUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D2"
    static let dataTransferUUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D3"
    
    // MTU and chunk sizes
    static let mtuSize = 512
    static let headerSize = 7
    static let maxPayloadSize = mtuSize - headerSize
    static let chunkSize = 505 // MTU - header
}

// Packet types
enum ControlType: UInt8 {
    case startTransferAudioFile = 0x01
    case completeTransferAudioFile = 0x02
}

enum StatusType: UInt8 {
    case fileAdded = 0x40
    case fileDeleted = 0x41
}

enum DataTransferType: UInt8 {
    case beginTransferAudioFile = 0x80
    case transferAudioFile = 0x81
    case endTransferAudioFile = 0x82
}

// Packet structure
struct Packet {
    let type: UInt8
    let id: UInt16
    let seq: UInt16
    let hasMore: Bool
    let length: UInt16
    let payload: Data
    
    var fragmentNumber: UInt16 {
        return seq & 0x7FFF
    }
    
    // Regular initializer for creating packets directly
    init(type: UInt8, id: UInt16, seq: UInt16, hasMore: Bool, length: UInt16, payload: Data) {
        self.type = type
        self.id = id
        self.seq = seq
        self.hasMore = hasMore
        self.length = length
        self.payload = payload
    }
    
    init?(from data: Data) {
        guard data.count >= ProtocolConstants.headerSize else {
            return nil
        }
        
        self.type = data[0]
        self.id = data.readUInt16BE(at: 1)
        
        let seqField = data.readUInt16BE(at: 3)
        self.hasMore = (seqField & 0x8000) != 0
        self.seq = seqField & 0x7FFF
        
        self.length = data.readUInt16BE(at: 5)
        
        if data.count >= ProtocolConstants.headerSize + Int(length) {
            self.payload = data.subdata(in: ProtocolConstants.headerSize..<(ProtocolConstants.headerSize + Int(length)))
        } else {
            self.payload = Data()
        }
    }
    
    func toData() -> Data {
        var data = Data()
        
        // TYPE (1 byte)
        data.append(type)
        
        // ID (2 bytes, big endian)
        data.appendUInt16BE(id)
        
        // SEQ (2 bytes, big endian) with MORE flag
        let seqValue = hasMore ? (seq | 0x8000) : (seq & 0x7FFF)
        data.appendUInt16BE(seqValue)
        
        // LENGTH (2 bytes, big endian)
        data.appendUInt16BE(UInt16(payload.count))
        
        // PAYLOAD
        data.append(payload)
        
        return data
    }
    
    static func createPacket(type: UInt8, id: UInt16, seq: UInt16 = 0, payload: Data = Data(), hasMore: Bool = false) -> Data {
        let packet = Packet(
            type: type,
            id: id,
            seq: seq,
            hasMore: hasMore,
            length: UInt16(payload.count),
            payload: payload
        )
        return packet.toData()
    }
}

// Fragment manager for reassembling fragmented packets
class FragmentManager {
    private var fragments: [UInt16: [UInt16: Data]] = [:] // [ID: [Fragment Number: Data]]
    private var expectedFragments: [UInt16: Set<UInt16>] = [:] // Track which fragments we're expecting
    
    func addFragment(_ packet: Packet) -> Data? {
        let id = packet.id
        let fragmentNum = packet.fragmentNumber
        
        // Initialize storage for this ID if needed
        if fragments[id] == nil {
            fragments[id] = [:]
            expectedFragments[id] = Set()
        }
        
        // Store this fragment
        fragments[id]?[fragmentNum] = packet.payload
        expectedFragments[id]?.insert(fragmentNum)
        
        // If this packet has more fragments, we're not done
        if packet.hasMore {
            // Record that we expect the next fragment
            expectedFragments[id]?.insert(fragmentNum + 1)
            return nil
        }
        
        // This is the last fragment, try to reassemble
        guard let fragmentsForId = fragments[id] else {
            return nil
        }
        
        // Check if we have all fragments (0 to fragmentNum)
        let allFragmentNumbers = Array(0...fragmentNum)
        guard allFragmentNumbers.allSatisfy({ fragmentsForId[$0] != nil }) else {
            // Missing some fragments
            return nil
        }
        
        // Reassemble the complete payload
        var completePayload = Data()
        for num in allFragmentNumbers {
            if let fragment = fragmentsForId[num] {
                completePayload.append(fragment)
            }
        }
        
        // Clean up
        fragments.removeValue(forKey: id)
        expectedFragments.removeValue(forKey: id)
        
        return completePayload
    }
    
    func reset() {
        fragments.removeAll()
        expectedFragments.removeAll()
    }
    
    func resetForId(_ id: UInt16) {
        fragments.removeValue(forKey: id)
        expectedFragments.removeValue(forKey: id)
    }
}

// Extensions for Data manipulation
extension Data {
    func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 1 < count else { return 0 }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }
    
    func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        return UInt32(self[offset]) << 24 |
               UInt32(self[offset + 1]) << 16 |
               UInt32(self[offset + 2]) << 8 |
               UInt32(self[offset + 3])
    }
    
    mutating func appendUInt16BE(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
    
    mutating func appendUInt32BE(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
