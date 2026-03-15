param([string]$uri)
# Just create the trigger file — the watcher (running in WT context) does the rest
$sessionId = ($uri -replace 'claude-focus://', '' -replace '/.*', '')
$triggerFile = Join-Path $env:TEMP "claude-focus-trigger-$sessionId"
New-Item $triggerFile -Force | Out-Null
