import collections, datetime, os, subprocess
import pyaudio, webrtcvad

# ====== 設定 ======
SAMPLE_RATE = 16000          # 8000/16000/32000/48000 のいずれか
FRAME_MS    = 30             # 10/20/30 ms のみ
CHANNELS    = 1
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
FRAME_BYTES = int(SAMPLE_RATE * FRAME_MS / 1000) * SAMPLE_WIDTH
PRE_FRAMES  = int(PRE_ROLL_S * 1000 / FRAME_MS)
HANG_FRAMES = int(POST_ROLL_S * 1000 / FRAME_MS)
MIN_FRAMES  = int(MIN_SEG_S * 1000 / FRAME_MS)
MAX_FRAMES  = int(MAX_SEG_S * 1000 / FRAME_MS)

os.makedirs(OUT_DIR, exist_ok=True)

def now_ts():
    return datetime.datetime.utcnow().strftime("%Y%m%d_%H%M%S_%f")[:-3] + "Z"

def save_as_mp3(path, raw_pcm: bytes):
    """
    RAW PCM(s16le, mono, 16kHz) を ffmpeg にパイプで渡して MP3 に変換・保存。
    """
    proc = subprocess.Popen(
        [
            "ffmpeg",
            "-f", "s16le", "-ar", str(SAMPLE_RATE), "-ac", str(CHANNELS), "-i", "pipe:0",
            "-acodec", "libmp3lame", "-b:a", MP3_BITRATE,
            "-y",  # 上書き
            path
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    try:
        proc.stdin.write(raw_pcm)
        proc.stdin.close()
        proc.wait()
    except BrokenPipeError:
        pass

def main():
    p = pyaudio.PyAudio()
    stream = p.open(format=p.get_format_from_width(SAMPLE_WIDTH),
                    channels=CHANNELS,
                    rate=SAMPLE_RATE,
                    input=True,
                    frames_per_buffer=int(SAMPLE_RATE*FRAME_MS/1000),
                    stream_callback=None)

    vad = webrtcvad.Vad(VAD_MODE)
    prebuffer = collections.deque(maxlen=PRE_FRAMES)
    recent_flags = collections.deque(maxlen=START_N)

    collecting = False
    seg_frames = []
    silence_run = 0
    seg_start_ts = None

    print("Listening… Ctrl+C to stop.")
    try:
        while True:
            data = stream.read(int(SAMPLE_RATE*FRAME_MS/1000), exception_on_overflow=False)
            if len(data) != FRAME_BYTES:
                continue

            is_voiced = vad.is_speech(data, SAMPLE_RATE)
            recent_flags.append(1 if is_voiced else 0)

            if not collecting:
                prebuffer.append(data)
                if sum(recent_flags) >= START_K:
                    collecting = True
                    seg_frames = list(prebuffer)  # プレロール
                    silence_run = 0
                    seg_start_ts = now_ts()
            else:
                seg_frames.append(data)
                silence_run = 0 if is_voiced else silence_run + 1

                # 終了判定
                if silence_run >= HANG_FRAMES or len(seg_frames) >= MAX_FRAMES:
                    if len(seg_frames) >= MIN_FRAMES:
                        filename = f"{seg_start_ts}__len{len(seg_frames)*FRAME_MS}ms.mp3"
                        outpath = os.path.join(OUT_DIR, filename)
                        save_as_mp3(outpath, b"".join(seg_frames))
                        print("Saved:", outpath)
                    # リセット
                    collecting = False
                    seg_frames = []
                    prebuffer.clear()
                    recent_flags.clear()
    except KeyboardInterrupt:
        pass
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()

if __name__ == "__main__":
    main()