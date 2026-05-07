<#
.SYNOPSIS
Unofficial Katteni Fix for Gemini CLI (PR-26392)

.DESCRIPTION
This script patches the Gemini CLI bundle to improve reliability on Windows.
Tested on: Gemini CLI v0.41.2
License: MIT (Use at your own risk. No support provided.)
Maintainer: DovahahkiinYuzuko

.PARAMETER Restore
Restores files from the latest backup.

.PARAMETER DryRun
Previews the target files and planned replacements without modifying them.
#>

param(
    [switch]$Restore,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " Unofficial Katteni Fix for Gemini CLI" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

# --- 0. Environment Checks ---
# Check if Windows
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    Write-Host "[ERROR] This script is strictly for Windows. / このスクリプトはWindows環境専用です。" -ForegroundColor Red
    exit 1
}

# Check Admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[WARN] Not running as Administrator. File write operations may fail. / 管理者権限で実行されていません。ファイルの書き換えに失敗する可能性があります。" -ForegroundColor Yellow
}

# Check if npm is installed
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] npm is not installed or not in PATH. / npmコマンドが見つかりません。Node.jsがインストールされているか確認してください。" -ForegroundColor Red
    exit 1
}

# --- 1. Detect target directory ---
Write-Host "`n[INFO] Detecting npm global modules path... / npmパスを検出中..."
try {
    # Invoke-Expressionを避け、安全な呼び出し演算子(&)を使用
    $npmRoot = (& npm root -g 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($npmRoot)) {
        throw "npm root -g failed or returned empty."
    }
} catch {
    Write-Host "[ERROR] Failed to execute 'npm root -g'. / npmパスの取得に失敗しました。" -ForegroundColor Red
    exit 1
}

$targetDir = Join-Path $npmRoot "@google/gemini-cli/bundle"
if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] Gemini CLI bundle not found at: $targetDir / インストール先が見つかりません。" -ForegroundColor Red
    exit 1
}

Set-Location $targetDir
Write-Host "[INFO] Target directory / 対象ディレクトリ: $targetDir`n" -ForegroundColor Green

# --- 2. Restore Mode ---
if ($Restore) {
    if ($DryRun) {
        Write-Host "[INFO] Running in DRY-RUN mode. Previewing restore only. / 確認モード（実際の復元は行われません）" -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] Initiating Restore Mode... / 復元モードを開始します..." -ForegroundColor Yellow
    }
    
    $restoredCount = 0
    Get-ChildItem -File -Filter "*.js" | ForEach-Object {
        $file = $_.FullName
        $fileName = $_.Name
        # フルパスワイルドカード直書きを避け、Filterで安全に検索
        $backups = Get-ChildItem -Path (Split-Path $file) -Filter "$fileName.*.bak" -File | Sort-Object CreationTime -Descending
        
        if ($backups.Count -gt 0) {
            $latestBackup = $backups[0]
            if (-not $DryRun) {
                Copy-Item -Path $latestBackup.FullName -Destination $file -Force
            }
            $actionWord = if ($DryRun) { "Would restore" } else { "RESTORED" }
            Write-Host "  [$actionWord] $fileName <- $($latestBackup.Name) [$($latestBackup.CreationTime.ToString('yyyy/MM/dd HH:mm:ss'))]" -ForegroundColor Green
            $restoredCount++
        }
    }
    
    if ($restoredCount -eq 0) {
        Write-Host "[WARN] No backup files found. / バックアップファイルが見つかりません。" -ForegroundColor Yellow
    } else {
        Write-Host "`n[SUCCESS] Processed $restoredCount files. / $restoredCount 件のファイルを処理しました。" -ForegroundColor Magenta
    }
    exit 0
}

# --- 3. Patch Mode ---
# PowerShellのバージョン差異（BOM混入）を回避してUTF-8で保存
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$totalMatches = 0
$totalApplied = 0
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Rules: Name, MatchPattern, ReplaceTarget, ReplaceWith
$patchRules = @(
    @{
        Name = "Slash Commands"
        Match = '([a-zA-Z0-9_$]+)\.startsWith\("\/"\)'
        ReplaceTarget = '([a-zA-Z0-9_$]+)\.startsWith\("\/"\)'
        ReplaceWith = '$1.trim().startsWith("/")'
        Filter = "*.js"
    },
    @{
        Name = "Startup Hang"
        Match = 'maxBuffer:\s*10\s*\*\s*1024\s*\*\s*1024'
        ReplaceTarget = 'maxBuffer:\s*10\s*\*\s*1024\s*\*\s*1024'
        ReplaceWith = 'maxBuffer:10*1024*1024,timeout:5000'
        Filter = "*.js"
    },
    @{
        Name = "Zombie Process (initialSignal)"
        Match = 'process\.kill\(-pid,\s*initialSignal\)'
        ReplaceTarget = 'process\.kill\(-pid,\s*initialSignal\)'
        ReplaceWith = '(process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,initialSignal))'
        Filter = "*.js"
    },
    @{
        Name = "Zombie Process (SIGKILL)"
        Match = 'process\.kill\(-pid,\s*"SIGKILL"\)'
        ReplaceTarget = 'process\.kill\(-pid,\s*"SIGKILL"\)'
        ReplaceWith = '(process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,"SIGKILL"))'
        Filter = "*.js"
    },
    @{
        Name = "Activity Logger (Limit)"
        Match = 'bufferLimit\s*=\s*10;'
        ReplaceTarget = 'bufferLimit\s*=\s*10;'
        ReplaceWith = 'bufferLimit=1;'
        Filter = "devtoolsService*.js"
    },
    @{
        Name = "Activity Logger (Flush)"
        Match = '>\s*this\.bufferLimit'
        ReplaceTarget = '>\s*this\.bufferLimit'
        ReplaceWith = '>=this.bufferLimit'
        Filter = "devtoolsService*.js"
    },
    @{
        Name = "Classifier Threshold (Routing)"
        Match = 'const defaultValue = 90;'
        ReplaceTarget = 'const defaultValue = 90;'
        ReplaceWith = 'const defaultValue = 50;'
        Filter = "*.js"
    },
    @{
        Name = "History Search Window (Token Opt)"
        Match = 'HISTORY_SEARCH_WINDOW(\d*) = 20;'
        ReplaceTarget = 'HISTORY_SEARCH_WINDOW(\d*) = 20;'
        ReplaceWith = 'HISTORY_SEARCH_WINDOW$1 = 10;'
        Filter = "*.js"
    },
    @{
        Name = "API Retry (Add POST)"
        Match = 'var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];'
        ReplaceTarget = 'var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];'
        ReplaceWith = 'var retryMethods = ["get", "post", "put", "head", "delete", "options", "trace"];'
        Filter = "*.js"
    }
)

if ($DryRun) {
    Write-Host "[INFO] Running in DRY-RUN mode. No files will be modified. / 確認モード（実際の書き換えは行われません）`n" -ForegroundColor Yellow
}

foreach ($rule in $patchRules) {
    Write-Host "[PROCESS] Patching $($rule.Name)..." -ForegroundColor Cyan
    $ruleMatchCount = 0

    Get-ChildItem -File -Filter $rule.Filter | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match $rule.Match) {
            $newContent = $content -replace $rule.ReplaceTarget, $rule.ReplaceWith
            
            if ($content -ne $newContent) {
                if (-not $DryRun) {
                    $backupPath = "$($_.FullName).$timestamp.bak"
                    if (-not (Test-Path $backupPath)) {
                        Copy-Item $_.FullName $backupPath
                    }
                    Write-Utf8NoBom -Path $_.FullName -Content $newContent
                    $totalApplied++
                }
                Write-Host "  [$($rule.Name)] Matched: $($_.Name)" -ForegroundColor Green
                $ruleMatchCount++
                $totalMatches++
            }
        }
    }
    if ($ruleMatchCount -eq 0) {
        Write-Host "  [SKIP] No files matched or already patched. / 対象なし、または適用済み" -ForegroundColor DarkGray
    }
}

Write-Host "-----------------------------------------------------------"
if ($totalMatches -gt 0) {
    if ($DryRun) {
        Write-Host "[SUCCESS] Dry run complete. $totalMatches replacement candidates found. / 確認完了（$totalMatches 件の置換候補を発見）" -ForegroundColor Magenta
    } else {
        Write-Host "[SUCCESS] All patches applied! ($totalApplied replacements) / 適用完了（$totalApplied 件の置換に成功）" -ForegroundColor Magenta
    }
} else {
    Write-Host "[WARN] No patches were applied. The environment might already be patched or the bundle structure has changed. / 適用可能なパッチがありませんでした。" -ForegroundColor Yellow
}