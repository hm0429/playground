//
//  AudioPlayer.swift
//  TMSBLEClient
//
//  Audio playback manager for TMS BLE Client
//

import Foundation
import AVFoundation
import Combine

class AudioPlayer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentFile: AudioFile?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("[AudioPlayer] Failed to setup audio session: \(error)")
        }
    }
    
    func play(_ audioFile: AudioFile) {
        // Stop current playback if any
        stop()
        
        guard let fileURL = audioFile.getFileURL() else {
            print("[AudioPlayer] No file URL available for: \(audioFile.fileName)")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            currentFile = audioFile
            audioFile.isPlaying = true
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            
            // Start timer to update progress
            startProgressTimer()
            
            print("[AudioPlayer] Started playing: \(audioFile.fileName)")
        } catch {
            print("[AudioPlayer] Failed to play audio file: \(error)")
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        currentFile?.isPlaying = false
        stopProgressTimer()
        print("[AudioPlayer] Paused playback")
    }
    
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        currentFile?.isPlaying = true
        startProgressTimer()
        print("[AudioPlayer] Resumed playback")
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentFile?.isPlaying = false
        currentFile = nil
        currentTime = 0
        duration = 0
        playbackProgress = 0
        stopProgressTimer()
        print("[AudioPlayer] Stopped playback")
    }
    
    func togglePlayPause(for audioFile: AudioFile) {
        if currentFile?.id == audioFile.id {
            if isPlaying {
                pause()
            } else {
                resume()
            }
        } else {
            play(audioFile)
        }
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        updateProgress()
    }
    
    func seekToProgress(_ progress: Double) {
        let time = duration * progress
        seek(to: time)
    }
    
    private func startProgressTimer() {
        stopProgressTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func stopProgressTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        if duration > 0 {
            playbackProgress = currentTime / duration
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - AVAudioPlayerDelegate
extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("[AudioPlayer] Finished playing")
        stop()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("[AudioPlayer] Decode error: \(error?.localizedDescription ?? "unknown")")
        stop()
    }
}
