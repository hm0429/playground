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
let dataTransferIndicateCallback = null;
let currentTransfer = null;
let isConnected = false;
let nextTransferId = 1; // Transfer ID counter (increments for each transfer)

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
function createPacket(type, id = 0, seq = 0, payload = Buffer.alloc(0)) {
    const header = Buffer.alloc(7);
    header.writeUInt8(type, 0);              // TYPE (1 byte)
    header.writeUInt16BE(id, 1);             // ID (2 bytes)
    header.writeUInt16BE(seq, 3);            // SEQ (2 bytes)
    header.writeUInt16BE(payload.length, 5); // LENGTH (2 bytes)
    
    return Buffer.concat([header, payload]);
}

function parsePacket(data) {
    if (data.length < 7) {
        throw new Error('Invalid packet: too short');
    }
    
    return {
        type: data.readUInt8(0),
        id: data.readUInt16BE(1),
        seq: data.readUInt16BE(3),
        length: data.readUInt16BE(5),
        payload: data.slice(7)
    };
}

// Status notification functions
function notifyFileAdded(fileId) {
    if (!statusUpdateCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    
    const packet = createPacket(config.STATUS_TYPES.FILE_ADDED, 0, 0, payload);
    statusUpdateCallback(packet);
    console.log(`[STATUS] Notified file added: ${fileId}`);
}

function notifyFileDeleted(fileId) {
    if (!statusUpdateCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    
    const packet = createPacket(config.STATUS_TYPES.FILE_DELETED, 0, 0, payload);
    statusUpdateCallback(packet);
    console.log(`[STATUS] Notified file deleted: ${fileId}`);
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
    
    console.log(`[Transfer] Starting transfer #${nextTransferId} for file: ${fileInfo.name} (${fileInfo.size} bytes)`);
    console.log(`[Transfer] Using chunk size: ${config.CHUNK_SIZE} bytes (MTU: ${config.MTU_SIZE}, Header: ${config.HEADER_SIZE})`);
    
    // Read file data
    const fileData = fs.readFileSync(fileInfo.path);
    const totalChunks = Math.ceil(fileData.length / config.CHUNK_SIZE);
    
    // Use incremental transfer ID and wrap around at 16-bit limit
    const transferId = nextTransferId;
    nextTransferId = (nextTransferId + 1) % 65536; // Wrap around at 2^16
    
    currentTransfer = {
        fileInfo: fileInfo,
        fileData: fileData,
        totalChunks: totalChunks,
        currentChunk: 0,
        transferId: transferId
    };
    
    // Send BEGIN_TRANSFER_AUDIO_FILE with metadata (using indicate)
    // Metadata structure: FileID(4) + FileSize(4) + Hash(32) + TotalChunks(2) = 42 bytes
    const metadata = Buffer.alloc(4 + 4 + 32 + 2);
    metadata.writeUInt32BE(fileInfo.id, 0);
    metadata.writeUInt32BE(fileInfo.size, 4);
    
    const hashBuffer = fileInfo.hash.slice(0, 32);
    hashBuffer.copy(metadata, 8);
    
    metadata.writeUInt16BE(totalChunks, 40);
    
    const beginPacket = createPacket(
        config.DATA_TRANSFER_TYPES.BEGIN_TRANSFER_AUDIO_FILE,
        currentTransfer.transferId,
        0,
        metadata
    );
    
    // Verify packet size doesn't exceed MTU
    if (beginPacket.length > config.MTU_SIZE) {
        console.error(`[Transfer] BEGIN packet size (${beginPacket.length}) exceeds MTU (${config.MTU_SIZE})`);
        currentTransfer = null;
        return false;
    }
    
    if (dataTransferIndicateCallback) {
        dataTransferIndicateCallback(beginPacket, (error) => {
            if (!error) {
                console.log(`[Transfer] BEGIN packet indicated successfully (Transfer ID: ${transferId})`);
                // Start sending chunks
                sendNextChunk();
            } else {
                console.error('[Transfer] Failed to indicate BEGIN packet:', error);
                currentTransfer = null;
            }
        });
    }
    
    return true;
}

function sendNextChunk() {
    if (!currentTransfer || !dataTransferUpdateCallback) {
        return;
    }
    
    const { fileData, totalChunks, currentChunk, transferId } = currentTransfer;
    
    if (currentChunk >= totalChunks) {
        console.log('[Transfer] All chunks sent');
        return;
    }
    
    const start = currentChunk * config.CHUNK_SIZE;
    const end = Math.min(start + config.CHUNK_SIZE, fileData.length);
    const chunk = fileData.slice(start, end);
    
    const isLastChunk = (currentChunk === totalChunks - 1);
    const packetType = isLastChunk 
        ? config.DATA_TRANSFER_TYPES.END_TRANSFER_AUDIO_FILE
        : config.DATA_TRANSFER_TYPES.TRANSFER_AUDIO_FILE;
    
    const packet = createPacket(
        packetType,
        transferId,
        currentChunk,
        chunk
    );
    
    // Verify packet size doesn't exceed MTU
    if (packet.length > config.MTU_SIZE) {
        console.error(`[Transfer] Packet size (${packet.length}) exceeds MTU (${config.MTU_SIZE}) for chunk ${currentChunk}`);
        currentTransfer = null;
        return;
    }
    
    if (isLastChunk && dataTransferIndicateCallback) {
        // Use indicate for last chunk
        dataTransferIndicateCallback(packet, (error) => {
            if (!error) {
                console.log(`[Transfer] END packet indicated successfully (chunk ${currentChunk + 1}/${totalChunks}, size: ${chunk.length} bytes)`);
            } else {
                console.error('[Transfer] Failed to indicate END packet:', error);
            }
        });
    } else {
        // Use notify for intermediate chunks
        dataTransferUpdateCallback(packet);
        console.log(`[Transfer] Sent chunk ${currentChunk + 1}/${totalChunks} (size: ${chunk.length} bytes)`);
    }
    
    currentTransfer.currentChunk++;
    
    // Schedule next chunk
    if (!isLastChunk) {
        setTimeout(sendNextChunk, 10); // Small delay to avoid overwhelming the connection
    }
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
    properties: ['notify', 'indicate'],
    onSubscribe: (maxValueSize, updateValueCallback) => {
        console.log(`[DATA_TRANSFER] Client subscribed for notify (max value size: ${maxValueSize})`);
        dataTransferUpdateCallback = updateValueCallback;
    },
    onUnsubscribe: () => {
        console.log('[DATA_TRANSFER] Client unsubscribed from notify');
        dataTransferUpdateCallback = null;
    },
    onIndicate: (updateValueCallback) => {
        console.log('[DATA_TRANSFER] Client subscribed for indicate');
        dataTransferIndicateCallback = updateValueCallback;
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
    dataTransferIndicateCallback = null;
    // Optionally reset transfer ID on disconnect (comment out to keep incrementing across sessions)
    // nextTransferId = 1;
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
