# TMSAudioRecorder

Mac向けのシンプルな音声録音アプリケーション。指定した間隔で音声を録音し、MP3ファイルとして保存します。

## 機能

- 指定した秒数ごとに音声を自動的に分割して保存
- MP3形式で圧縮保存
- ファイル名は `yyyyMMddHHmmss.mp3` 形式
- デフォルトの保存先は `recorded_audio` ディレクトリ

## 必要要件

- macOS
- Node.js (v14以上)
- sox (音声録音ツール)

## セットアップ

1. **soxのインストール**
   ```bash
   brew install sox
   ```

2. **依存パッケージのインストール**
   ```bash
   npm install
   ```

## 使用方法

録音を開始するには：
```bash
npm start
```
または
```bash
node index.js
```

録音を停止するには `Ctrl+C` を押してください。

## 設定

`config.js` ファイルで以下の設定を変更できます：

- `RECORDING_INTERVAL_SECONDS`: 録音間隔（秒）。デフォルトは10秒
- `OUTPUT_DIRECTORY`: 音声ファイルの保存先ディレクトリ
- `AUDIO_CONFIG`: 音声録音の詳細設定
- `MP3_CONFIG`: MP3エンコードの設定

### 設定例

録音間隔を30秒に変更する場合：
```javascript
RECORDING_INTERVAL_SECONDS: 30,
```

## ファイル構成

```
TMSAudioRecorder/
├── index.js           # メインの録音スクリプト
├── config.js          # 設定ファイル
├── package.json       # Node.jsプロジェクト設定
├── recorded_audio/    # 録音ファイル保存先（自動作成）
└── README.md          # このファイル
```

## トラブルシューティング

### "sox is not installed" エラーが出る場合
Homebrewを使用してsoxをインストールしてください：
```bash
brew install sox
```

### 録音が開始されない場合
- マイクへのアクセス権限を確認してください
- macOSのシステム環境設定 > セキュリティとプライバシー > プライバシー > マイクで、ターミナルまたは使用しているアプリケーションにマイクへのアクセスが許可されていることを確認してください

## ライセンス

ISC