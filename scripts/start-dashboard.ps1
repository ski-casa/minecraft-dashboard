<#
.SYNOPSIS
    Opens the Minecraft HUD dashboard as a fullscreen kiosk browser window on
    the Xeneon Edge (the 32:9 monitor).

.DESCRIPTION
    Uses Microsoft Edge (or Chrome) with its own profile so it never merges
    into your normal browser windows, pinned to the ultra-wide monitor, with
    pinch-zoom and swipe-navigation disabled so touches only reach the widgets.
    Idempotent: does nothing if the dashboard is already open.

.EXAMPLE
    .\start-dashboard.ps1            # open (or leave running)
    .\start-dashboard.ps1 -Restart   # close and reopen
    .\start-dashboard.ps1 -Stop
#>
[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$Stop,
    [string]$Browser
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$page = Join-Path $root 'dashboard\index.html'
$url = ([System.Uri]$page).AbsoluteUri
$marker = 'minecraft-hud-dashboard'
$profileDir = Join-Path $env:LOCALAPPDATA "MinecraftHUD\$marker"

$existing = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -match '^(msedge|chrome)\.exe$' -and $_.CommandLine -like "*$marker*" }
if ($existing) {
    if ($Restart -or $Stop) {
        $existing | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
        Write-Host "Closed dashboard."
        if ($Stop) { return }
    } else {
        Write-Host "Dashboard already running."
        return
    }
} elseif ($Stop) {
    Write-Host "Dashboard not running."
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

Add-Type -AssemblyName System.Windows.Forms
$edge = [System.Windows.Forms.Screen]::AllScreens |
    Where-Object { $_.Bounds.Width * 10 -ge $_.Bounds.Height * 30 } |
    Select-Object -First 1
if (-not $edge) {
    throw "No 32:9 monitor found. Is the Xeneon Edge connected and 'Show iCUE Widgets' turned off so it acts as a normal display?"
}
$b = $edge.Bounds
Write-Host "Xeneon Edge: $($edge.DeviceName) $($b.Width)x$($b.Height) at ($($b.X),$($b.Y))"

$arguments = @(
    "--user-data-dir=`"$profileDir`"",
    '--no-first-run',
    '--inprivate',        # Edge: no sign-in/sync/extensions/first-run pages
    '--incognito',        # same for Chrome (unknown flags are ignored)
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
