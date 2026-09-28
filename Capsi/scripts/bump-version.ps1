# Capsi - bump the application version (patch, minor or major).
#
# Flutter is the application client. Rust remains the shared native core.
#
# Usage:
#   Capsi/scripts/bump-version.ps1 patch
#   Capsi/scripts/bump-version.ps1 minor
#   Capsi/scripts/bump-version.ps1 major

param(
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Bump = 'patch'
)

$ErrorActionPreference = 'Stop'

$AppRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $AppRoot

$flutterPubspec = Join-Path $AppRoot 'flutter/pubspec.yaml'
$nativeManifest = Join-Path $AppRoot 'flutter/native/Cargo.toml'
$workspaceManifest = Join-Path $AppRoot 'Cargo.toml'

$found = Select-String -Path $flutterPubspec -Pattern '(?m)^version: *([0-9]+)[.]([0-9]+)[.]([0-9]+)[+]([0-9]+)' | Select-Object -First 1
if (-not $found) { throw "Capsi: could not find Flutter version in $flutterPubspec" }

$major = [int]$found.Matches[0].Groups[1].Value
$minor = [int]$found.Matches[0].Groups[2].Value
$patch = [int]$found.Matches[0].Groups[3].Value
$build = [int]$found.Matches[0].Groups[4].Value
$old = "$major.$minor.$patch"

if ($Bump -eq 'major') { $major++; $minor = 0; $patch = 0 }
elseif ($Bump -eq 'minor') { $minor++; $patch = 0 }
else { $patch++ }

$new = "$major.$minor.$patch"
$newVersion = "$new+$($build + 1)"
$oldEsc = [regex]::Escape($old)

function Replace-Text($path, $pattern, $replacement) {
    if (-not (Test-Path $path)) { throw "Capsi: missing file $path" }
    $enc = New-Object System.Text.UTF8Encoding($false)
    $text = $enc.GetString([System.IO.File]::ReadAllBytes($path))
    $updated = $text -replace $pattern, $replacement
    if ($updated -ceq $text) { throw "Capsi: expected version was not found in $path" }
    [System.IO.File]::WriteAllBytes($path, $enc.GetBytes($updated))
}

Replace-Text $flutterPubspec ('(?m)^version: *' + $oldEsc + '[+]([0-9]+)') ('version: ' + $newVersion)
Replace-Text $nativeManifest ('(?m)^version *= *"' + $oldEsc + '"') ('version = "' + $new + '"')
Replace-Text $workspaceManifest ('(?m)^version *= *"' + $oldEsc + '"') ('version = "' + $new + '"')

# Website fallback filename only. The website itself is a separate product
# presentation and does not share application source with Flutter.
foreach ($path in @(
    (Join-Path $RepoRoot 'Website/app.js'),
    (Join-Path $RepoRoot 'Website/assets/js/config.js')
)) {
    if (Test-Path $path) {
        $enc = New-Object System.Text.UTF8Encoding($false)
        $text = $enc.GetString([System.IO.File]::ReadAllBytes($path))
        $updated = $text -replace ('Capsi_' + $oldEsc + '_x64-setup[.]exe'), ('Capsi_' + $new + '_x64-setup.exe')
        [System.IO.File]::WriteAllBytes($path, $enc.GetBytes($updated))
    }
}

Write-Host "Capsi: version bumped $old -> $new"
