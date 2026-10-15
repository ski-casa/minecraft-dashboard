# Shared helpers, dot-sourced by the other scripts:  . (Join-Path $PSScriptRoot 'common.ps1')

$script:RequiredJava = 25
$script:UserAgent = 'steve/minecraft-dashboard (setup scripts)'

function Get-JavaMajor([string]$JavaExe) {
    try {
        $line = (& $JavaExe -version 2>&1 | Select-Object -First 1) -join ''
        if ($line -match '"(\d+)') { return [int]$Matches[1] }
    } catch {}
    return 0
}

# A JDK of the required major version: JAVA_HOME if it qualifies, else one
# bundled under tools\jdk-<major>*; $null when there is none.
function Find-Jdk([string]$ToolsDir) {
    if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\java.exe") -and (Get-JavaMajor "$env:JAVA_HOME\bin\java.exe") -ge $script:RequiredJava) {
        return $env:JAVA_HOME
    }
    $bundled = Get-ChildItem -Path $ToolsDir -Directory -Filter "jdk-$($script:RequiredJava)*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($bundled -and (Test-Path "$($bundled.FullName)\bin\java.exe")) { return $bundled.FullName }
    return $null
}

# Find-Jdk, downloading a Temurin JDK into tools\ when none is found (~200 MB, once).
function Get-OrInstallJdk([string]$ToolsDir) {
    $jdk = Find-Jdk $ToolsDir
    if ($jdk) { return $jdk }
    $major = $script:RequiredJava
    Write-Host "No JDK $major found; downloading Temurin JDK $major into $ToolsDir ..."
    New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
    $zip = Join-Path $env:TEMP "temurin-jdk$major.zip"
    Invoke-WebRequest -Uri "https://api.adoptium.net/v3/binary/latest/$major/ga/windows/x64/jdk/hotspot/normal/eclipse" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $ToolsDir -Force
    Remove-Item $zip -Force
    $jdk = Find-Jdk $ToolsDir
    if (-not $jdk) { throw "JDK download did not produce tools\jdk-$major*. Install a JDK $major and set JAVA_HOME." }
    return $jdk
}

# Newest Modrinth version of a project for a game version on Fabric, stable first; $null if none.
function Get-ModrinthVersion([string]$Slug, [string]$GameVersion) {
    $gv = [uri]::EscapeDataString("[""$GameVersion""]")
    $ld = [uri]::EscapeDataString('["fabric"]')
    $url = "https://api.modrinth.com/v2/project/$Slug/version?game_versions=$gv&loaders=$ld"
    try {
        $versions = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = $script:UserAgent }
    } catch {
        return $null
    }
    if (-not $versions) { return $null }
    foreach ($type in 'release', 'beta', 'alpha') {
        $match = $versions | Where-Object { $_.version_type -eq $type } | Select-Object -First 1
        if ($match) { return $match }
    }
    return $versions | Select-Object -First 1
}

# Minecraft version of the newest installed Fabric profile (folder fabric-loader-<loader>-<game>), or $null.
function Get-InstalledFabricGameVersion([string]$MinecraftDir) {
    $profiles = Get-ChildItem -Path (Join-Path $MinecraftDir 'versions') -Directory -Filter 'fabric-loader-*' -ErrorAction SilentlyContinue
    if (-not $profiles) { return $null }
    $newest = $profiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $parts = $newest.Name -split '-'
    if ($parts.Count -lt 4) { return $null }
    return ($parts[3..($parts.Count - 1)] -join '-')
}

function Test-MinecraftRunning {
    return [bool](Get-Process -Name javaw, java -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Minecraft' })
}
