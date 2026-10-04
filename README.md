# Veeam-JobParameterSheet

Veeam Backup & Replication のバックアップジョブ設定を抽出し、CSV・JSON・HTML パラメータシートとして出力するツールです。

## ファイル構成

| ファイル | 説明 |
|----------|------|
| `veeam.ps1` | ジョブ設定を抽出して CSV/JSON に出力し、パラメータシートを自動生成する |
| `Generate-ParameterSheet.ps1` | `RawJobDefinition.json` から HTML パラメータシートを生成する |
| `Examples/` | サンプル出力ファイル |

## 使い方

### 1. veeam.ps1（通常の使い方）

Veeam Backup PowerShell コンソールで実行します。

```powershell
.\veeam.ps1
```

カレントディレクトリ配下に `Output\YYYYMMDD_HHmmss\` フォルダが作成され、以下のファイルが出力されます。
実行完了後、自動的に HTML パラメータシートも生成されます。

| 出力ファイル | 内容 |
|-------------|------|
| `Jobs.csv` | ジョブ一覧（名前・種別・リポジトリ等） |
| `Objects.csv` | 保護対象 VM 一覧 |
| `Options.csv` | ジョブ詳細設定（縦持ち形式） |
| `Schedule.csv` | スケジュール設定（縦持ち形式） |
| `RawJobDefinition.json` | 全設定の生データ（差分比較用） |
| `RawJobDefinition.html` | HTML パラメータシート |

### 2. Generate-ParameterSheet.ps1（単独実行）

既存の `RawJobDefinition.json` から HTML パラメータシートを再生成します。

```powershell
.\Generate-ParameterSheet.ps1 -JsonPath .\Output\20261004_153000\RawJobDefinition.json
```

`-OutputPath` を指定しない場合は JSON と同じフォルダに `.html` として出力されます。

## 動作環境

- Veeam Backup & Replication がインストールされた Windows サーバー
- Windows PowerShell 5.1 または PowerShell 7 以降
- Veeam Backup PowerShell スナップインが利用可能な環境
