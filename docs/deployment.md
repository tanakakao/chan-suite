# 社内 Windows PC／サーバーへの配置

## 前提方針

- chan-suite と各アプリは独立した Git リポジトリとして管理します。
- Python 仮想環境、Node.js 依存関係、環境変数は各アプリ内で個別に管理します。複数アプリで Python 仮想環境を共有しません。
- 本手順は Docker、Reverse Proxy、Windows Service、自動更新を使用しません。

## 配置手順

1. 配置先で chan-suite を clone します。

   ```powershell
   git clone <chan-suite-repository-url> chan-suite
   Set-Location .\chan-suite
   ```

2. `apps/` 配下へ各アプリを clone します。

   ```powershell
   Set-Location .\apps
   git clone <chan-portal-repository-url> chan-portal
   git clone <bochan-repository-url> bochan
   git clone <malchan-repository-url> malchan
   git clone <cauchan-repository-url> cauchan
   git clone <dchan-repository-url> dchan
   Set-Location ..
   ```

3. 各アプリの README に従い、Python／Node.js の依存関係と環境変数を個別にセットアップします。自動インストールは行われません。
4. `.\deploy\status.ps1` を実行し、ディレクトリとポートの状態を確認します。
5. 各アプリのディレクトリへ移動し、それぞれの従来の方法で単独起動できることを確認してから停止します。
6. 各アプリ直下に対応する起動スクリプトがあることを確認し、`.\deploy\start_all.ps1` で一括起動します。未配置のアプリや起動スクリプトのないアプリは安全にスキップされます。
7. 社内 LAN へ公開する場合は、各アプリの待受設定を必要に応じて `0.0.0.0` にし、Windows Defender Firewall で必要な Frontend ポート（5172～5176）の受信だけを許可します。Backend API ポートの直接公開が必要かは個別に判断してください。
8. 別の社内 PC から `http://<server-ip>:5172` へアクセスし、chan-portal とリンク先を確認します。

## 公開時の注意

`0.0.0.0` は全インターフェースで待ち受けるためのアドレスであり、ブラウザへ入力する URL ではありません。利用者は `http://<server-ip>:5172` または `http://<server-hostname>:5172` を使用します。

chan-portal 内の各アプリ URL が `127.0.0.1` のままだと、閲覧者自身の PC を参照してしまいます。chan-portal リポジトリ側の設定を、実際のサーバー IP またはホスト名（bochan は 5173、malchan は 5174、cauchan は 5175、dchan は 5176）へ変更してください。chan-suite からアプリのソースは変更しません。

## 停止とログ

初期版の `.\deploy\stop_all.ps1` は安全性を優先し、プロセスを終了しません。起動したターミナル、または各アプリが提供する停止手順を使用してください。ポート番号だけを根拠にプロセスを kill しないでください。

起動スクリプトの標準出力と標準エラーは `logs/` に保存され、Git には登録されません。障害時はアプリ自身のログと合わせて確認します。
