# session-color — Windows setup (run by the /session-color:setup skill)
#
#   pwsh -NoProfile -File setup.ps1 -Data <CLAUDE_PLUGIN_DATA>             build + stage the exe
#   pwsh -NoProfile -File setup.ps1 -Data <CLAUDE_PLUGIN_DATA> -Uninstall  remove it, reset the tint
#
# Builds session-color.exe with cargo and copies it into the plugin's persistent data directory.
# The hook dispatcher (hooks/session-color.sh) runs the exe from THERE, not from the plugin root:
# the root is a per-version cache path that moves on every plugin update, the data dir is stable
# across updates. This script never touches ~/.claude/settings.json — the hooks come from the
# plugin's hooks.json, so there is nothing to register (and `/plugin uninstall` removes them).

param(
    [Parameter(Mandatory = $true)][string]$Data,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$srcDir = $PSScriptRoot                      # <plugin root>/windows
$exe = Join-Path $Data "session-color.exe"

if ($Uninstall) {
    if (Test-Path $exe) { Remove-Item $exe -Force; Write-Host "Removed $exe" }
    else { Write-Host "Nothing staged at $exe" }
    # Reset the background of the current terminal, if any.
    Write-Host -NoNewline "`e]111`a"
    Write-Host "Done. Run /plugin uninstall session-color@cc-plugins to remove the hooks themselves."
    exit 0
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Host "cargo not found — install Rust from https://rustup.rs/ and re-run."
    exit 1
}

Write-Host "Building session-color..."
# Build into the data dir too, so no artifacts land in the (read-mostly, per-version) plugin root.
$target = Join-Path $Data "build\session-color"
cargo build --release --manifest-path (Join-Path $srcDir "Cargo.toml") --target-dir $target 2>&1 | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed."; exit 1 }

New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $target "release\session-color.exe") $exe -Force
Write-Host "Staged $exe"
Write-Host "Done! Restart Claude Code to activate (the hooks are already registered by the plugin)."
