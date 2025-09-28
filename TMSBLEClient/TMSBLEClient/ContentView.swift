//
//  ContentView.swift
//  TMSBLEClient
//
//  Main UI for TMS BLE Client
//

import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Connection Tab
            ConnectionView(bleManager: bleManager)
                .tabItem {
                    Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(0)
            
            // Files Tab
            FilesView(bleManager: bleManager, audioPlayer: audioPlayer)
                .tabItem {
                    Label("Files", systemImage: "music.note.list")
                }
                .tag(1)
            
            // Player Tab
            PlayerView(audioPlayer: audioPlayer)
                .tabItem {
                    Label("Player", systemImage: "play.circle")
                }
                .tag(2)
        }
    }
}

// MARK: - Connection View
struct ConnectionView: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        NavigationView {
            VStack {
                // Status Card
                VStack(spacing: 12) {
                    HStack {
                        Circle()
                            .fill(bleManager.isConnected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(bleManager.connectionStatus)
                            .font(.headline)
                        Spacer()
                    }
                    
                    if bleManager.isConnected, let peripheral = bleManager.connectedPeripheral {
                        HStack {
                            Text("Device:")
                                .foregroundColor(.secondary)
                            Text(peripheral.name ?? "Unknown Device")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()
                
                // Scan Controls
                if !bleManager.isConnected {
                    VStack(spacing: 16) {
                        Button(action: {
                            if bleManager.isScanning {
                                bleManager.stopScanning()
                            } else {
                                bleManager.startScanning()
                            }
                        }) {
                            HStack {
                                Image(systemName: bleManager.isScanning ? "stop.circle.fill" : "magnifyingglass.circle.fill")
                                Text(bleManager.isScanning ? "Stop Scanning" : "Start Scanning")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bleManager.isScanning ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        
                        // Discovered Peripherals List
                        if !bleManager.discoveredPeripherals.isEmpty {
                            List(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                                Button(action: {
                                    bleManager.connect(to: peripheral)
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(peripheral.name ?? "Unknown Device")
                                                .font(.headline)
                                            Text(peripheral.identifier.uuidString)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .listStyle(InsetGroupedListStyle())
                        } else if bleManager.isScanning {
                            Spacer()
                            ProgressView("Searching for devices...")
                                .padding()
                            Spacer()
                        }
                    }
                } else {
                    // Connected Controls
                    VStack(spacing: 16) {
                        // Auto-download Toggle
                        VStack(spacing: 8) {
                            HStack {
                                Label("Auto-download", systemImage: "arrow.down.circle")
                                    .font(.headline)
                                Spacer()
                                Toggle("", isOn: $bleManager.autoDownloadEnabled)
                                    .labelsHidden()
                            }
                            
                            Text("Automatically download new files when detected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(bleManager.autoDownloadEnabled ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Transfer Statistics
                        VStack(spacing: 8) {
                            HStack {
                                Text("Pending Files:")
                                Spacer()
                                Text("\(bleManager.transferManager.pendingFileIds.count)")
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Text("Completed Transfers:")
                                Spacer()
                                Text("\(bleManager.transferManager.completedTransfers.count)")
                                    .fontWeight(.semibold)
                            }
                            
                            if let current = bleManager.transferManager.currentTransfer {
                                HStack {
                                    Text("Current Transfer:")
                                    Spacer()
                                    Text(current.fileName)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                }
                                
                                ProgressView(value: current.transferProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .padding(.top, 4)
                                
                                Text("\(Int(current.transferProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Action Buttons
                        if !bleManager.autoDownloadEnabled && !bleManager.transferManager.pendingFileIds.isEmpty {
                            Button(action: {
                                if let nextFileId = bleManager.transferManager.getNextPendingFileId() {
                                    bleManager.requestTransfer(for: nextFileId)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Download Next Pending File")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .padding(.horizontal)
                            .disabled(bleManager.transferManager.currentTransfer != nil)
                        }
                        
                        Button(action: {
                            bleManager.requestOldestFileTransfer()
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Request Oldest File")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .disabled(bleManager.transferManager.currentTransfer != nil)
                        
                        Button(action: {
                            bleManager.requestAllPendingTransfers()
                        }) {
                            HStack {
                                Image(systemName: "arrow.down.to.line.circle.fill")
                                Text("Request All Pending Files")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .disabled(bleManager.transferManager.currentTransfer != nil || bleManager.transferManager.pendingFileIds.isEmpty)
                        
                        Button(action: {
                            bleManager.disconnect()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Disconnect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                
                if !bleManager.isConnected && !bleManager.isScanning && bleManager.discoveredPeripherals.isEmpty {
                    Spacer()
                }
            }
            .navigationTitle("TMS BLE Client")
        }
    }
}

// MARK: - Files View
struct FilesView: View {
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var audioPlayer: AudioPlayer
    @State private var selectedFile: AudioFile?
    
    var body: some View {
        NavigationView {
            VStack {
                if bleManager.audioFiles.isEmpty {
                    ContentUnavailableView(
                        "No Audio Files",
                        systemImage: "music.note",
                        description: Text("Connect to TMS BLE Server and transfer audio files")
                    )
                } else {
                    List(bleManager.audioFiles) { file in
                        FileRow(file: file, audioPlayer: audioPlayer)
                            .onTapGesture {
                                selectedFile = file
                            }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Audio Files")
            .sheet(item: $selectedFile) { file in
                FileDetailView(file: file, audioPlayer: audioPlayer)
            }
        }
    }
}

// MARK: - File Row
struct FileRow: View {
    @ObservedObject var file: AudioFile
    @ObservedObject var audioPlayer: AudioPlayer
    
    var body: some View {
        HStack {
            // Play/Pause Button
            Button(action: {
                audioPlayer.togglePlayPause(for: file)
            }) {
                Image(systemName: file.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(file.isTransferComplete ? .blue : .gray)
            }
            .disabled(!file.isTransferComplete)
            
            // File Info
            VStack(alignment: .leading, spacing: 4) {
                Text(file.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    if file.isTransferring {
                        Label("Transferring", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if file.isTransferComplete {
                        Label("\(file.fileSize / 1024) KB", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Pending", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
            
            // Transfer Progress
            if file.isTransferring {
                CircularProgressView(progress: file.transferProgress)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - File Detail View
struct FileDetailView: View {
    @ObservedObject var file: AudioFile
    @ObservedObject var audioPlayer: AudioPlayer
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // File Icon
                Image(systemName: "music.note")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .padding()
                
                // File Info
                VStack(spacing: 12) {
                    InfoRow(label: "File Name", value: file.fileName)
                    InfoRow(label: "File Size", value: "\(file.fileSize / 1024) KB")
                    InfoRow(label: "File ID", value: String(file.id))
                    InfoRow(label: "Status", value: file.isTransferComplete ? "Complete" : (file.isTransferring ? "Transferring" : "Pending"))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Transfer Progress
                if file.isTransferring {
                    VStack {
                        Text("Transfer Progress")
                            .font(.headline)
                        ProgressView(value: file.transferProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                        Text("\(Int(file.transferProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                // Play Button
                if file.isTransferComplete {
                    Button(action: {
                        audioPlayer.togglePlayPause(for: file)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(systemName: file.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            Text(file.isPlaying ? "Pause" : "Play")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
                
                // Delete Button
                Button(action: {
                    file.deleteFile()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                        Text("Delete File")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("File Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Player View
struct PlayerView: View {
    @ObservedObject var audioPlayer: AudioPlayer
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                if let currentFile = audioPlayer.currentFile {
                    // Album Art Placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 250, height: 250)
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 100))
                            .foregroundColor(.white)
                    }
                    .padding()
                    
                    // Track Info
                    VStack(spacing: 8) {
                        Text(currentFile.fileName)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Text("File ID: \(currentFile.id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Progress Slider
                    VStack {
                        Slider(value: Binding(
                            get: { audioPlayer.playbackProgress },
                            set: { audioPlayer.seekToProgress($0) }
                        ))
                        .accentColor(.blue)
                        
                        HStack {
                            Text(audioPlayer.formatTime(audioPlayer.currentTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(audioPlayer.formatTime(audioPlayer.duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Playback Controls
                    HStack(spacing: 40) {
                        Button(action: {
                            audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
                        }) {
                            Image(systemName: "gobackward.15")
                                .font(.title)
                                .foregroundColor(.primary)
                        }
                        
                        Button(action: {
                            if audioPlayer.isPlaying {
                                audioPlayer.pause()
                            } else {
                                audioPlayer.resume()
                            }
                        }) {
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.blue)
                        }
                        
                        Button(action: {
                            audioPlayer.seek(to: min(audioPlayer.duration, audioPlayer.currentTime + 15))
                        }) {
                            Image(systemName: "goforward.15")
                                .font(.title)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding()
                    
                    // Stop Button
                    Button(action: {
                        audioPlayer.stop()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("Stop")
                        }
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .cornerRadius(25)
                    }
                    
                    Spacer()
                } else {
                    ContentUnavailableView(
                        "No Audio Playing",
                        systemImage: "speaker.slash",
                        description: Text("Select an audio file to play")
                    )
                }
            }
            .navigationTitle("Player")
        }
    }
}

// MARK: - Helper Views
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.blue, lineWidth: 4)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }
}

// Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
