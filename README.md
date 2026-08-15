# chan-suite

`chan-suite` は、chan シリーズの独立した Web アプリを同じ PC／社内サーバーへ配置し、一括起動や状態確認を行うデプロイ／ランチャーです。各アプリは monorepo、Git submodule、subtree にせず、独立した Git repository のまま維持します。

## リポジトリと実行環境の関係

```text
                    Git repositories
                         │
           ┌─────────────┼─────────────┐
           │             │             │
        bochan        malchan       cauchan ...
           │
           ├── 開発者 PC
           │      └─ repository 単独の Local 実行
           │
           └── 社内サーバー
                  └─ chan-suite/apps/bochan
                           │
                           └─ Intranet 実行
```

同じソースコードを Git から clone し、**実行環境だけを変える**設計です。依存方向は `chan-suite → 各アプリ` だけであり、各アプリは chan-suite を知らなくても単独で動作します。

```text
chan-suite/
├─ apps/               ← 各アプリの独立した Git repository（Git 管理外）
├─ config/apps.json    ← アプリ固有のパス、ポート、有効／無効
├─ config/profiles.json← Local／Intranet の bind/public host
├─ deploy/             ← clone・一括起動・状態確認スクリプト
└─ logs/               ← 実行時ログ（Git 管理外）
```

## アプリの配置

chan-suite を clone 後、各リポジトリを `apps/` にまとめて clone できます。

Windows:

```cmd
.\deploy\clone_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/clone_all.sh
```

既定では次のリポジトリを `https://github.com/tanakakao/` から clone します。

```text
apps/
├─ chan-portal/
├─ bochan/
├─ malchan/
├─ cauchan/
└─ dchan/
```

既に `.git` を持つディレクトリはスキップします。同名ディレクトリが存在しても Git repository でない場合は上書きせず、エラーとして報告します。clone に失敗した repository があっても残りを処理し、最後に非ゼロ終了コードを返します。

fork や別 owner から clone する場合は `CHAN_GITHUB_OWNER` を指定できます。

```cmd
set CHAN_GITHUB_OWNER=your-account
.\deploy\clone_all.bat
```

```bash
CHAN_GITHUB_OWNER=your-account sh ./deploy/clone_all.sh
```

clone スクリプトは `git pull`、依存関係のインストール、アプリ起動を行いません。既存 repository の更新やセットアップは各アプリ側で個別に管理します。

## Local development

各アプリの従来のローカル開発方法は変更されません。chan-suite を介さず、repository 単独で起動できます。

```powershell
Set-Location .\apps\bochan
<bochan 独自の既存起動方法>
```

chan-suite から一括ローカル起動・確認する場合は次を実行します。`-Profile` 省略時も、安全な `Local` です。

```powershell
.\deploy\start_all.ps1 -Profile Local
.\deploy\status.ps1 -Profile Local
```

Local の bind host と public host はともに `127.0.0.1` です。

## Intranet deployment

社内 LAN へ明示的に公開する実行コンテキストは次のように指定します。

```powershell
.\deploy\start_all.ps1 `
    -Profile Intranet `
    -ServerHost chan-server

.\deploy\status.ps1 -Profile Intranet -ServerHost chan-server
```

`-ServerHost` は利用者が接続できるホスト名または IP です。省略時は `CHAN_SERVER_HOST` 環境変数を参照し、どちらもなければエラーになります。`0.0.0.0` は待受用でありアクセス URL ではありません。利用者は `http://chan-server:5172` から chan-portal へアクセスします。実環境のホスト名や IP は repository に固定しません。

## 起動仕様と環境変数

`start_all.ps1` は `enabled: true` かつディレクトリが存在するアプリだけを扱います。設定ポートのいずれかが LISTEN 中なら二重起動を避けてスキップします。全設定ポートが空いているとき、アプリ直下から次の順で最初のスクリプトを起動します。

1. `start_app.bat`
2. `start_web.bat`
3. `start.bat`
4. `start_app.ps1`
5. `start_web.ps1`
6. `start.ps1`

該当ファイルがなければ警告してスキップし、`npm`、`python`、`uvicorn` などを推測実行しません。標準出力は `logs/<name>.log`、標準エラーは `logs/<name>.error.log` に保存します。

起動時だけ子プロセスへ次の実行コンテキストを渡し、呼び出し元 PowerShell の値は復元します。

- `CHAN_SUITE_PROFILE`
- `CHAN_BIND_HOST`
- `CHAN_PUBLIC_HOST`
- `CHAN_FRONTEND_PORT`
- `CHAN_BACKEND_PORT`

chan-portal には加えて、`apps.json` の各 frontend port と resolved public host から作った `VITE_BOCHAN_URL`、`VITE_MALCHAN_URL`、`VITE_CAUCHAN_URL`、`VITE_DCHAN_URL` を、その子プロセス起動時だけ渡します。各 repository の `.env` や設定ファイルは変更せず、一時ファイルも作りません。

### 各アプリ側で必要な対応

chan-suite は実行コンテキストを提供しますが、実際の bind を強制しません。

```text
chan-suite
    ↓ environment
CHAN_BIND_HOST=0.0.0.0
    ↓
bochan startup script
    ↓
Vite / FastAPI
```

各アプリの起動スクリプトや Vite／FastAPI 設定が `CHAN_BIND_HOST` を参照しなければ、Intranet 指定でも実際の待受アドレスは変わりません。未対応アプリは後続タスクで個別対応が必要です。LISTEN 中のアドレスを取得でき、Intranet で loopback のみと判定された場合、start/status は到達できない可能性を警告します。

## 状態確認・停止

`status.ps1` は profile、bind/public host、各ポートの状態と利用者向け URL を表示します。

```powershell
.\deploy\status.ps1
.\deploy\stop_all.ps1
```

`stop_all.ps1` は確実なプロセス所有権を検証できないため何も kill しません。各アプリ固有の停止方法を案内し、ポートだけを根拠に無関係なプロセスを終了しません。

## 初期ポート

| アプリ | Frontend | Backend API |
|---|---:|---:|
| chan-portal | 5172 | なし |
| bochan | 5173 | 8001 |
| malchan | 5174 | 8002 |
| cauchan | 5175 | 8003 |
| dchan | 5176 | 8004 |

実行ポリシーで拒否される環境では、組織のセキュリティ方針を確認したうえで `powershell.exe -ExecutionPolicy Bypass -File .\deploy\status.ps1` のように実行してください。詳しい配置手順は [docs/deployment.md](docs/deployment.md) を参照してください。
