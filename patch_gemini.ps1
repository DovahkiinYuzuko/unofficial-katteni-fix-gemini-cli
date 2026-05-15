<#
.SYNOPSIS
Unofficial Katteni Fix for Gemini CLI (PR-26392) - Yuzuko Edition

.DESCRIPTION
This script patches the Gemini CLI bundle to improve reliability on Windows.
Features:
- Model selection loop (Auto-fallback from Flash to Pro/Lite)
- Dynamic token limits (Up to 10M for Gemini 3)
- Enhanced UI feedback during retries
- Safe process termination (Taskkill with self-kill protection)
- Slash Command Guard (Safe version)

Tested on: Gemini CLI v0.42.0
License: MIT
Maintainer: DovahkiinYuzuko
#>

param(
    [switch]$Restore,
    [switch]$DryRun,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host " Unofficial Katteni Fix for Gemini CLI (Yuzuko Edition)" -ForegroundColor Cyan
Write-Host "===========================================================" -ForegroundColor Cyan

# --- 0. Environment Checks ---
if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
    Write-Host "[ERROR] This script is strictly for Windows." -ForegroundColor Red
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[WARN] Not running as Administrator. File write operations may fail." -ForegroundColor Yellow
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] npm is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

# --- 1. Detect target directory ---
Write-Host "`n[INFO] Detecting npm global modules path..."
try {
    $npmRoot = (& npm root -g 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($npmRoot)) {
        throw "npm root -g failed or returned empty."
    }
} catch {
    Write-Host "[ERROR] Failed to execute 'npm root -g'." -ForegroundColor Red
    exit 1
}

$targetDir = Join-Path $npmRoot "@google/gemini-cli/bundle"
if (-not (Test-Path $targetDir)) {
    Write-Host "[ERROR] Gemini CLI bundle not found at: $targetDir" -ForegroundColor Red
    exit 1
}

Set-Location $targetDir
Write-Host "[INFO] Target directory: $targetDir`n" -ForegroundColor Green

# --- 2. Restore Mode ---
if ($Restore) {
    Write-Host "[INFO] Initiating Restore Mode..." -ForegroundColor Yellow
    $restoredCount = 0
    Get-ChildItem -File -Filter "*.js" | ForEach-Object {
        $file = $_.FullName
        $fileName = $_.Name
        $backups = Get-ChildItem -Path (Split-Path $file) -Filter "$fileName.*.bak" -File | Sort-Object CreationTime -Descending
        
        if ($backups.Count -gt 0) {
            $latestBackup = $backups[0]
            if (-not $DryRun) {
                Copy-Item -Path $latestBackup.FullName -Destination $file -Force
            }
            Write-Host "  [RESTORED] $fileName <- $($latestBackup.Name)" -ForegroundColor Green
            $restoredCount++
        }
    }
    Write-Host "`n[SUCCESS] Processed $restoredCount files." -ForegroundColor Magenta
    exit 0
}

# --- 3. Patch Mode ---
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$totalApplied = 0
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$patchRules = @(
    # --- Slash Command Fixes (Updated & Safe) ---
    @{
        Name = "Slash Commands Loading Guard (v0.42+)"
        Match = 'if \(!commands\) \{\s*return false;\s*\}\s*if \(typeof rawQuery !== "string"\)'
        ReplaceTarget = 'if \(!commands\) \{\s*return false;\s*\}\s*if \(typeof rawQuery !== "string"\)'
        ReplaceWith = 'if (!commands) { if (typeof rawQuery === "string" && (rawQuery.trim().startsWith("/") || rawQuery.trim().startsWith("?"))) { addItem({ type: "error", text: "Slash commands are still loading. Please try again in a moment." }, Date.now()); return { type: "handled" }; } return false; } if (typeof rawQuery !== "string")'
    },
    @{
        Name = "Slash Commands Unknown Guard (v0.42+)"
        Match = 'if \(!commandToExecute\) \{[\s\S]*?if \(isMcpLoading\) \{[\s\S]*?return \{ type: "handled" \};\s*\}\s*return false;\s*\}\s*setIsProcessing\(true\);'
        ReplaceTarget = '(if \(!commandToExecute\) \{[\s\S]*?if \(isMcpLoading\) \{[\s\S]*?return \{ type: "handled" \};\s*\}\s*)return false;(\s*\}\s*setIsProcessing\(true\);)'
        ReplaceWith = '$1setIsProcessing(true); if (addToHistory) { addItem({ type: "user", text: trimmed }, Date.now()); } addMessage({ type: "error", content: `Unknown command: ${trimmed}`, timestamp: new Date() }); setIsProcessing(false); return { type: "handled" };$2'
    },
    @{
        Name = "Slash Commands Detection Trim"
        Match = '(?<!\.trim\(\))\.startsWith\(["'']\/["'']\)'
        ReplaceTarget = '([a-zA-Z0-9_$]+)\.(?!trim\(\)\.)startsWith\(["'']\/["'']\)'
        ReplaceWith = '$1.trim().startsWith("/")'
    },
    @{
        Name = "Slash Commands Execution Guard (Fix)"
        Match = '(?<!function\s+)handleSlashCommand\(([a-zA-Z0-9_$.]+)(?=[,\)])'
        ReplaceTarget = 'handleSlashCommand\(([a-zA-Z0-9_$.]+)(?=[,\)])'
        ReplaceWith = 'handleSlashCommand($1.trim()'
    },
    @{
        Name = "Slash Commands Reload Debounce (500ms)"
        Match = 'const reloadCommands = \(0, import_react[0-9]+\.useCallback\)\(\(\) => \{\s*setReloadTrigger\(\(v\) => v \+ 1\);\s*\}, \[\]\);'
        ReplaceTarget = 'const reloadCommands = \(0, import_react([0-9]+)\.useCallback\)\(\(\) => \{\s*setReloadTrigger\(\(v\) => v \+ 1\);\s*\}, \[\]\);'
        ReplaceWith = 'var reloadTimer; const reloadCommands = (0, import_react$1.useCallback)(() => { if (reloadTimer) clearTimeout(reloadTimer); reloadTimer = setTimeout(() => setReloadTrigger((v) => v + 1), 500); }, []);'
    },
    @{
        Name = "Slash Commands Latest-Wins Loading (No Abort)"
        Match = '(?s)\(0, import_react[0-9]+\.useEffect\)\(\(\) => \{.*?const controller = new AbortController\(\);.*?await CommandService\.create\(.*?controller\.signal.*?\}\s*\}, \[config, reloadTrigger, isConfigInitialized\]\);'
        ReplaceTarget = '(?s)\(0, import_react([0-9]+)\.useEffect\)\(\(\) => \{.*?const controller = new AbortController\(\);.*?await CommandService\.create\(\s*\[\s*new BuiltinCommandLoader\(config\),\s*new SkillCommandLoader\(config\),\s*new McpPromptLoader\(config\),\s*new FileCommandLoader\(config\)\s*\]\s*,.*?controller\.signal.*?\}\s*\}, \[config, reloadTrigger, isConfigInitialized\]\);'
        ReplaceWith = '(0, import_react$1.useEffect)(() => { let active = true; (async () => { try { const svc = await CommandService.create([new BuiltinCommandLoader(config), new SkillCommandLoader(config), new McpPromptLoader(config), new FileCommandLoader(config)], null); if (!active) return; setCommands(svc.getCommands()); } catch (e) { if (active) addItem({ type: "error", text: `Failed to load slash commands: ${e.message}` }, Date.now()); } })(); return () => { active = false; }; }, [config, reloadTrigger, isConfigInitialized]);'
    },
    @{
        Name = "Windows Process Discovery Speedup & Cache"
        Match = '(?s)async function getProcessTableWindows\(\) \{.*?const powershellCommand = "Get-CimInstance Win32_Process .*?ConvertTo-Json -Compress";'
        ReplaceTarget = '(?s)async function getProcessTableWindows\(\) \{.*?const powershellCommand = "Get-CimInstance Win32_Process .*?ConvertTo-Json -Compress";'
        ReplaceWith = 'var _pCache=null,_pTime=0,_pPending=null; async function getProcessTableWindows(){const now=Date.now();if(_pCache&&(now-_pTime<60000))return _pCache;if(_pPending)return _pPending;_pPending=(async()=>{const map=new Map();try{const names="code,idea64,cursor,windsurf,codium";const cmd=`Get-Process -Name ${names} -ErrorAction SilentlyContinue | Select-Object Id,ParentId,Name | ConvertTo-Json -Compress`;const {stdout}=await execAsync2(`powershell -Command "${cmd}"`,{maxBuffer:10*1024*1024,timeout:3000});if(stdout?.trim()){let ps=JSON.parse(stdout);if(!Array.isArray(ps))ps=[ps];for(const p of ps){if(p&&typeof p.Id==="number")map.set(p.Id,{pid:p.Id,parentPid:p.ParentId||0,name:p.Name||"",command:""});}}}catch(e){}_pCache=map;_pTime=Date.now();return map})();try{return await _pPending}finally{_pPending=null;}}'
    },
    @{
        Name = "BuiltinCommandLoader Non-blocking & Fail-Soft"
        Match = '(?s)async loadCommands\(_signal\) \{.*?handle = startupProfiler\.start\("load_builtin_commands"\);.*?return allDefinitions\.filter\(\(cmd\) => cmd !== null\);\s*\}'
        ReplaceTarget = '(?s)async loadCommands\(_signal\) \{.*?handle = startupProfiler\.start\("load_builtin_commands"\);.*?return allDefinitions\.filter\(\(cmd\) => cmd !== null\);\s*\}'
        ReplaceWith = 'async loadCommands(_signal){let h;try{try{h=startupProfiler.start("load_builtin_commands")}catch(e){}const isN=await isNightly(process.cwd());const ideP=ideCommand().catch(()=>null);const addD=(s)=>{if(!s)return s;const w=s.map(c=>c.name!=="checkpoints"?c:{...c,subCommands:addD(c.subCommands)});return !isN?w:w.some(c=>c.name===debugCommand.name)?w:[...w,{...debugCommand,suggestionGroup:"checkpoints"}]};const ideC=await Promise.race([ideP,new Promise(r=>setTimeout(()=>r(null),1000))]);const safe=(c,n)=>{try{return typeof c==="function"?c():c}catch(e){return null}};const c2=safe(()=>addD(chatCommand.subCommands),"c");const defs=[safe(aboutCommand,"a"),...this.config?.isAgentsEnabled()?[safe(agentsCommand,"ag")]:[],safe(authCommand,"au"),safe(bugCommand,"b"),safe(bugMemoryCommand,"bm"),safe({...chatCommand,subCommands:c2},"ch"),safe(clearCommand,"cl"),safe(commandsCommand,"cm"),safe(compressCommand,"cp"),safe(copyCommand,"co"),safe(corgiCommand,"cg"),safe(docsCommand,"d"),safe(directoryCommand,"di"),safe(editorCommand,"e"),...this.config?.getExtensionsEnabled()===false?[safe({name:"extensions",description:"Manage extensions",kind:"built-in",autoExecute:false,subCommands:[],action:async(c)=>({type:"message",messageType:"error",content:getAdminErrorMessage("Extensions",this.config??void 0)})},"ed")]:[safe(()=>extensionsCommand(this.config?.getEnableExtensionReloading()),"ex")],safe(helpCommand,"h"),safe(footerCommand,"f"),safe(shortcutsCommand,"sh"),...this.config?.getEnableHooksUI()?[safe(hooksCommand,"ho")]:[],safe(rewindCommand,"rw"),safe(ideC,"i"),safe(initCommand,"in"),...isN?[safe(oncallCommand,"oc")]:[],...this.config?.getMcpEnabled()===false?[safe({name:"mcp",description:"Manage configured MCP servers",kind:"built-in",autoExecute:false,subCommands:[],action:async(c)=>({type:"message",messageType:"error",content:getAdminErrorMessage("MCP",this.config??void 0)})},"md")]:[safe(mcpCommand,"m")],safe(memoryCommand,"me"),safe(modelCommand,"mo"),...this.config?.getFolderTrust()?[safe(permissionsCommand,"pe")]:[],...this.config?.isPlanEnabled()?[safe(planCommand,"pl")]:[],safe(policiesCommand,"po"),safe(privacyCommand,"pr"),...isDevelopment?[safe(profileCommand,"pf")]:[],safe(quitCommand,"q"),safe(()=>restoreCommand(this.config),"rs"),safe({...resumeCommand,subCommands:addD(resumeCommand.subCommands)},"re"),safe(statsCommand,"st"),safe(themeCommand,"th"),safe(toolsCommand,"tl"),...this.config?.isSkillsSupportEnabled()?this.config?.getSkillManager()?.isAdminEnabled()===false?[safe({name:"skills",description:"Manage agent skills",kind:"built-in",autoExecute:false,subCommands:[],action:async(c)=>({type:"message",messageType:"error",content:getAdminErrorMessage("Agent skills",this.config??void 0)})},"sd")]:[safe(skillsCommand,"sk")]:[],safe(settingsCommand,"se"),safe(gemmaStatusCommand,"gs"),safe(tasksCommand,"ta"),safe(vimCommand,"vi"),safe(setupGithubCommand,"sg"),safe(terminalSetupCommand,"ts"),...this.config?.isVoiceModeEnabled()?[safe(voiceCommand,"v")]:[],...this.config?.getContentGeneratorConfig()?.authType===AuthType.LOGIN_WITH_GOOGLE?[safe(upgradeCommand,"u")]:[]];return defs.filter(c=>c!==null)}finally{h?.end()}}'
    },

    # --- Existing PR fixes ---
    @{
        Name = "Zombie Process Duplicate Cleanup"
        Match = '\((?:pid===process\.pid\|\|pid===process\.ppid\?undefined:process\.platform==="win32"\?require\("child_process"\)\.spawnSync\("taskkill",\["/F","/T","/PID",pid\.toString\(\)\]\):\(?)+process\.kill\(-pid,(initialSignal|"SIGKILL")\)(?:\))+'
        ReplaceTarget = '\((?:pid===process\.pid\|\|pid===process\.ppid\?undefined:process\.platform==="win32"\?require\("child_process"\)\.spawnSync\("taskkill",\["/F","/T","/PID",pid\.toString\(\)\]\):\(?)+process\.kill\(-pid,(initialSignal|"SIGKILL")\)(?:\))+'
        ReplaceWith = '(pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,$1))'
    },
    @{
        Name = "Zombie Process (SIGKILL/SIGTERM) with Guard"
        Match = '(?m)^(?!.*taskkill)(.*)process\.kill\(-pid,\s*(initialSignal|"SIGKILL")\)(.*)$'
        ReplaceTarget = '(?m)^(?!.*taskkill)(.*)process\.kill\(-pid,\s*(initialSignal|"SIGKILL")\)(.*)$'
        ReplaceWith = '$1(pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,$2))$3'
    },
    @{
        Name = "API Retry (Add POST)"
        Match = 'var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];'
        ReplaceTarget = 'var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];'
        ReplaceWith = 'var retryMethods = ["get", "post", "put", "head", "delete", "options", "trace"];'
    },

    # --- New Yuzuko Edition fixes ---
    @{
        Name = "Model Selection Loop (Auto-Fallback)"
        Match = 'resolvePolicyChain\(([a-zA-Z0-9_$]+),\s*([a-zA-Z0-9_$]+)\)(?!\s*,\s*true)'
        ReplaceTarget = 'resolvePolicyChain\(([a-zA-Z0-9_$]+),\s*([a-zA-Z0-9_$]+)\)'
        ReplaceWith = 'resolvePolicyChain($1, $2, true)'
    },
    @{
        Name = "Dynamic Token Limits (Gemini 3 Support)"
        Match = 'function tokenLimit\([a-zA-Z0-9_$]+\)\s*\{\s*(?!if\(.*\.includes\("gemini-3"\)\))'
        ReplaceTarget = 'function tokenLimit\(([a-zA-Z0-9_$]+)\)\s*\{\s*(?!if\(.*\.includes\("gemini-3"\)\))switch\s*\(\$1\)\s*\{'
        ReplaceWith = 'function tokenLimit($1){if($1.includes("gemini-3"))return 10000000;switch($1){'
    },
    @{
        Name = "Token Limit Default (2M)"
        Match = 'var DEFAULT_TOKEN_LIMIT = 1048576;'
        ReplaceTarget = 'var DEFAULT_TOKEN_LIMIT = 1048576;'
        ReplaceWith = 'var DEFAULT_TOKEN_LIMIT = 2000000;'
    },
    @{
        Name = "Retry UI Feedback (Model Switching Message)"
        Match = 'onRetry:\s*\((attempt,\s*error[a-zA-Z0-9_$]*,\s*delayMs)\)\s*=>\s*\{\s*(?!const isModelChanged)(?=const actualMaxAttempts)'
        ReplaceTarget = 'onRetry:\s*\((attempt,\s*error[a-zA-Z0-9_$]*,\s*delayMs)\)\s*=>\s*\{\s*(?!const isModelChanged)(?=const actualMaxAttempts)'
        ReplaceWith = 'onRetry: ($1) => { const isModelChanged = getDisplayString(currentAttemptModel) !== getDisplayString(modelConfigKey.model); const message = isModelChanged ? `Switching to ${getDisplayString(currentAttemptModel)} due to availability issues...` : undefined;'
    },
    @{
        Name = "Retry UI Feedback Duplicate Cleanup"
        Match = '(const isModelChanged = getDisplayString\(currentAttemptModel\) !== getDisplayString\(modelConfigKey\.model\); const message = isModelChanged \? `Switching to \$\{getDisplayString\(currentAttemptModel\)\} due to availability issues\.\.\.` : undefined;\s*){2,}'
        ReplaceTarget = '(const isModelChanged = getDisplayString\(currentAttemptModel\) !== getDisplayString\(modelConfigKey\.model\); const message = isModelChanged \? `Switching to \$\{getDisplayString\(currentAttemptModel\)\} due to availability issues\.\.\.` : undefined;\s*){2,}'
        ReplaceWith = 'const isModelChanged = getDisplayString(currentAttemptModel) !== getDisplayString(modelConfigKey.model); const message = isModelChanged ? `Switching to ${getDisplayString(currentAttemptModel)} due to availability issues...` : undefined; '
    },
    @{
        Name = "Retry Payload Expansion (Emit Message)"
        Match = 'model:\s*getDisplayString\(currentAttemptModel\)(?!,\s*message)'
        ReplaceTarget = 'model:\s*getDisplayString\(currentAttemptModel\)(?!,\s*message)'
        ReplaceWith = 'model: getDisplayString(currentAttemptModel), message'
    },
    @{
        Name = "UI Loader Message Support"
        Match = '(?<!retryStatus\.message \? retryStatus\.message : )retryStatus\.attempt\s*>=\s*[A-Z_]+_RETRY_HINT_ATTEMPT_THRESHOLD\s*\?\s*"[^"]*"\s*:\s*null'
        ReplaceTarget = '(?<!retryStatus\.message \? retryStatus\.message : )retryStatus\.attempt\s*>=\s*[A-Z_]+_RETRY_HINT_ATTEMPT_THRESHOLD\s*\?\s*"[^"]*"\s*:\s*null'
        ReplaceWith = 'retryStatus.message ? retryStatus.message : $&'
    }
)

function Update-PatchRulesToText {
    param([string]$Content)

    foreach ($rule in $patchRules) {
        if ($Content -match $rule.Match) {
            $Content = $Content -replace $rule.ReplaceTarget, $rule.ReplaceWith
        }
    }

    return $Content
}

function Assert-SelfTest {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "[SELFTEST] FAILED: $Name"
    }

    Write-Host "[SELFTEST] PASS: $Name" -ForegroundColor Green
}

if ($SelfTest) {
    Write-Host "`n[SELFTEST] Running bundled patch rule checks..." -ForegroundColor Cyan

    $loadingGuardFixture = @'
if (!commands) {
        return false;
      }
      if (typeof rawQuery !== "string") {
        return false;
      }
'@
    $patchedLoadingGuard = Apply-PatchRulesToText $loadingGuardFixture
    Assert-SelfTest "slash command loading guard is inserted" ($patchedLoadingGuard -match 'Slash commands are still loading')
    Assert-SelfTest "slash command loading guard is idempotent" ((Apply-PatchRulesToText $patchedLoadingGuard) -eq $patchedLoadingGuard)

    $unknownGuardFixture = @'
if (!commandToExecute) {
        const isMcpLoading = config?.getMcpClientManager()?.getDiscoveryState() === "in_progress" /* IN_PROGRESS */;
        if (isMcpLoading) {
          setIsProcessing(true);
          if (addToHistory) {
            addItem({ type: "user" /* USER */, text: trimmed }, Date.now());
          }
          addMessage({
            type: "error" /* ERROR */,
            content: `Unknown command: ${trimmed}. Command might have been from an MCP server but MCP servers are not done loading.`,
            timestamp: /* @__PURE__ */ new Date()
          });
          setIsProcessing(false);
          return { type: "handled" };
        }
        return false;
      }
      setIsProcessing(true);
'@
    $patchedUnknownGuard = Apply-PatchRulesToText $unknownGuardFixture
    Assert-SelfTest "unknown slash command guard is inserted" ($patchedUnknownGuard -match 'content: `Unknown command: \$\{trimmed\}`')
    Assert-SelfTest "unknown slash command guard removes false fallthrough" ($patchedUnknownGuard -notmatch 'return false;\s*\}\s*setIsProcessing\(true\);')
    Assert-SelfTest "unknown slash command guard is idempotent" ((Apply-PatchRulesToText $patchedUnknownGuard) -eq $patchedUnknownGuard)

    $retryDuplicateFixture = @'
onRetry: (attempt, error40, delayMs) => { const isModelChanged = getDisplayString(currentAttemptModel) !== getDisplayString(modelConfigKey.model); const message = isModelChanged ? `Switching to ${getDisplayString(currentAttemptModel)} due to availability issues...` : undefined; const isModelChanged = getDisplayString(currentAttemptModel) !== getDisplayString(modelConfigKey.model); const message = isModelChanged ? `Switching to ${getDisplayString(currentAttemptModel)} due to availability issues...` : undefined;const actualMaxAttempts = getAvailabilityContext()?.policy.maxAttempts ?? maxAttempts ?? DEFAULT_MAX_ATTEMPTS2;
'@
    $patchedRetryDuplicate = Apply-PatchRulesToText $retryDuplicateFixture
    Assert-SelfTest "retry UI duplicate declarations are collapsed" (([regex]::Matches($patchedRetryDuplicate, 'const isModelChanged =')).Count -eq 1)
    Assert-SelfTest "retry UI duplicate cleanup is idempotent" ((Apply-PatchRulesToText $patchedRetryDuplicate) -eq $patchedRetryDuplicate)

    $zombieDuplicateFixture = '      (pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):(pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,initialSignal)));'
    $patchedZombieDuplicate = Apply-PatchRulesToText $zombieDuplicateFixture
    Assert-SelfTest "zombie process duplicate wrappers are collapsed" (([regex]::Matches($patchedZombieDuplicate, 'spawnSync\("taskkill"')).Count -eq 1)
    Assert-SelfTest "zombie process patch is idempotent" ((Apply-PatchRulesToText $patchedZombieDuplicate) -eq $patchedZombieDuplicate)

    Write-Host "[SELFTEST] All checks passed." -ForegroundColor Magenta
    Write-Output "[SELFTEST] OK"
    exit 0
}

if ($DryRun) {
    Write-Host "[INFO] Running in DRY-RUN mode.`n" -ForegroundColor Yellow
}

# Apply patches across all bundle files
$targetFiles = Get-ChildItem -File -Filter "*.js"
foreach ($file in $targetFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    $filePatched = $false

    $content = Update-PatchRulesToText $content
    $filePatched = $originalContent -ne $content

    if ($filePatched -and ($originalContent -ne $content)) {
        if (-not $DryRun) {
            $backupPath = "$($file.FullName).$timestamp.bak"
            Copy-Item $file.FullName $backupPath
            Write-Utf8NoBom -Path $file.FullName -Content $content
            $totalApplied++
        }
        Write-Host "  [PATCHED] $($file.Name)" -ForegroundColor Green
    }
}

Write-Host "-----------------------------------------------------------"
if ($totalApplied -gt 0 -or $DryRun) {
    Write-Host "[SUCCESS] Operation complete." -ForegroundColor Magenta
} else {
    Write-Host "[WARN] No patches were applied." -ForegroundColor Yellow
}
