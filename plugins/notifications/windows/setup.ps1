# notifications — Windows setup (run by the /notifications:setup skill)
#
#   pwsh -NoProfile -File setup.ps1 -Data <CLAUDE_PLUGIN_DATA>             build, stage, register
#   pwsh -NoProfile -File setup.ps1 -Data <CLAUDE_PLUGIN_DATA> -Uninstall  unregister, unstage
#
# What it does (install):
#   1. cargo build --release, into <Data>\build so nothing lands in the per-version plugin root.
#   2. Stage notifications.exe in <Data> (stable across plugin updates — the registry below points
#      at it). Seed <Data>\config.json from config.json.example and copy the webhook templates if
#      they aren't there yet; <Data>\icons\ is where icons go (config paths are relative to <Data>,
#      because the exe locates config.json by walking up from its own directory).
#   3. Register the claude-focus:// and claude-editor:// protocol handlers (HKCU) at the staged exe —
#      the toast's "Focus Terminal" / "Open in Editor" buttons go through them.
#   4. Register the AUMID (HKLM, needs elevation → UAC prompt) with the display name + icon from
#      config. Declining still works — just no icon on toasts.
#
# It never touches ~/.claude/settings.json: the hooks come from the plugin's hooks.json (and go
# away with `/plugin uninstall`). This replaces the old `notifications.exe install` step.

param(
    [Parameter(Mandatory = $true)][string]$Data,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$srcDir = $PSScriptRoot                       # <plugin root>/windows
$exe = Join-Path $Data "notifications.exe"
$aumid = "ClaudeCode.Hooks"

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated([string]$cmd, [string]$skippedMsg) {
    if (Test-Admin) { Invoke-Expression $cmd; return $true }
    try { Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -Command $cmd" -Wait; return $true }
    catch { Write-Host $skippedMsg; return $false }
}

if ($Uninstall) {
    # The focus watcher (on-submit) may be running — stop it before touching the exe.
    Get-Process -Name "notifications" -ErrorAction SilentlyContinue | Stop-Process -Force

    foreach ($proto in @("claude-focus", "claude-editor")) {
        $key = "HKCU:\Software\Classes\$proto"
        if (Test-Path $key) { Remove-Item $key -Recurse -Force; Write-Host "Unregistered ${proto}://" }
    }
    $hkcuKey = "HKCU:\Software\Classes\AppUserModelId\$aumid"
    if (Test-Path $hkcuKey) { Remove-Item $hkcuKey -Force }
    $hklmKey = "HKLM:\Software\Classes\AppUserModelId\$aumid"
    Invoke-Elevated "if (Test-Path '$hklmKey') { Remove-Item '$hklmKey' -Force }" `
        "Skipped HKLM removal (admin declined). Remove manually: HKLM\Software\Classes\AppUserModelId\$aumid" | Out-Null

    # Per-session state files the hooks leave in %TEMP%.
    Get-ChildItem $env:TEMP -Filter "claude-*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^claude-(timer|watcher|focus-trigger)-' } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if (Test-Path $exe) { Remove-Item $exe -Force; Write-Host "Removed $exe" }
    Write-Host "Done. Config and icons in $Data are kept; run /plugin uninstall notifications@cc-plugins to remove the hooks (and the data dir)."
    exit 0
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "cargo not found — install Rust from https://rustup.rs/ and re-run."
    exit 1
}

# 1. Build
Write-Host "Building notifications..."
$target = Join-Path $Data "build\notifications"
cargo build --release --manifest-path (Join-Path $srcDir "Cargo.toml") --target-dir $target 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed."; exit 1 }

# 2. Stage
New-Item -ItemType Directory -Force -Path $Data, (Join-Path $Data "icons") | Out-Null
Get-Process -Name "notifications" -ErrorAction SilentlyContinue | Stop-Process -Force  # a live watcher locks the exe
Copy-Item (Join-Path $target "release\notifications.exe") $exe -Force
Write-Host "Staged $exe"

$configPath = Join-Path $Data "config.json"
if (-not (Test-Path $configPath)) {
    Copy-Item (Join-Path $srcDir "config.json.example") $configPath
    Write-Host "Created $configPath from the example — edit it to set title/editor/webhook"
}
foreach ($tpl in Get-ChildItem $srcDir -Filter "webhook.*.json.example") {
    $dst = Join-Path $Data $tpl.Name
    if (-not (Test-Path $dst)) { Copy-Item $tpl.FullName $dst }
}

# 3. Protocol handlers (HKCU, no elevation needed) → the staged exe
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
    Write-Host "Registered $($proto.name):// → $exe"
}

# 4. AUMID (HKLM, needs elevation for icon support)
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$title = if ($config -and $config.title) { $config.title } else { "CC Notification" }
$iconFile = if ($config -and $config.icons -and $config.icons.title) { $config.icons.title } else { "icons\title.ico" }
$iconPath = Join-Path $Data $iconFile
$aumidKey = "HKLM:\Software\Classes\AppUserModelId\$aumid"
$regCmd = "New-Item -Path '$aumidKey' -Force | Out-Null; " +
    "New-ItemProperty -Path '$aumidKey' -Name 'DisplayName' -Value '$title' -PropertyType ExpandString -Force | Out-Null; " +
    "New-ItemProperty -Path '$aumidKey' -Name 'IconUri' -Value '$iconPath' -PropertyType ExpandString -Force | Out-Null"
if (Invoke-Elevated $regCmd "Registered AUMID without icon (admin declined). Re-run as admin to add the icon.") {
    Write-Host "Registered AUMID: $aumid ($title) [HKLM]"
} else {
    $fallbackKey = "HKCU:\Software\Classes\AppUserModelId\$aumid"
    New-Item -Path $fallbackKey -Force | Out-Null
    New-ItemProperty -Path $fallbackKey -Name "DisplayName" -Value $title -PropertyType ExpandString -Force | Out-Null
}
if (-not (Test-Path $iconPath)) { Write-Host "Note: no icon at $iconPath — drop one there (see config icons.title) for a titled toast." }

Write-Host "Done! Restart Claude Code to activate (the hooks are already registered by the plugin)."
