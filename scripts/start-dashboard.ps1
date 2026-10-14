<#
.SYNOPSIS
    Opens the Minecraft HUD dashboard as a fullscreen kiosk browser window on
    the Xeneon Edge (the 32:9 monitor), or on any monitor you name.

.DESCRIPTION
    Uses Microsoft Edge (or Chrome) with its own profile so it never merges
    into your normal browser windows (the profile also keeps the layout you
    arrange on screen), pinned to one monitor, with pinch-zoom and
    swipe-navigation disabled so touches only reach the widgets.
    Idempotent: does nothing if the dashboard is already open.

    Without -Monitor, the monitor remembered with -Remember (or chosen on
    the dashboard's own Screen menu) is used if it is connected; otherwise
    the 32:9 monitor (the Edge); if there is none, the last monitor that is
    not the primary one, or the primary one when that is all there is.

    Also starts dashboard-control.ps1 (hidden) so the page can list the
    monitors and move itself; -Stop stops it too.

.EXAMPLE
    .\start-dashboard.ps1            # open (or leave running)
    .\start-dashboard.ps1 -Restart   # close and reopen
    .\start-dashboard.ps1 -Stop
    .\start-dashboard.ps1 -Monitor 2 # second monitor as listed by -ListMonitors
    .\start-dashboard.ps1 -Monitor 2 -Remember   # ...and from now on
    .\start-dashboard.ps1 -ListMonitors
#>
[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$Stop,
    [string]$Browser,
    [int]$Monitor = 0,
    [switch]$Remember,
    [switch]$ListMonitors
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$screens = @([System.Windows.Forms.Screen]::AllScreens)
if ($ListMonitors) {
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $s = $screens[$i]; $b = $s.Bounds
        $tags = @()
        if ($s.Primary) { $tags += 'primary' }
        if ($b.Width * 10 -ge $b.Height * 30) { $tags += '32:9 (Xeneon Edge)' }
        Write-Host ("{0}: {1} {2}x{3} at ({4},{5}) {6}" -f ($i + 1), $s.DeviceName, $b.Width, $b.Height, $b.X, $b.Y, ($tags -join ', '))
    }
    return
}
$root = Split-Path $PSScriptRoot -Parent
$page = Join-Path $root 'dashboard\index.html'
$url = ([System.Uri]$page).AbsoluteUri
$marker = 'minecraft-hud-dashboard'
$profileDir = Join-Path $env:LOCALAPPDATA "MinecraftHUD\$marker"
$monitorFile = Join-Path $env:LOCALAPPDATA 'MinecraftHUD\monitor.txt'
$control = Join-Path $PSScriptRoot 'dashboard-control.ps1'

$processes = Get-CimInstance Win32_Process
$existing = $processes | Where-Object { $_.Name -match '^(msedge|chrome)\.exe$' -and $_.CommandLine -like "*$marker*" }
$controlProc = $processes | Where-Object { $_.CommandLine -like '*dashboard-control.ps1*' }
if ($existing) {
    if ($Restart -or $Stop) {
        $existing | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
        Write-Host "Closed dashboard."
    } else {
        Write-Host "Dashboard already running."
        return
    }
} elseif ($Stop) {
    Write-Host "Dashboard not running."
}
if ($Stop) {
    $controlProc | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    return
}

if (-not $Browser) {
    $Browser = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Browser) { throw "No Chromium browser found (Edge or Chrome)." }

$target = $null
if ($Monitor -gt 0) {
    if ($Monitor -gt $screens.Count) { throw "Monitor $Monitor does not exist; -ListMonitors shows $($screens.Count)." }
    $target = $screens[$Monitor - 1]
    $label = "Monitor $Monitor"
    if ($Remember) {
        New-Item -ItemType Directory -Force (Split-Path $monitorFile) | Out-Null
        Set-Content -Path $monitorFile -Value $target.DeviceName
        Write-Host "Remembered $($target.DeviceName) for next time."
    }
} elseif (Test-Path $monitorFile) {
    $wanted = (Get-Content $monitorFile -First 1).Trim()
    $target = $screens | Where-Object { $_.DeviceName -eq $wanted } | Select-Object -First 1
    if ($target) { $label = 'Remembered monitor' }
    else { Write-Warning "Remembered monitor $wanted is not connected; picking one automatically." }
}
if (-not $target) {
    $target = $screens | Where-Object { $_.Bounds.Width * 10 -ge $_.Bounds.Height * 30 } | Select-Object -First 1
    $label = 'Xeneon Edge'
    if (-not $target) {
        $target = @($screens | Where-Object { -not $_.Primary } | Select-Object -Last 1)[0]
        if ($target) { $label = 'Secondary monitor' }
        else { $target = $screens | Where-Object { $_.Primary } | Select-Object -First 1; $label = 'Primary monitor' }
        Write-Warning "No 32:9 monitor found (is the Xeneon Edge connected with 'Show iCUE Widgets' off?). Using the $($label.ToLower()); pick one with -Monitor <n> (see -ListMonitors)."
    }
}
$b = $target.Bounds
Write-Host "$label`: $($target.DeviceName) $($b.Width)x$($b.Height) at ($($b.X),$($b.Y))"

# Not --inprivate/--incognito: the dashboard keeps the layout arranged on
# screen in this profile's localStorage, which a private window would discard.
$arguments = @(
    "--user-data-dir=`"$profileDir`"",
    '--no-first-run',
    '--edge-kiosk-type=fullscreen',
    '--no-default-browser-check',
    '--disable-session-crashed-bubble',
    '--disable-pinch',
    '--overscroll-history-navigation=0',
    "--window-position=$($b.X),$($b.Y)",
    "--window-size=$($b.Width),$($b.Height)",
    '--kiosk',
    "`"$url`""
)
Start-Process -FilePath $Browser -ArgumentList $arguments
Write-Host "Dashboard opened with $(Split-Path $Browser -Leaf)."

# The control service lets the page list monitors and move itself (Screen menu).
if (-not $controlProc) {
    $shell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    Start-Process -FilePath $shell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$control`"")
    Write-Host "Started dashboard-control (http://localhost:27422/)."
}
