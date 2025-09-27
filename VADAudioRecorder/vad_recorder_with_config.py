#!/usr/bin/env python3
import json
import sys
from vad_recorder import VADRecorder

def load_config(config_file='config.json'):
    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"設定ファイル {config_file} が見つかりません。デフォルト設定を使用します。")
        return {
            'sample_rate': 16000,
            'chunk_duration_ms': 30,
            'padding_duration_ms': 300,
            'vad_aggressiveness': 2,
            'output_dir': 'recordings'
        }
    except json.JSONDecodeError as e:
        print(f"設定ファイルの読み込みエラー: {e}")
        sys.exit(1)

def main():
    config = load_config()

    print("VAD録音設定:")
    print(f"  サンプリングレート: {config['sample_rate']} Hz")
    print(f"  チャンク長: {config['chunk_duration_ms']} ms")
    print(f"  パディング: {config['padding_duration_ms']} ms")
    print(f"  VAD感度: {config['vad_aggressiveness']} (0-3, 高いほど厳しく)")
    print(f"  出力ディレクトリ: {config['output_dir']}")
    print("-" * 50)

    recorder = VADRecorder(config)
    recorder.start()

if __name__ == '__main__':
    main()