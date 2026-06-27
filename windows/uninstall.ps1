# CC Hooks — Windows Uninstall
#
# Run: pwsh -NoProfile -File uninstall.ps1                # uninstall all hooks
#      pwsh -NoProfile -File uninstall.ps1 notifications  # uninstall a specific hook
#      pwsh -NoProfile -File uninstall.ps1 session-color
#
# The notifications hook triggers a UAC prompt for HKLM registry removal.

param([string]$target = "all")

$winDir = $PSScriptRoot

function Uninstall-Notifications {
    Get-Process -Name "notifications" -ErrorAction SilentlyContinue | Stop-Process -Force

    foreach ($proto in @("claude-focus", "claude-editor")) {
        $key = "HKCU:\Software\Classes\$proto"
        if (Test-Path $key) { Remove-Item $key -Recurse -Force }
    }

    $hkcuKey = "HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
    if (Test-Path $hkcuKey) { Remove-Item $hkcuKey -Force }

    $hklmKey = "HKLM:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
    $regCmd = "if (Test-Path '$hklmKey') { Remove-Item '$hklmKey' -Force }"
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Invoke-Expression $regCmd
    } else {
        try { Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -Command $regCmd" -Wait }
        catch { Write-Host "Skipped HKLM removal (admin declined). Remove manually: HKLM\Software\Classes\AppUserModelId\ClaudeCode.Hooks" }
    }

    # Hook config + temp file cleanup
    $exe = Join-Path $winDir "notifications\target\release\notifications.exe"
    if (Test-Path $exe) {
        & $exe uninstall
    } else {
        Write-Host "Uninstalled notifications"
    }
}

function Uninstall-SessionColor {
    $exe = Join-Path $winDir "session-color\target\release\session-color.exe"
    if (Test-Path $exe) {
        & $exe uninstall
    } else {
        Write-Host "session-color binary not found — nothing to uninstall"
    }

    # Reset background on the current terminal, if any.
    Write-Host -NoNewline "`e]111`a"
}

switch ($target) {
    "all"           { Uninstall-Notifications; Uninstall-SessionColor }
    "notifications" { Uninstall-Notifications }
    "session-color" { Uninstall-SessionColor }
    default { Write-Host "Unknown hook: $target (expected: notifications, session-color)"; exit 1 }
}
