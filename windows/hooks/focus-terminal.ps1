param([string]$sessionId, [int]$wtPid, [int]$claudePid, [string]$tabRuntimeId)

$triggerFile = Join-Path $env:TEMP "claude-focus-trigger-$sessionId"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -MemberDefinition @'
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -Name Win32 -Namespace Focus

$lastFocus = 0
while ($true) {
    # Exit if WT or Claude session is gone
    if (-not (Get-Process -Id $wtPid -ErrorAction SilentlyContinue)) { exit }
    if ($claudePid -and -not (Get-Process -Id $claudePid -ErrorAction SilentlyContinue)) { exit }

    if (Test-Path $triggerFile) {
        Remove-Item $triggerFile -Force -ErrorAction SilentlyContinue
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if (($now - $lastFocus) -lt 2000) { continue }
        $lastFocus = $now
        try {
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
            $done = $false
            for ($w = 0; $w -lt $allWindows.Count -and -not $done; $w++) {
                $tabs = $allWindows[$w].FindAll(
                    [System.Windows.Automation.TreeScope]::Descendants, $tabCond
                )
                for ($i = 0; $i -lt $tabs.Count; $i++) {
                    $rid = $tabs[$i].GetRuntimeId() -join ","
                    if (($tabRuntimeId -and $rid -eq $tabRuntimeId) -or
                        (-not $tabRuntimeId -and $tabs[$i].Current.Name -match 'Claude Code')) {
                        $hwnd = [IntPtr]$allWindows[$w].Current.NativeWindowHandle
                        [Focus.Win32]::ShowWindow($hwnd, 9)
                        [Focus.Win32]::SetForegroundWindow($hwnd)
                        $pattern = $tabs[$i].GetCurrentPattern(
                            [System.Windows.Automation.SelectionItemPattern]::Pattern
                        )
                        $pattern.Select()
                        $done = $true
                        break
                    }
                }
            }
        } catch {}
    }
    Start-Sleep -Milliseconds 200
}
