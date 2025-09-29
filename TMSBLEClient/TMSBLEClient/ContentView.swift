import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var audioPlayer = AudioPlayer()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection Section
                ConnectionHeaderView(bleManager: bleManager)
                
                // Control Section
                ControlSectionView(bleManager: bleManager)
                
                // Transfer Status
                if !bleManager.transferStatus.isEmpty {
                    TransferStatusView(
                        status: bleManager.transferStatus,
                        progress: bleManager.transferProgress
                    )
                }
                
                // Audio Files List
                AudioFilesListView(
                    audioFiles: bleManager.audioFiles,
                    audioPlayer: audioPlayer,
                    onDelete: bleManager.deleteAudioFile
                )
            }
            .navigationTitle("TMS BLE Client")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            setupAudioSession()
        }
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
}

// MARK: - Connection Header View
struct ConnectionHeaderView: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Circle()
                    .fill(bleManager.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(bleManager.connectionStatus)
                    .font(.system(.body, design: .monospaced))
                
                Spacer()
                
                if bleManager.isConnected {
                    Button("Disconnect") {
                        bleManager.disconnect()
                    }
                    .buttonStyle(.bordered)
                } else if bleManager.isScanning {
                    Button("Stop Scan") {
                        bleManager.stopScanning()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        bleManager.startScanning()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Control Section View
struct ControlSectionView: View {
    @ObservedObject var bleManager: BLEManager
    
    var body: some View {
        VStack(spacing: 15) {
            // Get Oldest File Button
            Button(action: {
                bleManager.requestOldestFile()
            }) {
                Label("Get Oldest File", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!bleManager.isConnected)
            
            // Auto Download Toggle
            Toggle(isOn: $bleManager.autoDownload) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Auto Download New Files")
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

// MARK: - Transfer Status View
struct TransferStatusView: View {
    let status: String
    let progress: Double
    
    var body: some View {
        VStack(spacing: 8) {
            Text(status)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

// MARK: - Audio Files List View
struct AudioFilesListView: View {
    let audioFiles: [AudioFile]
    @ObservedObject var audioPlayer: AudioPlayer
    let onDelete: (AudioFile) -> Void
    
    var body: some View {
        List {
            if audioFiles.isEmpty {
                Text("No audio files received")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(audioFiles) { file in
                    AudioFileRow(
                        file: file,
                        isPlaying: audioPlayer.currentlyPlayingId == file.id && audioPlayer.isPlaying,
                        onPlay: {
                            if audioPlayer.currentlyPlayingId == file.id {
                                audioPlayer.togglePlayPause()
                            } else {
                                audioPlayer.play(file)
                            }
                        },
                        onDelete: {
                            onDelete(file)
                        }
                    )
                }
            }
        }
        .listStyle(PlainListStyle())
    }
}

// MARK: - Audio File Row
struct AudioFileRow: View {
    let file: AudioFile
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.filename)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                
                Text(file.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.data.count), countStyle: .binary))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Play Button
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Delete Button
            Button(action: onDelete) {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
