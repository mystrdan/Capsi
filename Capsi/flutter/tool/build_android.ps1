# Build the Capsi Android release APK with the Rust FFI bridge for every ABI.
#
# The Flutter UI and the shared Rust core are packaged together: the core is
# cross-compiled with cargo-ndk into android/app/src/main/jniLibs/<abi>/
# libcapsi_ffi.so, which is what lib/capsi_native.dart opens at start-up.
#
# Usage:
#   tool\build_android.ps1

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

. (Join-Path $PSScriptRoot "build_steps.ps1")

$Abis = @("arm64-v8a", "armeabi-v7a", "x86_64")

function Require-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found on PATH."
  }
}

Require-Command flutter
Require-Command cargo

if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) {
  throw "cargo-ndk was not found on PATH. Install it with: cargo install cargo-ndk --locked"
}

if (-not (Test-Path "android")) {
  Write-Host "Flutter Android runner is missing. Generating it..."
  Invoke-Native "flutter" @("create", "--platforms=android", ".") "flutter create failed"
}

& (Join-Path $PSScriptRoot "configure_android.ps1")
& (Join-Path $PSScriptRoot "make_icons.ps1")

Write-Host "Resolving Flutter packages..."
Invoke-Native "flutter" @("pub", "get") "flutter pub get failed"

Write-Host "Building Capsi Rust native bridge for: $($Abis -join ', ')"
$ndkArgs = @("ndk")
foreach ($abi in $Abis) {
  $ndkArgs += @("-t", $abi)
}
$ndkArgs += @("-o", "../android/app/src/main/jniLibs", "build", "--release")

Push-Location native
try {
  Invoke-Native "cargo" $ndkArgs "cargo-ndk could not build the Capsi bridge"
} finally {
  Pop-Location
}

foreach ($abi in $Abis) {
  $library = "android/app/src/main/jniLibs/$abi/libcapsi_ffi.so"
  if (-not (Test-Path $library)) {
    throw "Expected $library was not produced. The APK would start without the Rust core."
  }
}

Write-Host "Building Capsi Android application..."
Invoke-Native "flutter" @("build", "apk", "--release") "flutter build apk --release failed"

$apk = "build/app/outputs/flutter-apk/app-release.apk"
if (-not (Test-Path $apk)) {
  throw "Flutter build completed but $apk was not found."
}

Write-Host ""
Write-Host "Capsi Android release is ready:"
Write-Host (Resolve-Path $apk).Path
