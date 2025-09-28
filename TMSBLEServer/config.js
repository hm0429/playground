module.exports = {
    // BLE Configuration
    LOCAL_NAME: "TMS_BLE_SERVER",
    SERVICE_UUID: "572542C4-2198-4D1E-9820-1FEAEA1BB9D0".replace(/-/g, ''),
    
    // Characteristic UUIDs
    CHARACTERISTICS: {
        CONTROL: "572542C4-2198-4D1E-9820-1FEAEA1BB9D1".replace(/-/g, ''),
        STATUS: "572542C4-2198-4D1E-9820-1FEAEA1BB9D2".replace(/-/g, ''),
        DATA_TRANSFER: "572542C4-2198-4D1E-9820-1FEAEA1BB9D3".replace(/-/g, ''),
    },
    
    // Audio file monitoring configuration
    // REQUIRED filename format: YYYYMMDDHHMMSS.mp3 (e.g., 20240328153045.mp3)
    // Files not matching this format will be ignored
    AUDIO_DIR: '~/.tms/recordings',
    AUDIO_EXTENSIONS: ['.mp3'],
    
    // Transfer configuration
    // Note: In future, MTU could be negotiated dynamically and SEQ can be used for packet fragmentation
    MTU_SIZE: 512, // BLE MTU size
    HEADER_SIZE: 7, // Protocol header size (TYPE + ID + SEQ + LENGTH)
    get CHUNK_SIZE() {
        // Actual data chunk size = MTU - Header
        return this.MTU_SIZE - this.HEADER_SIZE;
    },
    
    // Protocol Types
    CONTROL_TYPES: {
        START_TRANSFER_AUDIO_FILE: 0x01,
        COMPLETE_TRANSFER_AUDIO_FILE: 0x02,
    },
    
    STATUS_TYPES: {
        FILE_ADDED: 0x40,
        FILE_DELETED: 0x41,
    },
    
    DATA_TRANSFER_TYPES: {
        BEGIN_TRANSFER_AUDIO_FILE: 0x80,
        TRANSFER_AUDIO_FILE: 0x81,
        END_TRANSFER_AUDIO_FILE: 0x82,
    }
};
