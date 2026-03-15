$hooksDir = $PSScriptRoot
$vbs = Join-Path $hooksDir "launch-hidden.vbs"

# Register claude-focus:// protocol
$base = "HKCU:\Software\Classes\claude-focus"
New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name "(Default)" -Value "URL:Claude Focus Protocol"
New-ItemProperty -Path $base -Name "URL Protocol" -Value "" -Force | Out-Null
New-Item -Path "$base\shell\open\command" -Force | Out-Null
$handler = Join-Path $hooksDir "protocol-handler.ps1"
Set-ItemProperty -Path "$base\shell\open\command" -Name "(Default)" -Value "`"wscript.exe`" `"$vbs`" `"pwsh.exe -NoProfile -File `"$handler`" %1`""
Write-Host "Registered claude-focus://"

# Register claude-editor:// protocol
$base = "HKCU:\Software\Classes\claude-editor"
New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name "(Default)" -Value "URL:Claude Editor Protocol"
New-ItemProperty -Path $base -Name "URL Protocol" -Value "" -Force | Out-Null
New-Item -Path "$base\shell\open\command" -Force | Out-Null
$handler = Join-Path $hooksDir "editor-handler.ps1"
Set-ItemProperty -Path "$base\shell\open\command" -Name "(Default)" -Value "`"wscript.exe`" `"$vbs`" `"pwsh.exe -NoProfile -File `"$handler`" %1`""
Write-Host "Registered claude-editor://"
