# chan-suite

`chan-suite` は、chan シリーズの独立した Web アプリを同じ社内 PC／サーバーへ配置し、一括起動や状態確認を行うためのデプロイ／ランチャー用リポジトリです。各アプリのソースを含む monorepo ではなく、Git submodule／subtree も使用しません。

## リポジトリの関係

```text
chan-suite/
├─ apps/
│  ├─ chan-portal   ← independent Git repository
│  ├─ bochan        ← independent Git repository
│  ├─ malchan       ← independent Git repository
│  ├─ cauchan       ← independent Git repository
│  └─ dchan         ← independent Git repository
├─ config/          ← 共通ポート・パス・有効／無効設定
├─ deploy/          ← 一括管理 PowerShell スクリプト
└─ logs/            ← 実行時ログ（Git 管理外）
```

`apps/` 以下の実アプリと `logs/` 以下の実行時ファイルは chan-suite の Git 管理対象外です。各アプリ内の `.git` は、そのアプリ自身の独立したリポジトリに属します。

## アプリの配置

chan-suite を clone した後、各リポジトリを手動で配置します。自動 clone、pull、依存関係のインストールは行いません。

```powershell
Set-Location .\apps
git clone <chan-portal-repository-url> chan-portal
git clone <bochan-repository-url> bochan
git clone <malchan-repository-url> malchan
git clone <cauchan-repository-url> cauchan
git clone <dchan-repository-url> dchan
Set-Location ..
```

既存のローカルリポジトリを対応する `apps/<name>` に配置しても構いません。パス、ポート、起動対象は `config/apps.json` で変更できます。

## 個別起動と一括操作

各アプリは chan-suite に依存しません。たとえば `Set-Location .\apps\bochan` の後、bochan が従来提供している方法で単独起動できます。

リポジトリルートで次を実行します。

```powershell
# 状態確認
.\deploy\status.ps1

# 一括起動
.\deploy\start_all.ps1

# 一括停止（初期版は安全のため案内のみ）
.\deploy\stop_all.ps1
```

実行ポリシーで拒否される環境では、組織のセキュリティ方針を確認したうえで `powershell.exe -ExecutionPolicy Bypass -File .\deploy\status.ps1` のように実行してください。

### 起動仕様

`start_all.ps1` は `enabled: true` かつディレクトリが存在するアプリだけを扱います。設定ポートのいずれかが LISTEN 中なら二重起動を避けてスキップします。全設定ポートが空いているとき、アプリ直下から次の順で最初のスクリプトを起動します。

1. `start_app.bat`
2. `start_web.bat`
3. `start.bat`
4. `start_app.ps1`
5. `start_web.ps1`
6. `start.ps1`

該当ファイルがなければ警告してスキップし、`npm`、`python`、`uvicorn` などを推測実行しません。標準出力は `logs/<name>.log`、標準エラーは `logs/<name>.error.log` に保存します。Frontend／Backend が別スクリプトの場合は、今後アプリ固有設定を追加する必要があります。

### 停止仕様

初期版は確実なプロセス所有権を検証できないため PID による自動停止を実装していません。`stop_all.ps1` は何も kill せず、各アプリ固有の停止方法を案内します。ポートだけを根拠にした強制終了は行いません。

## 初期ポート

| アプリ | Frontend | Backend API |
|---|---:|---:|
| chan-portal | 5172 | なし |
| bochan | 5173 | 8001 |
| malchan | 5174 | 8002 |
| cauchan | 5175 | 8003 |
| dchan | 5176 | 8004 |

## 社内公開

`127.0.0.1` で待ち受けるサービスには同じ PC からしか接続できません。社内 LAN から利用する場合、各アプリ側の既存設定で、必要に応じて `0.0.0.0` に待受アドレスを変更します。`0.0.0.0` はアクセス用 URL ではありません。利用者は `http://<server-ip>:5172`（chan-portal）など、サーバーの実 IP アドレスまたはホスト名へアクセスします。

chan-portal が各アプリへリンクする URL も、社内公開時には `127.0.0.1` ではなく実際のサーバー IP またはホスト名へ、**chan-portal 側の設定として**変更してください。chan-suite は chan-portal のソースを変更しません。Firewall の許可は必要なポートだけに限定してください。

詳しい配置手順は [docs/deployment.md](docs/deployment.md) を参照してください。
