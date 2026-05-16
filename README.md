# Unofficial Katteni Fix for Gemini CLI (Windows)

## 目次 / INDEX
[日本語](#日本語) | [English](#english)

---

## 日本語

### 概要
このスクリプト（`patch_gemini.js`）は、Windows環境における Gemini CLI の動作不良やパフォーマンスの問題を解決するための非公式パッチです。
公式リポジトリに修正がマージされるまでの間、「応急処置」として作成されました。npmでグローバルインストールされたGemini CLIのビルド済みファイルを直接修正し、計15項目の重要な改善を適用します。

**プルリクエスト:**
[https://github.com/google-gemini/gemini-cli/pull/26392](https://github.com/google-gemini/gemini-cli/pull/26392)

### 修正される問題
1. **スラッシュコマンドの改善**: `/model` などのコマンド末尾の空白や改行をトリムし、v0.42.0以降で未ロードや未知のスラッシュコマンドがAIへ誤送信される経路をガードします。
2. **ゾンビプロセスの完全終了**: 実行キャンセル時に裏でプロセスが残り続ける問題を、Windows標準の `taskkill /F /T` で解決。自己殺害防止ガード付きです。
3. **APIリトライの強化**: `GET` に加え `POST` リクエストもリトライ対象とし、ネットワーク耐性を向上。
4. **モデル選択の自動ループ（Autoモード改善）**: 429エラー時にモデル（Pro/Flash/Lite）を自動でローテーションして継続させます。
5. **トークン上限の動的解放**: Gemini 3等のモデルで上限を自動的に最大10Mまで引き上げ、ポテンシャルを解放します。
6. **リトライUIの改善**: 「FlashからProに切り替え中」などの詳細な状況をリアルタイムで表示します。
7. **ログのリアルタイム書き出し**: 短いタスクでも即座に `latest.log` に反映されるよう、バッファを最適化。
8. **サブエージェントの無限ループ封印**: 3回連続でツール実行に失敗した場合に自動停止する安全装置（サーキットブレーカー）を導入。
9. **バイナリインジェクション対応**: 画像等のバイナリデータを扱う際のモデルの安定性を劇的に向上させる新プロトコルを実装。
10. **スケジューラのフリーズ防止**: ツール実行の待機処理にタイムアウトとループ制限を設け、CLIのハングを物理的に防ぎます。
11. **サブエージェントの429耐性**: サブエージェント内でも最大10回までの指数バックオフ付き自動リトライを実行します。
12. **WriteFileの信頼性向上**: AIによる自動修正が失敗した場合でも、オリジナル内容で書き込むフォールバックを実装。
13. **二重適用防止ガード（等冪性の確保）**: パッチを何度実行しても `SyntaxError` にならない高度な正規表現ガードを搭載。
14. **スラッシュコマンドのハング解消**: Windowsのプロセス取得を高速化し、キャッシュと非同期ロードを導入。起動時の無限ロードを完全に防止します。
15. **コマンドローダーの堅牢化（Fail-Soft）**: 個別のコマンド生成に例外保護を追加。一部のコマンドが万一失敗しても、他の主要コマンドは正常に動作し続けます。

### 動作要件
* Windows 10 または Windows 11
* Node.js および npm がインストールされていること
* Gemini CLI がグローバルインストールされていること（`npm install -g @google/gemini-cli`）

### 使い方（推奨）
パッチを適用する前に、Gemini CLIを一度クリーンインストールすることを強く推奨します。

1. **Gemini CLIの再インストール**（クリーンな状態にするため）:
   ```bash
   npm uninstall -g @google/gemini-cli
   npm install -g @google/gemini-cli
   ```
2. 本リポジトリから `patch_gemini.js` をダウンロードします。
3. ターミナル（コマンドプロンプトやPowerShell）を **管理者権限** で起動します。
4. スクリプトが保存されているディレクトリに移動し、スクリプトを実行します。
   ```bash
   node patch_gemini.js
   ```

### オプション機能
* **確認モード (Dry Run)**: 実際にファイルを書き換えずに、どのファイルが修正対象になるかを確認します。
  ```bash
  node patch_gemini.js --dry-run
  ```
* **復元モード (Restore)**: パッチ適用時に自動作成されたバックアップ（`.bak`）から、ファイルを元の状態に戻します。
  ```bash
  node patch_gemini.js --restore
  ```
* **セルフテスト (Self Test)**: v0.42.0向けのスラッシュコマンド修正ルールが現在のスクリプト内で正しく適用・再適用できるかを検証します。
  ```bash
  node patch_gemini.js --selftest
  ```

### 想定される問題とトラブルシューティング

#### Q. 「npmコマンドが見つからない」と表示される
Node.jsがインストールされていないか、環境変数（PATH）に登録されていません。Node.jsをインストールし直すか、システムの環境変数設定を確認してください。

#### Q. Gemini CLIをアップデートしたらバグが再発した
`npm update -g @google/gemini-cli` などでCLIをアップデートすると、ファイルが公式の（バグを含んだ）状態に上書きされます。アップデート後は再度このパッチスクリプトを実行してください。

### 免責事項
本スクリプトは非公式のコミュニティパッチです。MITライセンスのもとで提供されており、「現状のまま」いかなる保証もなしに提供されます。本スクリプトの使用によって生じたデータの損失や環境の破損について、作成者は一切の責任を負いません。自己責任でご使用ください。

### 更新履歴
#### [2026-05-17] パッチ形式の移行
- **PowerShell (.ps1) から JavaScript (.js) へ完全移行**
  - PowerShell 特有の正規表現フリーズ問題やエスケープ問題を解消。
  - Node.js 環境での実行により、より高速かつ安定したパッチ適用が可能になりました。
  - 今後は `patch_gemini.js` をメインとしてメンテナンスを行います。

---

## English

### Overview
This script (`patch_gemini.js`) is an unofficial hotfix to resolve critical bugs and performance issues with the Gemini CLI on Windows environments.
It acts as a temporary workaround until official fixes are merged, by directly patching the compiled JavaScript bundle of your globally installed Gemini CLI. It applies a total of 15 critical improvements.

**PR:**
[https://github.com/google-gemini/gemini-cli/pull/26392](https://github.com/google-gemini/gemini-cli/pull/26392)

### What it Fixes
1. **Slash Command Improvements**: Trims whitespace/newlines from commands like `/model` and guards the v0.42.0+ paths where unloaded or unknown slash commands can fall through to the AI as normal prompts.
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
14. **Slash Command Hang Resolution**: Implements high-speed process discovery with caching and non-blocking loading on Windows, preventing infinite startup hangs.
15. **Fail-Soft Command Loader**: Adds exception protection to individual command generation, ensuring core commands remain functional even if specific extensions fail.

### Requirements
* Windows 10 or Windows 11
* Node.js and npm installed
* Gemini CLI installed globally (`npm install -g @google/gemini-cli`)

### Usage (Recommended)
It is highly recommended to perform a clean installation of Gemini CLI before applying this patch.

1. **Reinstall Gemini CLI** (to ensure a clean state):
   ```bash
   npm uninstall -g @google/gemini-cli
   npm install -g @google/gemini-cli
   ```
2. Download `patch_gemini.js`.
3. Open a terminal (Command Prompt or PowerShell) as an **Administrator**.
4. Navigate to the directory where the script is saved and run it:
   ```bash
   node patch_gemini.js
   ```

### Options
* **Dry Run**: Preview which files will be modified without actually changing them.
  ```bash
  node patch_gemini.js --dry-run
  ```
* **Restore**: Revert the files to their original state using the automatically generated `.bak` backups.
  ```bash
  node patch_gemini.js --restore
  ```
* **Self Test**: Verifies that the v0.42.0 slash-command patch rules apply cleanly and remain idempotent.
  ```bash
  node patch_gemini.js --selftest
  ```

### Troubleshooting

#### Q. I get an error saying "npm is not recognized."
Node.js is either not installed or not in your system's PATH. Please install Node.js or check your environment variables.

#### Q. The bugs came back after I updated the Gemini CLI.
Updating the CLI (e.g., via `npm update -g @google/gemini-cli`) overwrites the patched files with the official codebase. You will need to run this patch script again after every update.

### Disclaimer
This is an unofficial community patch provided under the MIT License. It is provided "as is", without warranty of any kind. The author is not responsible for any data loss, system instability, or other damages resulting from the use of this script. Use at your own risk.

### Update History
#### [2026-05-17] Migration of Patch Format
- **Fully migrated from PowerShell (.ps1) to JavaScript (.js)**
  - Resolved PowerShell-specific regex freezing and escaping issues.
  - Execution in Node.js environment enables faster and more stable patching.
  - Future maintenance will be focused on `patch_gemini.js`.
