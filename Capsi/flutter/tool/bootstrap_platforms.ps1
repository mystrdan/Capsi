$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK is required."
}

flutter pub get
flutter create --platforms=windows,android,ios,macos,linux .

Write-Host ""
Write-Host "Flutter platform runners generated."
Write-Host "Next: build the Rust bridge for the target platform and package/link it into the runner."
