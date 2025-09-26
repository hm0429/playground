import SwiftUI

struct ContentView: View {
    @StateObject private var bleManager = BLECentralManager()
    @State private var messageToSend = "Hello BLE"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Status Section
                VStack {
                    Text("Status")
                        .font(.headline)
                    Text(bleManager.statusText)
                        .foregroundColor(bleManager.isConnected ? .green : .gray)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Connection Controls
                HStack(spacing: 20) {
                    Button(action: {
                        if bleManager.isScanning {
                            bleManager.stopScanning()
                        } else {
                            bleManager.startScanning()
                        }
                    }) {
                        Text(bleManager.isScanning ? "Stop Scan" : "Start Scan")
                            .frame(width: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bleManager.isConnected)
                    
                    Button(action: {
                        bleManager.disconnect()
                    }) {
                        Text("Disconnect")
                            .frame(width: 100)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!bleManager.isConnected)
                }
                
                // Discovered Peripherals
                if !bleManager.peripherals.isEmpty {
                    VStack {
                        Text("Discovered Devices")
                            .font(.headline)
                        
                        List(bleManager.peripherals, id: \.peripheral.identifier) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.peripheral.name ?? "Unknown Device")
                                        .font(.body)
                                    Text("RSSI: \(item.rssi)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Button("Connect") {
                                    bleManager.connect(to: item.peripheral)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 150)
                    }
                }
                
                Divider()
                
                // Data Display
                VStack {
                    Text("Received Value")
                        .font(.headline)
                    Text("\(bleManager.receivedValue)")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                
                // Read/Write Controls
                VStack(spacing: 10) {
                    Button(action: {
                        bleManager.readValue()
                    }) {
                        Text("Read Value")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bleManager.isConnected)
                    
                    HStack {
                        TextField("Message to send", text: $messageToSend)
                            .textFieldStyle(.roundedBorder)
                        
                        Button(action: {
                            let data = messageToSend.data(using: .utf8) ?? Data()
                            bleManager.writeValue(data)
                        }) {
                            Text("Send")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!bleManager.isConnected)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("BLE Central")
        }
    }
}

#Preview {
    ContentView()
}
