# CC Hooks — Windows Install
#
# Run: pwsh -NoProfile -File install.ps1                # install all hooks
#      pwsh -NoProfile -File install.ps1 notifications  # install a specific hook
#      pwsh -NoProfile -File install.ps1 session-color
#
# The notifications hook triggers a UAC prompt for the HKLM registry write
# (icon + display name). Declining still works — just no icon on toasts.

param([string]$target = "all")

$winDir = $PSScriptRoot

function Install-Notifications {
    $notifDir = Join-Path $winDir "notifications"
    $exe = Join-Path $notifDir "target\release\notifications.exe"

    # Build
    Write-Host "Building notifications..."
    cargo build --release --manifest-path (Join-Path $notifDir "Cargo.toml") 2>&1 | Select-Object -Last 3

    # Copy config if it doesn't exist
    $configPath = Join-Path $notifDir "config.json"
    if (-not (Test-Path $configPath)) {
        Copy-Item (Join-Path $notifDir "config.json.example") $configPath
        Write-Host "Created config.json from example — edit to configure title/editor"
    }

    # Protocol handlers (HKCU, no elevation needed)
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

    # AUMID registry (HKLM, needs elevation for icon support)
    $config = if (Test-Path $configPath) { Get-Content $configPath -Raw | ConvertFrom-Json } else { $null }
    $title = if ($config -and $config.title) { $config.title } else { "CC Notification" }
    $iconFile = if ($config -and $config.icons -and $config.icons.title) { $config.icons.title } else { "icons\title.ico" }
    $iconPath = Join-Path $notifDir $iconFile
    if (-not (Test-Path $iconPath)) { $iconPath = Join-Path $notifDir "icons\title.ico" }

    $aumidKey = "HKLM:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
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
            $fallbackKey = "HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Hooks"
            New-Item -Path $fallbackKey -Force | Out-Null
            New-ItemProperty -Path $fallbackKey -Name "DisplayName" -Value $title -PropertyType ExpandString -Force | Out-Null
            Write-Host "Registered AUMID without icon (admin declined). To add icon, run as admin:"
            Write-Host "  pwsh -NoProfile -File $($MyInvocation.MyCommand.Path)"
        }
    }

    # Hook config
    & $exe install
}

function Install-SessionColor {
    $scDir = Join-Path $winDir "session-color"
    $exe = Join-Path $scDir "target\release\session-color.exe"

    Write-Host "Building session-color..."
    cargo build --release --manifest-path (Join-Path $scDir "Cargo.toml") 2>&1 | Select-Object -Last 3

    # Additive merge — preserves notifications hooks on shared events.
    & $exe install
}

switch ($target) {
    # Notifications first, then session-color: session-color merges additively
    # onto the shared events (UserPromptSubmit/Stop/SessionEnd) last.
    "all"           { Install-Notifications; Install-SessionColor }
    "notifications" { Install-Notifications }
    "session-color" { Install-SessionColor }
    default { Write-Host "Unknown hook: $target (expected: notifications, session-color)"; exit 1 }
}

Write-Host "Done! Restart Claude Code to activate hooks."
