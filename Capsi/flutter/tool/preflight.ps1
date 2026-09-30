$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

. (Join-Path $PSScriptRoot 'build_steps.ps1')

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
Invoke-Native "flutter" @("--version") "flutter --version failed"
Invoke-Native "cargo" @("--version") "cargo --version failed"

Write-Host 'Checking Flutter package metadata...'
Invoke-Native "flutter" @("pub", "get") "flutter pub get failed"

Write-Host 'Checking Rust FFI crate...'
Invoke-Native "cargo" @("check", "--manifest-path", "native/Cargo.toml") "cargo check failed"

Write-Host 'Checking Flutter analyzer...'
Invoke-Native "flutter" @("analyze") "flutter analyze failed"

Write-Host ''
Write-Host 'Preflight passed.'
