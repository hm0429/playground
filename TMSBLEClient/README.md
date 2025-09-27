# TMS BLE Client

iOS application for receiving and playing audio files from TMS BLE Server via Bluetooth Low Energy.

## Features

- **BLE Connection**: Connects to TMS BLE Server automatically
- **Auto Transfer**: Automatically receives new audio files when they become available
- **Audio Playback**: Play received MP3 files directly in the app
- **File Management**: View list of received files with metadata
  - File IDs displayed in YYYYMMDDHHMMSS format (converted from Unix timestamp)
  - File size and timestamp information
- **Persistent Storage**: Saves received files for offline playback

## Requirements

- iOS 16.0+
- iPhone or iPad with Bluetooth support
- TMS BLE Server running on a Node.js device

## Setup

1. Open `TMSBLEClient.xcodeproj` in Xcode
2. Select your development team in project settings
3. Build and run on your iOS device

## Usage

1. **Connect to Server**
   - Tap "Connect" to scan for TMS BLE Server
   - Connection status is shown with a green/red indicator

2. **Auto Transfer Mode**
   - Tap "Start Auto" to automatically receive new files
   - Server will send files as they appear in the monitored directory

3. **Manual Transfer**
   - Tap the download icon next to any file to request it manually

4. **Play Audio**
   - Tap the play icon to start playback
   - Tap stop icon to stop playback

## Architecture

### Core Components

- **TMSBLEClientApp.swift**: Main app entry point
- **ContentView.swift**: Main UI with file list and controls
- **BLEManager.swift**: Handles all BLE operations and file transfers
- **AudioFile.swift**: Data model for audio files
- **AudioPlayer.swift**: Audio playback functionality

### BLE Protocol

The app communicates with TMS BLE Server using the following characteristics:

- **Service UUID**: `572542C4-2198-4D1E-9820-1FEAEA1BB9D0`
- **CONTROL**: Send commands to server (start/stop transfer)
- **STATUS**: Receive file notifications from server
- **DATA_TRANSFER**: Receive actual file data

### Data Transfer Protocol

1. Server notifies client of available files via STATUS
2. Client requests file transfer via CONTROL
3. Server sends file in chunks via DATA_TRANSFER
4. Client acknowledges completion via CONTROL
5. Server deletes file after successful transfer

## File Storage & Persistence

### Storage Location
- Audio files are stored in the app's Documents directory
- Archive file: `Documents/audioFiles.archive`
- Files persist across app launches

### Automatic Saving
Files are automatically saved when:
- New file transfer completes
- File is deleted from the list
- App goes to background or becomes inactive

### Data Safety & Integrity Verification
- **Hash Verification**: SHA-256 hash comparison between server and client
- **Sequence Checking**: Validates all chunks received in correct order
- **Size Validation**: Verifies received data size matches expected size
- **Duplicate Detection**: Identifies and logs duplicate chunk sequences
- **Missing Chunk Detection**: Reports any missing sequences
- **Atomic File Writes**: Prevents file corruption during save
- **Comprehensive Logging**: Detailed transfer progress and integrity reports

## Permissions

The app requires Bluetooth permissions to function. Users will be prompted to grant access on first launch.

## Troubleshooting

- **Cannot Connect**: Ensure TMS BLE Server is running and advertising
- **No Files Appearing**: Check that audio recorder is saving files to monitored directory
- **Playback Issues**: Ensure files are valid MP3 format

## Development

To modify the BLE protocol or add features:

1. Update UUIDs in `BLEManager.swift` if server changes
2. Modify packet structure in `createPacket` and `parsePacket` methods
3. Add new UI controls in `ContentView.swift`
