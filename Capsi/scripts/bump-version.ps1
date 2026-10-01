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
$coreManifest = Join-Path $AppRoot 'crates/capsi-core/Cargo.toml'
$flutterClient = Join-Path $AppRoot 'flutter/lib/main.dart'

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
Replace-Text $coreManifest ('(?m)^version *= *"' + $oldEsc + '"') ('version = "' + $new + '"')

# The Flutter client keeps a display-only fallback for when the native bridge
# cannot be loaded; it has to move with the release or About shows a stale build.
Replace-Text $flutterClient ('capsiVersionFallback = ''' + $oldEsc + '''') ('capsiVersionFallback = ''' + $new + '''')

# Website presentation: the download button names the release artifact and the
# hero eyebrow repeats the version. The website is a separate product surface,
# so both are updated only while the files are present.
foreach ($path in @(
    (Join-Path $RepoRoot 'Website/App.jsx')
)) {
    if (Test-Path $path) {
        Replace-Text $path ('Capsi-' + $oldEsc + '-x64[.]msi') ('Capsi-' + $new + '-x64.msi')
        Replace-Text $path ('(?m)CAPSI ' + $oldEsc + '\b') ('CAPSI ' + $new)
    }
}

# Documentation and tooling strings that quote the release version. These are
# soft targets: a file that no longer mentions the version is not an error.
function Replace-TextIfPresent($path, $pattern, $replacement) {
    if (-not (Test-Path $path)) { return }
    $enc = New-Object System.Text.UTF8Encoding($false)
    $text = $enc.GetString([System.IO.File]::ReadAllBytes($path))
    if ($text -notmatch $pattern) { return }
    $updated = $text -replace $pattern, $replacement
    if ($updated -cne $text) {
        [System.IO.File]::WriteAllBytes($path, $enc.GetBytes($updated))
    }
}

Replace-TextIfPresent (Join-Path $AppRoot 'flutter/README.md') ('The Flutter client currently tracks Capsi `' + $oldEsc) ('The Flutter client currently tracks Capsi `' + $new)
Replace-TextIfPresent (Join-Path $AppRoot 'scripts/rc-preproc/main.rs') ('preprocessor\) ' + $oldEsc) ('preprocessor) ' + $new)

Write-Host "Capsi: version bumped $old -> $new"
