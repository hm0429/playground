const bleno = require('@abandonware/bleno');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const chokidar = require('chokidar');
const os = require('os');

// BLE Configuration
const LOCAL_NAME = "TMS_BLE_SERVER";
const SERVICE_UUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D0".replace(/-/g, '').toLowerCase();
const CONTROL_UUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D1".replace(/-/g, '').toLowerCase();
const STATUS_UUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D2".replace(/-/g, '').toLowerCase();
const DATA_TRANSFER_UUID = "572542C4-2198-4D1E-9820-1FEAEA1BB9D3".replace(/-/g, '').toLowerCase();

// Protocol Types
const CONTROL_TYPE = {
    START_TRANSFER_AUDIO_FILE: 0x01,
    COMPLETE_TRANSFER_AUDIO_FILE: 0x02,
    BEGIN_TRANSFER_AUDIO_FILE: 0x21,
    END_TRANSFER_AUDIO_FILE: 0x22
};

const STATUS_TYPE = {
    FILE_ADDED: 0x40,
    FILE_DELETED: 0x41
};

const DATA_TRANSFER_TYPE = {
    TRANSFER_AUDIO_FILE: 0x80
};

// Configuration
const RECORDINGS_DIR = path.join(os.homedir(), '.tms', 'recordings');
const CHUNK_SIZE = 500; // BLE MTU minus protocol overhead
const MTU_SIZE = 512; // iOS default MTU

// State management
let connectedClient = null;
let statusUpdateCallback = null;
let controlIndicateCallback = null;
let dataTransferUpdateCallback = null;
let currentTransfer = null;
let messageIdCounters = {
    control: 0,
    status: 0,
    dataTransfer: 0
};

// Ensure recordings directory exists
if (!fs.existsSync(RECORDINGS_DIR)) {
    fs.mkdirSync(RECORDINGS_DIR, { recursive: true });
    console.log(`[Server] Created recordings directory: ${RECORDINGS_DIR}`);
}

// Helper functions
function getNextMessageId(characteristic) {
    messageIdCounters[characteristic] = (messageIdCounters[characteristic] + 1) & 0xFFFF;
    return messageIdCounters[characteristic];
}

function createPacket(type, messageId, seq, payload) {
    const header = Buffer.alloc(7);
    header[0] = type;
    header.writeUInt16BE(messageId, 1);
    header.writeUInt16BE(seq, 3);
    header.writeUInt16BE(payload.length, 5);
    return Buffer.concat([header, payload]);
}

function parsePacket(data) {
    if (data.length < 7) {
        throw new Error('Invalid packet: too short');
    }
    
    const type = data[0];
    const messageId = data.readUInt16BE(1);
    const seq = data.readUInt16BE(3);
    const length = data.readUInt16BE(5);
    const payload = data.slice(7, 7 + length);
    
    return { type, messageId, seq, length, payload };
}

function getFileIdFromFilename(filename) {
    // Extract YYYYMMDDHHMMSS from filename
    const match = filename.match(/(\d{14})\.mp3$/);
    if (!match) return null;
    
    const dateStr = match[1];
    const year = parseInt(dateStr.substr(0, 4));
    const month = parseInt(dateStr.substr(4, 2)) - 1;
    const day = parseInt(dateStr.substr(6, 2));
    const hour = parseInt(dateStr.substr(8, 2));
    const minute = parseInt(dateStr.substr(10, 2));
    const second = parseInt(dateStr.substr(12, 2));
    
    const date = new Date(year, month, day, hour, minute, second);
    return Math.floor(date.getTime() / 1000); // Unix timestamp in seconds
}

function getFilenameFromFileId(fileId) {
    const date = new Date(fileId * 1000);
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const hour = String(date.getHours()).padStart(2, '0');
    const minute = String(date.getMinutes()).padStart(2, '0');
    const second = String(date.getSeconds()).padStart(2, '0');
    
    return `${year}${month}${day}${hour}${minute}${second}.mp3`;
}

function getAudioFiles() {
    try {
        const files = fs.readdirSync(RECORDINGS_DIR)
            .filter(f => f.endsWith('.mp3'))
            .map(f => ({
                filename: f,
                fileId: getFileIdFromFilename(f),
                path: path.join(RECORDINGS_DIR, f),
                stats: fs.statSync(path.join(RECORDINGS_DIR, f))
            }))
            .filter(f => f.fileId !== null)
            .sort((a, b) => a.fileId - b.fileId);
        return files;
    } catch (error) {
        console.error(`[Server] Error reading audio files: ${error.message}`);
        return [];
    }
}

function getOldestFile() {
    const files = getAudioFiles();
    return files.length > 0 ? files[0] : null;
}

function getFileByFileId(fileId) {
    const filename = getFilenameFromFileId(fileId);
    const filepath = path.join(RECORDINGS_DIR, filename);
    
    if (fs.existsSync(filepath)) {
        return {
            filename: filename,
            fileId: fileId,
            path: filepath,
            stats: fs.statSync(filepath)
        };
    }
    return null;
}

function calculateFileHash(filepath) {
    const fileBuffer = fs.readFileSync(filepath);
    return crypto.createHash('sha256').update(fileBuffer).digest();
}

// BLE Characteristics
class ControlCharacteristic extends bleno.Characteristic {
    constructor() {
        super({
            uuid: CONTROL_UUID,
            properties: ['write', 'indicate'],
            descriptors: [
                new bleno.Descriptor({
                    uuid: '2901',
                    value: 'Control commands'
                })
            ]
        });
    }
    
    onWriteRequest(data, offset, withoutResponse, callback) {
        try {
            const packet = parsePacket(data);
            console.log(`[Control] Received write - Type: 0x${packet.type.toString(16)}, ID: ${packet.messageId}, SEQ: ${packet.seq}`);
            
            switch (packet.type) {
                case CONTROL_TYPE.START_TRANSFER_AUDIO_FILE:
                    this.handleStartTransfer(packet);
                    break;
                case CONTROL_TYPE.COMPLETE_TRANSFER_AUDIO_FILE:
                    this.handleCompleteTransfer(packet);
                    break;
                default:
                    console.log(`[Control] Unknown type: 0x${packet.type.toString(16)}`);
            }
            
            callback(bleno.Characteristic.RESULT_SUCCESS);
        } catch (error) {
            console.error(`[Control] Write error: ${error.message}`);
            callback(bleno.Characteristic.RESULT_UNLIKELY_ERROR);
        }
    }
    
    handleStartTransfer(packet) {
        let file = null;
        
        if (packet.payload.length === 4) {
            // File ID provided
            const fileId = packet.payload.readUInt32BE(0);
            console.log(`[Control] START_TRANSFER requested for File ID: ${fileId}`);
            file = getFileByFileId(fileId);
        } else {
            // No File ID, get oldest file
            console.log(`[Control] START_TRANSFER requested for oldest file`);
            file = getOldestFile();
        }
        
        if (!file) {
            console.log(`[Control] No file found for transfer`);
            return;
        }
        
        console.log(`[Control] Starting transfer for file: ${file.filename}`);
        this.startFileTransfer(file);
    }
    
    startFileTransfer(file) {
        try {
            const fileData = fs.readFileSync(file.path);
            const fileHash = calculateFileHash(file.path);
            const totalChunks = Math.ceil(fileData.length / CHUNK_SIZE);
            
            // Prepare transfer state
            currentTransfer = {
                fileId: file.fileId,
                filename: file.filename,
                filepath: file.path,
                fileData: fileData,
                fileHash: fileHash,
                totalChunks: totalChunks,
                currentChunk: 0,
                messageId: getNextMessageId('control')
            };
            
            // Send BEGIN_TRANSFER_AUDIO_FILE
            const metadata = Buffer.alloc(42);
            metadata.writeUInt32BE(file.fileId, 0);
            metadata.writeUInt32BE(fileData.length, 4);
            fileHash.copy(metadata, 8);
            metadata.writeUInt16BE(totalChunks, 40);
            
            const beginPacket = createPacket(
                CONTROL_TYPE.BEGIN_TRANSFER_AUDIO_FILE,
                currentTransfer.messageId,
                0, // Single packet, no fragmentation
                metadata
            );
            
            if (controlIndicateCallback) {
                console.log(`[Control] Sending BEGIN_TRANSFER - File ID: ${file.fileId}, Size: ${fileData.length}, Chunks: ${totalChunks}`);
                controlIndicateCallback(beginPacket);
                
                // Start sending data chunks after a short delay
                setTimeout(() => this.sendNextChunk(), 100);
            }
        } catch (error) {
            console.error(`[Control] Error starting transfer: ${error.message}`);
            currentTransfer = null;
        }
    }
    
    sendNextChunk() {
        if (!currentTransfer || !dataTransferUpdateCallback) {
            return;
        }
        
        if (currentTransfer.currentChunk >= currentTransfer.totalChunks) {
            // All chunks sent, send END_TRANSFER
            this.sendEndTransfer();
            return;
        }
        
        const start = currentTransfer.currentChunk * CHUNK_SIZE;
        const end = Math.min(start + CHUNK_SIZE, currentTransfer.fileData.length);
        const chunkData = currentTransfer.fileData.slice(start, end);
        
        const packet = createPacket(
            DATA_TRANSFER_TYPE.TRANSFER_AUDIO_FILE,
            currentTransfer.messageId,
            currentTransfer.currentChunk,
            chunkData
        );
        
        console.log(`[DataTransfer] Sending chunk ${currentTransfer.currentChunk + 1}/${currentTransfer.totalChunks} (${chunkData.length} bytes)`);
        dataTransferUpdateCallback(packet);
        
        currentTransfer.currentChunk++;
        
        // Continue sending next chunk
        setTimeout(() => this.sendNextChunk(), 20);
    }
    
    sendEndTransfer() {
        if (!currentTransfer || !controlIndicateCallback) {
            return;
        }
        
        const payload = Buffer.alloc(4);
        payload.writeUInt32BE(currentTransfer.fileId, 0);
        
        const endPacket = createPacket(
            CONTROL_TYPE.END_TRANSFER_AUDIO_FILE,
            currentTransfer.messageId,
            0,
            payload
        );
        
        console.log(`[Control] Sending END_TRANSFER for File ID: ${currentTransfer.fileId}`);
        controlIndicateCallback(endPacket);
    }
    
    handleCompleteTransfer(packet) {
        if (packet.payload.length !== 4) {
            console.log(`[Control] Invalid COMPLETE_TRANSFER payload`);
            return;
        }
        
        const fileId = packet.payload.readUInt32BE(0);
        console.log(`[Control] COMPLETE_TRANSFER received for File ID: ${fileId}`);
        
        // Delete the file
        const file = getFileByFileId(fileId);
        if (file) {
            try {
                fs.unlinkSync(file.path);
                console.log(`[Control] Deleted file: ${file.filename}`);
                
                // Send FILE_DELETED notification
                sendFileDeletedNotification(fileId);
            } catch (error) {
                console.error(`[Control] Error deleting file: ${error.message}`);
            }
        }
        
        // Clear transfer state
        currentTransfer = null;
    }
    
    onSubscribe(maxValueSize, updateValueCallback) {
        console.log(`[Control] Client subscribed to indications`);
        controlIndicateCallback = updateValueCallback;
    }
    
    onUnsubscribe() {
        console.log(`[Control] Client unsubscribed from indications`);
        controlIndicateCallback = null;
    }
}

class StatusCharacteristic extends bleno.Characteristic {
    constructor() {
        super({
            uuid: STATUS_UUID,
            properties: ['notify'],
            descriptors: [
                new bleno.Descriptor({
                    uuid: '2901',
                    value: 'Status notifications'
                })
            ]
        });
    }
    
    onSubscribe(maxValueSize, updateValueCallback) {
        console.log(`[Status] Client subscribed to notifications`);
        statusUpdateCallback = updateValueCallback;
    }
    
    onUnsubscribe() {
        console.log(`[Status] Client unsubscribed from notifications`);
        statusUpdateCallback = null;
    }
}

class DataTransferCharacteristic extends bleno.Characteristic {
    constructor() {
        super({
            uuid: DATA_TRANSFER_UUID,
            properties: ['notify'],
            descriptors: [
                new bleno.Descriptor({
                    uuid: '2901',
                    value: 'Data transfer'
                })
            ]
        });
    }
    
    onSubscribe(maxValueSize, updateValueCallback) {
        console.log(`[DataTransfer] Client subscribed to notifications`);
        dataTransferUpdateCallback = updateValueCallback;
    }
    
    onUnsubscribe() {
        console.log(`[DataTransfer] Client unsubscribed from notifications`);
        dataTransferUpdateCallback = null;
    }
}

// Status notifications
function sendFileAddedNotification(fileId) {
    if (!statusUpdateCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    
    const packet = createPacket(
        STATUS_TYPE.FILE_ADDED,
        getNextMessageId('status'),
        0,
        payload
    );
    
    console.log(`[Status] Sending FILE_ADDED notification for File ID: ${fileId}`);
    statusUpdateCallback(packet);
}

function sendFileDeletedNotification(fileId) {
    if (!statusUpdateCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    
    const packet = createPacket(
        STATUS_TYPE.FILE_DELETED,
        getNextMessageId('status'),
        0,
        payload
    );
    
    console.log(`[Status] Sending FILE_DELETED notification for File ID: ${fileId}`);
    statusUpdateCallback(packet);
}

// File monitoring
const watcher = chokidar.watch(RECORDINGS_DIR, {
    persistent: true,
    ignoreInitial: true,
    awaitWriteFinish: {
        stabilityThreshold: 2000,
        pollInterval: 100
    }
});

watcher.on('add', (filepath) => {
    const filename = path.basename(filepath);
    if (filename.endsWith('.mp3')) {
        const fileId = getFileIdFromFilename(filename);
        if (fileId) {
            console.log(`[FileMonitor] New file detected: ${filename} (File ID: ${fileId})`);
            sendFileAddedNotification(fileId);
        }
    }
});

watcher.on('unlink', (filepath) => {
    const filename = path.basename(filepath);
    if (filename.endsWith('.mp3')) {
        const fileId = getFileIdFromFilename(filename);
        if (fileId) {
            console.log(`[FileMonitor] File deleted: ${filename} (File ID: ${fileId})`);
            sendFileDeletedNotification(fileId);
        }
    }
});

// BLE Service
const controlCharacteristic = new ControlCharacteristic();
const statusCharacteristic = new StatusCharacteristic();
const dataTransferCharacteristic = new DataTransferCharacteristic();

const service = new bleno.PrimaryService({
    uuid: SERVICE_UUID,
    characteristics: [
        controlCharacteristic,
        statusCharacteristic,
        dataTransferCharacteristic
    ]
});

// BLE Event Handlers
bleno.on('stateChange', (state) => {
    console.log(`[BLE] State changed: ${state}`);
    if (state === 'poweredOn') {
        bleno.startAdvertising(LOCAL_NAME, [SERVICE_UUID]);
    } else {
        bleno.stopAdvertising();
    }
});

bleno.on('advertisingStart', (error) => {
    if (error) {
        console.error(`[BLE] Advertising start error: ${error}`);
        return;
    }
    
    console.log(`[BLE] Advertising started - Name: ${LOCAL_NAME}, Service UUID: ${SERVICE_UUID}`);
    bleno.setServices([service]);
});

bleno.on('accept', (clientAddress) => {
    console.log(`[BLE] Client connected: ${clientAddress}`);
    connectedClient = clientAddress;
});

bleno.on('disconnect', (clientAddress) => {
    console.log(`[BLE] Client disconnected: ${clientAddress}`);
    connectedClient = null;
    
    // Reset all states
    currentTransfer = null;
    statusUpdateCallback = null;
    controlIndicateCallback = null;
    dataTransferUpdateCallback = null;
    messageIdCounters = {
        control: 0,
        status: 0,
        dataTransfer: 0
    };
    
    console.log(`[BLE] All states reset`);
});

// Startup
console.log(`[Server] TMS BLE Server starting...`);
console.log(`[Server] Recordings directory: ${RECORDINGS_DIR}`);
console.log(`[Server] Found ${getAudioFiles().length} audio files`);
