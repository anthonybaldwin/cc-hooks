$json = [Console]::In.ReadToEnd() | ConvertFrom-Json
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$cwd = (Get-Location).Path

# Find WindowsTerminal PID and Claude process PID
$p = Get-Process -Id $PID
$wtPid = 0
$claudePid = 0
while ($p) {
    try {
        $parent = $p.Parent
        if ($parent -and $parent.ProcessName -eq 'claude') { $claudePid = $parent.Id }
        if ($parent -and $parent.ProcessName -eq 'WindowsTerminal') {
            $wtPid = $parent.Id
            break
        }
        $p = $parent
    } catch { break }
}

# Find our tab's RuntimeId (unique, survives reordering)
$tabRuntimeId = ""
if ($wtPid -gt 0) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $procCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $wtPid
        )
        $allWindows = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
            [System.Windows.Automation.TreeScope]::Children, $procCond
        )
        $tabCond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        for ($w = 0; $w -lt $allWindows.Count; $w++) {
            $tabs = $allWindows[$w].FindAll(
                [System.Windows.Automation.TreeScope]::Descendants, $tabCond
            )
            for ($i = 0; $i -lt $tabs.Count; $i++) {
                try {
                    $sel = $tabs[$i].GetCurrentPattern(
                        [System.Windows.Automation.SelectionItemPattern]::Pattern
                    )
                    if ($sel.Current.IsSelected) {
                        $tabRuntimeId = $tabs[$i].GetRuntimeId() -join ","
                        break
                    }
                } catch {}
            }
            if ($tabRuntimeId) { break }
        }
    } catch {}
}

$sid = $json.session_id
[IO.File]::WriteAllText((Join-Path $env:TEMP "claude-timer-$sid.txt"), "$ts|$wtPid|$cwd|$tabRuntimeId")

# Skip watcher when not in Windows Terminal (IDE sessions handle their own focus)
if ($wtPid -eq 0) { exit }

# Kill any existing watcher for this session (match by session ID in command line)
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match "focus-terminal" -and $_.CommandLine -match $sid } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# Spawn focus watcher via WMI + VBS (truly detached)
$hooksDir = $PSScriptRoot
$script = (Join-Path $hooksDir "focus-terminal.ps1") -replace '\\', '\\'
$vbs = (Join-Path $hooksDir "launch-hidden.vbs") -replace '\\', '\\'
try {
    $cmd = "pwsh.exe -NoProfile -WindowStyle Hidden -File `"$script`" -sessionId `"$sid`" -wtPid $wtPid -claudePid $claudePid -tabRuntimeId `"$tabRuntimeId`""
    ([wmiclass]"Win32_Process").Create("wscript.exe `"$vbs`" `"$cmd`"") | Out-Null
} catch {}
