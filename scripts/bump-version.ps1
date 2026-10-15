<#
.SYNOPSIS
    Sets the project version everywhere it is recorded, writes the changelog
    entry, and optionally commits, tags and pushes the release.

.DESCRIPTION
    Places that carry the version (all updated together):
      VERSION                          the source of truth
      mod\gradle.properties            mod_version (-> the jar name)
      widgets\*\manifest.json          "version" (-> the iCUE packages)
      dashboard\index.html             HUD_VERSION (shown in the Screen dialog)
      README.md                        the "**Version x.y.z**" line
      CHANGELOG.md                     a new "## x.y.z — date" section at the top

    The changelog section is pre-filled with the commit subjects since the
    previous release tag (edit it before committing, or pass -Notes).

.EXAMPLE
    .\bump-version.ps1 1.1.0                       # update the files, show the git commands
    .\bump-version.ps1 1.1.0 -Commit -Push         # ...and commit "Release v1.1.0", tag v1.1.0, push
    .\bump-version.ps1 1.1.0 -Notes "Fixed the map trail; new villager widget"
    .\bump-version.ps1 -Check                      # just verify every place agrees with VERSION
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Version,
    [string[]]$Notes,
    [switch]$Commit,
    [switch]$Push,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$files = @{
    version   = 'VERSION'
    gradle    = 'mod\gradle.properties'
    index     = 'dashboard\index.html'
    readme    = 'README.md'
    changelog = 'CHANGELOG.md'
}
$manifests = Get-ChildItem -Path 'widgets' -Directory | ForEach-Object { Join-Path $_.FullName 'manifest.json' } | Where-Object { Test-Path $_ }

# Reads a file keeping its line endings; the regex replace below keeps them too.
function Edit-File([string]$Path, [scriptblock]$Transform) {
    $raw = Get-Content $Path -Raw
    $new = & $Transform $raw
    if ($new -ne $raw) { Set-Content -Path $Path -Value $new -NoNewline -Encoding UTF8; return $true }
    return $false
}

function Get-Versions {
    $v = [ordered]@{}
    $v['VERSION'] = (Get-Content $files.version -Raw).Trim()
    $v['mod/gradle.properties'] = [regex]::Match((Get-Content $files.gradle -Raw), '(?m)^mod_version=(.*)$').Groups[1].Value.Trim()
    $v['dashboard/index.html'] = [regex]::Match((Get-Content $files.index -Raw), 'var HUD_VERSION = "([^"]*)"').Groups[1].Value
    $v['README.md'] = [regex]::Match((Get-Content $files.readme -Raw), '\*\*Version ([^*]+)\*\*').Groups[1].Value
    foreach ($m in $manifests) {
        $rel = (Resolve-Path $m -Relative) -replace '\\', '/' -replace '^\./', ''
        $v[$rel] = [regex]::Match((Get-Content $m -Raw), '"version":\s*"([^"]*)"').Groups[1].Value
    }
    return $v
}

# --- Check mode ---------------------------------------------------------------
if ($Check -or -not $Version) {
    $all = Get-Versions
    $expected = $all['VERSION']
    $bad = $all.GetEnumerator() | Where-Object { $_.Value -ne $expected }
    if ($bad) {
        Write-Host "VERSION is $expected but these disagree:" -ForegroundColor Red
        $bad | ForEach-Object { Write-Host ("  {0,-40} {1}" -f $_.Key, ($_.Value ? $_.Value : '(missing)')) }
        exit 1
    }
    Write-Host "All $($all.Count) places agree: version $expected" -ForegroundColor Green
    if (-not $Version) { Write-Host "Pass a version to bump, e.g. .\bump-version.ps1 1.1.0" }
    exit 0
}

# --- Bump ---------------------------------------------------------------------
if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { throw "'$Version' is not a semantic version (e.g. 1.1.0 or 1.1.0-beta.1)." }
$previous = (Get-Content $files.version -Raw).Trim()
if ($Version -eq $previous) { Write-Warning "Already at $Version; files are checked but the changelog is not touched." }

$changed = @()
if (Edit-File $files.version { param($s) "$Version`n" }) { $changed += $files.version }
if (Edit-File $files.gradle { param($s) $s -replace '(?m)^mod_version=.*$', "mod_version=$Version" }) { $changed += $files.gradle }
if (Edit-File $files.index { param($s) $s -replace 'var HUD_VERSION = "[^"]*"', "var HUD_VERSION = `"$Version`"" }) { $changed += $files.index }
if (Edit-File $files.readme { param($s) $s -replace '\*\*Version [^*]+\*\*', "**Version $Version**" }) { $changed += $files.readme }
foreach ($m in $manifests) {
    if (Edit-File $m { param($s) $s -replace '"version":\s*"[^"]*"', "`"version`": `"$Version`"" }) { $changed += (Resolve-Path $m -Relative) }
}

# Changelog: a new section with the commit subjects since the last tag as a starting point.
if ($Version -ne $previous) {
    $lastTag = (git describe --tags --abbrev=0 2>$null)
    if ($Notes) {
        $bullets = $Notes | ForEach-Object { "- $_" }
    } else {
        $range = if ($lastTag) { "$lastTag..HEAD" } else { 'HEAD' }
        $subjects = @(git log $range --pretty=format:%s --no-merges 2>$null) | Where-Object { $_ -and $_ -notmatch '^Release v' }
        $bullets = if ($subjects) { $subjects | ForEach-Object { "- $_" } } else { @('- (describe the changes)') }
    }
    $section = "## $Version — $(Get-Date -Format 'yyyy-MM-dd')`n`n" + ($bullets -join "`n") + "`n`n"
    if (Edit-File $files.changelog {
            param($s)
            $nl = if ($s -match "`r`n") { "`r`n" } else { "`n" }
            $block = $section -replace "`n", $nl
            if ($s -match '(?m)^## ') { [regex]::new('(?m)^## ').Replace($s, ($block + '## ').Replace('$', '$$'), 1) }
            else { $s.TrimEnd() + $nl + $nl + $block }
        }) { $changed += $files.changelog }
}

Write-Host "Version $previous -> $Version" -ForegroundColor Cyan
$changed | ForEach-Object { Write-Host "  updated $_" }
$verify = Get-Versions
$wrong = $verify.GetEnumerator() | Where-Object { $_.Value -ne $Version }
if ($wrong) { throw "After the bump these still disagree: $(($wrong | ForEach-Object { $_.Key }) -join ', ')" }

# --- Release ------------------------------------------------------------------
if ($Commit) {
    if (git status --porcelain | Where-Object { $_ -notmatch '^\s*[MA]\s' -and $_ -notmatch 'VERSION|gradle.properties|manifest.json|index.html|README.md|CHANGELOG.md' }) {
        Write-Warning "There are other uncommitted changes; they will be included in the release commit."
    }
    git add -A
    git commit -q -m "Release v$Version"
    git tag -a "v$Version" -m "Minecraft Dashboard $Version"
    Write-Host "Committed and tagged v$Version" -ForegroundColor Green
    if ($Push) {
        git push --follow-tags
        Write-Host "Pushed." -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Review CHANGELOG.md, then release with:" -ForegroundColor Yellow
    Write-Host "  git add -A; git commit -m `"Release v$Version`"; git tag -a v$Version -m `"Minecraft Dashboard $Version`"; git push --follow-tags"
    Write-Host "(or re-run with -Commit -Push to do that for you)"
}
