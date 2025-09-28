# TMS BLE Protocol

TMS BLE Server と TMS BLE Client の通信プロトコルを定義します。

## BLE サービス構成

## Service

```
Service UUID: 572542C4-2198-4D1E-9820-1FEAEA1BB9D0
```

## Characteristics

| Characteristic | UUID | Properties | Description |
|---------------|------|------------|------|
| CONTROL | 572542C4-2198-4D1E-9820-1FEAEA1BB9D1 | Write | 操作命令の送受信 |
| STATUS | 572542C4-2198-4D1E-9820-1FEAEA1BB9D2 | Notify | ステータス通知 |
| DATA_TRANSFER | 572542C4-2198-4D1E-9820-1FEAEA1BB9D3 | Notify | データ転送 |

## データ転送フロー

### 最新の音声ファイルを取得
| 1. Peripheral: 新たなファイルが追加されたことを通知 | STATUS:FILE_ADDED(File ID) |
| 2. Central: Peripheral にファイルの送信指示 | CONTROL:START_TRANSFER_AUDIO_FILE(File ID) |
| 3. Peripheral: Central にファイルの転送を開始 | DATA_TRANSFER:BEGIN_TRANSFER_AUDIO_FILE(Metadata) |
| 4. Peripheral: Central にファイルのデータを転送 | DATA_TRANSFER:CONTINUE_TRANSFER_AUDIO_FILE(Chunk) |
| 5. Peripheral: Central にファイルのデータを完了 | DATA_TRANSFER:END_TRANSFER_AUDIO_FILE(Chunk) |
| 6. Central: Peripheral にファイルの転送完了通知 | CONTROL:COMPLETE_TRANSFER_AUDIO_FILE(File ID) |
| 7. Peripheral: 転送済みのファイルを削除・通知 | STATUS:FILE_DELETED(File ID) |


## 通信プロトコル詳細

### データフォーマット
| フィールド | サイズ | 説明 |
|-----------|--------|------|
| TYPE | 1 byte | データ種別 |
| ID | 2 bytes | ID |
| SEQ | 2 bytes | シーケンス番号 |
| LENGTH | 2 bytes | Payload のデータ長 |
| Payload | 可変長 | TYPE に応じたデータ |

### CONTROL Characteristic

#### TYPE
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| START_TRANSFER_AUDIO_FILE | 0x01 | File ID (4 bytes) | 音声ファイルの転送開始指示 |
| COMPLETE_TRANSFER_AUDIO_FILE | 0x04 | File ID (4 bytes) | 転送完了通知（ファイル削除） |

**File ID**
- 音声ファイルの ID
- unixtime (秒) 
- 最も古いファイルを指定する場合はファイル ID を省略します。

### STATUS Characteristic

#### TYPE
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| FILE_ADDED | 0x40 | File ID (4 bytes) | ファイル追加通知 |
| FILE_DELETED | 0x41 | File ID (4 bytes) | ファイル削除通知 |

### DATA_TRANSFER Characteristic
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| BEGIN_TRANSFER_AUDIO_FILE | 0x80 | Metadata | 転送開始 |
| CONTINUE_TRANSFER_AUDIO_FILE | 0x81 | 音声データ（バイナリ） | 転送継続 |
| END_TRANSFER_AUDIO_FILE | 0x82 | 音声データ（バイナリ） |  転送終了 |

**BEGIN_TRANSFER_AUDIO_FILE のペイロード（メタデータ）の構造**
| フィールド | サイズ | 説明 |
|-----------|--------|------|
| File ID | 4 bytes (BE) | ファイル ID (unixtime) |
| File Size | 4 bytes (BE) | ファイルサイズ（バイト） |
| File Hash | 256 bytes | ファイルハッシュ（SHA256） |
| Total Chunks | 2 bytes (BE) | 総チャンク数 |
---

## Memo
- Peripheral はなるべくシンプルに
- Central は Status で通知を受けたファイル名をキューする仕組みが必要
- ファイルのリストや充電状況等を通知する機能を追加