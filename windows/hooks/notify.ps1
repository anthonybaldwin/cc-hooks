param([string]$HookEvent)

$json = [Console]::In.ReadToEnd() | ConvertFrom-Json
$config = Get-Content (Join-Path $PSScriptRoot "..\config.json") -Raw | ConvertFrom-Json
$dir = Split-Path -Leaf (Get-Location).Path

# Message and icon from config (with defaults)
$Message = if ($config.messages.$HookEvent) { $config.messages.$HookEvent } else { $HookEvent }
$iconFile = if ($config.icons.$HookEvent) { $config.icons.$HookEvent } else { "icon.png" }
$imgPath = Join-Path $PSScriptRoot $iconFile
$img = if (Test-Path $imgPath) { $imgPath } else { $null }

$f = Join-Path $env:TEMP "claude-timer-$($json.session_id).txt"

$elapsed = ""
$cwd = (Get-Location).Path
$wtPid = 0
if (Test-Path $f) {
    $parts = (Get-Content $f).Split("|", 4)
    $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$parts[0]
    $wtPid = [int]$parts[1]
    $cwd = $parts[2]
    # Skip notifications when running inside an IDE (Zed, VS Code, etc.)
    if ($wtPid -eq 0) { exit }
    $s = [math]::Floor($ms / 1000)
    if ($s -lt 1)    { $elapsed = "(<1s)" }
    elseif ($s -lt 60)   { $elapsed = "({0}s)" -f $s }
    elseif ($s -lt 3600) { $elapsed = "({0}m {1}s)" -f [math]::Floor($s/60), ($s%60) }
    else                 { $elapsed = "({0}h {1}m)" -f [math]::Floor($s/3600), ([math]::Floor($s/60)%60) }
}

Import-Module BurntToast

$sid = $json.session_id

$text1 = New-BTText -Text $dir
$text2 = New-BTText -Text "$Message $elapsed"
$appLogo = if ($img) { New-BTImage -Source $img -AppLogoOverride } else { $null }
$bindingParams = @{ Children = $text1, $text2 }
if ($appLogo) { $bindingParams.AppLogo = $appLogo }
$binding = New-BTBinding @bindingParams
$visual = New-BTVisual -BindingGeneric $binding

# Buttons
$buttons = @()
$buttons += New-BTButton -Content "Focus Terminal" -Arguments "claude-focus://$sid" -ActivationType Protocol
if ($config.editor) {
    $editorUri = "claude-editor://" + ($cwd -replace "\\", "/")
    $editorLabel = "Open in " + (Get-Culture).TextInfo.ToTitleCase($config.editor)
    $buttons += New-BTButton -Content $editorLabel -Arguments $editorUri -ActivationType Protocol
}
$actions = New-BTAction -Buttons $buttons

$content = New-BTContent -Visual $visual -Actions $actions
$content.Launch = "claude-focus://$sid"
$content.ActivationType = [Microsoft.Toolkit.Uwp.Notifications.ToastActivationType]::Protocol

Submit-BTNotification -Content $content -UniqueIdentifier $sid
