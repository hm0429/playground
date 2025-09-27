const bleno = require('@abandonware/bleno');
const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const config = require('./config');

// Global state
let autoTransferMode = false;
let currentTransferId = 0;
let fileMap = new Map(); // Map of File ID to file path
let activeTransfer = null;
let connectedCentral = null;

// Logging function
function log(message) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${message}`);
  
  // Append to log file
  const logEntry = `[${timestamp}] ${message}\n`;
  fs.appendFileSync(path.join(__dirname, 'AGENT_LOG.md'), logEntry);
}

// Initialize log file
function initLogFile() {
  const logPath = path.join(__dirname, 'AGENT_LOG.md');
  if (!fs.existsSync(logPath)) {
    const header = `# TMS BLE Server Agent Log\n\n`;
    fs.writeFileSync(logPath, header);
  }
  log('BLE Server started');
}

// Generate File ID from timestamp
function generateFileId(filePath) {
  const stats = fs.statSync(filePath);
  return Math.floor(stats.mtimeMs / 1000); // Unix timestamp in seconds
}

// Calculate file hash
function calculateFileHash(filePath) {
  const fileBuffer = fs.readFileSync(filePath);
  const hashSum = crypto.createHash('sha256');
  hashSum.update(fileBuffer);
  return hashSum.digest();
}

// Create buffer with common header (Type, ID, SEQ, Payload Length)
function createPacket(type, id, seq, payload) {
  const header = Buffer.alloc(9);
  header.writeUInt8(type, 0);
  header.writeUInt32BE(id, 1);
  header.writeUInt16BE(seq, 5);
  header.writeUInt16BE(payload ? payload.length : 0, 7);
  
  if (payload) {
    return Buffer.concat([header, payload]);
  }
  return header;
}

// CONTROL Characteristic - handles commands from Central
class ControlCharacteristic extends bleno.Characteristic {
  constructor() {
    super({
      uuid: config.CONTROL_UUID.replace(/-/g, ''),
      properties: ['write', 'writeWithoutResponse']
    });
  }

  onWriteRequest(data, offset, withoutResponse, callback) {
    try {
      if (data.length < 9) {
        log('Invalid CONTROL command: insufficient data');
        callback(bleno.Characteristic.RESULT_INVALID_ATTRIBUTE_LENGTH);
        return;
      }

      const command = data.readUInt8(0);
      const id = data.readUInt32BE(1);
      const seq = data.readUInt16BE(5);
      const payloadLength = data.readUInt16BE(7);
      
      log(`Received CONTROL command: 0x${command.toString(16)}, ID: ${id}, SEQ: ${seq}`);

      switch (command) {
        case config.COMMANDS.START_TRANSFER_AUDIO_FILE:
          if (payloadLength >= 4) {
            const fileId = data.readUInt32BE(9);
            handleStartTransfer(fileId);
          }
          break;
          
        case config.COMMANDS.START_TRANSFER_AUDIO_FILE_AUTO:
          autoTransferMode = true;
          log('Auto transfer mode enabled');
          checkAndTransferPendingFiles();
          break;
          
        case config.COMMANDS.STOP_TRANSFER_AUDIO_FILE_AUTO:
          autoTransferMode = false;
          log('Auto transfer mode disabled');
          break;
          
        case config.COMMANDS.COMPLETE_TRANSFER_AUDIO_FILE:
          if (payloadLength >= 4) {
            const fileId = data.readUInt32BE(9);
            handleCompleteTransfer(fileId);
          }
          break;
          
        default:
          log(`Unknown command: 0x${command.toString(16)}`);
      }
      
      callback(bleno.Characteristic.RESULT_SUCCESS);
    } catch (error) {
      log(`Error in CONTROL write: ${error.message}`);
      callback(bleno.Characteristic.RESULT_UNLIKELY_ERROR);
    }
  }
}

// STATUS Characteristic - notifies Central of file changes
class StatusCharacteristic extends bleno.Characteristic {
  constructor() {
    super({
      uuid: config.STATUS_UUID.replace(/-/g, ''),
      properties: ['notify']
    });
    this.updateValueCallback = null;
  }

  onSubscribe(maxValueSize, updateValueCallback) {
    log('Central subscribed to STATUS notifications');
    this.updateValueCallback = updateValueCallback;
    connectedCentral = this;
  }

  onUnsubscribe() {
    log('Central unsubscribed from STATUS notifications');
    this.updateValueCallback = null;
    connectedCentral = null;
  }

  notifyFileStatus(type, fileId) {
    if (!this.updateValueCallback) return;
    
    const payload = Buffer.alloc(4);
    payload.writeUInt32BE(fileId, 0);
    const packet = createPacket(type, ++currentTransferId, 0, payload);
    
    this.updateValueCallback(packet);
    log(`Notified STATUS: type=0x${type.toString(16)}, fileId=${fileId}`);
  }
}

// DATA_TRANSFER Characteristic - handles actual file transfer
class DataTransferCharacteristic extends bleno.Characteristic {
  constructor() {
    super({
      uuid: config.DATA_TRANSFER_UUID.replace(/-/g, ''),
      properties: ['notify']
    });
    this.updateValueCallback = null;
  }

  onSubscribe(maxValueSize, updateValueCallback) {
    log('Central subscribed to DATA_TRANSFER notifications');
    this.updateValueCallback = updateValueCallback;
  }

  onUnsubscribe() {
    log('Central unsubscribed from DATA_TRANSFER notifications');
    this.updateValueCallback = null;
  }

  async transferFile(fileId, filePath) {
    if (!this.updateValueCallback) {
      log('No subscriber for DATA_TRANSFER');
      return false;
    }

    try {
      // Read file
      const fileData = fs.readFileSync(filePath);
      const fileSize = fileData.length;
      const fileHash = calculateFileHash(filePath);
      
      // Calculate chunks
      const chunkSize = config.DATA_CHUNK_SIZE;
      const totalChunks = Math.ceil(fileSize / chunkSize);
      
      log(`Starting transfer: fileId=${fileId}, size=${fileSize}, chunks=${totalChunks}`);
      log(`  Hash: ${fileHash.toString('hex').substring(0, 16)}...`);
      
      // Send BEGIN packet with metadata
      const metadataBuffer = Buffer.alloc(266);
      metadataBuffer.writeUInt32BE(fileId, 0);
      metadataBuffer.writeUInt32BE(fileSize, 4);
      fileHash.copy(metadataBuffer, 8);
      metadataBuffer.writeUInt16BE(totalChunks, 264);
      
      const beginPacket = createPacket(
        config.TRANSFER_FLAGS.BEGIN_TRANSFER_AUDIO_FILE,
        ++currentTransferId,
        totalChunks - 1, // SEQ starts from totalChunks-1 and decrements
        metadataBuffer
      );
      
      this.updateValueCallback(beginPacket);
      await sleep(50); // Small delay between packets
      
      // Send data chunks
      let sentBytes = 0;
      for (let i = 0; i < totalChunks; i++) {
        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, fileSize);
        const chunk = fileData.slice(start, end);
        const seq = totalChunks - 1 - i; // Decrementing sequence
        sentBytes += chunk.length;
        
        const flag = (i === totalChunks - 1) 
          ? config.TRANSFER_FLAGS.END_TRANSFER_AUDIO_FILE
          : config.TRANSFER_FLAGS.CONTINUE_TRANSFER_AUDIO_FILE;
        
        const dataPacket = createPacket(
          flag,
          ++currentTransferId,
          seq,
          chunk
        );
        
        this.updateValueCallback(dataPacket);
        
        // Enhanced logging
        if (i === 0) {
          log(`  First chunk: seq=${seq}, size=${chunk.length} bytes`);
        } else if (i === totalChunks - 1) {
          log(`  Last chunk: seq=${seq}, size=${chunk.length} bytes`);
          log(`  Total sent: ${sentBytes} bytes (expected: ${fileSize} bytes)`);
        } else if (i % 10 === 0) {
          log(`  Progress: ${i + 1}/${totalChunks} chunks, sent: ${sentBytes} bytes`);
        }
        
        await sleep(20); // Delay between chunks to avoid overwhelming
      }
      
      log(`Transfer completed: fileId=${fileId}`);
      log(`  Final hash: ${fileHash.toString('hex').substring(0, 16)}...`);
      log(`  Bytes sent: ${sentBytes}/${fileSize}`);
      return true;
      
    } catch (error) {
      log(`Error transferring file: ${error.message}`);
      return false;
    }
  }
}

// Sleep utility
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Create instances of characteristics
const controlCharacteristic = new ControlCharacteristic();
const statusCharacteristic = new StatusCharacteristic();
const dataTransferCharacteristic = new DataTransferCharacteristic();

// BLE Service
class TMSAudioService extends bleno.PrimaryService {
  constructor() {
    super({
      uuid: config.SERVICE_UUID.replace(/-/g, ''),
      characteristics: [
        controlCharacteristic,
        statusCharacteristic,
        dataTransferCharacteristic
      ]
    });
  }
}

// File handling functions
function handleStartTransfer(fileId) {
  const filePath = fileMap.get(fileId);
  if (!filePath) {
    log(`File not found for ID: ${fileId}`);
    return;
  }
  
  if (activeTransfer) {
    log(`Transfer already in progress for ID: ${activeTransfer.fileId}`);
    return;
  }
  
  activeTransfer = { fileId, filePath };
  
  // Start transfer asynchronously
  dataTransferCharacteristic.transferFile(fileId, filePath).then(success => {
    if (success) {
      log(`Transfer successful: ${fileId}`);
    }
    activeTransfer = null;
    
    // Check for more files in auto mode
    if (autoTransferMode) {
      setTimeout(() => checkAndTransferPendingFiles(), 1000);
    }
  });
}

function handleCompleteTransfer(fileId) {
  const filePath = fileMap.get(fileId);
  if (!filePath) {
    log(`File not found for completion: ${fileId}`);
    return;
  }
  
  try {
    fs.unlinkSync(filePath);
    fileMap.delete(fileId);
    log(`File deleted after transfer: ${filePath}`);
    statusCharacteristic.notifyFileStatus(config.STATUS_TYPES.FILE_DELETED, fileId);
  } catch (error) {
    log(`Error deleting file: ${error.message}`);
  }
}

function checkAndTransferPendingFiles() {
  if (!autoTransferMode || activeTransfer) return;
  
  // Find oldest file not yet transferred
  const fileIds = Array.from(fileMap.keys()).sort((a, b) => a - b);
  if (fileIds.length > 0) {
    const fileId = fileIds[0];
    log(`Auto-transferring file: ${fileId}`);
    handleStartTransfer(fileId);
  }
}

// File monitoring
function setupFileWatcher() {
  const watchPath = path.resolve(__dirname, config.WATCH_DIR);
  
  // Create directory if it doesn't exist
  if (!fs.existsSync(watchPath)) {
    fs.mkdirSync(watchPath, { recursive: true });
    log(`Created watch directory: ${watchPath}`);
  }
  
  // Initialize with existing files
  const existingFiles = fs.readdirSync(watchPath)
    .filter(file => file.endsWith(config.FILE_EXTENSION));
  
  existingFiles.forEach(file => {
    const filePath = path.join(watchPath, file);
    const fileId = generateFileId(filePath);
    fileMap.set(fileId, filePath);
    log(`Found existing file: ${file} (ID: ${fileId})`);
  });
  
  // Watch for changes
  const watcher = chokidar.watch(watchPath, {
    ignored: /(^|[\/\\])\../,
    persistent: true,
    awaitWriteFinish: {
      stabilityThreshold: 2000,
      pollInterval: 100
    }
  });
  
  watcher
    .on('add', filePath => {
      if (!filePath.endsWith(config.FILE_EXTENSION)) return;
      
      const fileId = generateFileId(filePath);
      fileMap.set(fileId, filePath);
      log(`File added: ${path.basename(filePath)} (ID: ${fileId})`);
      
      // Notify Central
      statusCharacteristic.notifyFileStatus(config.STATUS_TYPES.FILE_ADDED, fileId);
      
      // Auto transfer if enabled
      if (autoTransferMode && !activeTransfer) {
        setTimeout(() => handleStartTransfer(fileId), 1000);
      }
    })
    .on('unlink', filePath => {
      if (!filePath.endsWith(config.FILE_EXTENSION)) return;
      
      // Find and remove from map
      for (const [fileId, path] of fileMap.entries()) {
        if (path === filePath) {
          fileMap.delete(fileId);
          log(`File removed: ${path.basename(filePath)} (ID: ${fileId})`);
          statusCharacteristic.notifyFileStatus(config.STATUS_TYPES.FILE_DELETED, fileId);
          break;
        }
      }
    })
    .on('error', error => log(`Watcher error: ${error}`));
  
  log(`Monitoring directory: ${watchPath}`);
}

// BLE event handlers
bleno.on('stateChange', state => {
  log(`BLE state changed: ${state}`);
  
  if (state === 'poweredOn') {
    bleno.startAdvertising(config.DEVICE_NAME, [config.SERVICE_UUID.replace(/-/g, '')]);
  } else {
    bleno.stopAdvertising();
  }
});

bleno.on('advertisingStart', error => {
  if (error) {
    log(`Advertising error: ${error}`);
    return;
  }
  
  log(`Advertising started: ${config.DEVICE_NAME}`);
  bleno.setServices([new TMSAudioService()]);
});

bleno.on('accept', clientAddress => {
  log(`Central connected: ${clientAddress}`);
});

bleno.on('disconnect', clientAddress => {
  log(`Central disconnected: ${clientAddress}`);
  connectedCentral = null;
  activeTransfer = null;
  autoTransferMode = false;
});

// Graceful shutdown
process.on('SIGINT', () => {
  log('Shutting down BLE server...');
  bleno.stopAdvertising();
  process.exit(0);
});

// Start the server
initLogFile();
setupFileWatcher();
log('TMS BLE Server initialized');
log(`Service UUID: ${config.SERVICE_UUID}`);
log(`Watching: ${path.resolve(__dirname, config.WATCH_DIR)}`);
