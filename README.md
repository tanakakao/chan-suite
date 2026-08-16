# chan-suite

`chan-suite` は、chan シリーズの独立した Web アプリを同じ PC／社内サーバーへ配置し、一括更新・セットアップ・起動・状態確認を行うデプロイ／ランチャーです。各アプリは monorepo、Git submodule、subtree にせず、独立した Git repository のまま維持します。

## 最短セットアップ

配置先にはあらかじめ **Git、uv、Node.js、pnpm** を用意してください。その後は chan-suite を clone して、リポジトリ直下の初期セットアップスクリプトを1回実行するだけです。

### Windows

```cmd
git clone https://github.com/tanakakao/chan-suite.git
cd chan-suite
install.bat
```

初期セットアップ後、そのまま全アプリを起動する場合:

```cmd
install.bat --start
```

### macOS / Linux / Git Bash

```bash
git clone https://github.com/tanakakao/chan-suite.git
cd chan-suite
sh ./install.sh
```

初期セットアップ後、そのまま全アプリを起動する場合:

```bash
sh ./install.sh --start
```

`install.bat` / `install.sh` は次を順番に実行します。

```text
前提ツール確認
   ↓
clone_all
   ├─ chan-portal
   ├─ bochan
   ├─ malchan
   ├─ cauchan
   └─ dchan
   ↓
setup_all
   ├─ Python: uv.lock → repositoryごとの .venv
   └─ Frontend: pnpm-lock.yaml → node_modules
   ↓
完了
   └─ --start 指定時のみ start_all
```

初期セットアップスクリプトは Git / uv / Node.js / pnpm のOSへのインストール自体は行いません。ツール不足時は処理を開始せず、不足しているツールを表示して終了します。

通常の Local 起動では、chan-portal が `http://127.0.0.1:5172`、各アプリが 5173～5176 で起動します。

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
├─ install.bat         ← Windows初期セットアップ
├─ install.sh          ← macOS/Linux/Git Bash初期セットアップ
├─ apps/               ← 各アプリの独立した Git repository（Git 管理外）
├─ config/apps.json    ← アプリ固有のパス、ポート、有効／無効
├─ config/profiles.json← Local／Intranet の bind/public host
├─ deploy/             ← clone・update・setup・start・status 用スクリプト
└─ logs/               ← 実行時ログ（Git 管理外）
```

## 個別操作

初期導入では通常 `install.bat` / `install.sh` を使えば十分です。以下は各処理を個別に実行したい場合に使用します。

### 1. アプリをまとめて clone

Windows:

```cmd
.\deploy\clone_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/clone_all.sh
```

既定では次のリポジトリを `https://github.com/tanakakao/` から `apps/` 配下へ clone します。

```text
apps/
├─ chan-portal/
├─ bochan/
├─ malchan/
├─ cauchan/
└─ dchan/
```

既に `.git` を持つディレクトリはスキップします。同名ディレクトリが存在しても Git repository でない場合は上書きせず、エラーとして報告します。fork や別 owner から clone する場合は `CHAN_GITHUB_OWNER` を指定できます。

### 2. 全 repository を安全に update

Windows:

```cmd
.\deploy\update_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/update_all.sh
```

`update_all` は各 repository の現在の branch に対して `git pull --ff-only` だけを実行します。working tree に未コミット変更がある、detached HEAD、非Gitディレクトリ、fast-forwardできない場合は勝手に変更せずエラーとして報告します。

### 3. Python / pnpm 依存関係をまとめて setup

Windows:

```cmd
.\deploy\setup_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/setup_all.sh
```

Python backend を持つ bochan / malchan / cauchan / dchan は **uv 必須**です。各 repository が Git 管理する `pyproject.toml` と `uv.lock` を正本とし、`setup_all` は `uv sync --locked` で repository ごとの `.venv` を作成・同期します。`uv.lock` が無い、または `pyproject.toml` と一致しない場合は配置先で新しい依存解決を行わずエラー終了します。

実際の同期範囲は次のとおりです。

- bochan: `uv sync --locked --extra web`
- malchan: `uv sync --locked --extra web --extra models --extra inverse --extra visualization`
- cauchan: `uv sync --locked`
- dchan: `uv sync --locked`
- chan-portal: Python backend なし

Frontend は各 `pnpm-lock.yaml` に対して `pnpm install --frozen-lockfile` を実行します。

Python は **3.12** を既定にしています。必要な場合だけ、各アプリの `requires-python` の範囲内で `CHAN_PYTHON_VERSION` を指定できます。

`.venv/` と `node_modules/` は各PC上の生成物であり Git には含めません。依存関係を意図的に変更する場合は各アプリ側で `pyproject.toml` を変更して `uv lock` を実行し、`uv.lock` も同じPRで更新します。chan-suite の `setup_all` は lockfile を生成・更新しません。

### 4. 全アプリを起動

Windows:

```cmd
.\deploy\start_all.bat
```

PowerShellを直接使う場合:

```powershell
.\deploy\start_all.ps1 -Profile Local
```

Intranet profile:

```cmd
.\deploy\start_all.bat Intranet chan-server
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/start_all.sh
```

Intranet profile:

```bash
sh ./deploy/start_all.sh Intranet chan-server
```

shell版は各 repository の `.venv` と pnpm frontend を直接起動し、`config/apps.json` のポートを参照します。標準出力・標準エラーと PID は `logs/` に保存します。

## 日常の更新フロー

初回セットアップ後は、基本的に次の3操作です。

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

各アプリは chan-suite を介さず、repository 単独でも開発・起動できます。

```powershell
Set-Location .\apps\bochan
.\start_web.bat
```

各アプリの `start_web.bat` も lockfile を前提とします。詳細なPython環境管理は各 repository の `ENVIRONMENT.md` を参照してください。

## 状態確認・停止

Windows:

```powershell
.\deploy\status.ps1
.\deploy\status.ps1 -Profile Intranet -ServerHost chan-server
.\deploy\stop_all.ps1
```

`stop_all.ps1` は安全性を優先し、ポート番号だけを根拠に無関係なプロセスを kill しません。

## 初期ポート

| アプリ | Frontend | Backend API |
|---|---:|---:|
| chan-portal | 5172 | なし |
| bochan | 5173 | 8001 |
| malchan | 5174 | 8002 |
| cauchan | 5175 | 8003 |
| dchan | 5176 | 8004 |

実際の値は `config/apps.json` を正とします。詳しい配置手順は [docs/deployment.md](docs/deployment.md) を参照してください。
