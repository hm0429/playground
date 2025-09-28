module.exports = {
  // BLE Service and Characteristic UUIDs
  SERVICE_UUID: '572542C4-2198-4D1E-9820-1FEAEA1BB9D0',
  CONTROL_UUID: '572542C4-2198-4D1E-9820-1FEAEA1BB9D1',
  STATUS_UUID: '572542C4-2198-4D1E-9820-1FEAEA1BB9D2',
  DATA_TRANSFER_UUID: '572542C4-2198-4D1E-9820-1FEAEA1BB9D3',
  
  // File monitoring settings
  WATCH_DIR: '../TMSAudioRecorder/recorded_audio/',
  FILE_EXTENSION: '.mp3',
  
  // BLE settings
  MTU_SIZE: 512,  // Maximum MTU size to negotiate
  DEFAULT_MTU: 23,  // Default BLE MTU
  DATA_CHUNK_SIZE: 500,  // Size of data chunks for transfer
  
  // Command codes for CONTROL characteristic
  COMMANDS: {
    START_TRANSFER_AUDIO_FILE: 0x01,
    COMPLETE_TRANSFER_AUDIO_FILE: 0x04
  },
  
  // Status codes for STATUS characteristic
  STATUS_TYPES: {
    FILE_ADDED: 0x40,
    FILE_DELETED: 0x41
  },
  
  // Transfer flags for DATA_TRANSFER characteristic
  TRANSFER_FLAGS: {
    BEGIN_TRANSFER_AUDIO_FILE: 0x80,
    CONTINUE_TRANSFER_AUDIO_FILE: 0x81,
    END_TRANSFER_AUDIO_FILE: 0x82
  },
  
  // Server settings
  DEVICE_NAME: 'TMS BLE Audio Server'
};
