<#
.SYNOPSIS
    Installs the Bionic Claude Code skill and the Subagent BionicClaude config app.

.DESCRIPTION
    Copies the skill files from this package into %USERPROFILE%\.claude\skills\bionic
    (where Claude Code looks for skills), and creates a desktop shortcut for the
    Subagent BionicClaude configuration app.

    Safe to re-run: if you already have a config.json or transcript.log in the target
    skill folder, this installer leaves them alone so you don't lose your saved
    settings or activity history. Everything else is overwritten with the version
    in this package.
#>

$ErrorActionPreference = "Continue"

$SourceRoot = Join-Path $PSScriptRoot "skill"
$TargetRoot = Join-Path $env:USERPROFILE ".claude\skills\bionic"
$TargetScripts = Join-Path $TargetRoot "scripts"
$LmsExe = Join-Path $env:USERPROFILE ".cache\lm-studio\bin\lms.exe"

Write-Host ""
Write-Host "=== Bionic Claude installer ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SourceRoot)) {
    Write-Host "ERROR: Could not find the 'skill' folder next to this installer at:" -ForegroundColor Red
    Write-Host "  $SourceRoot"
    Write-Host "Make sure you're running Install.ps1 from inside the BionicClaude package folder."
    exit 1
}

# --- 1. Check for LM Studio ---
if (Test-Path $LmsExe) {
    Write-Host "[OK] Found LM Studio's lms CLI at $LmsExe" -ForegroundColor Green
} else {
    Write-Host "[WARNING] lms.exe not found at $LmsExe" -ForegroundColor Yellow
    Write-Host "          This skill needs LM Studio installed to run the local model."
    Write-Host "          Install it from https://lmstudio.ai, then re-run this installer"
    Write-Host "          (or it will just work once LM Studio is installed -- no need to re-run)."
    Write-Host ""
}

# --- 2. Create target folder structure ---
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $TargetScripts -Force | Out-Null

# --- 3. Copy skill files (never touch an existing config.json / transcript.log) ---
Copy-Item -Path (Join-Path $SourceRoot "SKILL.md") -Destination $TargetRoot -Force
Write-Host "[OK] Installed SKILL.md" -ForegroundColor Green

Get-ChildItem -Path (Join-Path $SourceRoot "scripts") -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $TargetScripts -Force
}
Write-Host "[OK] Installed scripts to $TargetScripts" -ForegroundColor Green

$configPath = Join-Path $TargetRoot "config.json"
if (-not (Test-Path $configPath)) {
    '{"DefaultModel":"","Port":1234,"Temperature":0.2,"MaxTokens":4096}' | Set-Content -Path $configPath -Encoding UTF8
    Write-Host "[OK] Created default config.json" -ForegroundColor Green
} else {
    Write-Host "[OK] Existing config.json left untouched (your saved settings are safe)" -ForegroundColor Green
}

$transcriptPath = Join-Path $TargetRoot "transcript.log"
if (-not (Test-Path $transcriptPath)) {
    New-Item -ItemType File -Path $transcriptPath -Force | Out-Null
    Write-Host "[OK] Created empty transcript.log" -ForegroundColor Green
} else {
    Write-Host "[OK] Existing transcript.log left untouched" -ForegroundColor Green
}

# --- 4. Desktop shortcut for the config app ---
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Subagent BionicClaude.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut($desktopShortcut)
$shortcut.TargetPath = "wscript.exe"
$shortcut.Arguments = "`"$(Join-Path $TargetScripts 'Launch-BionicClaude.vbs')`""
$shortcut.WorkingDirectory = $TargetScripts
$shortcut.IconLocation = "shell32.dll,21"
$shortcut.Description = "Configure the local LLM subagent Claude Code delegates coding tasks to"
$shortcut.Save()
Write-Host "[OK] Created desktop shortcut: Subagent BionicClaude" -ForegroundColor Green

Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Skill installed to: $TargetRoot"
Write-Host "Claude Code will pick it up automatically the next time it starts (or right away"
Write-Host "if it's already running and re-scans skills)."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Double-click the 'Subagent BionicClaude' shortcut on your Desktop."
Write-Host "  2. Click 'Start Server', then load a model from the Installed Models list"
Write-Host "     (or 'Download New...' if you don't have one yet)."
Write-Host "  3. In Claude Code, just ask for a coding subtask -- Claude will use the"
Write-Host "     'bionic' skill automatically when it makes sense, or you can say"
Write-Host "     'ask Bionic to ...' explicitly."
Write-Host ""
Write-Host "See README.md in this folder for full documentation."
Write-Host ""
