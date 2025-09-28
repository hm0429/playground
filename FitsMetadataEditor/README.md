# FITS Metadata Editor

FITSファイルのメタデータを表示・編集するためのPythonツール集です。

## 機能

### 現在実装済み
- **fits_metadata_viewer.py**: FITSファイルのメタデータを表示
  - すべてのHDU（Header Data Unit）の概要表示
  - 特定HDUのヘッダー情報の詳細表示
  - キーワードによるフィルタリング
  - 複数HDUの一括表示

- **fits_metadata_editor.py**: FITSファイルのメタデータを編集
  - メタデータの追加
  - メタデータの更新
  - メタデータの削除
  - インタラクティブ編集モード
  - バッチ編集機能（JSONファイルから一括編集）
  - 自動バックアップ機能

## インストール

1. 必要な依存関係をインストール:
```bash
pip install -r requirements.txt
```

## 使用方法

### FITSメタデータビューアー

基本的な使い方:
```bash
python fits_metadata_viewer.py your_file.fits
```

#### オプション

- `--hdu, -h`: 表示するHDUのインデックスを指定（デフォルト: 0）
  ```bash
  python fits_metadata_viewer.py your_file.fits --hdu 1
  ```

- `--filter, -f`: 特定のキーワードを含むメタデータのみ表示
  ```bash
  python fits_metadata_viewer.py your_file.fits --filter DATE
  ```

- `--no-comments`: コメント列を非表示にする
  ```bash
  python fits_metadata_viewer.py your_file.fits --no-comments
  ```

- `--all-hdus, -a`: すべてのHDUのメタデータを表示
  ```bash
  python fits_metadata_viewer.py your_file.fits --all-hdus
  ```

### FITSメタデータエディター

基本的な使い方:

#### 1. メタデータの追加
新しいキーワードをヘッダーに追加:
```bash
python fits_metadata_editor.py add your_file.fits --keyword NEWKEY --value "新しい値" --comment "説明"

# 例：プロジェクト名を追加
python fits_metadata_editor.py add sample.fits -k PROJECT -v "MyProject" -c "プロジェクト名"
```

#### 2. メタデータの更新
既存のキーワードの値を変更:
```bash
python fits_metadata_editor.py update your_file.fits --keyword OBSERVER --value "新しい観測者名"

# コメントも更新する場合
python fits_metadata_editor.py update sample.fits -k OBSERVER -v "John Doe" -c "更新された観測者"
```

#### 3. メタデータの削除
キーワードを削除:
```bash
python fits_metadata_editor.py delete your_file.fits --keyword OLDKEY

# 確認プロンプトが表示されます
python fits_metadata_editor.py delete sample.fits -k COMMENT
```

#### 4. インタラクティブモード
対話式でメタデータを編集:
```bash
python fits_metadata_editor.py interactive your_file.fits

# 特定のHDUを編集
python fits_metadata_editor.py interactive sample.fits --hdu 1
```

インタラクティブモードのコマンド:
- `a` - 新しいキーワードを追加
- `u` - 既存のキーワードを更新
- `d` - キーワードを削除
- `l` - すべてのキーワードをリスト表示
- `h` - 編集するHDUを変更
- `s` - 変更を保存
- `q` - 終了

#### 5. バッチ編集
JSONファイルから複数の編集を一括実行:
```bash
python fits_metadata_editor.py batch your_file.fits batch_operations.json

# HDUを指定する場合
python fits_metadata_editor.py batch sample.fits batch_example.json --hdu 0
```

JSONファイルの形式:
```json
[
  {
    "action": "add",
    "keyword": "PROJECT",
    "value": "Sample Project",
    "comment": "Project name"
  },
  {
    "action": "update",
    "keyword": "OBSERVER",
    "value": "Updated Observer",
    "comment": "Updated via batch"
  },
  {
    "action": "delete",
    "keyword": "OLDKEY"
  }
]
```

#### エディターオプション

- `--no-backup`: バックアップファイルを作成しない（デフォルトは作成）
  ```bash
  python fits_metadata_editor.py --no-backup add sample.fits -k TEST -v "値"
  ```

- `--hdu, -h`: 編集するHDUのインデックスを指定（デフォルト: 0）
  ```bash
  python fits_metadata_editor.py add sample.fits --hdu 1 -k KEYWORD -v VALUE
  ```

### 表示例

スクリプトを実行すると、以下のような情報が表示されます：

1. **ファイル情報**
   - ファイル名
   - フルパス
   - ファイルサイズ
   - HDUの数

2. **HDUサマリー**
   - 各HDUのインデックス、名前、タイプ、データ形状、ヘッダーカード数

3. **ヘッダーメタデータ**
   - キーワード、値、コメントの表形式表示

## 依存関係

- Python 3.8以上
- astropy: FITSファイルの読み書き
- numpy: 数値計算
- tabulate: 表形式での出力
- click: コマンドラインインターフェース

## 今後の実装予定

- メタデータのエクスポート機能（CSV、JSON形式）
- メタデータの検証機能（必須キーワードのチェック）
- 複数ファイルの一括処理
- メタデータのテンプレート機能
- ヘッダーの比較機能

## ライセンス

MIT License

## トラブルシューティング

### FITSファイルが読み込めない場合
- ファイルパスが正しいか確認してください
- ファイルが破損していないか確認してください
- ファイルの拡張子が`.fits`、`.fit`、`.fts`のいずれかであることを確認してください

### 警告メッセージが表示される場合
スクリプトは検証警告を抑制していますが、重大なエラーがある場合は表示されます。
