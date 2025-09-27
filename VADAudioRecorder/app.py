import collections, datetime, os, subprocess
import pyaudio, webrtcvad

# ====== 設定 ======
SAMPLE_RATE = 16000          # 8000/16000/32000/48000 のいずれか
FRAME_MS    = 30             # 10/20/30 ms のみ
CHANNELS    = 1              # モノラル
SAMPLE_WIDTH= 2              # 16bit
VAD_MODE    = 2              # 0...3 (感度高...低)
PRE_ROLL_S  = 2.0            # 録音開始判定前に付加する秒数
POST_ROLL_S = 2.0            # 録音終了判定後に付加する秒数
START_K     = 10             # 直近 N 中 K 以上の発話があれば開始
START_N     = 15             # 録音開始判定のための直近 N フレーム
MIN_SEG_S   = 1.0            # 最小録音秒数
MAX_SEG_S   = 300            # 最大録音秒数
OUT_DIR     = "recordings"   # 録音ファイルの保存先
MP3_BITRATE = "128k"         # MP3 のビットレート

# ====== 内部計算 ======
FRAME_SAMPLES = SAMPLE_RATE * FRAME_MS // 1000
FRAME_BYTES = FRAME_SAMPLES * SAMPLE_WIDTH
PRE_FRAMES  = int(PRE_ROLL_S * 1000 / FRAME_MS)
HANG_FRAMES = int(POST_ROLL_S * 1000 / FRAME_MS)
MIN_FRAMES  = int(MIN_SEG_S * 1000 / FRAME_MS)
MAX_FRAMES  = int(MAX_SEG_S * 1000 / FRAME_MS)

def get_unique_filepath(timestamp):
    ts = timestamp.strftime("%Y%m%d%H%M%S")
    path = os.path.join(OUT_DIR, f"{ts}.mp3")
    return path
    
def save_as_mp3(path, raw_pcm: bytes):
    cmd = ["ffmpeg", "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", str(CHANNELS),
           "-i", "pipe:0", "-acodec", "libmp3lame", "-b:a", MP3_BITRATE, "-y", path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        proc.stdin.write(raw_pcm)
        proc.stdin.close()
        proc.wait()
    except BrokenPipeError:
        pass

def reset_state():
    return {
        'collecting': False,
        'seg_frames': [],
        'silence_run': 0,
        'seg_start_ts': None,
        'prebuffer': collections.deque(maxlen=PRE_FRAMES),
        'recent_flags': collections.deque(maxlen=START_N)
    }

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    
    p = pyaudio.PyAudio()
    stream = p.open(format=p.get_format_from_width(SAMPLE_WIDTH),
                    channels=CHANNELS,
                    rate=SAMPLE_RATE,
                    input=True,
                    frames_per_buffer=FRAME_SAMPLES)

    vad = webrtcvad.Vad(VAD_MODE)
    state = reset_state()

    print("Listening… Ctrl+C to stop.")
    try:
        while True:
            data = stream.read(FRAME_SAMPLES, exception_on_overflow=False)
            if len(data) != FRAME_BYTES:
                continue

            is_voiced = vad.is_speech(data, SAMPLE_RATE)
            state['recent_flags'].append(1 if is_voiced else 0)

            if not state['collecting']:
                state['prebuffer'].append(data)
                if sum(state['recent_flags']) >= START_K:
                    state['collecting'] = True
                    state['seg_frames'] = list(state['prebuffer'])  # プレロール
                    state['silence_run'] = 0
                    state['seg_start_ts'] = datetime.datetime.now(datetime.UTC)
                    print("Recording started.")
            else:
                state['seg_frames'].append(data)
                state['silence_run'] = 0 if is_voiced else state['silence_run'] + 1

                # 終了判定
                if state['silence_run'] >= HANG_FRAMES or len(state['seg_frames']) >= MAX_FRAMES:
                    if len(state['seg_frames']) >= MIN_FRAMES:
                        outpath = get_unique_filepath(state['seg_start_ts'])
                        save_as_mp3(outpath, b"".join(state['seg_frames']))
                        print("Recording stopped. Saved:", outpath)
                    state = reset_state()
                    
    except KeyboardInterrupt:
        pass
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()

if __name__ == "__main__":
    main()