# CC Hooks — Windows Install
#
# Run: pwsh -NoProfile -File install.ps1
# Triggers a UAC prompt for the HKLM registry write (icon + display name).
#
# What it does:
# 1. Builds notifications.exe from Rust source (cargo build --release)
# 2. Registers claude-focus:// and claude-editor:// protocol handlers (HKCU)
#    so toast button clicks route to the exe
# 3. Registers AUMID in HKLM for toast attribution (display name + icon)
#    Falls back to HKCU (no icon) if admin is declined
# 4. Merges hook config into ~/.claude/settings.json

$winDir = $PSScriptRoot
$notifDir = Join-Path $winDir "notifications"
$exe = Join-Path $notifDir "bin\notifications.exe"

# Build the Rust project
Write-Host "Building..."
cargo build --release --manifest-path (Join-Path $notifDir "Cargo.toml") 2>&1 | Select-Object -Last 3
New-Item -ItemType Directory -Path (Join-Path $notifDir "bin") -Force | Out-Null
Copy-Item (Join-Path $notifDir "target\release\notifications.exe") (Join-Path $notifDir "bin\notifications.exe") -Force

# Register protocol handlers
# - claude-focus://  → notifications.exe trigger %1 (creates trigger file for watcher)
# - claude-editor:// → notifications.exe editor %1 (opens configured editor)
foreach ($proto in @(
    @{ name = "claude-focus"; cmd = "trigger" },
    @{ name = "claude-editor"; cmd = "editor" }
)) {
    $base = "HKCU:\Software\Classes\$($proto.name)"
    New-Item -Path $base -Force | Out-Null
    Set-ItemProperty -Path $base -Name "(Default)" -Value "URL:$($proto.name) Protocol"
    New-ItemProperty -Path $base -Name "URL Protocol" -Value "" -Force | Out-Null
    New-Item -Path "$base\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "$base\shell\open\command" -Name "(Default)" -Value "`"$exe`" $($proto.cmd) `"%1`""
    Write-Host "Registered $($proto.name)://"
}

# Register AUMID in HKLM for toast notification attribution (icon + display name).
# Requires elevation — self-elevates via UAC prompt if not already admin.
$configPath = Join-Path $notifDir "config.json"
$config = if (Test-Path $configPath) { Get-Content $configPath -Raw | ConvertFrom-Json } else { $null }
$title = if ($config -and $config.title) { $config.title } else { "CC Notification" }
$iconFile = if ($config -and $config.icons -and $config.icons.title) { $config.icons.title } else { "icons\title.ico" }
$iconPath = Join-Path $notifDir $iconFile

$aumidKey = "HKLM:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
# Try configured icon path, fall back to .ico
if (-not (Test-Path $iconPath)) { $iconPath = Join-Path $notifDir "icons\title.ico" }
$regCmd = "New-Item -Path '$aumidKey' -Force | Out-Null; " +
    "New-ItemProperty -Path '$aumidKey' -Name 'DisplayName' -Value '$title' -PropertyType ExpandString -Force | Out-Null; " +
    "New-ItemProperty -Path '$aumidKey' -Name 'IconUri' -Value '$iconPath' -PropertyType ExpandString -Force | Out-Null"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Invoke-Expression $regCmd
    Write-Host "Registered AUMID: ClaudeCode.Hooks ($title) [HKLM]"
} else {
    try {
        Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -Command $regCmd" -Wait
        Write-Host "Registered AUMID: ClaudeCode.Hooks ($title) [HKLM]"
    } catch {
        # UAC declined — fall back to HKCU (no icon support, but DisplayName works)
        $fallbackKey = "HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
        New-Item -Path $fallbackKey -Force | Out-Null
        New-ItemProperty -Path $fallbackKey -Name "DisplayName" -Value $title -PropertyType ExpandString -Force | Out-Null
        Write-Host "Registered AUMID without icon (admin declined). To add icon, run as admin:"
        Write-Host "  pwsh -NoProfile -File $($MyInvocation.MyCommand.Path)"
    }
}

# Clean up old Start Menu shortcuts and HKCU AUMID from previous installs
$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
Get-ChildItem "$startMenu\*.lnk" | ForEach-Object {
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($_.FullName)
        if ($sc.TargetPath -match "notifications") { Remove-Item $_.FullName -Force; Write-Host "Removed old shortcut: $($_.Name)" }
    } catch {}
}
$oldKey = "HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
if (Test-Path $oldKey) { Remove-Item $oldKey -Force; Write-Host "Removed old HKCU AUMID key" }

# Add hooks to settings.json (only touches our hook events, preserves everything else)
$claude = Join-Path $env:USERPROFILE ".claude"
$settingsPath = "$claude\settings.json"
$settings = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json } else { [PSCustomObject]@{} }
$exePath = $exe -replace '\\', '/'
$hooks = @{
    UserPromptSubmit = @(@{ matcher = ""; hooks = @(@{ type = "command"; command = "$exePath on-submit"; async = $true }) })
    Notification = @(@{ matcher = ""; hooks = @(@{ type = "command"; command = "$exePath notify notification" }) })
    Stop = @(@{ matcher = ""; hooks = @(@{ type = "command"; command = "$exePath notify stop" }) })
    SessionEnd = @(@{ matcher = ""; hooks = @(@{ type = "command"; command = "$exePath on-end" }) })
}
if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{})
}
foreach ($event in $hooks.Keys) {
    $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue $hooks[$event] -Force
}
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Host "Updated $settingsPath"
