const bleno = require('@abandonware/bleno');
const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const config = require('./config');

// Global state
let currentTransferId = 0;
let fileMap = new Map(); // Map of File ID to file path
let activeTransfer = null;
let connectedCentral = null;

// Logging function
function log(message) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${message}`);
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
  const header = Buffer.alloc(7);
  header.writeUInt8(type, 0);
  header.writeUInt16BE(id, 1);
  header.writeUInt16BE(seq, 3);
  header.writeUInt16BE(payload ? payload.length : 0, 5);
  
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
      if (data.length < 7) {
        log('Invalid CONTROL command: insufficient data');
        callback(bleno.Characteristic.RESULT_INVALID_ATTRIBUTE_LENGTH);
        return;
      }

      const command = data.readUInt8(0);
      const id = data.readUInt16BE(1);
      const seq = data.readUInt16BE(3);
      const payloadLength = data.readUInt16BE(5);
      
      log(`Received CONTROL command: 0x${command.toString(16)}, ID: ${id}, SEQ: ${seq}`);

      switch (command) {
        case config.COMMANDS.START_TRANSFER_AUDIO_FILE:
          if (payloadLength >= 4) {
            const fileId = data.readUInt32BE(7);
            handleStartTransfer(fileId);
          } else {
            // If no file ID specified, transfer the oldest file
            handleStartTransfer(null);
          }
          break;
          
        case config.COMMANDS.COMPLETE_TRANSFER_AUDIO_FILE:
          if (payloadLength >= 4) {
            const fileId = data.readUInt32BE(7);
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
      
      // Use a single transfer ID for the entire transfer
      const transferId = ++currentTransferId;
      
      log(`Starting transfer: fileId=${fileId}, transferId=${transferId}, size=${fileSize}, chunks=${totalChunks}`);
      log(`  Hash: ${fileHash.toString('hex').substring(0, 16)}...`);
      
      // Send BEGIN packet with metadata
      const metadataBuffer = Buffer.alloc(266);
      metadataBuffer.writeUInt32BE(fileId, 0);
      metadataBuffer.writeUInt32BE(fileSize, 4);
      fileHash.copy(metadataBuffer, 8);
      metadataBuffer.writeUInt16BE(totalChunks, 264);
      
      const beginPacket = createPacket(
        config.TRANSFER_FLAGS.BEGIN_TRANSFER_AUDIO_FILE,
        transferId,
        0, // SEQ 0 for BEGIN packet
        metadataBuffer
      );
      
      this.updateValueCallback(beginPacket);
      await sleep(30); // Small delay between packets
      
      // Send data chunks
      let sentBytes = 0;
      const transferStartTime = Date.now();
      for (let i = 0; i < totalChunks; i++) {
        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, fileSize);
        const chunk = fileData.slice(start, end);
        const seq = i + 1; // SEQ starts from 1 for data chunks
        sentBytes += chunk.length;
        
        const flag = (i === totalChunks - 1) 
          ? config.TRANSFER_FLAGS.END_TRANSFER_AUDIO_FILE
          : config.TRANSFER_FLAGS.CONTINUE_TRANSFER_AUDIO_FILE;
        
        const dataPacket = createPacket(
          flag,
          transferId,
          seq,
          chunk
        );
        
        this.updateValueCallback(dataPacket);
        
        // Enhanced logging with speed calculation
        if (i === 0) {
          log(`  First chunk: seq=${seq}, size=${chunk.length} bytes`);
        } else if (i === totalChunks - 1) {
          log(`  Last chunk: seq=${seq}, size=${chunk.length} bytes`);
          log(`  Total sent: ${sentBytes} bytes (expected: ${fileSize} bytes)`);
        } else if (i % 10 === 0) {
          const elapsedTime = (Date.now() - transferStartTime) / 1000; // seconds
          const speed = elapsedTime > 0 ? (sentBytes / 1024 / elapsedTime) : 0; // KB/s
          const progress = ((i + 1) / totalChunks * 100).toFixed(1);
          log(`  Progress: ${progress}% (${i + 1}/${totalChunks} chunks)`);
          log(`    Sent: ${(sentBytes / 1024).toFixed(1)} KB, Speed: ${speed.toFixed(1)} KB/s`);
          
          // Estimate remaining time
          if (speed > 0) {
            const remainingBytes = fileSize - sentBytes;
            const eta = remainingBytes / (speed * 1024); // seconds
            if (eta < 60) {
              log(`    ETA: ${eta.toFixed(0)} seconds`);
            } else {
              log(`    ETA: ${(eta / 60).toFixed(1)} minutes`);
            }
          }
        }
        
        await sleep(30); // Delay between chunks to avoid overwhelming
      }
      
      // Calculate final transfer statistics
      const totalTime = (Date.now() - transferStartTime) / 1000; // seconds
      const avgSpeed = totalTime > 0 ? (sentBytes / 1024 / totalTime) : 0; // KB/s
      const throughput = avgSpeed * 8; // Kbps
      
      log(`Transfer completed: fileId=${fileId}`);
      log(`  Final hash: ${fileHash.toString('hex').substring(0, 16)}...`);
      log(`  Bytes sent: ${sentBytes}/${fileSize}`);
      log(`📊 Transfer Statistics:`);
      log(`  Duration: ${totalTime.toFixed(1)} seconds`);
      log(`  Average speed: ${avgSpeed.toFixed(1)} KB/s`);
      log(`  Throughput: ${throughput.toFixed(1)} Kbps`);
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
  let targetFileId = fileId;
  let filePath;
  
  if (fileId === null) {
    // If no file ID specified, get the oldest file
    const fileIds = Array.from(fileMap.keys()).sort((a, b) => a - b);
    if (fileIds.length === 0) {
      log('No files available for transfer');
      return;
    }
    targetFileId = fileIds[0];
    filePath = fileMap.get(targetFileId);
    log(`No file ID specified, transferring oldest file: ${targetFileId}`);
  } else {
    filePath = fileMap.get(fileId);
    if (!filePath) {
      log(`File not found for ID: ${fileId}`);
      return;
    }
  }
  
  if (activeTransfer) {
    log(`Transfer already in progress for ID: ${activeTransfer.fileId}`);
    return;
  }
  
  activeTransfer = { fileId: targetFileId, filePath };
  
  // Start transfer asynchronously
  dataTransferCharacteristic.transferFile(targetFileId, filePath).then(success => {
    if (success) {
      log(`Transfer successful: ${targetFileId}`);
    }
    activeTransfer = null;
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
});

// Graceful shutdown
process.on('SIGINT', () => {
  log('Shutting down BLE server...');
  bleno.stopAdvertising();
  process.exit(0);
});

// Start the server
setupFileWatcher();
log('TMS BLE Server initialized');
log(`Service UUID: ${config.SERVICE_UUID}`);
log(`Watching: ${path.resolve(__dirname, config.WATCH_DIR)}`);
