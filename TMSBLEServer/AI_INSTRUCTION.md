TMSBLEProtocol/PROTOCOL.md に準拠 BLE Server を Node.js で実装してください。

実装先は TMSBLEServer です。

BLEServer の実装には、BLETDataTransferExample/Peripheral/index.js を参考にしてください。

音声ファイルのデフォルト保存先は ~/.tms/recordings です。

音声ファイルは YYYYMMDDHHMMSS.mp3 という形式になっているため、この日時から unixtime (秒) を取得し、File ID として使用するようにしてください。

なるべくシンプルな実装になるよう心がけてください。

BLE のコネクションが切れたら、各種ステートをリセットするようにしてください。

