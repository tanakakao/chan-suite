# 開発者 PC／社内サーバーへの配置

## 前提方針

- chan-suite と各アプリは独立した Git repository として管理します。
- 同じアプリソースを clone し、開発者 PC と社内サーバーでは実行 profile だけを変えます。
- chan-suite は各アプリの `.env` やソースコードを書き換えません。
- Python backend は各アプリの `pyproject.toml` + `uv.lock` を正本とし、repository ごとの `.venv` を uv で生成します。
- Frontend は各アプリの `package.json` + `pnpm-lock.yaml` を正本とします。
- `.venv/` と `node_modules/` は生成物であり Git には含めません。
- Docker、Reverse Proxy、Windows Service、自動更新は使用しません。Linux共通サーバーのOS起動連動だけは、任意でsystemdを利用できます。

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

`start_all.bat` は PowerShell ランチャーを Local profile で呼び出します。

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

Windows の `start_all.ps1` と shell 版 `start_all.sh` は、どちらも `setup_all` が作成した各アプリの `.venv` と pnpm frontend を **chan-suite から直接起動**します。各アプリの `start_web.bat` の bind 設定には依存しません。

起動時は `config/apps.json` のポートを使い、profile に応じて FastAPI / Vite の bind host を直接指定します。Local は `127.0.0.1`、Intranet は `0.0.0.0` です。一方、portal のリンク、Frontend から参照する API URL、CORS origin には `ServerHost` で指定した利用者向け public host を使います。

たとえば次の起動では、

```cmd
.\deploy\start_all.bat Intranet chan-server
```

待受は `0.0.0.0` ですが、利用者向け URL は次のようになります。

```text
http://chan-server:5172
```

`0.0.0.0` をブラウザへ入力する必要はありません。

Windows では標準出力・標準エラーを `logs/<process>.log` / `logs/<process>.error.log` に保存します。Linux版は同じログに加え、安全な停止に必要なPID・実行ディレクトリ・プロセス開始IDを `logs/` に保存します。

### Linux / systemd自動起動

Linux共通サーバーでOS起動後に自動的にchan-suiteを起動する場合は、通常のLinuxユーザーで次を実行します。

```bash
sh ./deploy/systemd/install.sh Intranet <server-host>
```

systemd設定の書き込み時だけ `sudo` を要求し、サービス本体はインストーラーを実行したユーザーとして起動します。インストール時点で動いているアプリは変更せず、次回bootから自動起動します。

現在の手動起動プロセスを安全に停止し、その場でsystemd管理へ切り替える場合:

```bash
sh ./deploy/systemd/install.sh --now Intranet <server-host>
```

確認:

```bash
systemctl is-enabled chan-suite.service
sudo systemctl status chan-suite.service
```

再起動・停止・開始:

```bash
sudo systemctl restart chan-suite.service
sudo systemctl stop chan-suite.service
sudo systemctl start chan-suite.service
```

systemd launcherのログ:

```bash
journalctl -u chan-suite.service
```

frontend/backendのアプリログは従来どおり `logs/` に保存されます。

自動起動を無効化する場合:

```bash
sudo systemctl disable --now chan-suite.service
```

systemd設定を削除する場合:

```bash
sh ./deploy/systemd/uninstall.sh
```

`install.sh` は現在利用している `pnpm`、`node`、Python のパスを `/etc/chan-suite/chan-suite.env` に保存します。Node.jsやpnpmのインストール場所を変更した場合は、インストーラーを再実行してください。

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

systemd管理中に更新する場合は、依存関係の同期後にserviceを再起動してください。

```bash
sh ./deploy/update_all.sh
sh ./deploy/setup_all.sh
sudo systemctl restart chan-suite.service
```

## 開発者 PC

各アプリ repository 単独でも同じlockfile方針で開発・起動できます。

```powershell
Set-Location .\apps\bochan
.\start_web.bat
```

各アプリのPython環境の詳細は、その repository の `ENVIRONMENT.md` を参照してください。各アプリ単独の `start_web.bat` は主に Local 開発用であり、共通サーバーの Intranet 起動は chan-suite の `start_all` を使用します。

## Intranet profile と公開時の注意

`config/profiles.json` は Local の bind/public host を `127.0.0.1`、Intranet の bind host を `0.0.0.0` と定義します。Intranet の public host は環境依存なので repository に保存せず、起動時の `<server-host>` または `CHAN_SERVER_HOST` で指定します。

Windows / shell の両方で、FastAPI と Vite には bind host を直接渡します。malchan / cauchan / dchan の CORS origin と browser-facing API URL には public host を渡すため、`0.0.0.0` がブラウザ向けURLに混ざりません。

Firewallは組織の方針に従い、必要最小限の送信元とポートだけを許可してください。現在の構成では Frontend は5172～5176、Backend APIは8001～8004です。実際の値は `config/apps.json` を正とします。

## 状態確認

Windows:

```cmd
.\deploy\status.bat
.\deploy\status.bat Intranet <server-host>
```

Linux:

```bash
sh ./deploy/status.sh
sh ./deploy/status.sh Intranet <server-host>
```

状態確認では各ポートのLISTEN状態と利用者向けURLを表示します。systemd管理自体の状態は `sudo systemctl status chan-suite.service` で確認します。

## 停止とログ

Windowsの `stop_all.ps1` は安全性を優先し、現時点では実停止を行いません。

```powershell
.\deploy\stop_all.ps1
```

Linuxでは `start_all.sh` が保存した管理情報を照合して、安全に管理対象だけを停止できます。

```bash
sh ./deploy/stop_all.sh
```

PID、実行ディレクトリ、Linux `/proc` のプロセス開始IDを照合し、PID再利用などで別プロセスになっている場合は停止しません。ポート番号だけを根拠にkillすることもありません。

systemd管理時は通常、直接 `stop_all.sh` を呼ぶ代わりに次を使用します。

```bash
sudo systemctl stop chan-suite.service
```

Windows / Linuxともアプリログは `logs/<name>.log` / `logs/<name>.error.log` に保存します。systemd launcherのログは `journalctl -u chan-suite.service` で確認できます。
