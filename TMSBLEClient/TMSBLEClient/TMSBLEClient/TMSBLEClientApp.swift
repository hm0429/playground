import SwiftUI

@main
struct TMSBLEClientApp: App {
    @StateObject private var bleManager = BLEManager()
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .inactive, .background:
                        // Save files when app goes to background or becomes inactive
                        bleManager.saveFiles()
                        print("App going to background - saving audio files")
                    case .active:
                        print("App became active")
                    @unknown default:
                        break
                    }
                }
        }
    }
}
