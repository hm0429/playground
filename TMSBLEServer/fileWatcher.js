const chokidar = require('chokidar');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const EventEmitter = require('events');
const config = require('./config');

class FileWatcher extends EventEmitter {
    constructor(directory = config.AUDIO_DIR) {
        super();
        // Expand ~ to home directory
        this.directory = directory.replace(/^~/, os.homedir());
        this.files = new Map(); // fileId -> fileInfo
        this.watcher = null;
        
        // Create directory if it doesn't exist
        if (!fs.existsSync(this.directory)) {
            fs.mkdirSync(this.directory, { recursive: true });
            console.log(`[FileWatcher] Created directory: ${this.directory}`);
        }
    }
    
    start() {
        console.log(`[FileWatcher] Starting file watcher for: ${this.directory}`);
        
        // Initialize watcher
        this.watcher = chokidar.watch(this.directory, {
            persistent: true,
            ignoreInitial: true,
            awaitWriteFinish: {
                stabilityThreshold: 1000,
                pollInterval: 100
            }
        });
        
        // Handle file additions
        this.watcher.on('add', (filePath) => {
            const ext = path.extname(filePath).toLowerCase();
            if (config.AUDIO_EXTENSIONS.includes(ext)) {
                this.handleFileAdded(filePath);
            }
        });
        
        // Handle file removals
        this.watcher.on('unlink', (filePath) => {
            const ext = path.extname(filePath).toLowerCase();
            if (config.AUDIO_EXTENSIONS.includes(ext)) {
                this.handleFileRemoved(filePath);
            }
        });
        
        // Handle errors
        this.watcher.on('error', error => {
            console.error(`[FileWatcher] Error:`, error);
            this.emit('error', error);
        });
        
        this.watcher.on('ready', () => {
            // console.log(`[FileWatcher] Initial scan complete. Found ${this.files.size} audio files.`);
            this.emit('ready', Array.from(this.files.values()));
        });
    }
    
    handleFileAdded(filePath) {
        try {
            const stats = fs.statSync(filePath);
            const fileName = path.basename(filePath, path.extname(filePath)); // Remove extension
            
            // Parse YYYYMMDDHHMMSS format (required)
            if (!/^\d{14}$/.test(fileName)) {
                console.log(`[FileWatcher] Ignoring file '${path.basename(filePath)}' - filename must be in YYYYMMDDHHMMSS.mp3 format`);
                return;
            }
            
            const year = parseInt(fileName.substring(0, 4));
            const month = parseInt(fileName.substring(4, 6)) - 1; // Month is 0-indexed in Date
            const day = parseInt(fileName.substring(6, 8));
            const hour = parseInt(fileName.substring(8, 10));
            const minute = parseInt(fileName.substring(10, 12));
            const second = parseInt(fileName.substring(12, 14));
            
            const date = new Date(year, month, day, hour, minute, second);
            const fileId = Math.floor(date.getTime() / 1000); // Convert to Unix timestamp in seconds
            
            // console.log(`[FileWatcher] Parsed timestamp from filename: ${fileName} -> ${fileId} (${date.toISOString()})`);
            
            const fileInfo = {
                id: fileId,
                path: filePath,
                name: path.basename(filePath),
                size: stats.size,
                createdAt: date,
                hash: null // Will be calculated when needed for transfer
            };
            
            this.files.set(fileId, fileInfo);
            
            console.log(`[FileWatcher] File added: ${fileInfo.name} (ID: ${fileId})`);
            this.emit('fileAdded', fileInfo);
            
        } catch (error) {
            console.error(`[FileWatcher] Error handling file addition:`, error);
        }
    }
    
    handleFileRemoved(filePath) {
        // Find the file by path
        let fileInfo = null;
        let fileId = null;
        
        for (const [id, info] of this.files.entries()) {
            if (info.path === filePath) {
                fileId = id;
                fileInfo = info;
                break;
            }
        }
        
        if (fileInfo) {
            this.files.delete(fileId);
            console.log(`[FileWatcher] File removed: ${fileInfo.name} (ID: ${fileId})`);
            this.emit('fileRemoved', fileInfo);
        }
    }
    
    getFile(fileId) {
        if (fileId === undefined || fileId === null) {
            // Return the oldest file if no ID specified
            let oldestFile = null;
            for (const file of this.files.values()) {
                if (!oldestFile || file.id < oldestFile.id) {
                    oldestFile = file;
                }
            }
            return oldestFile;
        }
        return this.files.get(fileId);
    }
    
    getAllFiles() {
        return Array.from(this.files.values());
    }
    
    async getFileWithHash(fileId) {
        const fileInfo = this.getFile(fileId);
        if (!fileInfo) return null;
        
        // Calculate hash if not already done
        if (!fileInfo.hash) {
            fileInfo.hash = await this.calculateFileHash(fileInfo.path);
        }
        
        return fileInfo;
    }
    
    calculateFileHash(filePath) {
        return new Promise((resolve, reject) => {
            const hash = crypto.createHash('sha256');
            const stream = fs.createReadStream(filePath);
            
            stream.on('data', (data) => {
                hash.update(data);
            });
            
            stream.on('end', () => {
                resolve(hash.digest());
            });
            
            stream.on('error', reject);
        });
    }
    
    removeFile(fileId) {
        const fileInfo = this.files.get(fileId);
        if (!fileInfo) return false;
        
        try {
            // Delete the actual file
            if (fs.existsSync(fileInfo.path)) {
                fs.unlinkSync(fileInfo.path);
                console.log(`[FileWatcher] Deleted file: ${fileInfo.name}`);
                return true;
            }
        } catch (error) {
            console.error(`[FileWatcher] Error deleting file:`, error);
        }
        
        return false;
    }
    
    stop() {
        if (this.watcher) {
            this.watcher.close();
            console.log(`[FileWatcher] Stopped file watcher`);
        }
    }
}

module.exports = FileWatcher;
