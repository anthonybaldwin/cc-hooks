$json = [Console]::In.ReadToEnd() | ConvertFrom-Json
$sid = $json.session_id

# Kill the focus watcher (match by session ID in command line)
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match "focus-terminal" -and $_.CommandLine -match $sid } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# Clean up temp files
Remove-Item (Join-Path $env:TEMP "claude-timer-$sid.txt") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $env:TEMP "claude-focus-trigger-$sid") -Force -ErrorAction SilentlyContinue
