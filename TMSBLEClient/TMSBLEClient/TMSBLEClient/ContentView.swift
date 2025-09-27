import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var selectedFile: AudioFile?
    @State private var isPlaying = false
    @State private var showingConnectionAlert = false
    @State private var connectionAlertMessage = ""
    
    // Date formatter for File ID
    private let fileIdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()
    
    // Convert Unix timestamp to formatted string
    private func formatFileId(_ fileId: UInt32) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(fileId))
        return fileIdFormatter.string(from: date)
    }
    
    // Format file size
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Connection Status
                HStack {
                    Circle()
                        .fill(bleManager.isConnected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(bleManager.isConnected ? "Connected" : "Disconnected")
                        .font(.caption)
                    Spacer()
                    if bleManager.isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal)
                
                // Control Buttons
                HStack {
                    Button(action: {
                        if bleManager.isConnected {
                            bleManager.disconnect()
                        } else {
                            bleManager.startScanning()
                        }
                    }) {
                        Label(
                            bleManager.isConnected ? "Disconnect" : "Connect",
                            systemImage: bleManager.isConnected ? "wifi.slash" : "wifi"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(bleManager.isScanning)
                    
                    if bleManager.isConnected {
                        Button(action: {
                            bleManager.toggleAutoTransfer()
                        }) {
                            Label(
                                bleManager.isAutoTransferEnabled ? "Stop Auto" : "Start Auto",
                                systemImage: bleManager.isAutoTransferEnabled ? "stop.circle" : "play.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                
                // Transfer Status
                if let transfer = bleManager.activeTransfer {
                    VStack(spacing: 4) {
                        Text("Receiving: \(formatFileId(transfer.fileId))")
                            .font(.caption)
                        
                        ProgressView(value: Double(transfer.receivedChunks), total: Double(transfer.totalChunks))
                            .padding(.horizontal)
                        
                        HStack {
                            Text("\(transfer.receivedChunks) / \(transfer.totalChunks) chunks")
                                .font(.caption2)
                            
                            if transfer.transferRate > 0 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text("\(String(format: "%.1f", transfer.transferRate)) KB/s")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                
                                // ETA
                                let remainingBytes = Int(transfer.fileSize) - transfer.data.count
                                let eta = Double(remainingBytes) / (transfer.transferRate * 1024)
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if eta < 60 {
                                    Text("ETA: \(Int(eta))s")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("ETA: \(String(format: "%.1f", eta / 60))m")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                }
                
                // Audio Files List
                List {
                    ForEach(bleManager.audioFiles) { file in
                        HStack {
                            VStack(alignment: .leading) {
                                HStack(spacing: 4) {
                                    Text(formatFileId(file.fileId))
                                        .font(.headline)
                                        .fontDesign(.monospaced)
                                    
                                    if file.hasIntegrityIssue {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    }
                                }
                                
                                Text("\(formatFileSize(file.fileSize))")
                                    .font(.caption)
                                
                                if file.hasIntegrityIssue, let message = file.integrityMessage {
                                    Text(message)
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .lineLimit(1)
                                }
                                
                                HStack {
                                    Text(file.timestamp, style: .date)
                                        .font(.caption2)
                                    Text("•")
                                        .font(.caption2)
                                    Text(file.timestamp, style: .time)
                                        .font(.caption2)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                if selectedFile?.id == file.id && isPlaying {
                                    stopPlaying()
                                } else {
                                    playAudio(file)
                                }
                            }) {
                                Image(systemName: selectedFile?.id == file.id && isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                bleManager.requestFileTransfer(fileId: file.fileId)
                            }) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .disabled(!bleManager.isConnected)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteFiles)
                }
                .listStyle(.plain)
            }
            .navigationTitle("TMS BLE Client")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Connection Status", isPresented: $showingConnectionAlert) {
                Button("OK") { }
            } message: {
                Text(connectionAlertMessage)
            }
            .onReceive(bleManager.$connectionError) { error in
                if let error = error {
                    connectionAlertMessage = error
                    showingConnectionAlert = true
                    bleManager.connectionError = nil
                }
            }
        }
    }
    
    func playAudio(_ file: AudioFile) {
        AudioPlayer.shared.play(data: file.data) { success in
            if success {
                selectedFile = file
                isPlaying = true
            }
        }
    }
    
    func stopPlaying() {
        AudioPlayer.shared.stop()
        isPlaying = false
    }
    
    func deleteFiles(at offsets: IndexSet) {
        bleManager.audioFiles.remove(atOffsets: offsets)
        bleManager.saveFiles()  // Persist changes after deletion
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BLEManager())
    }
}
