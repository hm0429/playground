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
| CONTROL | 572542C4-2198-4D1E-9820-1FEAEA1BB9D1 | Write with Response, Indicate | 操作命令の送受信 |
| STATUS | 572542C4-2198-4D1E-9820-1FEAEA1BB9D2 | Notify | ステータス通知 |
| DATA_TRANSFER | 572542C4-2198-4D1E-9820-1FEAEA1BB9D3 | Notify | データ転送 |

## データ転送フロー

### 最新の音声ファイルを取得
| 1. Peripheral: 新たなファイルが追加されたことを通知 | STATUS:FILE_ADDED(File ID) |
| 2. Central: Peripheral にファイルの送信指示 | CONTROL:START_TRANSFER_AUDIO_FILE(File ID) |
| 3. Peripheral: Central にファイルの転送を開始 | CONTROL:BEGIN_TRANSFER_AUDIO_FILE(Metadata) |
| 4. Peripheral: Central にファイルのデータを転送 | DATA_TRANSFER:TRANSFER_AUDIO_FILE(Chunk) |
| 5. Peripheral: Central にファイルの転送終了を通知 | CONTROL:END_TRANSFER_AUDIO_FILE() |
| 6. Central: Peripheral にファイルの転送完了通知 | CONTROL:COMPLETE_TRANSFER_AUDIO_FILE(File ID) |
| 7. Peripheral: 転送済みのファイルを削除・通知 | STATUS:FILE_DELETED(File ID) |


## 通信プロトコル詳細

### データフォーマット
| フィールド | サイズ | 説明 |
|-----------|--------|------|
| TYPE | 1 byte | データ種別 |
| ID | 2 bytes | メッセージID (同一メッセージのフラグメントは同じID) |
| SEQ | 2 bytes | シーケンス番号 (フラグメント番号または順序番号) |
| LENGTH | 2 bytes | Payload のデータ長 |
| Payload | 可変長 | TYPE に応じたデータ |

**ID フィールドの使用方法**
- 各CharacteristicごとにIDカウンタを独立管理
- 各メッセージ（またはトランザクション）に対してユニークなIDを割り当て
- フラグメント化されたパケットは同一IDを持つ

**SEQ フィールドの使用方法**
- 上位ビット (bit 15): MORE フラグ (1: 後続フラグメントあり, 0: 最終/単一パケット)
- 下位15ビット (bit 0-14): フラグメント番号 (同一ID内での順序)
- MTUを超えるペイロードは同一ID、連続したSEQで分割送信
- データ転送系（TRANSFER_AUDIO_FILE）では、チャンク番号をSEQとして使用
- 単一パケットの場合、MORE=0、SEQ=0

### CONTROL Characteristic

#### TYPE (Write with Response)
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| START_TRANSFER_AUDIO_FILE | 0x01 | File ID (4 bytes) | 音声ファイルの転送開始指示 |
| COMPLETE_TRANSFER_AUDIO_FILE | 0x02 | File ID (4 bytes) | 転送完了通知（ファイル削除） |

#### TYPE (Indicate)
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| BEGIN_TRANSFER_AUDIO_FILE | 0x21 | Metadata | 転送開始 |
| END_TRANSFER_AUDIO_FILE | 0x22 | File ID (4 bytes) | 転送終了（Central でハッシュ検証） |

**File ID**
- 音声ファイルの ID
- unixtime (秒) 
- 最も古いファイルを指定する場合はファイル ID を省略します。

**BEGIN_TRANSFER_AUDIO_FILE のペイロード（メタデータ）の構造**
| フィールド | サイズ | 説明 |
|-----------|--------|------|
| File ID | 4 bytes (BE) | ファイル ID (unixtime) |
| File Size | 4 bytes (BE) | ファイルサイズ（バイト） |
| File Hash | 32 bytes | ファイルハッシュ（SHA256） |
| Total Chunks | 2 bytes (BE) | 総チャンク数 |

### STATUS Characteristic

#### TYPE
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| FILE_ADDED | 0x40 | File ID (4 bytes) | ファイル追加通知 |
| FILE_DELETED | 0x41 | File ID (4 bytes) | ファイル削除通知 |

### DATA_TRANSFER Characteristic

#### TYPE
| 名前 | 値 | ペイロード | 説明 |
|---------|-----|-----------|------|
| TRANSFER_AUDIO_FILE | 0x80 | 音声データ（バイナリ） | 転送継続 |

---

## Memo
- Peripheral はなるべくシンプルに
- Central は Status で通知を受けたファイル名をキューする仕組みが必要
- ファイルのリストや充電状況等を通知する機能を追加