<#
.SYNOPSIS
    Installs/updates the mods that feed the Xeneon Edge HUD into the vanilla
    launcher's Fabric profile, and applies the Minecraft settings the HUD needs.

.DESCRIPTION
    - Detects the newest installed Fabric profile in %APPDATA%\.minecraft\versions
      (override with -McVersion).
    - Downloads the matching JourneyMap + JourneyMap WebMap (and Borderless Mining
      unless -SkipBorderless) jars from Modrinth into the mods folder, replacing
      any versions this script previously installed.
    - Sets pauseOnLostFocus:false in options.txt so solo play keeps running when
      the touchscreen briefly takes focus.
    - Pins the JourneyMap webmap to enabled + the given port if its config file
      exists (it is created on the first game launch with JourneyMap installed —
      re-run this script once after that first launch).

    Re-run this script whenever you update Minecraft/Fabric to a new version.

.EXAMPLE
    .\install-mods.ps1
    .\install-mods.ps1 -McVersion 26.2
#>
[CmdletBinding()]
param(
    [string]$McVersion,
    [string]$MinecraftDir = "$env:APPDATA\.minecraft",
    [switch]$SkipBorderless,
    [int]$WebmapPort = 8080
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ModsDir = Join-Path $MinecraftDir 'mods'
$StateFile = Join-Path $ModsDir 'icuehud-mods.json'

if (-not (Test-Path $MinecraftDir)) {
    throw "Minecraft folder not found at $MinecraftDir. Is the vanilla launcher installed?"
}

# --- 1. Resolve the Minecraft version from the installed Fabric profiles -----
if (-not $McVersion) {
    $fabricProfiles = Get-ChildItem -Path (Join-Path $MinecraftDir 'versions') -Directory -Filter 'fabric-loader-*' -ErrorAction SilentlyContinue
    if (-not $fabricProfiles) {
        throw "No Fabric profile found in $MinecraftDir\versions. Install Fabric from https://fabricmc.net/use/installer/ first, or pass -McVersion."
    }
    # Folder name format: fabric-loader-<loaderVersion>-<gameVersion>.
    # Pick the most recently touched profile (= the one the launcher last used/installed).
    $newest = $fabricProfiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $parts = $newest.Name -split '-'
    if ($parts.Count -lt 4) {
        throw "Could not parse Fabric profile name '$($newest.Name)'. Pass -McVersion explicitly."
    }
    $McVersion = ($parts[3..($parts.Count - 1)] -join '-')
    Write-Host "Detected Fabric profile: $($newest.Name)  ->  Minecraft $McVersion"
} else {
    Write-Host "Using Minecraft version: $McVersion"
}

if (-not (Test-Path $ModsDir)) {
    New-Item -ItemType Directory -Path $ModsDir | Out-Null
}

# --- 2. Warn if the game looks like it's running -----------------------------
$mcRunning = Get-Process -Name javaw, java -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -match 'Minecraft' }
if ($mcRunning) {
    Write-Warning "Minecraft appears to be running. Close it and re-run this script so mod/option changes take effect cleanly."
}

# --- 3. Resolve + download mods from Modrinth --------------------------------
$projects = @(
    @{ Slugs = @('journeymap');         Required = $true;  Label = 'JourneyMap' },
    @{ Slugs = @('journeymap-web-map'); Required = $false; Label = 'JourneyMap WebMap addon' }
)
if (-not $SkipBorderless) {
    # First slug with a build for this MC version wins.
    $projects += @{ Slugs = @('cubes-without-borders', 'borderless-mining'); Required = $false; Label = 'Borderless fullscreen (no minimize on focus loss)' }
}

$previousState = @{}
if (Test-Path $StateFile) {
    try {
        (Get-Content $StateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
            $previousState[$_.Name] = $_.Value
        }
    } catch {
        Write-Warning "Could not read $StateFile; previously installed jars will be matched by name pattern instead."
    }
}

function Get-ModrinthVersion([string]$Slug, [string]$GameVersion) {
    $gv = [uri]::EscapeDataString("[""$GameVersion""]")
    $ld = [uri]::EscapeDataString('["fabric"]')
    $url = "https://api.modrinth.com/v2/project/$Slug/version?game_versions=$gv&loaders=$ld"
    try {
        $versions = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'steve/minecraft-icue-hud (installer script)' }
    } catch {
        return $null
    }
    if (-not $versions) { return $null }
    # API returns newest-first; prefer stable releases over betas/alphas.
    foreach ($type in 'release', 'beta', 'alpha') {
        $match = $versions | Where-Object { $_.version_type -eq $type } | Select-Object -First 1
        if ($match) { return $match }
    }
    return $versions | Select-Object -First 1
}

$newState = @{}
$failures = @()
foreach ($project in $projects) {
    Write-Host "`nResolving $($project.Label) for Minecraft $McVersion (fabric)..."
    $slug = $null
    $version = $null
    foreach ($candidate in $project.Slugs) {
        $version = Get-ModrinthVersion -Slug $candidate -GameVersion $McVersion
        if ($version) { $slug = $candidate; break }
    }
    if (-not $version) {
        $msg = "No Modrinth build of '$($project.Slugs -join "' or '")' found for Minecraft $McVersion (fabric). It may not be updated yet."
        if ($project.Required) { $failures += $msg } else { Write-Warning $msg }
        continue
    }
    $file = $version.files | Where-Object { $_.primary } | Select-Object -First 1
    if (-not $file) { $file = $version.files | Select-Object -First 1 }

    # Remove what we installed before (or obvious strays on first run) so jars never double up.
    if ($previousState.ContainsKey($slug)) {
        $old = Join-Path $ModsDir $previousState[$slug]
        if ((Test-Path $old) -and ($previousState[$slug] -ne $file.filename)) {
            Remove-Item $old -Force
            Write-Host "  removed old $($previousState[$slug])"
        }
    } else {
        Get-ChildItem -Path $ModsDir -Filter "$($slug -replace 'journeymap-web-map','journeymap-webmap')*.jar" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $file.filename } | ForEach-Object {
                Remove-Item $_.FullName -Force
                Write-Host "  removed stray $($_.Name)"
            }
        if ($slug -eq 'journeymap') {
            Get-ChildItem -Path $ModsDir -Filter 'journeymap-*.jar' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch 'webmap' -and $_.Name -ne $file.filename } | ForEach-Object {
                    Remove-Item $_.FullName -Force
                    Write-Host "  removed stray $($_.Name)"
                }
        }
    }

    $dest = Join-Path $ModsDir $file.filename
    if (Test-Path $dest) {
        Write-Host "  up to date: $($file.filename)"
    } else {
        Write-Host "  downloading $($file.filename) ($($version.version_number))..."
        Invoke-WebRequest -Uri $file.url -OutFile $dest -Headers @{ 'User-Agent' = 'steve/minecraft-icue-hud (installer script)' }
        Write-Host "  installed:  $($file.filename)"
    }
    $newState[$slug] = $file.filename
}

if ($failures) {
    throw ($failures -join "`n")
}
$newState | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8

# --- 4. options.txt: keep solo worlds running on focus loss ------------------
$optionsFile = Join-Path $MinecraftDir 'options.txt'
if (Test-Path $optionsFile) {
    $options = Get-Content $optionsFile
    if ($options -match '^pauseOnLostFocus:') {
        $patched = $options -replace '^pauseOnLostFocus:.*$', 'pauseOnLostFocus:false'
    } else {
        $patched = $options + 'pauseOnLostFocus:false'
    }
    if (Compare-Object $options $patched) {
        Set-Content -Path $optionsFile -Value $patched -Encoding UTF8
        Write-Host "`noptions.txt: set pauseOnLostFocus:false"
    } else {
        Write-Host "`noptions.txt: pauseOnLostFocus already false"
    }
} else {
    Write-Warning "options.txt not found (game never launched?). Re-run this script after the first launch."
}

# --- 5. Pin the JourneyMap webmap config if it exists ------------------------
$webmapConfigs = Get-ChildItem -Path (Join-Path $MinecraftDir 'journeymap\config') -Recurse -Filter '*webmap*.config*' -ErrorAction SilentlyContinue
if ($webmapConfigs) {
    foreach ($cfg in $webmapConfigs) {
        $raw = Get-Content $cfg.FullName -Raw
        $patched = $raw `
            -replace '("enabled"\s*:\s*"?)(false|true)', '${1}true' `
            -replace '("port"\s*:\s*"?)\d+', ('${1}' + $WebmapPort)
        if ($patched -ne $raw) {
            Set-Content -Path $cfg.FullName -Value $patched -Encoding UTF8
            Write-Host "Patched $($cfg.FullName): webmap enabled on port $WebmapPort"
        } else {
            Write-Host "Webmap config already enabled on port $WebmapPort ($($cfg.Name))"
        }
    }
} else {
    Write-Host "`nNo JourneyMap webmap config yet - it is created on the first game launch."
    Write-Host "Launch Minecraft once, then re-run this script to pin the webmap to port $WebmapPort."
}

Write-Host "`nDone. Launch Minecraft with the Fabric profile and check http://localhost:$WebmapPort/data/player once you're in a world."
