#!/usr/bin/env python3
import os
import wave
import threading
import queue
import time
from datetime import datetime
from collections import deque
import pyaudio
import webrtcvad

class VADRecorder:
    def __init__(self, config):
        self.sample_rate = config.get('sample_rate', 16000)
        self.chunk_duration_ms = config.get('chunk_duration_ms', 30)
        self.padding_duration_ms = config.get('padding_duration_ms', 300)
        self.vad_aggressiveness = config.get('vad_aggressiveness', 2)
        self.output_dir = config.get('output_dir', 'recordings')

        self.chunk_size = int(self.sample_rate * self.chunk_duration_ms / 1000)
        self.chunk_bytes = self.chunk_size * 2
        self.padding_chunks = int(self.padding_duration_ms / self.chunk_duration_ms)

        self.vad = webrtcvad.Vad(self.vad_aggressiveness)
        self.audio = pyaudio.PyAudio()

        self.audio_queue = queue.Queue()
        self.is_running = False

        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)

    def audio_callback(self, in_data, frame_count, time_info, status):
        self.audio_queue.put(in_data)
        return (None, pyaudio.paContinue)

    def process_audio(self):
        ring_buffer = deque(maxlen=self.padding_chunks)
        triggered = False
        voiced_frames = []

        print(f"VAD録音開始 (感度: {self.vad_aggressiveness}, 出力: {self.output_dir})")

        while self.is_running:
            try:
                chunk = self.audio_queue.get(timeout=0.1)
            except queue.Empty:
                continue

            is_speech = self.vad.is_speech(chunk, self.sample_rate)

            if not triggered:
                ring_buffer.append((chunk, is_speech))
                num_voiced = len([f for f, speech in ring_buffer if speech])

                if num_voiced > 0.5 * ring_buffer.maxlen:
                    triggered = True
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] 発話検出 - 録音開始")

                    for f, s in ring_buffer:
                        voiced_frames.append(f)
                    ring_buffer.clear()

            else:
                voiced_frames.append(chunk)
                ring_buffer.append((chunk, is_speech))
                num_unvoiced = len([f for f, speech in ring_buffer if not speech])

                if num_unvoiced > 0.9 * ring_buffer.maxlen:
                    triggered = False
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] 発話終了 - 保存中...")

                    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                    filename = os.path.join(self.output_dir, f'voice_{timestamp}.wav')
                    self.save_audio(voiced_frames, filename)
                    print(f"  → 保存完了: {filename}")

                    ring_buffer.clear()
                    voiced_frames = []

    def save_audio(self, frames, filename):
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(self.sample_rate)
            wf.writeframes(b''.join(frames))

    def start(self):
        self.is_running = True

        self.stream = self.audio.open(
            format=pyaudio.paInt16,
            channels=1,
            rate=self.sample_rate,
            input=True,
            frames_per_buffer=self.chunk_size,
            stream_callback=self.audio_callback
        )

        self.process_thread = threading.Thread(target=self.process_audio)
        self.process_thread.start()

        print("録音を開始しました。Ctrl+C で終了します。")

        try:
            while self.is_running:
                time.sleep(0.1)
        except KeyboardInterrupt:
            self.stop()

    def stop(self):
        print("\n録音を終了しています...")
        self.is_running = False

        if hasattr(self, 'process_thread'):
            self.process_thread.join()

        if hasattr(self, 'stream'):
            self.stream.stop_stream()
            self.stream.close()

        self.audio.terminate()
        print("終了しました。")

def main():
    config = {
        'sample_rate': 16000,
        'chunk_duration_ms': 30,
        'padding_duration_ms': 300,
        'vad_aggressiveness': 2,
        'output_dir': 'recordings'
    }

    recorder = VADRecorder(config)
    recorder.start()

if __name__ == '__main__':
    main()