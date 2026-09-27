# Capsi - bump the application version (patch, minor or major).
#
# Single source of truth for Capsi's version. The current version is read
# from Capsi/src-tauri/Cargo.toml, then rewritten everywhere a build consumes
# it, so a release never ships with mixed numbers:
#   Capsi/Cargo.toml                  workspace.package version
#   Capsi/crates/capsi-core/Cargo.toml  kept in lockstep with the app
#   Capsi/src-tauri/Cargo.toml
#   Capsi/src-tauri/tauri.conf.json  NSIS/APK file names, embedded version
#   Capsi/frontend/app.js             About panel (Version x.y.z)
#   Website/app.js and assets/js/config.js  offline fallback file name
#   Capsi/scripts/rc-preproc/main.rs  --version banner (tool label only)
#
# Cargo.lock is intentionally NOT rewritten: cargo refreshes the workspace
# version entries itself on the next build.
#
# Website note: only the Capsi_<version>_x64-setup.exe FILE NAME inside the
# offline fallback URL is rewritten. The live path resolves the real asset
# from the GitHub releases API, and releases/latest/download without a file
# name is left alone because GitHub needs the exact file name there.
#
# Usage (any working directory):
#   Capsi/scripts/bump-version.ps1          patch  1.0.0 -> 1.0.1
#   Capsi/scripts/bump-version.ps1 minor    minor  1.0.0 -> 1.1.0
#   Capsi/scripts/bump-version.ps1 major    major  1.0.0 -> 2.0.0
#
# Prints the new version but does NOT commit or tag. Verify with a build,
# then commit and tag v<new> yourself so CI agrees with the files.
# (Cargo.lock is refreshed by cargo itself on the next build; the bump leaves
# it alone.)

param(
    [ValidateSet('patch', 'minor', 'major')]
    [string]$Bump = 'patch'
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is Capsi/scripts, so its parent is the Tauri app root and
# the grandparent is the repo root (which holds Website).
$AppRoot = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $AppRoot

$manifest = Join-Path $AppRoot 'src-tauri/Cargo.toml'
$found = Select-String -Path $manifest -Pattern '(?m)^version *= *"([0-9]+)[.]([0-9]+)[.]([0-9]+)"' | Select-Object -First 1
if (-not $found) { throw "Capsi: could not find version in $manifest" }
$major = [int]$found.Matches[0].Groups[1].Value
$minor = [int]$found.Matches[0].Groups[2].Value
$patch = [int]$found.Matches[0].Groups[3].Value
$old = "$major.$minor.$patch"

if ($Bump -eq 'major') { $major = $major + 1; $minor = 0; $patch = 0 }
elseif ($Bump -eq 'minor') { $minor = $minor + 1; $patch = 0 }
else { $patch = $patch + 1 }
$new = "$major.$minor.$patch"

$oldEsc = [regex]::Escape($old)

function Set-Version($relativePath, $baseDir, $pattern, $replacement) {
    $full = Join-Path $baseDir $relativePath
    if (-not (Test-Path $full)) { throw "Capsi: missing file $full" }
    $enc = New-Object System.Text.UTF8Encoding($false)
    $text = $enc.GetString([System.IO.File]::ReadAllBytes($full))
    $updated = $text -replace $pattern, $replacement
    if ($updated -ceq $text) { throw "Capsi: version $old not found in $relativePath" }
    [System.IO.File]::WriteAllBytes($full, $enc.GetBytes($updated))
    Write-Host "Capsi: $relativePath -> $new"
}

# Cargo manifests: the version line under [package] / [workspace.package].
$cargoPattern = '(?m)^version *= *"' + $oldEsc + '"'
$cargoReplacement = 'version = "' + $new + '"'
Set-Version 'Cargo.toml' $AppRoot $cargoPattern $cargoReplacement
Set-Version 'crates/capsi-core/Cargo.toml' $AppRoot $cargoPattern $cargoReplacement
Set-Version 'src-tauri/Cargo.toml' $AppRoot $cargoPattern $cargoReplacement

# Tauri config: the version entry (drives NSIS/APK names and metadata).
# Tauri regenerates the copy under src-tauri/gen/android on android builds;
# that copy is git-ignored by Tauri itself, so it is not bumped here.
$tauriPattern = '"version": *"' + $oldEsc + '"'
$tauriReplacement = '"version": "' + $new + '"'
Set-Version 'src-tauri/tauri.conf.json' $AppRoot $tauriPattern $tauriReplacement

# Synced Android asset copy. Tauri rewrites this file from tauri.conf.json on
# every android build, and Tauri's own .gitignore excludes it from the repo,
# so it is kept in sync here on a best-effort basis only: when the copy is
# present and still carries the old version it is updated, otherwise it is
# left alone (a warning, never a failure).
$genAsset = 'src-tauri/gen/android/app/src/main/assets/tauri.conf.json'
$genFull = Join-Path $AppRoot $genAsset
if (Test-Path $genFull) {
    try {
        Set-Version $genAsset $AppRoot $tauriPattern $tauriReplacement
    } catch {
        Write-Host "Capsi: WARNING - left $genAsset alone: $($_.Exception.Message)"
    }
}

# Frontend About panel: Version x.y.z
Set-Version 'frontend/app.js' $AppRoot ('Version ' + $oldEsc) ('Version ' + $new)

# Website offline fallback file name: Capsi_x.y.z_x64-setup.exe
$exePattern = 'Capsi_' + $oldEsc + '_x64-setup[.]exe'
$exeReplacement = 'Capsi_' + $new + '_x64-setup.exe'
Set-Version 'Website/app.js' $RepoRoot $exePattern $exeReplacement
Set-Version 'Website/assets/js/config.js' $RepoRoot $exePattern $exeReplacement

# rc-preproc --version banner (tool label only).
Set-Version 'scripts/rc-preproc/main.rs' $AppRoot ('resource-file preprocessor[)] ' + $oldEsc) ('resource-file preprocessor) ' + $new)

Write-Host "Capsi: version bumped $old -> $new"
Write-Host "Capsi: build to verify, then commit and tag v$new"
