TMSBLEProtocol/PROTOCOL.md に準拠 BLE Server を Node.js で実装してください。

実装先は TMSBLEServer です。

BLEServer の実装には、BLETDataTransferExample/Peripheral/index.js を参考にしてください。

音声ファイルのデフォルト保存先は ~/.tms/recordings です。

なるべくシンプルな実装になるよう心がけてください。

BLE のコネクションが切れたら、各種ステートをリセットするようにしてください。

