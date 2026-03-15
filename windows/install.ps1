# Claude Code Hooks — Windows Install Script
# Points settings.json hooks at this repo and registers protocol handlers.

$repo = $PSScriptRoot
$hooksDir = Join-Path $repo "hooks"
$claude = Join-Path $env:USERPROFILE ".claude"

# Register protocol handlers
& pwsh -NoProfile -File "$hooksDir\register-protocol.ps1"

# Update settings.json (preserves existing settings)
$settingsPath = "$claude\settings.json"
$settings = if (Test-Path $settingsPath) {
    Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    [PSCustomObject]@{}
}

$hd = $hooksDir -replace '\\', '/'
$hooks = @{
    UserPromptSubmit = @(@{
        matcher = ""
        hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File $hd/on-submit.ps1" })
    })
    Notification = @(@{
        matcher = ""
        hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File $hd/notify.ps1 -HookEvent notification" })
    })
    Stop = @(@{
        matcher = ""
        hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File $hd/notify.ps1 -HookEvent stop" })
    })
    SessionEnd = @(@{
        matcher = ""
        hooks = @(@{ type = "command"; command = "pwsh -NoProfile -File $hd/on-end.ps1" })
    })
}

# Merge — only replace matching hook events, preserve others
if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([PSCustomObject]@{})
}
foreach ($event in $hooks.Keys) {
    $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue $hooks[$event] -Force
}

$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Host "Updated $settingsPath"

Write-Host ""
Write-Host "Done! Replace hooks/icon.png with your preferred notification icon."
