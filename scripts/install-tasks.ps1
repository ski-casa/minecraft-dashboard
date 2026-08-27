<#
.SYNOPSIS
    Registers (or removes) the focus guard as a hidden at-logon scheduled task
    for the current user, and starts it immediately.

.EXAMPLE
    .\install-tasks.ps1            # install + start
    .\install-tasks.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$taskName = 'MinecraftHUD-FocusGuard'

if ($Uninstall) {
    Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task $taskName"
    }
    return
}

$guardScript = Join-Path $PSScriptRoot 'focus-guard.ps1'
if (-not (Test-Path $guardScript)) {
    throw "focus-guard.ps1 not found next to this script."
}

$shell = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $shell) {
    $shell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
}

$action = New-ScheduledTaskAction -Execute $shell `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$guardScript`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Registered scheduled task $taskName (runs hidden at logon)."

Start-ScheduledTask -TaskName $taskName
Write-Host "Focus guard started."
