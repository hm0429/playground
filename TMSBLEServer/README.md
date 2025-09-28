# TMS BLE Server

A Bluetooth Low Energy (BLE) server implementation for audio file transfer following the TMS BLE Protocol.

## Features

- Real-time audio file monitoring
- Automatic file detection and notification
- Chunked file transfer over BLE
- File deletion after successful transfer
- Support for MP3 audio format

## Installation

```bash
npm install
```

## Usage

1. Start the server:
```bash
npm start
```

2. The server will:
   - Create `~/.tms/recordings` directory if it doesn't exist
   - Start monitoring for audio files
   - Begin BLE advertising as "TMS_BLE_SERVER"
   - Wait for client connections

3. Place audio files in the `~/.tms/recordings` directory
   - **Files MUST be named in YYYYMMDDHHMMSS.mp3 format**
   - Example: `20240328153045.mp3`
   - Only MP3 files are supported
   - Files with incorrect naming format or extension will be ignored
   - Files will be automatically detected
   - Clients will be notified of new files

## Protocol Overview

The server implements the TMS BLE Protocol with:

### Service
- UUID: `572542C4-2198-4D1E-9820-1FEAEA1BB9D0`

### Characteristics
1. **CONTROL** (`...B9D1`): Receives commands from clients
   - START_TRANSFER_AUDIO_FILE
   - COMPLETE_TRANSFER_AUDIO_FILE

2. **STATUS** (`...B9D2`): Notifies clients about file events
   - FILE_ADDED
   - FILE_DELETED

3. **DATA_TRANSFER** (`...B9D3`): Transfers file data
   - BEGIN_TRANSFER_AUDIO_FILE (metadata)
   - TRANSFER_AUDIO_FILE (chunks)
   - END_TRANSFER_AUDIO_FILE (final chunk)

## File Management

- Files are identified by Unix timestamp extracted from filename
- Required format: `YYYYMMDDHHMMSS.mp3` (MP3 only)
- Example: `20240328153045.mp3` → File ID: Unix timestamp for 2024-03-28 15:30:45
- Files with incorrect filename format or non-MP3 extension are ignored
- Files are automatically deleted after successful transfer
- The oldest file is selected if no specific file ID is provided
- Transfer IDs are incremented sequentially (1-65535) and wrap around

## Configuration

Edit `config.js` to customize:
- Audio directory path
- MTU size (default: 512 bytes)
- Chunk size (automatically calculated as MTU - 7 bytes for header)
- BLE UUIDs (if needed)

### MTU and Chunk Size

The server uses an MTU (Maximum Transmission Unit) of 512 bytes by default. The actual data chunk size is automatically calculated as:
- **Chunk Size = MTU - Protocol Header (7 bytes)**
- Default: 512 - 7 = 505 bytes per chunk

This ensures that each BLE packet, including the protocol header, fits within the MTU limit.

## Requirements

- Node.js 14 or higher
- Linux or macOS with Bluetooth support
- May require sudo/root permissions for BLE access

## Troubleshooting

### Permission Issues
On Linux, you may need to run with sudo or set capabilities:
```bash
sudo setcap cap_net_raw+eip $(eval readlink -f $(which node))
```

### Bluetooth Issues
- Ensure Bluetooth is enabled on your system
- Check that no other BLE servers are running
- Verify the Bluetooth adapter is not in use by other applications

## Architecture

- `index.js`: Main BLE server implementation
- `fileWatcher.js`: File system monitoring module
- `config.js`: Configuration settings
- `~/.tms/recordings/`: Default directory for audio files

## Protocol Flow

1. Server detects new audio file → STATUS: FILE_ADDED
2. Client requests transfer → CONTROL: START_TRANSFER
3. Server sends metadata → DATA_TRANSFER: BEGIN
4. Server sends chunks → DATA_TRANSFER: TRANSFER
5. Server sends final chunk → DATA_TRANSFER: END
6. Client confirms completion → CONTROL: COMPLETE
7. Server deletes file → STATUS: FILE_DELETED
