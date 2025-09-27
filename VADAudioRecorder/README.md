# VAD Audio Recorder

Voice Activity Detection (VAD) を使用した自動音声録音プログラム

## 機能

- 常時録音を行い、発話があった区間のみを自動的に検出・保存
- WebRTC VADによる高精度な音声検出
- 設定ファイルによるパラメータ調整

## インストール

```bash
pip install -r requirements.txt
```

## 使用方法

### 基本的な使用

```bash
python vad_recorder.py
```

### 設定ファイルを使用

```bash
python vad_recorder_with_config.py
```

## 設定項目 (config.json)

- `sample_rate`: サンプリングレート (Hz)
- `chunk_duration_ms`: チャンク長 (ミリ秒)
- `padding_duration_ms`: パディング時間 (ミリ秒)
- `vad_aggressiveness`: VAD感度 (0-3, 高いほど厳しく判定)
- `output_dir`: 録音ファイルの保存先ディレクトリ

## 録音ファイル

発話が検出されると、`recordings/voice_YYYYMMDD_HHMMSS.wav` として保存されます。