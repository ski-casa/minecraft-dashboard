<#
.SYNOPSIS
    Copies the canonical widgets\jm-api.js into every widget folder.

.DESCRIPTION
    Widgets are packaged for iCUE as standalone folders, so each carries its
    own copy of the shared API helper. Edit widgets\jm-api.js, then run this
    (package-widgets.ps1 runs it for you). -Check only reports drift.
#>
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'widgets\jm-api.js'
$sourceHash = (Get-FileHash $source).Hash
$drift = @()

Get-ChildItem -Path (Join-Path $root 'widgets') -Directory | ForEach-Object {
    if (-not (Test-Path (Join-Path $_.FullName 'index.html'))) { return }
    $target = Join-Path $_.FullName 'jm-api.js'
    if ((Test-Path $target) -and ((Get-FileHash $target).Hash -eq $sourceHash)) { return }
    if ($Check) {
        $drift += $_.Name
    } else {
        Copy-Item -Path $source -Destination $target -Force
        Write-Host "Updated widgets\$($_.Name)\jm-api.js"
    }
}

if ($Check -and $drift.Count) {
    throw "jm-api.js copies are out of date in: $($drift -join ', '). Run scripts\sync-jm-api.ps1."
}
if (-not $Check) { Write-Host "jm-api.js copies are in sync." }
