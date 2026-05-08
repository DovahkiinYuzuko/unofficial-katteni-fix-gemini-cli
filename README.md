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

1. **Gemini CLIの再インストール**:
   ```powershell
   npm uninstall -g @google/gemini-cli
   npm install -g @google/gemini-cli
   ```
2. 本リポジトリから `patch_gemini.ps1` をダウンロードし、**管理者権限**のPowerShellで実行します。
   ```powershell
   .\patch_gemini.ps1
   ```

---

## English

### Overview
This script (`patch_gemini.ps1`) is an unofficial hotfix for Gemini CLI on Windows. It addresses 13 critical reliability and performance issues by directly patching the compiled JavaScript bundle.

**PR:** [https://github.com/google-gemini/gemini-cli/pull/26392](https://github.com/google-gemini/gemini-cli/pull/26392)

### What it Fixes
1. **Slash Command Improvements**: Trims trailing whitespace to prevent commands from being incorrectly sent as prompts.
2. **Proper Process Termination**: Implements `taskkill /F /T` for complete process tree termination with self-kill guards.
3. **Enhanced API Retries**: Adds `POST` support to retry logic for improved network resilience.
4. **Auto-Model Rotation**: Loops through Pro/Flash/Lite models automatically upon encountering 429 errors.
5. **Dynamic Token Limits**: Automatically increases limits up to 10M for Gemini 3 models.
6. **Improved UI Feedback**: Real-time status updates during model switching and backoff periods.
7. **Real-time Log Flushing**: Buffer optimization ensuring `latest.log` updates immediately.
8. **Subagent Circuit Breaker**: Stops subagents after 3 consecutive tool failures to prevent token waste.
9. **Binary Injection Protocol**: New 3-turn protocol for stable multi-modal (image/file) processing.
10. **Scheduler Hardening**: Prevents main agent hangs with 60s timeouts and loop iteration limits.
11. **Subagent 429 Resilience**: Internal exponential backoff retry loop (up to 10 attempts) for subagents.
12. **WriteFile Robustness**: Fallback to original content if AI-assisted correction fails.
13. **Idempotent Patching**: Advanced regex guards preventing duplicate code insertion and `SyntaxError`s.

### Usage (Recommended)
1. **Reinstall Gemini CLI**:
   ```powershell
   npm uninstall -g @google/gemini-cli
   npm install -g @google/gemini-cli
   ```
2. Run `patch_gemini.ps1` in **Administrator** PowerShell.
