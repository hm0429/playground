const bleno = require('@abandonware/bleno');
const fs = require('fs');
const path = require('path');
const os = require('os');
const config = require('./config');
const FileWatcher = require('./fileWatcher');

// Global state
let fileWatcher = null;
let statusUpdateCallback = null;
let dataTransferUpdateCallback = null;
let currentTransfer = null;
let isConnected = false;

// Message ID counters per Characteristic
const messageIdCounters = {
    CONTROL: 1,      // CONTROL Characteristic message IDs
    STATUS: 1,       // STATUS Characteristic message IDs  
    DATA_TRANSFER: 1 // DATA_TRANSFER Characteristic message IDs (transfer sessions)
};

// Initialize file watcher
fileWatcher = new FileWatcher(config.AUDIO_DIR);

// File watcher event handlers
fileWatcher.on('fileAdded', (fileInfo) => {
    if (isConnected) {
        notifyFileAdded(fileInfo.id);
    }
});

fileWatcher.on('fileRemoved', (fileInfo) => {
    if (isConnected) {
        notifyFileDeleted(fileInfo.id);
    }
});

fileWatcher.on('ready', (files) => {
    // console.log(`[BLE Server] File watcher ready. ${files.length} files available.`);
});

// Helper functions for protocol data formatting
function createPacket(type, id = 0, seq = 0, payload = Buffer.alloc(0), hasMore = false) {
    const header = Buffer.alloc(7);
    header.writeUInt8(type, 0);              // TYPE (1 byte)
    header.writeUInt16BE(id, 1);             // ID (2 bytes)
    
    // SEQ field: bit 15 = MORE flag, bits 0-14 = fragment number
    const seqValue = hasMore ? (seq | 0x8000) : (seq & 0x7FFF);
    header.writeUInt16BE(seqValue, 3);       // SEQ (2 bytes)
    
    header.writeUInt16BE(payload.length, 5); // LENGTH (2 bytes)
    
    return Buffer.concat([header, payload]);
}

// Fragment large payloads based on MTU
function createFragmentedPackets(type, id, payload) {
    const maxPayloadSize = config.MTU_SIZE - 7; // MTU minus header size
    const packets = [];
    
    if (payload.length <= maxPayloadSize) {
        // Single packet - no fragmentation needed
        packets.push(createPacket(type, id, 0, payload, false));
    } else {
        // Fragment into multiple packets with same ID
        let offset = 0;
        let fragmentNum = 0;
        
        while (offset < payload.length) {
            const remaining = payload.length - offset;
            const chunkSize = Math.min(maxPayloadSize, remaining);
            const chunk = payload.slice(offset, offset + chunkSize);
            const hasMore = (offset + chunkSize) < payload.length;
            
            packets.push(createPacket(type, id, fragmentNum, chunk, hasMore));
            
            offset += chunkSize;
            fragmentNum++;
        }
    }
    
    return packets;
}

// Get next message ID for a specific Characteristic and increment counter
function getNextMessageId(characteristic) {
    if (!messageIdCounters.hasOwnProperty(characteristic)) {
        throw new Error(`Unknown characteristic: ${characteristic}`);
    }
    
    const id = messageIdCounters[characteristic];
    messageIdCounters[characteristic] = (messageIdCounters[characteristic] + 1) % 65536; // Wrap at 16-bit limit
    return id;
}

function parsePacket(data) {
    if (data.length < 7) {
        throw new Error('Invalid packet: too short');
    }
    
    const seqField = data.readUInt16BE(3);
    const hasMore = (seqField & 0x8000) !== 0;
    const fragmentNum = seqField & 0x7FFF;
    
    return {
        type: data.readUInt8(0),
        id: data.readUInt16BE(1),
        seq: fragmentNum,
        hasMore: hasMore,
        length: data.readUInt16BE(5),
        payload: data.slice(7)
    };
}

// Status notification functions
function notifyFileAdded(fileId) {
    if (!statusUpdateCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    
    const messageId = getNextMessageId('STATUS');
    const packet = createPacket(config.STATUS_TYPES.FILE_ADDED, messageId, 0, payload, false);
    statusUpdateCallback(packet);
    console.log(`[STATUS] Notified file added: ${fileId} (STATUS Message ID: ${messageId})`);
}

function notifyFileDeleted(fileId) {
    if (!statusUpdateCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    
    const messageId = getNextMessageId('STATUS');
    const packet = createPacket(config.STATUS_TYPES.FILE_DELETED, messageId, 0, payload, false);
    statusUpdateCallback(packet);
    console.log(`[STATUS] Notified file deleted: ${fileId} (STATUS Message ID: ${messageId})`);
}

// File transfer functions
async function startFileTransfer(fileId) {
    if (currentTransfer) {
        console.log('[Transfer] Transfer already in progress');
        return false;
    }
    
    const fileInfo = await fileWatcher.getFileWithHash(fileId);
    if (!fileInfo) {
        console.log(`[Transfer] File not found: ${fileId}`);
        return false;
    }
    
    // Get transfer ID from DATA_TRANSFER characteristic counter
    const transferId = getNextMessageId('DATA_TRANSFER');
    
    console.log(`[Transfer] Starting transfer for file: ${fileInfo.name} (${fileInfo.size} bytes)`);
    console.log(`[Transfer] DATA_TRANSFER ID: ${transferId}, Chunk size: ${config.CHUNK_SIZE} bytes (MTU: ${config.MTU_SIZE})`);
    
    // Read file data
    const fileData = fs.readFileSync(fileInfo.path);
    const totalChunks = Math.ceil(fileData.length / config.CHUNK_SIZE);
    
    currentTransfer = {
        fileInfo: fileInfo,
        fileData: fileData,
        totalChunks: totalChunks,
        currentChunk: 0,
        transferId: transferId
    };
    
    // Send BEGIN_TRANSFER_AUDIO_FILE with metadata
    // Metadata structure: FileID(4) + FileSize(4) + Hash(32) + TotalChunks(2) = 42 bytes
    const metadata = Buffer.alloc(4 + 4 + 32 + 2);
    metadata.writeUInt32BE(fileInfo.id, 0);
    metadata.writeUInt32BE(fileInfo.size, 4);
    
    const hashBuffer = fileInfo.hash.slice(0, 32);
    hashBuffer.copy(metadata, 8);
    
    metadata.writeUInt16BE(totalChunks, 40);
    
    // Use transfer ID for all packets in this transfer session
    const beginPacket = createPacket(
        config.DATA_TRANSFER_TYPES.BEGIN_TRANSFER_AUDIO_FILE,
        currentTransfer.transferId,
        0,  // SEQ=0 for BEGIN packet (single packet, no fragmentation)
        metadata,
        false
    );
    
    // Verify packet size doesn't exceed MTU
    if (beginPacket.length > config.MTU_SIZE) {
        console.error(`[Transfer] BEGIN packet size (${beginPacket.length}) exceeds MTU (${config.MTU_SIZE})`);
        currentTransfer = null;
        return false;
    }
    
    // Send using notify
    if (dataTransferUpdateCallback) {
        dataTransferUpdateCallback(beginPacket);
        console.log(`[Transfer] BEGIN packet sent (DATA_TRANSFER ID: ${transferId})`);
        // Start sending chunks after a small delay
        setTimeout(sendNextChunk, 50);
    } else {
        console.error('[Transfer] No callback available for sending BEGIN packet');
        currentTransfer = null;
        return false;
    }
    
    return true;
}

function sendNextChunk() {
    if (!currentTransfer || !dataTransferUpdateCallback) {
        return;
    }
    
    const { fileData, totalChunks, currentChunk, transferId } = currentTransfer;
    
    if (currentChunk >= totalChunks) {
        // All data chunks sent, now send END_TRANSFER_AUDIO_FILE without data
        sendEndTransfer();
        return;
    }
    
    const start = currentChunk * config.CHUNK_SIZE;
    const end = Math.min(start + config.CHUNK_SIZE, fileData.length);
    const chunk = fileData.slice(start, end);
    
    // Use chunk number as sequence for data transfer packets
    // This maintains the chunk ordering information
    const packet = createPacket(
        config.DATA_TRANSFER_TYPES.TRANSFER_AUDIO_FILE,
        transferId,
        currentChunk,  // Use chunk number as SEQ for ordering
        chunk,
        false  // No MORE flag needed - chunks are already sized for MTU
    );
    
    // Verify packet size doesn't exceed MTU
    if (packet.length > config.MTU_SIZE) {
        console.error(`[Transfer] Packet size (${packet.length}) exceeds MTU (${config.MTU_SIZE}) for chunk ${currentChunk}`);
        currentTransfer = null;
        return;
    }
    
    // Use notify for all data chunks
    dataTransferUpdateCallback(packet);
    console.log(`[Transfer] Sent chunk ${currentChunk + 1}/${totalChunks} (size: ${chunk.length} bytes, SEQ: ${currentChunk})`);
    
    currentTransfer.currentChunk++;
    
    // Schedule next chunk or end transfer
    setTimeout(sendNextChunk, 40); // Small delay to avoid overwhelming the connection
}

function sendEndTransfer() {
    if (!currentTransfer || !dataTransferUpdateCallback) {
        return;
    }
    
    const { transferId, totalChunks } = currentTransfer;
    
    // Send END_TRANSFER_AUDIO_FILE with no payload
    // Use the same transfer ID, SEQ=0 as it's a single packet
    const packet = createPacket(
        config.DATA_TRANSFER_TYPES.END_TRANSFER_AUDIO_FILE,
        transferId,
        0,  // SEQ=0 for END packet (single packet)
        Buffer.alloc(0), // Empty payload
        false  // No MORE flag
    );
    
    // Send using notify
    dataTransferUpdateCallback(packet);
    console.log(`[Transfer] END packet sent (DATA_TRANSFER ID: ${transferId}, Total chunks: ${totalChunks})`);
}

function completeFileTransfer(fileId) {
    if (currentTransfer && currentTransfer.fileInfo.id === fileId) {
        console.log(`[Transfer] Completing transfer for file: ${currentTransfer.fileInfo.name}`);
        currentTransfer = null;
        
        // Delete the file
        if (fileWatcher.removeFile(fileId)) {
            console.log(`[Transfer] File deleted after successful transfer: ${fileId}`);
        }
    }
}

// BLE Characteristics
const controlCharacteristic = new bleno.Characteristic({
    uuid: config.CHARACTERISTICS.CONTROL,
    properties: ['write'],
    onWriteRequest: (data, offset, withoutResponse, callback) => {
        try {
            const packet = parsePacket(data);
            console.log(`[CONTROL] Received packet - Type: 0x${packet.type.toString(16)}, ID: ${packet.id}`);
            
            switch(packet.type) {
                case config.CONTROL_TYPES.START_TRANSFER_AUDIO_FILE:
                    let fileId = null;
                    if (packet.payload.length >= 4) {
                        fileId = packet.payload.readUInt32BE(0);
                    }
                    console.log(`[CONTROL] Start transfer request for file: ${fileId || 'oldest'}`);
                    startFileTransfer(fileId);
                    break;
                    
                case config.CONTROL_TYPES.COMPLETE_TRANSFER_AUDIO_FILE:
                    if (packet.payload.length >= 4) {
                        const fileId = packet.payload.readUInt32BE(0);
                        console.log(`[CONTROL] Complete transfer request for file: ${fileId}`);
                        completeFileTransfer(fileId);
                    }
                    break;
                    
                default:
                    console.log(`[CONTROL] Unknown command type: 0x${packet.type.toString(16)}`);
            }
            
            callback(bleno.Characteristic.RESULT_SUCCESS);
        } catch (error) {
            console.error('[CONTROL] Error processing write request:', error);
            callback(bleno.Characteristic.RESULT_UNLIKELY_ERROR);
        }
    }
});

const statusCharacteristic = new bleno.Characteristic({
    uuid: config.CHARACTERISTICS.STATUS,
    properties: ['notify'],
    onSubscribe: (maxValueSize, updateValueCallback) => {
        console.log(`[STATUS] Client subscribed (max value size: ${maxValueSize})`);
        statusUpdateCallback = updateValueCallback;
        
        // Notify about existing files
        const files = fileWatcher.getAllFiles();
        files.forEach(file => {
            setTimeout(() => notifyFileAdded(file.id), 100);
        });
    },
    onUnsubscribe: () => {
        console.log('[STATUS] Client unsubscribed');
        statusUpdateCallback = null;
    }
});

const dataTransferCharacteristic = new bleno.Characteristic({
    uuid: config.CHARACTERISTICS.DATA_TRANSFER,
    properties: ['notify'],
    onSubscribe: (maxValueSize, updateValueCallback) => {
        console.log(`[DATA_TRANSFER] Client subscribed (max value size: ${maxValueSize})`);
        dataTransferUpdateCallback = updateValueCallback;
    },
    onUnsubscribe: () => {
        console.log('[DATA_TRANSFER] Client unsubscribed');
        dataTransferUpdateCallback = null;
    }
});

// BLE Service
const service = new bleno.PrimaryService({
    uuid: config.SERVICE_UUID,
    characteristics: [
        controlCharacteristic,
        statusCharacteristic,
        dataTransferCharacteristic
    ]
});

// BLE Event handlers
bleno.on('stateChange', (state) => {
    console.log(`[BLE] State changed: ${state}`);
    if (state === 'poweredOn') {
        bleno.startAdvertising(config.LOCAL_NAME, [config.SERVICE_UUID]);
        fileWatcher.start();
    } else {
        bleno.stopAdvertising();
        isConnected = false;
    }
});

bleno.on('advertisingStart', (error) => {
    if (error) {
        console.error('[BLE] Advertising start error:', error);
        return;
    }
    
    console.log('[BLE] Advertising started');
    bleno.setServices([service], (error) => {
        if (error) {
            console.error('[BLE] Set services error:', error);
        } else {
            console.log('[BLE] Services registered');
        }
    });
});

bleno.on('accept', (clientAddress) => {
    console.log(`[BLE] Client connected: ${clientAddress}`);
    isConnected = true;
});

bleno.on('disconnect', (clientAddress) => {
    console.log(`[BLE] Client disconnected: ${clientAddress}`);
    isConnected = false;
    currentTransfer = null;
    statusUpdateCallback = null;
    dataTransferUpdateCallback = null;
    
    // Reset message ID counters on disconnect (optional - comment out to persist across connections)
    // messageIdCounters.CONTROL = 1;
    // messageIdCounters.STATUS = 1;
    // messageIdCounters.DATA_TRANSFER = 1;
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\n[BLE Server] Shutting down...');
    fileWatcher.stop();
    bleno.stopAdvertising();
    process.exit();
});

console.log('[BLE Server] TMS BLE Server starting...');
console.log(`[BLE Server] Audio directory: ${config.AUDIO_DIR.replace(/^~/, os.homedir())}`);
console.log(`[BLE Server] Service UUID: ${config.SERVICE_UUID}`);
console.log(`[BLE Server] MTU: ${config.MTU_SIZE} bytes, Chunk size: ${config.CHUNK_SIZE} bytes`);
console.log(`[BLE Server] ID Counters - CONTROL: ${messageIdCounters.CONTROL}, STATUS: ${messageIdCounters.STATUS}, DATA_TRANSFER: ${messageIdCounters.DATA_TRANSFER}`);
