<#
.SYNOPSIS
    One-shot setup on Windows 11 with Minecraft installed: Fabric, the mods,
    the bridge mod, and the dashboard. Safe to re-run; it only does what is
    missing or out of date.

.DESCRIPTION
    Steps, each skipped when already done:
      1. Picks the Minecraft version: -McVersion, else the newest installed
         Fabric profile, else the latest release Mojang publishes.
      2. Gets a JDK 25 (downloaded into tools\ when none is installed).
      3. Installs the Fabric loader profile for that version with the official
         Fabric installer (it appears in the Minecraft Launcher as "fabric-loader-...").
      4. Installs Fabric API, JourneyMap, JourneyMap WebMap and a borderless
         fullscreen mod from Modrinth (install-mods.ps1), and sets the game
         options the dashboard needs.
      5. Pins mod\ to that Minecraft / loader / Fabric API version and builds
         and installs the bridge mod (build-mod.ps1).
      6. With -Autostart, registers the logon tasks (install-tasks.ps1).
      7. Opens the dashboard (start-dashboard.ps1) unless -NoDashboard.

    JourneyMap writes its webmap config on the first launch, so after the first
    game launch run this script once more: it then pins the webmap to port 8080.

.EXAMPLE
    .\setup.ps1                       # everything, for the newest Fabric profile or latest release
    .\setup.ps1 -McVersion 26.3       # a specific game version
    .\setup.ps1 -Autostart            # also start the dashboard (and focus guard) at logon
#>
[CmdletBinding()]
param(
    [string]$McVersion,
    [string]$MinecraftDir = "$env:APPDATA\.minecraft",
    [switch]$Autostart,
    [switch]$NoDashboard,
    [switch]$SkipModBuild,
    [int]$WebmapPort = 8080
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Split-Path $PSScriptRoot -Parent
$toolsDir = Join-Path $root 'tools'
$modDir = Join-Path $root 'mod'

function Step([string]$text) { Write-Host "`n== $text" -ForegroundColor Cyan }

# --- 0. Minecraft itself ------------------------------------------------------
Step "Checking the Minecraft install"
if (-not (Test-Path $MinecraftDir)) {
    throw "Minecraft folder not found at $MinecraftDir. Install Minecraft (the official launcher, Java Edition), start it once, then re-run. A different folder: -MinecraftDir <path>."
}
if (-not (Test-Path (Join-Path $MinecraftDir 'launcher_profiles.json'))) {
    throw "No launcher_profiles.json in $MinecraftDir. Open the Minecraft Launcher once (it creates the file), then re-run."
}
if (Test-MinecraftRunning) {
    Write-Warning "Minecraft is running. Mod changes apply on the next launch; close the game first if anything fails."
}
Write-Host "Minecraft folder: $MinecraftDir"

# --- 1. Game version ----------------------------------------------------------
Step "Choosing the Minecraft version"
if ($McVersion) {
    Write-Host "Requested: $McVersion"
} else {
    $McVersion = Get-InstalledFabricGameVersion $MinecraftDir
    if ($McVersion) {
        Write-Host "Newest installed Fabric profile is for Minecraft $McVersion"
    } else {
        $manifest = Invoke-RestMethod -Uri 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json' -Headers @{ 'User-Agent' = $script:UserAgent }
        $McVersion = $manifest.latest.release
        Write-Host "No Fabric profile yet; latest Minecraft release is $McVersion"
    }
}
if (-not (Get-ModrinthVersion -Slug 'journeymap' -GameVersion $McVersion)) {
    throw "JourneyMap has no Fabric build for Minecraft $McVersion yet (it usually follows within days). Use an older version with -McVersion <version>, e.g. the previous release."
}

# --- 2. JDK -------------------------------------------------------------------
Step "Java"
$jdk = Get-OrInstallJdk $toolsDir
$java = Join-Path $jdk 'bin\java.exe'
Write-Host "JDK $script:RequiredJava at $jdk"

# --- 3. Fabric loader profile -------------------------------------------------
Step "Fabric loader for Minecraft $McVersion"
$existing = Get-ChildItem -Path (Join-Path $MinecraftDir 'versions') -Directory -Filter "fabric-loader-*-$McVersion" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($existing) {
    Write-Host "Already installed: $($existing.Name)"
} else {
    $installers = Invoke-RestMethod -Uri 'https://meta.fabricmc.net/v2/versions/installer' -Headers @{ 'User-Agent' = $script:UserAgent }
    $installer = $installers | Where-Object { $_.stable } | Select-Object -First 1
    if (-not $installer) { $installer = $installers | Select-Object -First 1 }
    $jar = Join-Path $toolsDir "fabric-installer-$($installer.version).jar"
    if (-not (Test-Path $jar)) {
        New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
        Write-Host "Downloading Fabric installer $($installer.version) ..."
        Invoke-WebRequest -Uri $installer.url -OutFile $jar -Headers @{ 'User-Agent' = $script:UserAgent }
    }
    Write-Host "Installing the Fabric loader profile (this also downloads the vanilla $McVersion files) ..."
    & $java -jar $jar client -dir $MinecraftDir -mcversion $McVersion
    if ($LASTEXITCODE -ne 0) { throw "The Fabric installer failed (exit $LASTEXITCODE). See the output above." }
    $existing = Get-ChildItem -Path (Join-Path $MinecraftDir 'versions') -Directory -Filter "fabric-loader-*-$McVersion" | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $existing) { throw "The Fabric installer finished but no fabric-loader-*-$McVersion profile appeared in $MinecraftDir\versions." }
    Write-Host "Installed: $($existing.Name) (select this profile in the Minecraft Launcher)"
}
$loaderVersion = (($existing.Name -split '-')[2])

# --- 4. Mods from Modrinth + game options --------------------------------------
Step "Mods"
& (Join-Path $PSScriptRoot 'install-mods.ps1') -McVersion $McVersion -MinecraftDir $MinecraftDir -WebmapPort $WebmapPort

# --- 5. Bridge mod: pin to this version, build, install -----------------------
Step "Bridge mod"
$state = @{}
$stateFile = Join-Path $MinecraftDir 'mods\icuehud-mods.json'
if (Test-Path $stateFile) {
    (Get-Content $stateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
}
$apiVersion = $state['fabric-api.version']
$props = Join-Path $modDir 'gradle.properties'
$modJson = Join-Path $modDir 'src\main\resources\fabric.mod.json'
$before = Get-Content $props -Raw
$after = $before -replace '(?m)^minecraft_version=.*$', "minecraft_version=$McVersion" `
                 -replace '(?m)^loader_version=.*$', "loader_version=$loaderVersion"
if ($apiVersion) { $after = $after -replace '(?m)^fabric_api_version=.*$', "fabric_api_version=$apiVersion" }
if ($after -ne $before) {
    Set-Content -Path $props -Value $after -NoNewline
    Write-Host "gradle.properties: minecraft $McVersion, loader $loaderVersion$(if ($apiVersion) { ", fabric-api $apiVersion" })"
}
$jsonBefore = Get-Content $modJson -Raw
$jsonAfter = $jsonBefore -replace '"minecraft":\s*"[^"]*"', "`"minecraft`": `"~$McVersion`"" `
                         -replace '"fabricloader":\s*"[^"]*"', "`"fabricloader`": `">=$loaderVersion`""
if ($jsonAfter -ne $jsonBefore) {
    Set-Content -Path $modJson -Value $jsonAfter -NoNewline
    Write-Host "fabric.mod.json: minecraft ~$McVersion, fabricloader >=$loaderVersion"
}
if ($SkipModBuild) {
    Write-Host "Skipping the build (-SkipModBuild)."
} else {
    $env:JAVA_HOME = $jdk
    & (Join-Path $PSScriptRoot 'build-mod.ps1') -MinecraftDir $MinecraftDir
}

# --- 6. Logon tasks -----------------------------------------------------------
if ($Autostart) {
    Step "Logon tasks (dashboard + focus guard)"
    & (Join-Path $PSScriptRoot 'install-tasks.ps1')
}

# --- 7. Dashboard -------------------------------------------------------------
if (-not $NoDashboard) {
    Step "Dashboard"
    & (Join-Path $PSScriptRoot 'start-dashboard.ps1')
}

# --- What is left for you -----------------------------------------------------
Step "Done"
$webmapPinned = [bool](Get-ChildItem -Path (Join-Path $MinecraftDir 'journeymap\config') -Recurse -Filter '*webmap*.config*' -ErrorAction SilentlyContinue)
Write-Host "Minecraft $McVersion with Fabric $loaderVersion, mods in $MinecraftDir\mods."
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  1. In the Minecraft Launcher pick the profile '$($existing.Name)' and play; join a world."
if (-not $webmapPinned) {
    Write-Host "  2. Then run scripts\setup.ps1 once more: JourneyMap creates its webmap config on that first"
    Write-Host "     launch and the script pins the webmap to port $WebmapPort (needed by every widget)."
    Write-Host "  3. In game, JourneyMap options (J -> Options -> Radar): keep mobs/animals/villagers/players on."
} else {
    Write-Host "  2. In game, JourneyMap options (J -> Options -> Radar): keep mobs/animals/villagers/players on."
}
Write-Host "  Check: http://localhost:$WebmapPort/data/player and http://localhost:27421/state answer while in a world."
Write-Host "  Then tap the gear in the dashboard's corner to arrange the screen."
