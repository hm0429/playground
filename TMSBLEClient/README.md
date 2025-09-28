# TMS BLE Client

iOS client application for receiving audio files from TMS BLE Server via Bluetooth Low Energy.

## Features

- **BLE Connection Management**: Scan, connect, and manage connections to TMS BLE Server
- **Audio File Transfer**: Receive audio files using the TMS BLE Protocol
- **Auto-download Mode**: Optional automatic download of new files when detected
- **File Management**: View list of transferred audio files with transfer status
- **Audio Playback**: Built-in audio player with playback controls
- **Transfer Progress**: Real-time progress indication during file transfers
- **Manual Transfer Options**: Request specific files or all pending files

## Requirements

- iOS 16.0+
- Xcode 14.0+
- iPhone or iPad with Bluetooth capability

## Installation

1. Open `TMSBLEClient.xcodeproj` in Xcode
2. Select your development team in the project settings
3. Build and run on a physical iOS device (Bluetooth not available in simulator)

## Usage

### Connection Tab
- Tap "Start Scanning" to discover nearby TMS BLE Servers
- Select a server from the list to connect
- Toggle "Auto-download" to automatically download new files when detected
- View connection status and transfer statistics
- Request individual files or all pending files manually

### Files Tab
- View list of all audio files (pending, transferring, or completed)
- Tap play button to start playback
- Tap file for detailed information
- Swipe to delete files

### Player Tab
- Full-featured audio player interface
- Playback controls (play/pause, seek, stop)
- Progress slider with time display
- Currently playing file information

## Protocol Implementation

The app implements the TMS BLE Protocol as defined in `TMSBLEProtocol/PROTOCOL.md`:

### Service UUID
- `572542C4-2198-4D1E-9820-1FEAEA1BB9D0`

### Characteristics
- **CONTROL** (`...B9D1`): Send control commands (Write with Response)
- **STATUS** (`...B9D2`): Receive status notifications (Notify)
- **DATA_TRANSFER** (`...B9D3`): Receive file data (Notify)

### Data Transfer Flow
1. Receive FILE_ADDED notification from server
2. Send START_TRANSFER_AUDIO_FILE command
3. Receive BEGIN_TRANSFER_AUDIO_FILE with metadata
4. Receive multiple TRANSFER_AUDIO_FILE packets with chunks
5. Receive END_TRANSFER_AUDIO_FILE notification
6. Send COMPLETE_TRANSFER_AUDIO_FILE acknowledgment
7. Receive FILE_DELETED notification

## Architecture

- **BLEManager**: Handles all Bluetooth communication
- **TransferManager**: Manages file transfer state and progress
- **PacketParser**: Parses protocol packets and handles fragmentation
- **AudioFile**: Model for audio file with transfer state
- **AudioPlayer**: AVAudioPlayer wrapper for playback
- **ContentView**: Main UI with three tabs

## Permissions

The app requires Bluetooth permission to function. Permission prompts are configured in `Info.plist`:
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

## Troubleshooting

- **Cannot find devices**: Ensure Bluetooth is enabled and TMS BLE Server is advertising
- **Connection fails**: Check that server is running and not connected to another device
- **Transfer fails**: Verify server has audio files available in configured directory
- **Playback issues**: Ensure audio files are in supported format (MP3 recommended)

## Notes

- Files are saved to app's Documents directory after successful transfer
- SHA256 hash verification ensures data integrity
- Supports automatic retry for pending transfers
- MTU size is configured for 512 bytes (iOS default)