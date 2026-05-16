
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

/**
 * Unofficial Katteni Fix for Gemini CLI (PR-26392) - Yuzuko Edition
 * 
 * This script patches the Gemini CLI bundle to improve reliability on Windows.
 * Features:
 * - Model selection loop (Auto-fallback from Flash to Pro/Lite)
 * - Dynamic token limits (Up to 10M for Gemini 3)
 * - Enhanced UI feedback during retries
 * - Safe process termination (Taskkill with self-kill protection)
 * - Slash Command Guard (Safe version)
 */

const args = process.argv.slice(2);
const isRestore = args.includes('--restore');
const isDryRun = args.includes('--dry-run');

const patchRules = [
    {
        name: "Slash Commands Loading Guard",
        match: /if \(!commands\) \{\s*return false;\s*\}\s*if \(typeof rawQuery !== "string"\)/,
        replace: 'if (!commands) { if (typeof rawQuery === "string" && (rawQuery.trim().startsWith("/") || rawQuery.trim().startsWith("?"))) { addItem({ type: "error", text: "Slash commands are still loading. Please try again in a moment." }, Date.now()); return { type: "handled" }; } return false; } if (typeof rawQuery !== "string")'
    },
    {
        name: "Slash Commands Unknown Guard",
        match: /(if \(!commandToExecute\) \{[\s\S]*?if \(isMcpLoading\) \{[\s\S]*?return \{ type: "handled" \};\s*\}\s*)return false;(\s*\}\s*setIsProcessing\(true\);)/,
        replace: '$1setIsProcessing(true); if (addToHistory) { addItem({ type: "user", text: trimmed }, Date.now()); } addMessage({ type: "error", content: `Unknown command: ${trimmed}`, timestamp: new Date() }); setIsProcessing(false); return { type: "handled" };$2'
    },
    {
        name: "Slash Commands Detection Trim",
        match: /([a-zA-Z0-9_$]+)\.(?!trim\(\)\.)startsWith\(["']\/["']\)/g,
        replace: '$1.trim().startsWith("/")'
    },
    {
        name: "Slash Commands Execution Guard (Fix)",
        match: /handleSlashCommand\(([a-zA-Z0-9_$.]+)(?=[,\)])/g,
        replace: 'handleSlashCommand($1.trim()'
    },
    {
        name: "Slash Commands Reload Debounce (500ms)",
        match: /const reloadCommands = \(0, import_react([0-9]+)\.useCallback\)\(\(\) => \{\s*setReloadTrigger\(\(v\) => v \+ 1\);\s*\}, \[\]\);/,
        replace: 'var reloadTimer; const reloadCommands = (0, import_react$1.useCallback)(() => { if (reloadTimer) clearTimeout(reloadTimer); reloadTimer = setTimeout(() => setReloadTrigger((v) => v + 1), 500); }, []);'
    },
    {
        name: "Slash Commands Latest-Wins Loading (No Abort)",
        match: /\(0, import_react([0-9]+)\.useEffect\)\(\(\) => \{[\s\S]*?const controller = new AbortController\(\);[\s\S]*?await CommandService\.create\(\s*\[\s*new BuiltinCommandLoader\(config\),\s*new SkillCommandLoader\(config\),\s*new McpPromptLoader\(config\),\s*new FileCommandLoader\(config\)\s*\]\s*,[\s\S]*?controller\.signal[\s\S]*?\}\s*\}, \[config, reloadTrigger, isConfigInitialized\]\);/,
        replace: '(0, import_react$1.useEffect)(() => { let active = true; (async () => { try { const svc = await CommandService.create([new BuiltinCommandLoader(config), new SkillCommandLoader(config), new McpPromptLoader(config), new FileCommandLoader(config)], null); if (!active) return; setCommands(svc.getCommands()); } catch (e) { if (active) addItem({ type: "error", text: `Failed to load slash commands: \${e.message}` }, Date.now()); } })(); return () => { active = false; }; }, [config, reloadTrigger, isConfigInitialized]);'
    },
    {
        name: "Windows Process Discovery Speedup & Cache",
        match: /async function getProcessTableWindows\(\) \{[\s\S]*?return processMap;\s*\}(?=\s*async function)/,
        replace: 'var _pCache=null,_pTime=0,_pPending=null; async function getProcessTableWindows(){const now=Date.now();if(_pCache&&(now-_pTime<60000))return _pCache;if(_pPending)return _pPending;_pPending=(async()=>{const map=new Map();try{const names="code,idea64,cursor,windsurf,codium";const cmd=`Get-Process -Name \${names} -ErrorAction SilentlyContinue | Select-Object Id,ParentId,Name | ConvertTo-Json -Compress`;const {stdout}=await execAsync2(`powershell -Command "\${cmd}"`,{maxBuffer:10*1024*1024,timeout:3000});if(stdout?.trim()){let ps=JSON.parse(stdout);if(!Array.isArray(ps))ps=[ps];for(const p of ps){if(p&&typeof p.Id==="number")map.set(p.Id,{pid:p.Id,parentPid:p.ParentId||0,name:p.Name||"",command:""});}}}catch(e){}_pCache=map;_pTime=Date.now();return map})();try{return await _pPending}finally{_pPending=null;}}'
    },
    {
        name: "BuiltinCommandLoader Non-blocking & Fail-Soft",
        match: /async loadCommands\(_signal\) \{[\s\S]*?handle = startupProfiler\.start\("load_builtin_commands"\);[\s\S]*?return allDefinitions\.filter\(\(cmd\) => cmd !== null\);\s*\}/,
        replace: 'async loadCommands(_signal){let h;try{try{h=startupProfiler.start("load_builtin_commands")}catch(e){}const isN=await isNightly(process.cwd());const ideP=ideCommand().catch(()=>null);const addD=(s)=>{if(!s)return s;const w=s.map(c=>c.name!=="checkpoints"?c:{...c,subCommands:addD(c.subCommands)});return !isN?w:w.some(c=>c.name===debugCommand.name)?w:[...w,{...debugCommand,suggestionGroup:"checkpoints"}]};const ideC=await Promise.race([ideP,new Promise(r=>setTimeout(()=>r(null),1000))]);const safe=(c,n)=>{try{return typeof c==="function"?c():c}catch(e){return null}};const c2=safe(()=>addD(chatCommand.subCommands),"c");const defs=[safe(aboutCommand,"a"),...this.config?.isAgentsEnabled()?[safe(agentsCommand,"ag")]:[],safe(authCommand,"au"),safe(bugCommand,"b"),safe(bugMemoryCommand,"bm"),safe({...chatCommand,subCommands:c2},"ch"),safe(clearCommand,"cl"),safe(commandsCommand,"cm"),safe(compressCommand,"cp"),safe(copyCommand,"co"),safe(corgiCommand,"cg"),safe(docsCommand,"d"),safe(directoryCommand,"di"),safe(editorCommand,"e"),...this.config?.getExtensionsEnabled()===false?[safe({name:"extensions",description:"Manage extensions",kind:"built-in",autoExecute:false,subCommands:[],action:async(c)=>({type:"message",messageType:"error",content:getAdminErrorMessage("Extensions",this.config??void 0)})},"ed")]:[safe(()=>extensionsCommand(this.config?.getEnableExtensionReloading()),"ex")],safe(helpCommand,"h"),safe(footerCommand,"f"),safe(shortcutsCommand,"sh"),...this.config?.getEnableHooksUI()?[safe(hooksCommand,"ho")]:[],safe(rewindCommand,"rw"),safe(ideC,"i"),safe(initCommand,"in"),...isN?[safe(oncallCommand,"oc")]:[],...this.config?.getMcpEnabled()===false?[safe({name:"mcp",description:"Manage configured MCP servers",kind:"built-in",autoExecute:false,subCommands:[],action:async(c)=>({type:"message",messageType:"error",content:getAdminErrorMessage("MCP",this.config??void 0)})},"md")]:[safe(mcpCommand,"m")],safe(memoryCommand,"me"),safe(modelCommand,"mo"),...this.config?.getFolderTrust()?[safe(permissionsCommand,"pe")]:[],...this.config?.isPlanEnabled()?[safe(planCommand,"pl")]:[],safe(policiesCommand,"po"),safe(privacyCommand,"pr"),...isDevelopment?[safe(profileCommand,"pf")]:[],safe(quitCommand,"q"),safe(()=>restoreCommand(this.config),"rs"),safe({...resumeCommand,subCommands:addD(resumeCommand.subCommands)},"re"),safe(statsCommand,"st"),safe(themeCommand,"th"),safe(toolsCommand,"tl"),...this.config?.isSkillsSupportEnabled()?this.config?.getSkillManager()?.isAdminEnabled()===false?[safe({name:"skills",description:"Manage agent skills",kind:"built-in",autoExecute:false,subCommands:[],action:async(c)=>({type:"message",messageType:"error",content:getAdminErrorMessage("Agent skills",this.config??void 0)})},"sd")]:[safe(skillsCommand,"sk")]:[],safe(settingsCommand,"se"),safe(gemmaStatusCommand,"gs"),safe(tasksCommand,"ta"),safe(vimCommand,"vi"),safe(setupGithubCommand,"sg"),safe(terminalSetupCommand,"ts"),...this.config?.isVoiceModeEnabled()?[safe(voiceCommand,"v")]:[],...this.config?.getContentGeneratorConfig()?.authType===AuthType.LOGIN_WITH_GOOGLE?[safe(upgradeCommand,"u")]:[]];return defs.filter(c=>c!==null)}finally{h?.end()}}'
    },
    {
        name: "Zombie Process Duplicate Cleanup",
        match: /\((?:pid===process\.pid\|\|pid===process\.ppid\?undefined:process\.platform==="win32"\?require\("child_process"\)\.spawnSync\("taskkill",\["\/F","\/T","\/PID",pid\.toString\(\)\]\):\(?)+process\.kill\(-pid,(initialSignal|"SIGKILL")\)(?:\))+/g,
        replace: '(pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,$1))'
    },
    {
        name: "Zombie Process (SIGKILL/SIGTERM) with Guard",
        match: /^(?!.*taskkill)(.*)process\.kill\(-pid,\s*(initialSignal|"SIGKILL")\)(.*)$/gm,
        replace: '$1(pid===process.pid||pid===process.ppid?undefined:process.platform==="win32"?require("child_process").spawnSync("taskkill",["/F","/T","/PID",pid.toString()]):process.kill(-pid,$2))$3'
    },
    {
        name: "API Retry (Add POST)",
        match: /var retryMethods = \["get", "put", "head", "delete", "options", "trace"\];/,
        replace: 'var retryMethods = ["get", "post", "put", "head", "delete", "options", "trace"];'
    },
    {
        name: "Model Selection Loop (Auto-Fallback)",
        match: /resolvePolicyChain\(([a-zA-Z0-9_$]+),\s*([a-zA-Z0-9_$]+)\)(?!\s*,\s*true)/g,
        replace: 'resolvePolicyChain($1, $2, true)'
    },
    {
        name: "Dynamic Token Limits (Gemini 3 Support)",
        match: /function tokenLimit\(([a-zA-Z0-9_$]+)\)\s*\{\s*(?!if\(.*\.includes\("gemini-3"\)\))switch\s*\(\$1\)\s*\{/,
        replace: 'function tokenLimit($1){if($1.includes("gemini-3"))return 10000000;switch($1){'
    },
    {
        name: "Token Limit Default (2M)",
        match: /var DEFAULT_TOKEN_LIMIT = 1048576;/,
        replace: 'var DEFAULT_TOKEN_LIMIT = 2000000;'
    },
    {
        name: "Retry UI Feedback (Model Switching Message)",
        match: /onRetry:\s*\((attempt,\s*error[a-zA-Z0-9_$]*,\s*delayMs)\)\s*=>\s*\{\s*(?!const isModelChanged)(?=const actualMaxAttempts)/,
        replace: 'onRetry: ($1) => { const isModelChanged = getDisplayString(currentAttemptModel) !== getDisplayString(modelConfigKey.model); const message = isModelChanged ? `Switching to \${getDisplayString(currentAttemptModel)} due to availability issues...` : undefined;'
    },
    {
        name: "Retry Payload Expansion (Emit Message)",
        match: /model:\s*getDisplayString\(currentAttemptModel\)(?!,\s*message)/g,
        replace: 'model: getDisplayString(currentAttemptModel), message'
    },
    {
        name: "UI Loader Message Support",
        match: /(?<!retryStatus\.message \? retryStatus\.message : )retryStatus\.attempt\s*>=\s*[A-Z_]+_RETRY_HINT_ATTEMPT_THRESHOLD\s*\?\s*"[^"]*"\s*:\s*null/g,
        replace: 'retryStatus.message ? retryStatus.message : $&'
    }
];

function patchFile(filePath) {
    let content = fs.readFileSync(filePath, 'utf8');
    const originalContent = content;
    let modified = false;

    for (const rule of patchRules) {
        if (rule.match.test(content)) {
            const newContent = content.replace(rule.match, rule.replace);
            if (newContent !== content) {
                content = newContent;
                if (!isDryRun) {
                    modified = true;
                }
                console.log(`  [PATCHED] Rule: ${rule.name}`);
            }
        }
    }

    if (modified && !isDryRun) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupPath = `${filePath}.${timestamp}.bak`;
        fs.writeFileSync(backupPath, originalContent);
        fs.writeFileSync(filePath, content);
        return true;
    }
    return false;
}

function restoreFiles(targetDir) {
    const files = fs.readdirSync(targetDir);
    let restoredCount = 0;
    for (const file of files) {
        if (file.endsWith('.js')) {
            const fullPath = path.join(targetDir, file);
            const backups = files
                .filter(f => f.startsWith(file + '.') && f.endsWith('.bak'))
                .sort()
                .reverse();
            if (backups.length > 0) {
                const latestBackup = path.join(targetDir, backups[0]);
                console.log(`  [RESTORED] ${file} <- ${backups[0]}`);
                fs.copyFileSync(latestBackup, fullPath);
                restoredCount++;
            }
        }
    }
    return restoredCount;
}

try {
    const npmRoot = execSync('npm root -g').toString().trim();
    const targetDir = path.join(npmRoot, '@google/gemini-cli/bundle');

    if (!fs.existsSync(targetDir)) {
        console.error(`Error: Gemini CLI bundle not found at ${targetDir}`);
        process.exit(1);
    }

    console.log(`Target directory: ${targetDir}`);

    if (isRestore) {
        console.log('\nInitiating Restore Mode...');
        const count = restoreFiles(targetDir);
        console.log(`\nFinished. Restored ${count} files.`);
        process.exit(0);
    }

    if (isDryRun) {
        console.log('\nRunning in DRY-RUN mode. No files will be modified.\n');
    }

    const files = fs.readdirSync(targetDir).filter(f => f.endsWith('.js'));
    let totalPatched = 0;

    for (const file of files) {
        const filePath = path.join(targetDir, file);
        if (patchFile(filePath)) {
            console.log(`  [SUCCESS] ${file} updated.`);
            totalPatched++;
        }
    }

    console.log(`\nFinished. Total files updated: ${totalPatched}`);
} catch (e) {
    console.error(`\n[ERROR] ${e.message}`);
    process.exit(1);
}
