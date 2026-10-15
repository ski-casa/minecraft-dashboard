<#
.SYNOPSIS
    Installs/updates the mods that feed the Xeneon Edge HUD into the vanilla
    launcher's Fabric profile, and applies the Minecraft settings the HUD needs.

.DESCRIPTION
    - Detects the newest installed Fabric profile in %APPDATA%\.minecraft\versions
      (override with -McVersion).
    - Downloads the matching JourneyMap + JourneyMap WebMap (and Borderless Fullscreen
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
. (Join-Path $PSScriptRoot 'common.ps1')

$ModsDir = Join-Path $MinecraftDir 'mods'
$StateFile = Join-Path $ModsDir 'icuehud-mods.json'

if (-not (Test-Path $MinecraftDir)) {
    throw "Minecraft folder not found at $MinecraftDir. Is the vanilla launcher installed?"
}

# --- 1. Resolve the Minecraft version from the installed Fabric profiles -----
if (-not $McVersion) {
    $McVersion = Get-InstalledFabricGameVersion $MinecraftDir
    if (-not $McVersion) {
        throw "No Fabric profile found in $MinecraftDir\versions. Run scripts\setup.ps1 (installs Fabric), or pass -McVersion."
    }
    Write-Host "Detected Fabric profile for Minecraft $McVersion"
} else {
    Write-Host "Using Minecraft version: $McVersion"
}

if (-not (Test-Path $ModsDir)) {
    New-Item -ItemType Directory -Path $ModsDir | Out-Null
}

# --- 2. Warn if the game looks like it's running -----------------------------
$gameRunning = Test-MinecraftRunning
if ($gameRunning) {
    Write-Warning "Minecraft is running: it holds its mod jars open, so mods already installed are kept at their current version (new ones are still added). Close the game and re-run to update them."
}

# --- 3. Resolve + download mods from Modrinth --------------------------------
$projects = @(
    @{ Slugs = @('fabric-api');         Required = $true;  Label = 'Fabric API (needed by JourneyMap and the bridge mod)' },
    @{ Slugs = @('journeymap');         Required = $true;  Label = 'JourneyMap' },
    @{ Slugs = @('journeymap-web-map'); Required = $false; Label = 'JourneyMap WebMap addon' }
)
if (-not $SkipBorderless) {
    # First slug with a build for this MC version wins.
    $projects += @{ Slugs = @('borderless-fullscreen', 'cubes-without-borders'); Required = $false; Label = 'Borderless fullscreen (no minimize on focus loss)' }
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

# Deletes a jar; false when it is locked (the game is running), so the caller
# keeps the old version rather than installing a second copy next to it.
function Remove-Jar([string]$Path, [string]$Why) {
    try {
        Remove-Item $Path -Force -ErrorAction Stop
        Write-Host "  removed $Why $(Split-Path $Path -Leaf)"
        return $true
    } catch {
        if ($gameRunning) { Write-Host "  kept $(Split-Path $Path -Leaf) (in use by the running game)" }
        else { Write-Warning "Could not remove $(Split-Path $Path -Leaf): $($_.Exception.Message). Keeping it." }
        return $false
    }
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
    $blocked = $false
    if ($previousState.ContainsKey($slug)) {
        $old = Join-Path $ModsDir $previousState[$slug]
        if ((Test-Path $old) -and ($previousState[$slug] -ne $file.filename)) {
            if (-not (Remove-Jar $old 'old')) { $blocked = $true }
        }
    } else {
        $pattern = switch ($slug) {
            'journeymap-web-map' { 'journeymap-webmap*.jar' }
            'journeymap'         { 'journeymap-*.jar' }
            'fabric-api'         { 'fabric-api-*.jar' }
            default              { "$slug*.jar" }
        }
        Get-ChildItem -Path $ModsDir -Filter $pattern -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne $file.filename -and -not ($slug -eq 'journeymap' -and $_.Name -match 'webmap') } | ForEach-Object {
                if (-not (Remove-Jar $_.FullName 'stray')) { $blocked = $true }
            }
    }
    if ($blocked) {
        $kept = if ($previousState.ContainsKey($slug)) { $previousState[$slug] } else {
            (Get-ChildItem -Path $ModsDir -Filter $pattern | Where-Object { -not ($slug -eq 'journeymap' -and $_.Name -match 'webmap') } | Select-Object -First 1).Name
        }
        if ($kept) { $newState[$slug] = $kept }
        continue
    }

    $dest = Join-Path $ModsDir $file.filename
    if (Test-Path $dest) {
        Write-Host "  up to date: $($file.filename)"
    } else {
        Write-Host "  downloading $($file.filename) ($($version.version_number))..."
        Invoke-WebRequest -Uri $file.url -OutFile $dest -Headers @{ 'User-Agent' = $script:UserAgent }
        Write-Host "  installed:  $($file.filename)"
    }
    $newState[$slug] = $file.filename
    $newState["$slug.version"] = $version.version_number   # setup.ps1 pins the mod build to fabric-api's
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

# --- 6. The repo's own mod (armor + materials widgets), if it has been built --
$builtJar = Get-ChildItem -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'mod\build\libs') -Filter 'icuehud-*.jar' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '-(sources|dev)\.jar$' } | Select-Object -First 1
if ($builtJar) {
    Write-Host ""
    & (Join-Path $PSScriptRoot 'build-mod.ps1') -SkipBuild -MinecraftDir $MinecraftDir
} else {
    Write-Host "`nBridge mod not built yet; run scripts\build-mod.ps1 (or scripts\setup.ps1) for the mod-backed widgets."
}

Write-Host "`nDone. Launch Minecraft with the Fabric profile and check http://localhost:$WebmapPort/data/player once you're in a world."
