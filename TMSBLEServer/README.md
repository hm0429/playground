# TMS BLE Audio Server

BLE（Bluetooth Low Energy）を使用して音声ファイルを転送するPeripheralサーバーの実装です。

## 機能

- 📁 ディレクトリ監視による自動ファイル検出
- 📡 BLE経由でのファイル転送
- 🔄 自動転送モード対応
- 📊 転送状態のリアルタイム通知
- 🔒 SHA256ハッシュによる整合性検証

## 必要要件

- macOS (BLEサポート)
- Node.js v14以上
- Bluetooth対応デバイス

## インストール

```bash
npm install
```

## 使用方法

### 1. サーバーの起動

```bash
npm start
```

または

```bash
node index.js
```

### 2. 監視対象ディレクトリ

デフォルトで以下のディレクトリを監視します：
- `../TMSAudioRecorder/recorded_audio/`

MP3ファイルが追加されると自動的に検出されます。

### 3. BLE接続情報

| 項目 | 値 |
|------|-----|
| デバイス名 | TMS BLE Audio Server |
| Service UUID | 572542C4-2198-4D1E-9820-1FEAEA1BB9D0 |

### 4. Characteristics

| Characteristic | UUID | 用途 |
|----------------|------|------|
| CONTROL | ...B9D1 | コマンド受信 |
| STATUS | ...B9D2 | ステータス通知 |
| DATA_TRANSFER | ...B9D3 | データ転送 |

## 動作フロー

1. **ファイル検出**: MP3ファイルが監視ディレクトリに追加される
2. **通知**: CentralデバイスにFILE_ADDEDステータスを送信
3. **転送開始**: CentralからSTART_TRANSFERコマンドを受信
4. **データ送信**: ファイルをチャンク分割して転送
5. **完了通知**: 転送完了後、CentralからCOMPLETE_TRANSFERコマンドを受信
6. **ファイル削除**: 転送済みファイルを削除

## 自動転送モード

CentralデバイスがSTART_TRANSFER_AUDIO_FILE_AUTOコマンドを送信すると、新規ファイルを自動的に転送開始します。

## ログ

すべての動作ログは `AGENT_LOG.md` に記録されます。

## 設定変更

`config.js` ファイルを編集することで、以下の設定を変更できます：

- 監視ディレクトリパス
- ファイル拡張子
- MTUサイズ
- チャンクサイズ

## トラブルシューティング

### エラー: "bleno not compatible"
macOSのセキュリティ設定でBluetoothアクセスを許可してください。

### エラー: "EACCES"
管理者権限で実行してください：
```bash
sudo npm start
```

### ファイルが検出されない
- 監視ディレクトリが存在することを確認
- ファイル拡張子が`.mp3`であることを確認

## ライセンス

ISC
