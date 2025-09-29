import Foundation
import AVFoundation
import Combine

class AudioPlayer: NSObject, ObservableObject {
    private var player: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentlyPlayingId: UUID?
    
    func play(_ audioFile: AudioFile) {
        stop()
        
        do {
            player = try AVAudioPlayer(data: audioFile.data)
            player?.delegate = self
            player?.play()
            isPlaying = true
            currentlyPlayingId = audioFile.id
            print("[AudioPlayer] Playing file: \(audioFile.filename)")
        } catch {
            print("[AudioPlayer] Error playing audio: \(error)")
        }
    }
    
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentlyPlayingId = nil
    }
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentlyPlayingId = nil
        }
    }
}
