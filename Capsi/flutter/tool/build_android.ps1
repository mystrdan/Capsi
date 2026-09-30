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

# cargo-ndk, Gradle and Flutter report progress on stderr. PowerShell promotes
# every line a native tool writes there into an error record, so with "Stop" a
# healthy build aborts on its first progress message. Native steps run with
# "Continue" and are judged by their exit code instead.
function Invoke-BuildStep {
  param(
    [ScriptBlock]$Step,
    [string]$Failure
  )
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  $exit = 0
  try {
    # Surface native stderr as ordinary build text: without this, Windows
    # PowerShell turns each line into a NativeCommandError record.
    & $Step 2>&1 | ForEach-Object {
      if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ }
    }
    $exit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($exit -ne 0) { throw "$Failure (exit code $exit)" }
}

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
  Invoke-BuildStep { flutter create --platforms=android . } "flutter create failed"
}

& (Join-Path $PSScriptRoot "configure_android.ps1")
& (Join-Path $PSScriptRoot "make_icons.ps1")

Write-Host "Resolving Flutter packages..."
Invoke-BuildStep { flutter pub get } "flutter pub get failed"

Write-Host "Building Capsi Rust native bridge for: $($Abis -join ', ')"
$ndkArgs = @("ndk")
foreach ($abi in $Abis) {
  $ndkArgs += @("-t", $abi)
}
$ndkArgs += @("-o", "../android/app/src/main/jniLibs", "build", "--release")

Push-Location native
try {
  Invoke-BuildStep { cargo @ndkArgs } "cargo-ndk could not build the Capsi bridge"
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
Invoke-BuildStep { flutter build apk --release } "flutter build apk --release failed"

$apk = "build/app/outputs/flutter-apk/app-release.apk"
if (-not (Test-Path $apk)) {
  throw "Flutter build completed but $apk was not found."
}

Write-Host ""
Write-Host "Capsi Android release is ready:"
Write-Host (Resolve-Path $apk).Path
