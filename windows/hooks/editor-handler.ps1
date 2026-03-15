param([string]$uri)
$config = Get-Content (Join-Path $PSScriptRoot "..\config.json") -Raw | ConvertFrom-Json
$path = ($uri -replace 'claude-editor://', '').TrimEnd('/')
$path = $path -replace '/', '\'
if ($path -and (Test-Path $path) -and $config.editor) { & $config.editor $path }
