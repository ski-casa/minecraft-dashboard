<#
.SYNOPSIS
    Builds the iCUE HUD Bridge mod (mod/) and installs the jar into the
    Minecraft mods folder.

.DESCRIPTION
    Runs the Gradle wrapper in mod/ on a JDK 25, which Fabric's build tooling
    requires. If no JDK 25 is found (JAVA_HOME, or tools\jdk-25* in this repo)
    a Temurin JDK 25 is downloaded into tools\ once (~200 MB, gitignored).
    The first build also fetches the Minecraft jar and Fabric, so it takes a
    few minutes; later builds are quick.

    The built jar replaces any older icuehud-*.jar in the mods folder.
    install-mods.ps1 calls this with -SkipBuild to reinstall an already built jar.

.EXAMPLE
    .\build-mod.ps1
    .\build-mod.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$MinecraftDir = "$env:APPDATA\.minecraft"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$modDir = Join-Path $root 'mod'
$toolsDir = Join-Path $root 'tools'
$modsDir = Join-Path $MinecraftDir 'mods'

. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $SkipBuild) {
    $jdk = Get-OrInstallJdk $toolsDir
    Write-Host "Using JDK at $jdk"
    $env:JAVA_HOME = $jdk

    # OneDrive (or a stale Gradle daemon) sometimes holds buildclasses open, which makes
    # compileJava fail to clean it. Clear it ourselves; if that fails too, move it aside.
    $classes = Join-Path $modDir 'buildclasses'
    if (Test-Path $classes) {
        try { Remove-Item -Recurse -Force $classes -ErrorAction Stop }
        catch {
            $aside = Join-Path $modDir ("buildclasses-stale-" + (Get-Date -Format 'yyyyMMddHHmmss'))
            try { Rename-Item $classes $aside -ErrorAction Stop; Write-Host "buildclasses was locked; moved aside to $(Split-Path $aside -Leaf) (safe to delete later)" }
            catch { Write-Warning "buildclasses is locked and could not be moved; the build may fail. Close editors/Gradle daemons using moduild and retry." }
        }
    }
    Push-Location $modDir
    try {
        Write-Host "Building mod in $modDir ..."
        # --no-daemon: a lingering daemon keeps build\ open, which fails the next build when the repo lives in OneDrive.
        & .\gradlew.bat build --console=plain --no-daemon -q
        if ($LASTEXITCODE -ne 0) { throw "Gradle build failed (exit $LASTEXITCODE). See the output above." }
    } finally {
        Pop-Location
    }
}

$jar = Get-ChildItem -Path (Join-Path $modDir 'build\libs') -Filter 'icuehud-*.jar' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '-(sources|dev)\.jar$' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $jar) {
    throw "No built jar in mod\build\libs. Run build-mod.ps1 without -SkipBuild."
}

if (-not (Test-Path $modsDir)) { New-Item -ItemType Directory -Path $modsDir | Out-Null }
$mcRunning = Test-MinecraftRunning
if ($mcRunning) {
    Write-Warning "Minecraft is running; the new jar is picked up on the next launch."
}
# Never leave two icuehud jars behind (Fabric refuses to start with duplicate mods):
# if an old one is locked by the running game, keep it and skip the install.
$blocked = $false
Get-ChildItem -Path $modsDir -Filter 'icuehud-*.jar' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $jar.Name } | ForEach-Object {
        try {
            Remove-Item $_.FullName -Force -ErrorAction Stop
            Write-Host "  removed old $($_.Name)"
        } catch {
            Write-Warning "Could not replace $($_.Name) (in use by the running game). Close Minecraft and run build-mod.ps1 -SkipBuild to install $($jar.Name)."
            $blocked = $true
        }
    }
if (-not $blocked) {
    Copy-Item -Path $jar.FullName -Destination (Join-Path $modsDir $jar.Name) -Force
    Write-Host "Installed $($jar.Name) -> $modsDir"
}
Write-Host "In a world, http://localhost:27421/state should answer."
