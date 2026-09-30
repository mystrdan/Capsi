# Generates the standard Flutter runners for every Capsi platform.
#
# A fresh `flutter create` runner is only a template: the Android side still
# carries the placeholder application id and debug-only INTERNET permission,
# and every platform still shows the stock Flutter icon. Bootstrap therefore
# finishes with the same two steps the platform builds run - the Capsi runner
# settings and the logo stamp - so a generated tree is correct immediately.

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

. (Join-Path $PSScriptRoot "build_steps.ps1")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK is required."
}

Invoke-Native "flutter" @("pub", "get") "flutter pub get failed"
Invoke-Native "flutter" @("create", "--platforms=windows,android,ios,macos,linux", ".") "flutter create failed"

if (Test-Path "android") {
  & (Join-Path $PSScriptRoot "configure_android.ps1")
}
& (Join-Path $PSScriptRoot "make_icons.ps1")

Write-Host ""
Write-Host "Flutter platform runners generated and configured for Capsi."
Write-Host "Next: build the Rust bridge for the target platform and package/link it into the runner."
