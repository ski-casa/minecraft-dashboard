<#
.SYNOPSIS
    Registers (or removes) the HUD background tasks for the current user and
    starts them immediately:
      - MinecraftHUD-FocusGuard : keeps Minecraft in control when the Edge is tapped
      - MinecraftHUD-Dashboard  : opens the kiosk dashboard on the Edge at logon

.EXAMPLE
    .\install-tasks.ps1            # install + start both
    .\install-tasks.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$tasks = @(
    @{ Name = 'MinecraftHUD-FocusGuard'; Script = 'focus-guard.ps1';     Delay = $null },
    @{ Name = 'MinecraftHUD-Dashboard';  Script = 'start-dashboard.ps1'; Delay = 'PT20S' }  # let displays settle after logon
)

if ($Uninstall) {
    foreach ($t in $tasks) {
        if (Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $t.Name -Confirm:$false
            Write-Host "Removed scheduled task $($t.Name)"
        }
    }
    & (Join-Path $PSScriptRoot 'start-dashboard.ps1') -Stop
    return
}

$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $shell) {
    $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

foreach ($t in $tasks) {
    $script = Join-Path $PSScriptRoot $t.Script
    if (-not (Test-Path $script)) { throw "$($t.Script) not found next to this script." }

    $action = New-ScheduledTaskAction -Execute $shell `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    if ($t.Delay) { $trigger.Delay = $t.Delay }
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $t.Name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "Registered scheduled task $($t.Name) (runs hidden at logon)."
    Start-ScheduledTask -TaskName $t.Name
    Write-Host "  started."
}
