- 作業ディレクトリ以下で作業するようにしてください。
- 作業ディレクトリ: TMSBLEServer
- 作業ログを ANGENT_LOG.md にタイムスタンプ付きで残すようにしてください。

# 概要
Central　に音声ファイルを BLE により転送する機能を有するプログラムです。

# 要件
- Mac で動作します。
- Node.js で実装します。
- BLE Peripheral として動作します。
- 以下の3つの Characteristic を持ちます。
  - CONTROL
  - STATUS
  - DATA_TRANSFER

## CONTROL Chracteristic
- Central から Peripheral に操作命令を出します。
- Peripheral から Central に、操作命令に対するレスポンスを返します。

### Central から Peripheral への操作命令プロトコル

#### Header
Command             1 byte      操作命令
Payload Length      2 bytes     ペイロードのデータ長

##### Command
- START_TRANSFER_AUDIO_FILE: 音声ファイルを指定して転送するように指示。Payload は ID
- START_TRANSFER_AUDIO_FILE_AUTO: 自動的に音声ファイルを自動転送するように指示
- STOP_TRANSFER_AUDIO_FILE_AUTO: 音声ファイルの自動転送を停止するよう指示
- COMPLETE_TRANSFER_AUDIO_FILE: 音声ファイルの転送が完了したことを Peripheral 側に通知。Peripheral はこれを受けて音声ファイルを削除。

## STATUS Characteristic
- Peripheral から Central に Notify で Status を送信します。

#### Header
Type                1 byte      ステータスのタイプ
ID                  4 bytes     インクリメント
SEQ                 2 bytes     Payload が1回の転送で収まらない場合は複数チャンクに分けて送信。デクリメントしていく。０が最後。
Payload Length      2 bytes     ペイロードのデータ長  

##### Type
- FILE_ADDED: ファイルが追加された時に通知されます。
- FILE_DELETED: ファイルが削除された時に通知されます。

## DATA_TRANSFER
- Peripheral から Central にデータを転送します。

#### Header
Flag                1 byte      データ転送のフラグ
ID                  4 bytes     unixtime
SEQ                 2 bytes     シーケンス番号（デクリメントしていく？
Payload Length      2 bytes     ペイロードのデータ長 

##### Flag
- BEGIN_TRANSFER_AUDIO_FILE: 一連のデータ転送開始時に呼ばれます。Payload はバイナリ。
- CONTINUE_TRANSFER_AUDIO_FILE:  一連のデータ転送中に呼ばれます。Payload はバイナリ。
- END_TRANSFER_AUDIO_FILE:  一連のデータ転送終了時に呼ばれます。Payload はバイナリ。





- ファイルの監視先はデフォルトでは ../TMSAudioRecorder/recorded_audio/ ディレクトリとします。
- 監視先ディレクトリを常に監視し、mp3 ファイルの追加や削除を通知できるようにします。

