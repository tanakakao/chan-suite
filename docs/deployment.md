# 開発者 PC／社内サーバーへの配置

## 前提方針

- chan-suite と各アプリは独立した Git repository として管理します。
- 同じアプリソースを clone し、開発者 PC と社内サーバーでは実行 profile だけを変えます。
- chan-suite は各アプリの `.env` やソースコードを書き換えません。
- Python backend は各アプリの `pyproject.toml` + `uv.lock` を正本とし、repository ごとの `.venv` を uv で生成します。
- Frontend は各アプリの `package.json` + `pnpm-lock.yaml` を正本とします。
- `.venv/` と `node_modules/` は生成物であり Git には含めません。
- Docker、Reverse Proxy、Windows Service、自動更新は使用しません。

## 必要なツール

配置先では次を利用可能にしてください。

- Git
- uv
- Node.js
- pnpm

Python は既定で 3.12 を使用します。各 Python repository も `.python-version` で 3.12 を既定としています。

## 推奨ライフサイクル

```text
初回:
clone_all
   ↓
setup_all
   ↓
start_all

以後:
update_all
   ↓
setup_all
   ↓
start_all
```

`clone`、`update`、`setup`、`start` を別スクリプトに分離し、repository 更新だけで依存関係やプロセスを暗黙に変更しない設計です。

## 1. chan-suite を clone

```powershell
git clone https://github.com/tanakakao/chan-suite.git chan-suite
Set-Location .\chan-suite
```

## 2. 各アプリを一括 clone

Windows:

```cmd
.\deploy\clone_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/clone_all.sh
```

既定では `tanakakao/chan-portal`、`tanakakao/bochan`、`tanakakao/malchan`、`tanakakao/cauchan`、`tanakakao/dchan` を `apps/` 配下へ clone します。既に Git repository として存在するディレクトリはスキップし、非 Git の同名ディレクトリは上書きしません。

別 owner の repository を使う場合:

```cmd
set CHAN_GITHUB_OWNER=your-account
.\deploy\clone_all.bat
```

```bash
CHAN_GITHUB_OWNER=your-account sh ./deploy/clone_all.sh
```

## 3. 依存関係を一括 setup

Windows:

```cmd
.\deploy\setup_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/setup_all.sh
```

### Python

bochan / malchan / cauchan / dchan は、各 repository に commit された `uv.lock` を使います。`setup_all` は新しいlockfileを生成せず、必ず `uv sync --locked` で `.venv` を同期します。

```text
bochan    uv sync --locked --extra web
malchan   uv sync --locked --extra web --extra models --extra inverse --extra visualization
cauchan   uv sync --locked
dchan     uv sync --locked
```

`uv.lock` が存在しない場合、または `pyproject.toml` と lockfile が一致しない場合はエラーにします。社内サーバーや利用者PCで依存バージョンを暗黙に再解決しません。

依存関係を意図的に変更する場合は、対象アプリの開発PRで次の順に行います。

```text
pyproject.toml を変更
      ↓
uv lock
      ↓
uv.lock の差分をレビュー
      ↓
uv sync --locked ... / tests
      ↓
pyproject.toml と uv.lock を同じPRでcommit
```

`.venv/` は各checkoutごとの生成物なので commit しません。

Python 3.12 以外を意図的に使う場合は、対象アプリの `requires-python` の範囲内で `CHAN_PYTHON_VERSION` を指定できます。

```cmd
set CHAN_PYTHON_VERSION=3.11
.\deploy\setup_all.bat
```

```bash
CHAN_PYTHON_VERSION=3.11 sh ./deploy/setup_all.sh
```

通常運用では 3.12 のまま使うことを推奨します。

### Frontend

Frontend は各 repository の pnpm lockfile を使用します。

```text
chan-portal      ./pnpm-lock.yaml
bochan           web/pnpm-lock.yaml
malchan          frontend/pnpm-lock.yaml
cauchan          web/pnpm-lock.yaml
dchan            frontend/pnpm-lock.yaml
```

すべて `pnpm install --frozen-lockfile` で導入し、lockfile がない場合は暗黙に作成せずエラーにします。

## 4. 全アプリを起動

### Windows / Local

```cmd
.\deploy\start_all.bat
```

`start_all.bat` は既存のPowerShellランチャーを呼び出します。

```powershell
.\deploy\start_all.ps1 -Profile Local
```

### Windows / Intranet

```cmd
.\deploy\start_all.bat Intranet <server-host>
```

または:

```powershell
.\deploy\start_all.ps1 -Profile Intranet -ServerHost <server-host>
```

### macOS / Linux / Git Bash

Local:

```bash
sh ./deploy/start_all.sh
```

Intranet:

```bash
sh ./deploy/start_all.sh Intranet <server-host>
```

または:

```bash
CHAN_SERVER_HOST=<server-host> sh ./deploy/start_all.sh Intranet
```

shell版は `setup_all` が作成した各アプリの `.venv` と pnpm frontend を直接起動します。ポートは `config/apps.json` を読み取り、Vite/FastAPIへbind hostを直接指定します。標準出力・標準エラー・PIDは `logs/` 配下へ保存します。

## 5. repositoryを一括 update

Windows:

```cmd
.\deploy\update_all.bat
```

macOS / Linux / Git Bash:

```bash
sh ./deploy/update_all.sh
```

各 repository の現在branchに対して `git pull --ff-only` を実行します。working treeに変更がある、detached HEAD、fast-forwardできない、非Gitディレクトリ、といった状態では更新せずエラーにします。

このため、開発中のローカル変更を自動stash・reset・mergeすることはありません。更新後に `setup_all` を再実行すれば、変更後の `uv.lock` / `pnpm-lock.yaml` とローカル環境が同期されます。

## 開発者 PC

各アプリ repository 単独でも同じlockfile方針で開発・起動できます。

```powershell
Set-Location .\apps\bochan
.\start_web.bat
```

各アプリのPython環境の詳細は、その repository の `ENVIRONMENT.md` を参照してください。chan-suiteの一括操作は、各repository単独の開発方法を置き換えるものではありません。

## Intranet profile と公開時の注意

`config/profiles.json` は Local の bind/public host を `127.0.0.1`、Intranet の bind host を `0.0.0.0` と定義します。Intranet の public host は環境依存なので repository に保存しません。`0.0.0.0` はブラウザへ入力する URL ではありません。

Windowsの `start_all.ps1` は各repositoryの既存起動スクリプトへ `CHAN_BIND_HOST` などを渡します。その起動スクリプト側がまだこれらの値を参照していない場合、アプリ自身の既定bind hostが優先される場合があります。Local profileには影響しません。

shell版 `start_all.sh` はFastAPI/Viteへbind hostを直接指定します。

Firewallは組織の方針に従い、必要最小限の送信元とポートだけを許可してください。Frontendは初期設定で5172～5176、Backend APIは8001～8004です。実際の値は `config/apps.json` を正とします。

## 状態確認

Windows:

```powershell
.\deploy\status.ps1 -Profile Local
.\deploy\status.ps1 -Profile Intranet -ServerHost <server-host>
```

状態確認では各ポートのLISTEN状態と利用者向けURLを表示します。

## 停止とログ

```powershell
.\deploy\stop_all.ps1
```

`stop_all.ps1` は安全性を優先し、ポート番号だけを根拠に無関係なプロセスをkillしません。各アプリ固有の停止手順を案内します。

Windows PowerShell起動のログは `logs/<name>.log` / `logs/<name>.error.log` に保存します。shell版はFrontend/Backendごとのログと `logs/*.pid` を保存しますが、PIDは現時点では自動killには使いません。
