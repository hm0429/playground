# TMS BLE Server

TMSBLEProtocolに準拠したBLE Serverの実装です。

## インストール

```bash
npm install
```

## 実行

```bash
npm start
# または
sudo npm start  # BLEアクセスに権限が必要な場合
```

## 機能

- 音声ファイル（.mp3）の自動検出と通知
- BLE経由でのファイル転送
- 転送完了後の自動ファイル削除
- ファイルの追加・削除の監視

## ディレクトリ構成

音声ファイルは `~/.tms/recordings/` に保存されます。
ファイル名は `YYYYMMDDHHMMSS.mp3` 形式である必要があります。

## プロトコル

TMSBLEProtocol/PROTOCOL.md に準拠しています。

### Service UUID
- `572542C4-2198-4D1E-9820-1FEAEA1BB9D0`

### Characteristics
- CONTROL: `572542C4-2198-4D1E-9820-1FEAEA1BB9D1`
- STATUS: `572542C4-2198-4D1E-9820-1FEAEA1BB9D2`
- DATA_TRANSFER: `572542C4-2198-4D1E-9820-1FEAEA1BB9D3`
