$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK was not found on PATH."
}

if (-not (Test-Path "windows")) {
  Write-Host "Flutter Windows runner is missing. Generating it..."
  flutter create --platforms=windows .
}

flutter pub get

Write-Host "Building Capsi Rust native bridge..."
cargo build --manifest-path native/Cargo.toml --release

$ffi = Resolve-Path "native/target/release/capsi_ffi.dll"
Write-Host "Building Capsi Windows application..."
flutter build windows --release

$exe = Get-ChildItem -Path "build/windows" -Filter "capsi.exe" -Recurse -File |
  Select-Object -First 1

if (-not $exe) {
  throw "Flutter build completed but capsi.exe was not found under build/windows."
}

Copy-Item $ffi.Path (Join-Path $exe.DirectoryName "capsi_ffi.dll") -Force

Write-Host ""
Write-Host "Capsi Windows release is ready:"
Write-Host $exe.DirectoryName
