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
$RequiredJava = 25

function Get-JavaMajor([string]$JavaExe) {
    try {
        $line = (& $JavaExe -version 2>&1 | Select-Object -First 1) -join ''
        if ($line -match '"(\d+)') { return [int]$Matches[1] }
    } catch {}
    return 0
}

function Find-Jdk {
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe") -and (Get-JavaMajor "$env:JAVA_HOME\bin\java.exe") -ge $RequiredJava) {
        return $env:JAVA_HOME
    }
    $bundled = Get-ChildItem -Path $toolsDir -Directory -Filter "jdk-$RequiredJava*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($bundled -and (Test-Path "$($bundled.FullName)\bin\java.exe")) { return $bundled.FullName }
    return $null
}

if (-not $SkipBuild) {
    $jdk = Find-Jdk
    if (-not $jdk) {
        Write-Host "No JDK $RequiredJava found; downloading Temurin JDK $RequiredJava into $toolsDir ..."
        New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
        $zip = Join-Path $env:TEMP "temurin-jdk$RequiredJava.zip"
        Invoke-WebRequest -Uri "https://api.adoptium.net/v3/binary/latest/$RequiredJava/ga/windows/x64/jdk/hotspot/normal/eclipse" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $toolsDir -Force
        Remove-Item $zip -Force
        $jdk = Find-Jdk
        if (-not $jdk) { throw "JDK download did not produce tools\jdk-$RequiredJava*. Install a JDK $RequiredJava and set JAVA_HOME." }
    }
    Write-Host "Using JDK at $jdk"
    $env:JAVA_HOME = $jdk

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
$mcRunning = Get-Process -Name javaw -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Minecraft' }
if ($mcRunning) {
    Write-Warning "Minecraft is running; the new jar is picked up on the next launch."
}
Get-ChildItem -Path $modsDir -Filter 'icuehud-*.jar' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne $jar.Name } | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "  removed old $($_.Name)"
    }
Copy-Item -Path $jar.FullName -Destination (Join-Path $modsDir $jar.Name) -Force
Write-Host "Installed $($jar.Name) -> $modsDir"
Write-Host "In a world, http://localhost:27421/state should answer."
