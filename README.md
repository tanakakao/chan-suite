# chan-suite

`chan-suite` は、chan シリーズの独立した Web アプリを同じ PC／社内サーバーへ配置し、一括更新・セットアップ・起動・状態確認を行うデプロイ／ランチャーです。各アプリは monorepo、Git submodule、subtree にせず、独立した Git repository のまま維持します。

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
├─ deploy/             ← clone・update・setup・start・status 用スクリプト
└─ logs/               ← 実行時ログ（Git 管理外）
```

## 最短セットアップ

事前に Git、uv、Node.js、pnpm を利用可能にしてください。Python backend の環境は各アプリの `uv.lock`、Frontend は各 `pnpm-lock.yaml` から再現します。

### Windows

```cmd
git clone https://github.com/tanakakao/chan-suite.git
cd chan-suite

.\deploy\clone_all.bat
.\deploy\setup_all.bat
.\deploy\start_all.bat
```

### macOS / Linux / Git Bash

```bash
git clone https://github.com/tanakakao/chan-suite.git
cd chan-suite

sh ./deploy/clone_all.sh
sh ./deploy/setup_all.sh
sh ./deploy/start_all.sh
```

通常の Local 起動では、chan-portal が `http://127.0.0.1:5172`、各アプリが 5173～5176 で起動します。

## 1. アプリをまとめて clone

各リポジトリを `apps/` にまとめて clone します。

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

## 2. 全 repository を安全に update

Windows:

```cmd
.\deploy\update_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/update_all.sh
```

`update_all` は各 repository の現在の branch に対して `git pull --ff-only` だけを実行します。次の場合は勝手に変更せず、その repository をスキップして全体をエラー終了します。

- working tree に未コミット変更がある
- detached HEAD になっている
- 同名ディレクトリが Git repository ではない
- fast-forward だけでは更新できない

したがって、ローカルの開発内容を上書きする目的のスクリプトではありません。

## 3. Python / pnpm 依存関係をまとめて setup

Windows:

```cmd
.\deploy\setup_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/setup_all.sh
```

Python backend を持つ bochan / malchan / cauchan / dchan は **uv 必須**です。各 repository が Git 管理する `pyproject.toml` と `uv.lock` を正本とし、`setup_all` は `uv sync --locked` で repository ごとの `.venv` を作成・同期します。`uv.lock` が無い、または `pyproject.toml` と一致しない場合は、配置先で新しい依存解決を行わずエラー終了します。

Frontend は各 `pnpm-lock.yaml` に対して `pnpm install --frozen-lockfile` を実行します。したがって Python と Frontend のどちらも、開発PC・別PC・社内サーバーで同じ lockfile を利用します。

Python は4アプリで共通して利用できる **3.12** を既定にしています。各 repository の `.python-version` も 3.12 です。必要な場合だけ、各アプリの `requires-python` の範囲内で `CHAN_PYTHON_VERSION` を指定できます。

```cmd
set CHAN_PYTHON_VERSION=3.11
.\deploy\setup_all.bat
```

```bash
CHAN_PYTHON_VERSION=3.11 sh ./deploy/setup_all.sh
```

実際のPython同期コマンドは次の構成です。

- bochan: `uv sync --locked --extra web`
- malchan: `uv sync --locked --extra web --extra models --extra inverse --extra visualization`
- cauchan: `uv sync --locked`
- dchan: `uv sync --locked`
- chan-portal: Python backend なし

`.venv/` は各 repository 内に生成されますが Git には含めません。依存関係を意図的に変更する場合は各アプリ側で `pyproject.toml` を変更して `uv lock` を実行し、`uv.lock` も同じPRで更新します。chan-suite の `setup_all` は lockfile を生成・更新しません。

## 4. 全アプリを起動

### Windows

最も簡単な起動方法は次です。

```cmd
.\deploy\start_all.bat
```

`start_all.bat` は既存の `start_all.ps1` を Local profile で呼び出すラッパーです。PowerShellを直接使うこともできます。

```powershell
.\deploy\start_all.ps1 -Profile Local
```

Intranet profile は次のように指定します。

```cmd
.\deploy\start_all.bat Intranet chan-server
```

```powershell
.\deploy\start_all.ps1 -Profile Intranet -ServerHost chan-server
```

### macOS / Linux / Git Bash

```bash
sh ./deploy/start_all.sh
```

shell 版は各 repository の `.venv` と pnpm frontend を直接起動し、`config/apps.json` のポートを参照します。標準出力・標準エラーと PID は `logs/` に保存します。

Intranet profile:

```bash
sh ./deploy/start_all.sh Intranet chan-server
```

または `CHAN_SERVER_HOST` を利用できます。

```bash
CHAN_SERVER_HOST=chan-server sh ./deploy/start_all.sh Intranet
```

Local の bind/public host は `127.0.0.1`、Intranet の bind host は `0.0.0.0` です。`0.0.0.0` は待受用アドレスであり、ブラウザへ入力する URL ではありません。

## 日常の更新フロー

初回clone後は、基本的に次の3操作で更新できます。

Windows:

```cmd
.\deploy\update_all.bat
.\deploy\setup_all.bat
.\deploy\start_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/update_all.sh
sh ./deploy/setup_all.sh
sh ./deploy/start_all.sh
```

`setup_all` は commit 済みの `uv.lock` / `pnpm-lock.yaml` に従うため、依存関係が変わっていなければ再実行しても同じ環境へ同期されます。

## Local development

各アプリの従来のローカル開発方法は変更されません。chan-suite を介さず、repository 単独で起動できます。

```powershell
Set-Location .\apps\bochan
.\start_web.bat
```

各アプリの `start_web.bat` も lockfile を前提とします。詳細なPython環境管理は各 repository の `ENVIRONMENT.md` を参照してください。

chan-suite は一括管理用であり、各 repository の単独開発を置き換えるものではありません。

## Windows PowerShell 起動仕様

`start_all.ps1` は `enabled: true` かつディレクトリが存在するアプリだけを扱います。設定ポートのいずれかが LISTEN 中なら二重起動を避けてスキップします。全設定ポートが空いているとき、アプリ直下から次の順で最初のスクリプトを起動します。

1. `start_app.bat`
2. `start_web.bat`
3. `start.bat`
4. `start_app.ps1`
5. `start_web.ps1`
6. `start.ps1`

起動時だけ子プロセスへ次の実行コンテキストを渡し、呼び出し元 PowerShell の値は復元します。

- `CHAN_SUITE_PROFILE`
- `CHAN_BIND_HOST`
- `CHAN_PUBLIC_HOST`
- `CHAN_FRONTEND_PORT`
- `CHAN_BACKEND_PORT`

chan-portal には加えて、各 frontend port と resolved public host から作った `VITE_BOCHAN_URL`、`VITE_MALCHAN_URL`、`VITE_CAUCHAN_URL`、`VITE_DCHAN_URL` を渡します。

各アプリのWindows起動スクリプトが `CHAN_BIND_HOST` 等をまだ参照していない場合、Intranet profileでもそのアプリ自身の既定bind hostが優先される場合があります。Local profileには影響しません。shell版 `start_all.sh` はVite/FastAPIへbind hostを直接指定します。

## 状態確認・停止

Windowsでは `status.ps1` で profile、bind/public host、各ポートの状態と利用者向け URL を確認できます。

```powershell
.\deploy\status.ps1
.\deploy\status.ps1 -Profile Intranet -ServerHost chan-server
```

```powershell
.\deploy\stop_all.ps1
```

`stop_all.ps1` は安全性を優先し、ポート番号だけを根拠に無関係なプロセスを kill しません。shell版 `start_all.sh` は起動PIDを `logs/*.pid` に記録しますが、現時点では自動killには使用しません。

## 初期ポート

| アプリ | Frontend | Backend API |
|---|---:|---:|
| chan-portal | 5172 | なし |
| bochan | 5173 | 8001 |
| malchan | 5174 | 8002 |
| cauchan | 5175 | 8003 |
| dchan | 5176 | 8004 |

実際の値は `config/apps.json` を正とします。詳しい配置手順は [docs/deployment.md](docs/deployment.md) を参照してください。
