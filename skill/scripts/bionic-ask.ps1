param(
    [Parameter(Mandatory=$true)]
    [string]$Task,

    [string[]]$Files = @(),

    [string]$Model = "",

    [string]$LmsExe = "$env:USERPROFILE\.cache\lm-studio\bin\lms.exe",

    [Nullable[int]]$Port = $null,

    [Nullable[double]]$Temperature = $null,

    [Nullable[int]]$MaxTokens = $null
)

function Write-Status($msg) {
    Write-Host "[bionic] $msg" -ForegroundColor Cyan
}

# --- Transcript log so the user can watch what the subagent is doing (via the Activity Viewer) ---
$script:TranscriptPath = Join-Path $PSScriptRoot "..\transcript.log"
function Write-Transcript($text) {
    Add-Content -Path $script:TranscriptPath -Value $text -Encoding UTF8
}
$script:RequestTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# --- Load saved defaults from the config panel (Subagent BionicClaude), used for ---
# --- anything not explicitly passed on the command line ---
Import-Module (Join-Path $PSScriptRoot "BionicConfig.psm1") -Force
$cfg = Get-BionicConfig

if ([string]::IsNullOrWhiteSpace($Model) -and -not [string]::IsNullOrWhiteSpace($cfg.DefaultModel)) {
    $Model = $cfg.DefaultModel
}
if ($null -eq $Port) { $Port = [int]$cfg.Port }
if ($null -eq $Temperature) { $Temperature = [double]$cfg.Temperature }
if ($null -eq $MaxTokens) { $MaxTokens = [int]$cfg.MaxTokens }

if (-not (Test-Path $LmsExe)) {
    Write-Error "lms.exe not found at $LmsExe. Pass -LmsExe <path> if LM Studio is installed elsewhere."
    exit 1
}

# --- Ensure the LM Studio server is running (probe the REST API directly; ---
# --- lms.exe's own text output mixes stdout/stderr in ways that are brittle to parse) ---
$modelsUri = "http://127.0.0.1:$Port/v1/models"
$serverUp = $false
try {
    Invoke-RestMethod -Uri $modelsUri -Method Get -TimeoutSec 3 | Out-Null
    $serverUp = $true
} catch {
    Write-Status "LM Studio server not reachable on port $Port -- starting it..."
    & $LmsExe server start --port $Port 2>&1 | Out-Null
    $attempts = 0
    while ($attempts -lt 15) {
        Start-Sleep -Seconds 1
        $attempts++
        try {
            Invoke-RestMethod -Uri $modelsUri -Method Get -TimeoutSec 3 | Out-Null
            $serverUp = $true
            break
        } catch {
            $serverUp = $false
        }
    }
    if (-not $serverUp) {
        Write-Error "LM Studio server did not come up on port $Port after starting it. Check LM Studio is installed correctly."
        exit 1
    }
}

# NOTE: /v1/models lists every model available on disk, not just what's loaded in memory,
# and starting the server this way can drop whatever the LM Studio/Bionic GUI had loaded --
# so use `lms ps` (which only lists models currently loaded) to find the active model.
function Get-LoadedModelNames {
    $raw = & $LmsExe ps 2>&1 | Out-String
    if ($raw -match "No models are currently loaded|No models loaded") { return @() }
    $lines = $raw -split "`r?`n"
    $names = @()
    foreach ($line in $lines) {
        if ($line -notmatch "^\S") { continue }
        if ($line -match "^(IDENTIFIER|MODEL|---)") { continue }
        $name = ($line -split "\s{2,}")[0].Trim()
        if ($name) { $names += $name }
    }
    return $names
}

# Only one model may be loaded at a time -- loading a model that's already loaded creates a
# second in-memory instance (name:2, name:3, ...) instead of reusing it, and this skill never
# needs more than one model resident at once, so unload anything else before loading a new one.
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $loadedNames = Get-LoadedModelNames
    if ($loadedNames -contains $Model) {
        Write-Status "$Model is already loaded."
    } else {
        foreach ($other in $loadedNames) {
            Write-Status "Unloading $other to keep only one model loaded at a time..."
            & $LmsExe unload $other 2>&1 | Out-Null
        }
        Write-Status "Loading $Model ..."
        & $LmsExe load $Model 2>&1 | Out-Null
    }
} else {
    $loadedNames = Get-LoadedModelNames
    if ($loadedNames.Count -gt 0) {
        $Model = $loadedNames[0]
        Write-Status "No -Model specified; using currently loaded model: $Model"
    }
}

if ([string]::IsNullOrWhiteSpace($Model)) {
    $hint = "No model is currently loaded in LM Studio, and no -Model was specified. " +
            "Run '$LmsExe ls' to see available models, then either load one with " +
            "'$LmsExe load MODEL_NAME' or pass -Model MODEL_NAME to this script " +
            "(e.g. -Model deepseek-coder-6.7b-instruct for coding tasks)."
    Write-Error $hint
    exit 1
}

# --- Build the prompt with file context ---
$contextBlocks = @()
foreach ($f in $Files) {
    if (-not (Test-Path $f)) {
        Write-Status "Warning: file not found, skipping: $f"
        continue
    }
    $content = Get-Content -Raw -Path $f
    $ext = [System.IO.Path]::GetExtension($f).TrimStart('.')
    $resolved = (Resolve-Path $f).Path
    $contextBlocks += "File: $resolved`n``````$ext`n$content`n``````"
}

$systemPrompt = @"
You are a local coding subagent invoked by Claude Code to assist with a coding subtask.
You are running locally via LM Studio and have no direct file system access -- you can only
see the file contents given to you below and must respond with proposed changes as text.

When proposing changes to an existing file, output the FULL new contents of that file in a
fenced code block preceded by a line exactly of the form:
FILE: <the exact path given to you>

When creating a new file, use the same format with the intended path.

If you are only answering a question or giving advice (not proposing file changes), just
respond normally in plain text/markdown -- do not invent a FILE: block.

Be concise. Do not restate the task back to the user. Do not include explanations of what
you changed unless asked -- Claude Code will present your output to the user for review.
"@

$userPrompt = "Task:`n$Task"
if ($contextBlocks.Count -gt 0) {
    $userPrompt += "`n`nRelevant files:`n`n" + ($contextBlocks -join "`n`n")
}

$body = @{
    model = $Model
    messages = @(
        @{ role = "system"; content = $systemPrompt },
        @{ role = "user"; content = $userPrompt }
    )
    temperature = $Temperature
    max_tokens = $MaxTokens
    stream = $false
} | ConvertTo-Json -Depth 10

Write-Status "Sending task to $Model ..."

$fileList = if ($Files.Count -gt 0) { ($Files -join ", ") } else { "(none)" }
Write-Transcript @"
================================================================================
[$script:RequestTime] REQUEST -> $Model
Task: $Task
Files: $fileList
--------------------------------------------------------------------------------
"@

try {
    $response = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" `
        -Method Post -ContentType "application/json" -Body $body -TimeoutSec 300
} catch {
    $errMsg = "Request to local LM Studio server failed: $($_.Exception.Message)"
    Write-Transcript "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR`n$errMsg`n"
    Write-Error $errMsg
    exit 1
}

$answer = $response.choices[0].message.content

Write-Transcript @"
[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RESPONSE <- $Model
$answer

"@

Write-Output $answer
