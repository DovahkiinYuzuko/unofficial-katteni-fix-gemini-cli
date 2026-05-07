# Unofficial Katteni Fix for Gemini CLI (Windows)

## 目次 / INDEX
[日本語](#日本語) | [English](#english)

---

## 日本語

### 概要
このスクリプト（`patch_gemini.ps1`）は、Windows環境における Gemini CLI の動作不良やパフォーマンスの問題を解決するための非公式パッチです。
公式リポジトリに修正がマージされるまでの間の「応急処置」として作成されました。npmでグローバルインストールされたGemini CLIのビルド済みファイルを直接修正し、以下の問題を解決します。

**プルリクエスト:**
[https://github.com/google-gemini/gemini-cli/pull/26392](https://github.com/google-gemini/gemini-cli/pull/26392)

### 修正される問題
1. **スラッシュコマンドの無効化バグ**: `/model` などのコマンドがAIへのプロンプトとして誤認識される問題を修正します。
2. **起動時のハングアップ**: 起動時に数分間フリーズする問題（WMIスキャンのタイムアウト欠如）を修正し、起動を高速化します。
3. **ゾンビプロセスの残留**: 実行をキャンセルした際に裏でプロセスが残り続ける問題を、Windows標準の `taskkill` を用いて物理的に終了させることで解決します。
4. **ログの消失**: 短いタスクを実行した後にログが `latest.log` に書き出されない問題（バッファ制限）を修正し、即時書き出しに変更します。

### 動作要件
* Windows 10 または Windows 11
* Node.js および npm がインストールされていること
* Gemini CLI がグローバルインストールされていること（`npm install -g @google/gemini-cli`）

### 使い方
1. 本リポジトリ（またはGist）から `patch_gemini.ps1` をダウンロードします。
2. PowerShellを**管理者権限**で起動します。
3. スクリプトが保存されているディレクトリに移動し、スクリプトを実行します。
```powershell
.\patch_gemini.ps1
```

### オプション機能
* **確認モード (Dry Run)**: 実際にファイルを書き換えずに、どのファイルが修正対象になるかを確認します。
  ```powershell
  .\patch_gemini.ps1 -DryRun
  ```
* **復元モード (Restore)**: パッチ適用時に自動作成されたバックアップ（`.bak`）から、ファイルを元の状態に戻します。
  ```powershell
  .\patch_gemini.ps1 -Restore
  ```

### 想定される問題とトラブルシューティング

#### Q. 「スクリプトの実行がシステムで無効になっている」というエラーが出る
PowerShellのセキュリティ設定により、ダウンロードしたスクリプトの実行がブロックされています。管理者権限のPowerShellで以下のコマンドを実行し、一時的に実行ポリシーを許可してください。
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
```

#### Q. 「npmコマンドが見つからない」と表示される
Node.jsがインストールされていないか、環境変数（PATH）に登録されていません。Node.jsをインストールし直すか、システムの環境変数設定を確認してください。

#### Q. Gemini CLIをアップデートしたらバグが再発した
`npm update -g @google/gemini-cli` などでCLIをアップデートすると、ファイルが公式の（バグを含んだ）状態に上書きされます。アップデート後は再度このパッチスクリプトを実行してください。

### 免責事項
本スクリプトは非公式のコミュニティパッチです。MITライセンスのもとで提供されており、「現状のまま」いかなる保証もなしに提供されます。本スクリプトの使用によって生じたデータの損失や環境の破損について、作成者は一切の責任を負いません。自己責任でご使用ください。

---

## English

### Overview
This script (`patch_gemini.ps1`) is an unofficial hotfix to resolve critical bugs and performance issues with the Gemini CLI on Windows environments.
It acts as a temporary workaround until official fixes are merged, by directly patching the compiled JavaScript bundle of your globally installed Gemini CLI.

**PR:**
[https://github.com/google-gemini/gemini-cli/pull/26392](https://github.com/google-gemini/gemini-cli/pull/26392)

### What it Fixes
1. **Slash Command Bug**: Fixes the issue where commands like `/model` are incorrectly sent as regular prompts to the AI.
2. **Startup Hang**: Eliminates the multi-minute freeze on startup by adding a 5000ms timeout to WMI process scans.
3. **Zombie Processes**: Fixes the issue where background processes remain active after cancellation by implementing Windows-native `taskkill` for proper process tree termination.
4. **Missing Logs**: Resolves the issue where execution logs are not written to `latest.log` after short tasks by modifying the buffer limit to force immediate flushing.

### Requirements
* Windows 10 or Windows 11
* Node.js and npm installed
* Gemini CLI installed globally (`npm install -g @google/gemini-cli`)

### Usage
1. Download `patch_gemini.ps1`.
2. Open PowerShell as an **Administrator**.
3. Navigate to the directory where the script is saved and run it:
```powershell
.\patch_gemini.ps1
```

### Options
* **Dry Run**: Preview which files will be modified without actually changing them.
  ```powershell
  .\patch_gemini.ps1 -DryRun
  ```
* **Restore**: Revert the files to their original state using the automatically generated `.bak` backups.
  ```powershell
  .\patch_gemini.ps1 -Restore
  ```

### Troubleshooting

#### Q. I get an error saying "execution of scripts is disabled on this system."
PowerShell blocks the execution of downloaded scripts by default. Open PowerShell as an Administrator and run the following command to temporarily allow script execution:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
```

#### Q. I get an error saying "npm is not recognized."
Node.js is either not installed or not in your system's PATH. Please install Node.js or check your environment variables.

#### Q. The bugs came back after I updated the Gemini CLI.
Updating the CLI (e.g., via `npm update -g @google/gemini-cli`) overwrites the patched files with the official codebase. You will need to run this patch script again after every update.

### Disclaimer
This is an unofficial community patch provided under the MIT License. It is provided "as is", without warranty of any kind. The author is not responsible for any data loss, system instability, or other damages resulting from the use of this script. Use at your own risk.