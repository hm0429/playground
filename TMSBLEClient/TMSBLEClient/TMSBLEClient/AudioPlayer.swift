import Foundation
import AVFoundation

class AudioPlayer: NSObject {
    static let shared = AudioPlayer()
    
    private var audioPlayer: AVAudioPlayer?
    
    override private init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    func play(data: Data, completion: @escaping (Bool) -> Void) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            completion(true)
        } catch {
            print("Failed to play audio: \(error)")
            completion(false)
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    func pause() {
        audioPlayer?.pause()
    }
    
    func resume() {
        audioPlayer?.play()
    }
    
    var isPlaying: Bool {
        return audioPlayer?.isPlaying ?? false
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Audio playback finished: \(flag)")
        audioPlayer = nil
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio decode error: \(error?.localizedDescription ?? "Unknown error")")
        audioPlayer = nil
    }
}
