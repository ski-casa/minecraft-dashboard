<#
.SYNOPSIS
    Packages each folder in widgets/ into dist/<name>.icuewidget for import
    into iCUE.

.DESCRIPTION
    Uses Corsair's WidgetBuilder CLI (icuewidget) when it is on PATH - it
    validates the manifest as part of packaging. Falls back to a plain zip of
    the widget folder contents (manifest.json at the archive root), which iCUE
    also accepts.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$widgetsDir = Join-Path $root 'widgets'
$distDir = Join-Path $root 'dist'

New-Item -ItemType Directory -Force -Path $distDir | Out-Null
$cli = Get-Command icuewidget -ErrorAction SilentlyContinue

Get-ChildItem -Path $widgetsDir -Directory | ForEach-Object {
    $widget = $_
    if (-not (Test-Path (Join-Path $widget.FullName 'manifest.json'))) {
        Write-Warning "$($widget.Name): no manifest.json, skipped"
        return
    }
    $out = Join-Path $distDir "$($widget.Name).icuewidget"

    if ($cli) {
        & $cli.Source package $widget.FullName --output $out
        if ($LASTEXITCODE -ne 0) { throw "icuewidget package failed for $($widget.Name)" }
    } else {
        $tmp = "$out.zip"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        Compress-Archive -Path (Join-Path $widget.FullName '*') -DestinationPath $tmp -Force
        Move-Item -Path $tmp -Destination $out -Force
    }
    Write-Host "Packaged $($widget.Name) -> $out"
}

Write-Host "`nImport the .icuewidget files from $distDir in iCUE (Widgets panel -> +)."
