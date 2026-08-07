# 開発者 PC／社内 Windows サーバーへの配置

## 前提方針

- chan-suite と各アプリは独立した Git repository として管理します。
- 同じアプリソースを clone し、開発者 PC と社内サーバーでは実行 profile だけを変えます。
- chan-suite は各アプリの `.env`、Vite／FastAPI 設定、起動スクリプトを書き換えません。
- Python 仮想環境と Node.js 依存関係は各アプリ内で個別に管理します。
- Docker、Reverse Proxy、Windows Service、自動更新は使用しません。

## 開発者 PC

各アプリ repository 単独で従来どおり開発・起動し、`127.0.0.1` での待受を基本とします。

```powershell
Set-Location .\apps\bochan
<bochan 独自の既存起動方法>
```

一括ローカル起動が必要な場合だけ repository root から実行します。profile 省略時も Local です。

```powershell
.\deploy\start_all.ps1 -Profile Local
.\deploy\status.ps1 -Profile Local
```

## 社内サーバー

1. 配置先で chan-suite を clone します。

   ```powershell
   git clone <chan-suite-repository-url> chan-suite
   Set-Location .\chan-suite
   ```

2. 各 repository を `chan-suite/apps/` 配下へ clone します。

   ```powershell
   Set-Location .\apps
   git clone <chan-portal-repository-url> chan-portal
   git clone <bochan-repository-url> bochan
   git clone <malchan-repository-url> malchan
   git clone <cauchan-repository-url> cauchan
   git clone <dchan-repository-url> dchan
   Set-Location ..
   ```

3. 各アプリの README に従い、依存関係を個別にセットアップします。
4. 各アプリを従来の方法で単独起動できることを確認して停止します。
5. 利用者が名前解決・到達できるホストを指定して一括起動します。

   ```powershell
   .\deploy\start_all.ps1 `
       -Profile Intranet `
       -ServerHost <server-host>
   ```

   `-ServerHost` を省略する場合は、先に `$env:CHAN_SERVER_HOST = '<server-host>'` を設定します。parameter が環境変数より優先されます。両方なければ安全にエラー終了します。

6. 状態と URL を確認します。

   ```powershell
   .\deploy\status.ps1 -Profile Intranet -ServerHost <server-host>
   ```

7. Windows Defender Firewall では必要な Frontend ポート（5172～5176）だけを許可します。Backend API ポートを直接公開するかは個別に判断します。
8. 別の社内 PC から `http://<server-host>:5172` へアクセスします。

## Profile と公開時の注意

`config/profiles.json` は Local の bind/public host を `127.0.0.1`、Intranet の bind host を `0.0.0.0` と定義します。Intranet の public host は環境依存なので repository に保存しません。`0.0.0.0` はブラウザへ入力する URL ではありません。

chan-suite は `CHAN_BIND_HOST` などを子プロセスへ渡すだけです。各アプリの起動スクリプトと Vite／FastAPI がその値を利用するまでは、Intranet profile だけで LAN 公開は完結しません。各アプリの対応状況を確認してください。chan-portal のリンク URL は `VITE_<APP>_URL` として起動時環境に渡されますが、chan-portal 側がそれらを参照する必要があります。

Intranet 状態確認で listener が loopback のみと判定できた場合は警告します。Firewall は組織の方針に従い、必要最小限の送信元とポートに限定してください。

## 停止とログ

`.\deploy\stop_all.ps1` は安全性を優先し、プロセスを終了しません。起動したターミナル、または各アプリが提供する停止手順を使用してください。ポート番号だけを根拠にプロセスを kill しません。

起動スクリプトの標準出力と標準エラーは `logs/` に保存され、Git には登録されません。
