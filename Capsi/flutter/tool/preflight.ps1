$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found on PATH."
  }
}

function Require-Path([string]$Path) {
  if (-not (Test-Path $Path)) {
    throw "Required path is missing: $Path"
  }
}

Require-Command 'flutter'
Require-Command 'cargo'

Require-Path 'pubspec.yaml'
Require-Path 'lib/main.dart'
Require-Path 'lib/capsi_native.dart'
Require-Path 'native/Cargo.toml'
Require-Path 'assets/capsi-logo-512.png'

Write-Host 'Capsi Flutter preflight'
Write-Host '-----------------------'
flutter --version
cargo --version

Write-Host 'Checking Flutter package metadata...'
flutter pub get

Write-Host 'Checking Rust FFI crate...'
cargo check --manifest-path native/Cargo.toml

Write-Host 'Checking Flutter analyzer...'
flutter analyze

Write-Host ''
Write-Host 'Preflight passed.'
