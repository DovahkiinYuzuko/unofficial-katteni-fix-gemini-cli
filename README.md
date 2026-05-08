# Unofficial Katteni Fix for Gemini CLI (Windows)

## 目次 / INDEX
[日本語](#日本語) | [English](#english)

---

## 日本語

### 概要
このスクリプト（`patch_gemini.ps1`）は、Windows環境における Gemini CLI の動作不良やパフォーマンスの問題を解決するための非公式パッチです。
公式リポジトリに修正がマージされるまでの間の「応急処置」として作成されました。npmでグローバルインストールされたGemini CLIのビルド済みファイルを直接修正し、計13項目の重要な改善を適用します。

**プルリクエスト:**
[https://github.com/google-gemini/gemini-cli/pull/26392](https://github.com/google-gemini/gemini-cli/pull/26392)

### 修正される問題
1. **スラッシュコマンドの改善**: `/model` などのコマンド末尾の空白や改行をトリムし、AIへの誤送信を確実に防ぎます。
2. **ゾンビプロセスの完全終了**: 実行キャンセル時に裏でプロセスが残り続ける問題を、Windows標準の `taskkill /F /T` で解決。自己殺害防止ガード付きです。
3. **APIリトライの強化**: `GET` に加え `POST` リクエストもリトライ対象とし、ネットワーク耐性を向上。
4. **モデル選択の自動ループ（Autoモード改善）**: 429エラー時にモデル（Pro/Flash/Lite）を自動でローテーションして継続させます。
5. **トークン上限の動的解放**: Gemini 3等のモデルで上限を自動的に最大10Mまで引き上げ、ポテンシャルを解放します。
6. **リトライUIの改善**: 「FlashからProに切り替え中」などの詳細な状況をリアルタイムで表示します。
7. **ログのリアルタイム書き出し**: 短いタスクでも即座に `latest.log` に反映されるよう、バッファを最適化。
8. **サブエージェントの無限ループ封印**: 3回連続でツール実行に失敗した場合に自動停止する安全装置（サーキットブレーカー）を導入。
9. **バイナリインジェクション対応**: 画像等のバイナリデータを扱う際のモデルの安定性を劇的に向上させる新プロトコルを実装。
10. **スケジューラのフリーズ防止**: ツール実行の待機処理にタイムアウトとループ制限を設け、CLIのハングを物理的に防ぎます。
11. **サブエージェントの429耐性**: サブエージェント側でも最大10回までの指数バックオフ付き自動リトライを実行します。
12. **WriteFileの信頼性向上**: AIによる自動修正が失敗した場合でも、オリジナル内容で書き込むフォールバックを実装。
13. **二重適用防止ガード（等冪性の確保）**: パッチを何度実行しても `SyntaxError` にならない高度な正規表現ガードを搭載。

### 動作要件
* Windows 10 または Windows 11
* Node.js および npm がインストールされていること
* Gemini CLI がグローバルインストールされていること（`npm install -g @google/gemini-cli`）

### 使い方（推奨）
パッチを適用する前に、Gemini CLIを一度クリーンインストールすることを強く推奨します。

1. **Gemini CLIの再インストール**（クリーンな状態にするため）:
   ```powershell
   npm uninstall -g @google/gemini-cli
   npm install -g @google/gemini-cli
   ```
2. 本リポジトリ（またはGist）から `patch_gemini.ps1` をダウンロードします。
3. PowerShellを**管理者権限**で起動します。
4. スクリプトが保存されているディレクトリに移動し、スクリプトを実行します。
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
1. **Slash Command Improvements**: Trims whitespace/newlines from commands like `/model` to prevent them from being incorrectly sent as prompts to the AI.
2. **Proper Process Termination**: Fixes the issue where background processes remain active after cancellation by implementing Windows-native `taskkill /F /T` for complete process tree termination. Includes safety guards to prevent self-killing.
3. **Enhanced API Retries**: Adds `POST` support to retry logic for improved network resilience.
4. **Auto-Model Selection Loop**: Improves the Auto mode fallback logic. Instead of stopping after one failed attempt, it now loops through available models (Pro/Flash/Lite) when encountering 429 (Quota) errors.
5. **Dynamic Token Limit Expansion**: Automatically increases the CLI's internal token limit (from 1M up to 10M) when using next-gen models like Gemini 3, unlocking their full potential.
6. **Improved Retry UI Feedback**: Provides real-time status updates in the terminal during model switching and backoff periods (e.g., "Switching from Flash to Pro due to availability issues...").
7. **Real-time Log Flushing**: Optimizes log buffering so that `latest.log` is updated immediately, even for very short tasks.
8. **Subagent Circuit Breaker**: Stops subagents after 3 consecutive tool failures to prevent repetitive errors and token waste.
9. **Binary Injection Protocol**: New 3-turn injection protocol (Tool Response -> Synthetic Model Ack -> Binary Data) for stable multi-modal processing.
10. **Scheduler Hardening**: Prevents main agent hangs with 60s timeouts and 1000-iteration loop limits.
11. **Subagent 429 Resilience**: Internal exponential backoff retry loop (up to 10 attempts) specifically for subagent API calls.
12. **WriteFile Robustness**: Fallback to original content if LLM-based file correction fails.
13. **Idempotent Patching**: Advanced regex guards preventing duplicate code insertion and `SyntaxError`s when running the script multiple times.

### Requirements
* Windows 10 or Windows 11
* Node.js and npm installed
* Gemini CLI installed globally (`npm install -g @google/gemini-cli`)

### Usage (Recommended)
It is highly recommended to perform a clean installation of Gemini CLI before applying this patch.

1. **Reinstall Gemini CLI** (to ensure a clean state):
   ```powershell
   npm uninstall -g @google/gemini-cli
   npm install -g @google/gemini-cli
   ```
2. Download `patch_gemini.ps1`.
3. Open PowerShell as an **Administrator**.
4. Navigate to the directory where the script is saved and run it:
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
