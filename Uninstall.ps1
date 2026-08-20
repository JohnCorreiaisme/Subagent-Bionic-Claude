<#
.SYNOPSIS
    Removes the Bionic Claude Code skill and its desktop shortcut.

.DESCRIPTION
    Deletes %USERPROFILE%\.claude\skills\bionic (the skill Claude Code loads, including
    your saved config.json and transcript.log) and the "Subagent BionicClaude" desktop
    shortcut. Does NOT uninstall LM Studio or delete any downloaded models -- those are
    managed by LM Studio itself, independent of this skill.
#>

$TargetRoot = Join-Path $env:USERPROFILE ".claude\skills\bionic"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Subagent BionicClaude.lnk"

Write-Host ""
Write-Host "=== Bionic Claude uninstaller ===" -ForegroundColor Cyan
Write-Host ""

if (Test-Path $TargetRoot) {
    $confirm = Read-Host "This will delete $TargetRoot (including saved settings and activity log). Continue? [y/N]"
    if ($confirm -eq "y" -or $confirm -eq "Y") {
        Remove-Item -Path $TargetRoot -Recurse -Force
        Write-Host "[OK] Removed $TargetRoot" -ForegroundColor Green
    } else {
        Write-Host "Skipped removing skill files."
    }
} else {
    Write-Host "[OK] Skill folder not found, nothing to remove: $TargetRoot" -ForegroundColor Green
}

if (Test-Path $desktopShortcut) {
    Remove-Item -Path $desktopShortcut -Force
    Write-Host "[OK] Removed desktop shortcut" -ForegroundColor Green
} else {
    Write-Host "[OK] Desktop shortcut not found, nothing to remove" -ForegroundColor Green
}

Write-Host ""
Write-Host "Uninstall complete. LM Studio itself and any downloaded models were left in place."
Write-Host ""
