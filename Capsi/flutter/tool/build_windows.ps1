# Build the Capsi Windows release with the Rust FFI bridge beside the executable.
#
# Run from anywhere: .\tool\build_windows.ps1
#
# Flutter owns the UI, capsi-core owns the product logic, and native/ is the
# C ABI between them. The produced capsi_ffi.dll is copied next to capsi.exe
# because the Dart FFI layer opens the library from the executable directory.

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

# Flutter, cargo and CMake report progress and warnings on stderr. PowerShell
# promotes every line a native tool writes there into an error record, so with
# "Stop" a build that is going perfectly aborts on its first progress message
# (silently, when the output is redirected into a log). Native steps therefore
# run with "Continue" and are judged by their exit code instead.
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

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK was not found on PATH."
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "Rust cargo was not found on PATH."
}

# A missing Visual Studio C++ toolchain is the usual reason this step fails on a
# fresh Windows machine, and CMake is not part of the default C++ workload.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  $vsPath = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath | Select-Object -First 1
  if (-not $vsPath) {
    throw "Visual Studio with the 'Desktop development with C++' workload (MSVC v143 build tools) is required. Install it with: & `"${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe`" modify --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.CMake.Project --passive"
  }
  $cmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  if (-not (Test-Path $cmake)) {
    throw "CMake was not found inside Visual Studio at $cmake. Add the 'C++ CMake tools for Windows' component to the Visual Studio installation."
  }
  # Flutter only looks for CMake on PATH, so borrow the copy shipped with VS.
  if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    $env:Path = (Split-Path $cmake) + ";$env:Path"
  }
}

if (-not (Test-Path "windows")) {
  Write-Host "Flutter Windows runner is missing. Generating it..."
  Invoke-BuildStep { flutter create --platforms=windows . } "flutter create failed"
}

& (Join-Path $PSScriptRoot "make_icons.ps1")

Write-Host "Resolving Flutter packages..."
Invoke-BuildStep { flutter pub get } "flutter pub get failed"

Write-Host "Building Capsi Rust native bridge..."
Invoke-BuildStep { cargo build --manifest-path native/Cargo.toml --release } "Building the Rust FFI bridge failed"

$ffi = Resolve-Path "native/target/release/capsi_ffi.dll"

Write-Host "Building Capsi Windows application..."
Invoke-BuildStep { flutter build windows --release } "flutter build windows --release failed"

$exe = Get-ChildItem -Path "build/windows" -Filter "capsi.exe" -Recurse -File |
  Select-Object -First 1

if (-not $exe) {
  throw "Flutter build completed but capsi.exe was not found under build/windows."
}

Copy-Item $ffi.Path (Join-Path $exe.DirectoryName "capsi_ffi.dll") -Force

Write-Host ""
Write-Host "Capsi Windows release is ready:"
Write-Host $exe.DirectoryName
