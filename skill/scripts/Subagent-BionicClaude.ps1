Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

Import-Module (Join-Path $PSScriptRoot "BionicConfig.psm1") -Force

$LmsExe = "$env:USERPROFILE\.cache\lm-studio\bin\lms.exe"
$script:Port = 1234
$script:DownloadJob = $null
$script:DownloadProcess = $null
$script:TranscriptPath = Join-Path $PSScriptRoot "..\transcript.log"
$script:TranscriptLastWrite = [DateTime]::MinValue

# ---------- helpers ----------

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$ts] $msg`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
}

function Set-Busy($busy, $downloadMode = $false) {
    $form.Cursor = if ($busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    foreach ($ctrl in @($btnStart, $btnStop, $btnRefresh, $btnLoadModel, $btnUnloadModel, $btnUnloadAll, $btnDownload, $btnSave, $btnClearTerm, $modelList)) {
        $ctrl.Enabled = -not $busy
    }
    if ($downloadMode) {
        $btnCancelDownload.Visible = $busy
        $btnCancelDownload.Enabled = $true
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-LoadedModelNames {
    # /v1/models lists every model available on disk, not just what's loaded in memory,
    # so use `lms ps` (which only lists models currently loaded) as the source of truth.
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

function Get-ServerStatus {
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$($script:Port)/v1/models" -Method Get -TimeoutSec 2
        $loadedNames = Get-LoadedModelNames
        return @{ Running = $true; Loaded = $loadedNames }
    } catch {
        return @{ Running = $false; Loaded = @() }
    }
}

function Get-InstalledModels {
    # Parses `lms ls` text output into a list of model identifiers (LLMs only, not embedding models).
    $raw = & $LmsExe ls 2>&1 | Out-String
    $lines = $raw -split "`r?`n"
    $models = @()
    $inLlmSection = $false
    foreach ($line in $lines) {
        if ($line -match "^LLM\s") { $inLlmSection = $true; continue }
        if ($line -match "^EMBEDDING\s") { $inLlmSection = $false; continue }
        if (-not $inLlmSection) { continue }
        if ($line -notmatch "^\S") { continue }
        $name = ($line -split "\s{2,}")[0].Trim()
        # Strip a "(N variant)" / "(N variants)" suffix -- lms ls shows that next to the name
        # with only a single space, so it isn't caught by the double-space column split above,
        # and it isn't part of the real model identifier `lms load`/`lms unload` expect.
        $name = $name -replace "\s*\(\d+\s+variants?\)\s*$", ""
        if ($name) { $models += $name }
    }
    return $models
}

function Refresh-Status {
    Set-Busy $true
    try {
        $status = Get-ServerStatus
        if ($status.Running) {
            $lblServerStatus.Text = "Server: RUNNING on port $($script:Port)"
            $lblServerStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        } else {
            $lblServerStatus.Text = "Server: NOT running"
            $lblServerStatus.ForeColor = [System.Drawing.Color]::DarkRed
        }

        $loadedIds = @($status.Loaded)
        $installed = Get-InstalledModels

        $modelList.Items.Clear()
        foreach ($m in $installed) {
            $label = if ($loadedIds -contains $m) { "$m   [LOADED]" } else { $m }
            [void]$modelList.Items.Add($label)
        }

        $comboDefault.Items.Clear()
        [void]$comboDefault.Items.Add("(auto - whatever is loaded)")
        foreach ($m in $installed) { [void]$comboDefault.Items.Add($m) }

        $cfg = Get-BionicConfig
        if ([string]::IsNullOrWhiteSpace($cfg.DefaultModel)) {
            $comboDefault.SelectedIndex = 0
        } else {
            $idx = $comboDefault.Items.IndexOf($cfg.DefaultModel)
            $comboDefault.SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }
        }
        $txtPort.Text = "$($cfg.Port)"
        $txtTemp.Text = "$($cfg.Temperature)"
        $txtMaxTokens.Text = "$($cfg.MaxTokens)"
        $script:Port = [int]$cfg.Port

        Log "Status refreshed. $($installed.Count) model(s) installed, $($loadedIds.Count) loaded."
    } catch {
        Log "Error refreshing status: $($_.Exception.Message)"
    } finally {
        Set-Busy $false
    }
}

function Refresh-Transcript {
    if (-not (Test-Path $script:TranscriptPath)) { return }
    try {
        $info = Get-Item $script:TranscriptPath -ErrorAction Stop
        if ($info.LastWriteTime -eq $script:TranscriptLastWrite) { return }
        $script:TranscriptLastWrite = $info.LastWriteTime

        $content = Get-Content -Raw -Path $script:TranscriptPath -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($content)) {
            $content = "No activity yet. This updates automatically whenever Claude Code sends a task to the local subagent."
        }
        $termBox.Text = $content
        $termBox.SelectionStart = $termBox.Text.Length
        $termBox.ScrollToCaret()
    } catch {
        # transcript file may be mid-write; skip this poll, try again next tick
    }
}

function Get-SelectedModelName {
    if ($modelList.SelectedItem) {
        return ($modelList.SelectedItem -split "\s{2,}")[0].Trim()
    }
    return $null
}

# ---------- UI ----------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Subagent BionicClaude"
$form.Size = New-Object System.Drawing.Size(560, 900)
$form.MinimumSize = New-Object System.Drawing.Size(560, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true

$title = New-Object System.Windows.Forms.Label
$title.Text = "Subagent BionicClaude"
$title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(15, 10)
$title.Size = New-Object System.Drawing.Size(500, 30)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Configure the local LM Studio model Claude Code delegates coding subtasks to."
$subtitle.Location = New-Object System.Drawing.Point(15, 40)
$subtitle.Size = New-Object System.Drawing.Size(520, 20)
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($subtitle)

# --- Server group ---
$grpServer = New-Object System.Windows.Forms.GroupBox
$grpServer.Text = "LM Studio Server"
$grpServer.Location = New-Object System.Drawing.Point(15, 70)
$grpServer.Size = New-Object System.Drawing.Size(515, 80)
$form.Controls.Add($grpServer)

$lblServerStatus = New-Object System.Windows.Forms.Label
$lblServerStatus.Text = "Server: unknown"
$lblServerStatus.Location = New-Object System.Drawing.Point(15, 25)
$lblServerStatus.Size = New-Object System.Drawing.Size(300, 20)
$grpServer.Controls.Add($lblServerStatus)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Server"
$btnStart.Location = New-Object System.Drawing.Point(15, 45)
$btnStart.Size = New-Object System.Drawing.Size(110, 26)
$grpServer.Controls.Add($btnStart)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = "Stop Server"
$btnStop.Location = New-Object System.Drawing.Point(135, 45)
$btnStop.Size = New-Object System.Drawing.Size(110, 26)
$grpServer.Controls.Add($btnStop)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = "Refresh Status"
$btnRefresh.Location = New-Object System.Drawing.Point(255, 45)
$btnRefresh.Size = New-Object System.Drawing.Size(110, 26)
$grpServer.Controls.Add($btnRefresh)

# --- Models group ---
$grpModels = New-Object System.Windows.Forms.GroupBox
$grpModels.Text = "Installed Models"
$grpModels.Location = New-Object System.Drawing.Point(15, 160)
$grpModels.Size = New-Object System.Drawing.Size(515, 230)
$form.Controls.Add($grpModels)

$modelList = New-Object System.Windows.Forms.ListBox
$modelList.Location = New-Object System.Drawing.Point(15, 22)
$modelList.Size = New-Object System.Drawing.Size(485, 120)
$grpModels.Controls.Add($modelList)

$btnLoadModel = New-Object System.Windows.Forms.Button
$btnLoadModel.Text = "Load Selected"
$btnLoadModel.Location = New-Object System.Drawing.Point(15, 150)
$btnLoadModel.Size = New-Object System.Drawing.Size(110, 26)
$grpModels.Controls.Add($btnLoadModel)

$btnUnloadModel = New-Object System.Windows.Forms.Button
$btnUnloadModel.Text = "Unload Selected"
$btnUnloadModel.Location = New-Object System.Drawing.Point(135, 150)
$btnUnloadModel.Size = New-Object System.Drawing.Size(110, 26)
$grpModels.Controls.Add($btnUnloadModel)

$btnUnloadAll = New-Object System.Windows.Forms.Button
$btnUnloadAll.Text = "Unload All"
$btnUnloadAll.Location = New-Object System.Drawing.Point(15, 182)
$btnUnloadAll.Size = New-Object System.Drawing.Size(110, 26)
$btnUnloadAll.ForeColor = [System.Drawing.Color]::DarkRed
$grpModels.Controls.Add($btnUnloadAll)

$btnDownload = New-Object System.Windows.Forms.Button
$btnDownload.Text = "Download New..."
$btnDownload.Location = New-Object System.Drawing.Point(135, 182)
$btnDownload.Size = New-Object System.Drawing.Size(130, 26)
$grpModels.Controls.Add($btnDownload)

$btnCancelDownload = New-Object System.Windows.Forms.Button
$btnCancelDownload.Text = "Cancel Download"
$btnCancelDownload.Location = New-Object System.Drawing.Point(275, 182)
$btnCancelDownload.Size = New-Object System.Drawing.Size(105, 26)
$btnCancelDownload.ForeColor = [System.Drawing.Color]::DarkRed
$btnCancelDownload.Visible = $false
$grpModels.Controls.Add($btnCancelDownload)

# --- Defaults group ---
$grpDefaults = New-Object System.Windows.Forms.GroupBox
$grpDefaults.Text = "Defaults used by the Bionic skill"
$grpDefaults.Location = New-Object System.Drawing.Point(15, 400)
$grpDefaults.Size = New-Object System.Drawing.Size(515, 140)
$form.Controls.Add($grpDefaults)

$lblDefault = New-Object System.Windows.Forms.Label
$lblDefault.Text = "Default model:"
$lblDefault.Location = New-Object System.Drawing.Point(15, 28)
$lblDefault.Size = New-Object System.Drawing.Size(100, 20)
$grpDefaults.Controls.Add($lblDefault)

$comboDefault = New-Object System.Windows.Forms.ComboBox
$comboDefault.Location = New-Object System.Drawing.Point(120, 25)
$comboDefault.Size = New-Object System.Drawing.Size(380, 24)
$comboDefault.DropDownStyle = "DropDownList"
$grpDefaults.Controls.Add($comboDefault)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Port:"
$lblPort.Location = New-Object System.Drawing.Point(15, 60)
$lblPort.Size = New-Object System.Drawing.Size(100, 20)
$grpDefaults.Controls.Add($lblPort)

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Location = New-Object System.Drawing.Point(120, 57)
$txtPort.Size = New-Object System.Drawing.Size(80, 24)
$grpDefaults.Controls.Add($txtPort)

$lblTemp = New-Object System.Windows.Forms.Label
$lblTemp.Text = "Temperature:"
$lblTemp.Location = New-Object System.Drawing.Point(220, 60)
$lblTemp.Size = New-Object System.Drawing.Size(90, 20)
$grpDefaults.Controls.Add($lblTemp)

$txtTemp = New-Object System.Windows.Forms.TextBox
$txtTemp.Location = New-Object System.Drawing.Point(310, 57)
$txtTemp.Size = New-Object System.Drawing.Size(60, 24)
$grpDefaults.Controls.Add($txtTemp)

$lblMaxTokens = New-Object System.Windows.Forms.Label
$lblMaxTokens.Text = "Max tokens:"
$lblMaxTokens.Location = New-Object System.Drawing.Point(15, 92)
$lblMaxTokens.Size = New-Object System.Drawing.Size(100, 20)
$grpDefaults.Controls.Add($lblMaxTokens)

$txtMaxTokens = New-Object System.Windows.Forms.TextBox
$txtMaxTokens.Location = New-Object System.Drawing.Point(120, 89)
$txtMaxTokens.Size = New-Object System.Drawing.Size(80, 24)
$grpDefaults.Controls.Add($txtMaxTokens)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Save Settings"
$btnSave.Location = New-Object System.Drawing.Point(380, 100)
$btnSave.Size = New-Object System.Drawing.Size(120, 28)
$grpDefaults.Controls.Add($btnSave)

# --- Operational log box (start/stop/load/unload/download status messages) ---
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Location = New-Object System.Drawing.Point(15, 546)
$logBox.Size = New-Object System.Drawing.Size(515, 65)
$logBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$form.Controls.Add($logBox)

# --- Bionic Activity terminal panel: live transcript of what the subagent is being asked / replying ---
$lblTerm = New-Object System.Windows.Forms.Label
$lblTerm.Text = "Bionic Activity - live subagent transcript"
$lblTerm.Location = New-Object System.Drawing.Point(15, 619)
$lblTerm.Size = New-Object System.Drawing.Size(400, 18)
$lblTerm.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
$lblTerm.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblTerm)

$btnClearTerm = New-Object System.Windows.Forms.Button
$btnClearTerm.Text = "Clear"
$btnClearTerm.Location = New-Object System.Drawing.Point(455, 613)
$btnClearTerm.Size = New-Object System.Drawing.Size(75, 24)
$btnClearTerm.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($btnClearTerm)

$termBox = New-Object System.Windows.Forms.TextBox
$termBox.Multiline = $true
$termBox.ScrollBars = "Vertical"
$termBox.ReadOnly = $true
$termBox.Location = New-Object System.Drawing.Point(15, 636)
$termBox.Size = New-Object System.Drawing.Size(515, 220)
$termBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$termBox.BackColor = [System.Drawing.Color]::Black
$termBox.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 0)
$termBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$termBox.BorderStyle = "FixedSingle"
$form.Controls.Add($termBox)

# ---------- events ----------

$btnStart.Add_Click({
    Set-Busy $true
    try {
        Log "Starting LM Studio server..."
        & $LmsExe server start --port $script:Port 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    } finally {
        Set-Busy $false
        Refresh-Status
    }
})

$btnStop.Add_Click({
    Set-Busy $true
    try {
        Log "Stopping LM Studio server..."
        & $LmsExe server stop 2>&1 | Out-Null
    } finally {
        Set-Busy $false
        Refresh-Status
    }
})

$btnRefresh.Add_Click({ Refresh-Status })

$btnClearTerm.Add_Click({
    Set-Content -Path $script:TranscriptPath -Value "" -Encoding UTF8 -NoNewline
    $script:TranscriptLastWrite = [DateTime]::MinValue
    Refresh-Transcript
    Log "Cleared Bionic Activity transcript."
})

$btnLoadModel.Add_Click({
    $name = Get-SelectedModelName
    if (-not $name) { Log "Select a model first."; return }
    Set-Busy $true
    try {
        # Only one model may be loaded at a time. Loading a model that's already loaded creates
        # a second instance (name:2, name:3, ...) instead of reusing it, so skip in that case;
        # if a different model is loaded, unload it first so we never end up with more than one.
        $alreadyLoaded = Get-LoadedModelNames
        if ($alreadyLoaded -contains $name) {
            Log "$name is already loaded; skipping (avoids creating a duplicate instance)."
        } else {
            foreach ($other in $alreadyLoaded) {
                Log "Unloading $other to keep only one model loaded at a time..."
                & $LmsExe unload $other 2>&1 | Out-Null
            }
            Log "Loading $name (this can take a while for large models)..."
            & $LmsExe load $name -y 2>&1 | Out-Null
            Log "Load requested for $name."
        }
    } finally {
        Set-Busy $false
        Refresh-Status
    }
})

$btnUnloadModel.Add_Click({
    $name = Get-SelectedModelName
    if (-not $name) { Log "Select a model first."; return }
    Set-Busy $true
    try {
        Log "Unloading $name..."
        & $LmsExe unload $name 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    } finally {
        Set-Busy $false
        Refresh-Status
    }
})

$btnUnloadAll.Add_Click({
    Set-Busy $true
    try {
        Log "Unloading all loaded models..."
        & $LmsExe unload --all 2>&1 | Out-Null
        Start-Sleep -Seconds 1
    } finally {
        Set-Busy $false
        Refresh-Status
    }
})

$btnDownload.Add_Click({
    $name = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Model to search/download, e.g. 'qwen/qwen2.5-coder-7b-instruct' or a search term like 'qwen coder':",
        "Download New Model", "")
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    Set-Busy $true -downloadMode $true
    Log "Starting download of: $name"

    # Run download as a background job so UI stays responsive
    $script:DownloadJob = Start-Job -ScriptBlock {
        param($lmsPath, $modelName)
        & $lmsPath get $modelName -y 2>&1
    } -ArgumentList $LmsExe, $name

    # Poll the job and stream output to log
    $pollTimer = New-Object System.Windows.Forms.Timer
    $pollTimer.Interval = 500
    $pollTimer.Add_Tick({
        if ($script:DownloadJob -and $script:DownloadJob.State -eq "Running") {
            # Capture any new output since last poll
            $output = Receive-Job -Job $script:DownloadJob -Keep 2>$null
            if ($output) {
                foreach ($line in @($output)) {
                    if ($line) { Log "  $line" }
                }
            }
        } else {
            # Job finished
            $pollTimer.Stop()
            $output = Receive-Job -Job $script:DownloadJob 2>$null
            if ($output) {
                foreach ($line in @($output)) {
                    if ($line) { Log "  $line" }
                }
            }
            $exitCode = $script:DownloadJob.State
            if ($exitCode -eq "Completed") {
                Log "Download of $name completed successfully."
            } else {
                Log "Download of $name failed or was cancelled."
            }
            $script:DownloadJob = $null
            Set-Busy $false -downloadMode $true
            Refresh-Status
        }
    })
    $pollTimer.Start()
})

$btnCancelDownload.Add_Click({
    if ($script:DownloadJob) {
        Log "Cancelling download..."
        Stop-Job -Job $script:DownloadJob
        Remove-Job -Job $script:DownloadJob
        $script:DownloadJob = $null
        Set-Busy $false -downloadMode $true
    }
})

$btnSave.Add_Click({
    $defaultModel = if ($comboDefault.SelectedIndex -le 0) { "" } else { $comboDefault.SelectedItem.ToString() }
    $port = 1234
    $temp = 0.2
    $maxTok = 4096
    if (-not [int]::TryParse($txtPort.Text, [ref]$port)) { Log "Invalid port, keeping 1234."; $port = 1234 }
    if (-not [double]::TryParse($txtTemp.Text, [ref]$temp)) { Log "Invalid temperature, keeping 0.2."; $temp = 0.2 }
    if (-not [int]::TryParse($txtMaxTokens.Text, [ref]$maxTok)) { Log "Invalid max tokens, keeping 4096."; $maxTok = 4096 }

    $config = @{
        DefaultModel = $defaultModel
        Port         = $port
        Temperature  = $temp
        MaxTokens    = $maxTok
    }
    Set-BionicConfig -Config $config
    $script:Port = $port
    Log "Settings saved to $(Get-BionicConfigPath)"
})

$transcriptTimer = New-Object System.Windows.Forms.Timer
$transcriptTimer.Interval = 1000
$transcriptTimer.Add_Tick({ Refresh-Transcript })
$transcriptTimer.Start()

$form.Add_Shown({
    Refresh-Status
    Refresh-Transcript
})
[void]$form.ShowDialog()
