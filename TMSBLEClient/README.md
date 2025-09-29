# TMS BLE Client

TMSBLEProtocolに準拠したiOS用BLE Clientアプリケーションです。

## 機能

- TMS BLE Serverとの自動接続
- 最も古い音声ファイルの取得
- 新規ファイルの自動ダウンロード（スイッチで切替可能）
- 取得した音声ファイルの再生
- ファイル転送状況の表示

## ビルド方法

1. Xcodeでプロジェクトを開く
```bash
open TMSBLEClient.xcodeproj
```

2. ターゲットデバイスを選択（実機またはシミュレータ）

3. ビルド＆実行（Cmd + R）

## 使い方

1. **接続**
   - アプリ起動後、「Connect」ボタンをタップ
   - TMS BLE Serverが自動的に検出され接続されます

2. **ファイル取得**
   - 「Get Oldest File」ボタン：最も古いファイルを1つ取得
   - 「Auto Download New Files」スイッチ：ONにすると新規ファイルを自動取得

3. **音声再生**
   - 取得したファイルのリストから再生ボタンをタップ
   - 再生中はボタンが一時停止アイコンに変わります

4. **ファイル削除**
   - リスト内のゴミ箱アイコンをタップして削除

## UI構成

- **接続セクション**：BLE接続状態の表示と接続/切断ボタン
- **コントロールセクション**：ファイル取得ボタンと自動ダウンロードスイッチ
- **転送状況**：ファイル転送時の進捗表示
- **ファイルリスト**：取得したファイルの一覧と再生/削除機能

## 必要な権限

- Bluetoothアクセス権限（Info.plistに設定済み）

## プロトコル

TMSBLEProtocol/PROTOCOL.md に準拠しています。

### Service UUID
- `572542C4-2198-4D1E-9820-1FEAEA1BB9D0`

### Characteristics
- CONTROL: `572542C4-2198-4D1E-9820-1FEAEA1BB9D1`
- STATUS: `572542C4-2198-4D1E-9820-1FEAEA1BB9D2`
- DATA_TRANSFER: `572542C4-2198-4D1E-9820-1FEAEA1BB9D3`
