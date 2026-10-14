<#
.SYNOPSIS
    Tiny local service the dashboard page talks to for things a web page
    cannot do itself: listing the monitors and moving the kiosk window to
    one of them.

.DESCRIPTION
    Started hidden by start-dashboard.ps1 (one instance; exits if the port
    is already taken). Listens on http://localhost:27422/ and answers:

      GET  /monitors            the monitors, which one shows the dashboard
      POST /move?monitor=<n>    reopen the dashboard on monitor n (1-based,
                                as /monitors lists them) and remember it
      GET  /layouts             the saved layouts (name, screen, date)
      GET  /layouts/<name>      one saved layout
      POST /layouts/<name>      save the request body (JSON) under that name
      POST /layouts/<name>/delete

    The chosen monitor is written to %LOCALAPPDATA%\MinecraftHUD\monitor.txt
    (by device name) and start-dashboard.ps1 uses it from then on. Layouts
    are files in dashboard\layouts\<name>.json.
#>
[CmdletBinding()]
param([int]$Port = 27422)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$launcher = Join-Path $PSScriptRoot 'start-dashboard.ps1'
$layoutDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'dashboard\layouts'
$marker = 'minecraft-hud-dashboard'

# Layout names become file names: letters, digits, space, - _ . ( ) only.
function Get-LayoutPath([string]$name) {
    $name = [System.Uri]::UnescapeDataString($name).Trim()
    if ($name -notmatch '^[\w .()\-]{1,60}$' -or $name -match '^\.+$') { throw "layout name must be 1-60 letters, digits, spaces, - _ . ( )" }
    Join-Path $layoutDir "$name.json"
}
function Get-Layouts {
    if (-not (Test-Path $layoutDir)) { return @() }
    Get-ChildItem $layoutDir -Filter *.json | Sort-Object LastWriteTime -Descending | ForEach-Object {
        $info = [ordered]@{ name = $_.BaseName; savedAt = $_.LastWriteTime.ToString('s') }
        try {
            $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
            if ($j.screen) { $info.screen = $j.screen }
            if ($j.layout -and $j.layout.grid) { $info.grid = $j.layout.grid; $info.panels = @($j.layout.panels).Count }
        } catch {}
        $info
    }
}

function Get-Monitors {
    $screens = @([System.Windows.Forms.Screen]::AllScreens)
    # Which monitor the kiosk window is on, from its main window position.
    $current = $null
    $proc = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -match '^(msedge|chrome)\.exe$' -and $_.CommandLine -like "*$marker*" -and $_.CommandLine -like '*--kiosk*' } |
        Select-Object -First 1
    if ($proc) {
        $p = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
        if ($p -and $p.MainWindowHandle -ne 0) { $current = [System.Windows.Forms.Screen]::FromHandle($p.MainWindowHandle).DeviceName }
    }
    $i = 0
    $screens | ForEach-Object {
        $i++
        $b = $_.Bounds
        [ordered]@{
            index = $i; name = $_.DeviceName; width = $b.Width; height = $b.Height; x = $b.X; y = $b.Y
            primary = [bool]$_.Primary
            edge = [bool]($b.Width * 10 -ge $b.Height * 30)
            current = ($_.DeviceName -eq $current)
        }
    }
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() } catch { Write-Host "Port $Port is busy (another dashboard-control running?)."; return }
Write-Host "dashboard-control listening on http://localhost:$Port/"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request; $res = $ctx.Response
    $res.Headers.Add('Access-Control-Allow-Origin', '*')       # the page is opened from file://
    $res.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $res.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
    $res.Headers.Add('Cache-Control', 'no-store')
    $status = 200; $body = $null; $after = $null
    try {
        switch -Regex ("$($req.HttpMethod) $($req.Url.AbsolutePath)") {
            '^OPTIONS ' { $body = '' }
            '^GET /monitors$' {
                $body = @{ monitors = @(Get-Monitors) } | ConvertTo-Json -Depth 4
            }
            '^GET /layouts$' {
                $body = @{ layouts = @(Get-Layouts); dir = $layoutDir } | ConvertTo-Json -Depth 5
            }
            '^GET /layouts/[^/]+$' {
                $path = Get-LayoutPath ($req.Url.AbsolutePath -replace '^/layouts/', '')
                if (-not (Test-Path $path)) { throw "no such layout" }
                $body = Get-Content $path -Raw
            }
            '^POST /layouts/[^/]+$' {
                $path = Get-LayoutPath ($req.Url.AbsolutePath -replace '^/layouts/', '')
                $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                $text = $reader.ReadToEnd(); $reader.Close()
                $null = $text | ConvertFrom-Json          # must be JSON
                New-Item -ItemType Directory -Force $layoutDir | Out-Null
                [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
                $body = @{ ok = $true; name = [System.IO.Path]::GetFileNameWithoutExtension($path) } | ConvertTo-Json
            }
            '^POST /layouts/[^/]+/delete$' {
                $path = Get-LayoutPath ($req.Url.AbsolutePath -replace '^/layouts/(.+)/delete$', '$1')
                if (Test-Path $path) { Remove-Item $path -Force }
                $body = @{ ok = $true } | ConvertTo-Json
            }
            '^POST /move$' {
                $n = [int]$req.QueryString['monitor']
                $screens = @([System.Windows.Forms.Screen]::AllScreens)
                if ($n -lt 1 -or $n -gt $screens.Count) { throw "monitor must be 1..$($screens.Count)" }
                $body = @{ ok = $true; monitor = $n; name = $screens[$n - 1].DeviceName } | ConvertTo-Json
                # Answer first, then reopen the browser (the page is about to close).
                $after = { & $launcher -Restart -Monitor $n -Remember }.GetNewClosure()
            }
            default { $status = 404; $body = @{ error = 'not found' } | ConvertTo-Json }
        }
    } catch {
        $status = 400; $body = @{ error = "$_" } | ConvertTo-Json
    }
    $res.StatusCode = $status
    $res.ContentType = 'application/json'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$body)
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.Close()
    if ($after) { Start-Sleep -Milliseconds 300; try { & $after } catch { Write-Host "move failed: $_" } }
}
