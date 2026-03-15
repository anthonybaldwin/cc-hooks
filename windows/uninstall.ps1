# CC Hooks — Windows Uninstall
#
# Run: pwsh -NoProfile -File uninstall.ps1
# Triggers a UAC prompt for the HKLM registry removal.
#
# Removes: watcher processes, protocol handlers (HKCU), AUMID keys
# (HKCU + HKLM), and notification hooks from ~/.claude/settings.json.

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

$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties['hooks']) {
        foreach ($event in @("UserPromptSubmit", "Notification", "Stop", "SessionEnd")) {
            if ($settings.hooks.PSObject.Properties[$event]) {
                $filtered = @($settings.hooks.$event | Where-Object {
                    -not ($_.hooks | Where-Object { $_.command -match "notifications" })
                })
                if ($filtered.Count -eq 0) { $settings.hooks.PSObject.Properties.Remove($event) }
                else { $settings.hooks.$event = $filtered }
            }
        }
        if (($settings.hooks.PSObject.Properties | Measure-Object).Count -eq 0) {
            $settings.PSObject.Properties.Remove('hooks')
        }
        $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    }
}

Write-Host "Uninstalled"
