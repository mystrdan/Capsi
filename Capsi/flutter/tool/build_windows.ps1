# Build the Capsi Windows release with the Rust FFI bridge beside the executable,
# then package the result as an MSI installer.
#
# Run from anywhere: .\tool\build_windows.ps1
#
# Flutter owns the UI, capsi-core owns the product logic, and native/ is the
# C ABI between them. The produced capsi_ffi.dll is copied next to capsi.exe
# because the Dart FFI layer opens the library from the executable directory.
#
# The release is meant to run on a machine that has nothing but Windows on it,
# so the runner and the bridge link the C runtime statically and the installer
# has no prerequisite of its own to install first.

param(
  # Fail instead of falling back to CMake when Visual Studio has the C++ build
  # tools but not the workload marker that `flutter build windows` insists on.
  # Use it to verify that a machine is set up the standard way.
  [switch]$RequireFlutterToolchain,
  # Build the application only, and skip the installer.
  [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

. (Join-Path $PSScriptRoot "build_steps.ps1")

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter SDK was not found on PATH."
}

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "Rust cargo was not found on PATH."
}

# A missing Visual Studio C++ toolchain is the usual reason this step fails on a
# fresh Windows machine, and CMake is not part of the default C++ workload.
#
# Flutter decides whether an installation is usable by asking vswhere for one of
# the C++ workload IDs together with the C++ toolchain and CMake components.
# Asking only for the component (as this script first did) passes on a machine
# where Flutter then aborts with a bare "Unable to find suitable Visual Studio
# toolchain", so ask vswhere the same question Flutter asks and name the missing
# piece in the failure instead.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vcTools = "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
$vcCMake = "Microsoft.VisualStudio.Component.VC.CMake.Project"
$cppWorkloads = @(
  # The IDE workload, then the Build Tools workload.
  "Microsoft.VisualStudio.Workload.NativeDesktop",
  "Microsoft.VisualStudio.Workload.VCTools"
)

# Flutter is the primary driver of this build. It rejects a Visual Studio
# installation that lacks the workload marker even when the compiler and CMake
# are both present, so track whether the CMake project has to be driven directly.
$useCmakeBuild = $false

if (Test-Path $vswhere) {
  $vsPath = $null
  foreach ($workload in $cppWorkloads) {
    $vsPath = & $vswhere -latest -products * -requires $workload $vcTools $vcCMake `
      -property installationPath | Select-Object -First 1
    if ($vsPath) { break }
  }

  if (-not $vsPath) {
    # Separate "no C++ tooling at all" from "tooling present, workload ID
    # missing". The first needs Visual Studio installed. The second still has the
    # compiler, CMake and the Windows SDK, which is everything the project itself
    # needs, so build it through CMake instead of stopping the release.
    $componentsOnly = & $vswhere -latest -products * -requires $vcTools $vcCMake `
      -property installationPath | Select-Object -First 1
    $setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    if (-not $componentsOnly) {
      throw ("Visual Studio with the 'Desktop development with C++' workload is required. " +
        "Install it from an elevated prompt:`n" +
        "  & `"$setup`" modify --add Microsoft.VisualStudio.Workload.NativeDesktop " +
        "--add $vcCMake --passive --norestart")
    }
    if ($RequireFlutterToolchain) {
      throw ("Visual Studio at $componentsOnly has the C++ build tools and CMake " +
        "but not the 'Desktop development with C++' workload that Flutter requires. " +
        "Add it from an elevated prompt:`n" +
        "  & `"$setup`" modify --installPath `"$componentsOnly`" " +
        "--add Microsoft.VisualStudio.Workload.NativeDesktop --passive --norestart")
    }
    $vsPath = $componentsOnly
    $useCmakeBuild = $true
    Write-Warning ("Visual Studio at $vsPath has the C++ build tools but not the " +
      "'Desktop development with C++' workload marker, which `flutter build windows` " +
      "requires. Building the same CMake project with the same compiler directly. " +
      "Add the workload from an elevated prompt to retire this fallback:`n" +
      "  & `"$setup`" modify --installPath `"$vsPath`" " +
      "--add Microsoft.VisualStudio.Workload.NativeDesktop --passive --norestart")
  }

  $vsCmake = Join-Path $vsPath "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
  if (Test-Path $vsCmake) {
    # Flutter only looks for CMake on PATH, so borrow the copy shipped with VS.
    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
      $env:Path = (Split-Path $vsCmake) + ";$env:Path"
    }
  } else {
    Write-Warning "CMake was not found inside Visual Studio at $vsPath; using the copy on PATH instead."
  }
}

$cmake = $null
if ($vsCmake -and (Test-Path $vsCmake)) {
  $cmake = $vsCmake
} else {
  $onPath = Get-Command cmake -ErrorAction SilentlyContinue
  if ($onPath) { $cmake = $onPath.Source }
}
if (-not $cmake) {
  throw "CMake was not found. Add the 'C++ CMake tools for Windows' component to Visual Studio, or put CMake on PATH."
}

if (-not (Test-Path "windows")) {
  Write-Host "Flutter Windows runner is missing. Generating it..."
  Invoke-Native "flutter" @("create", "--platforms=windows", ".") "flutter create failed"
}

& (Join-Path $PSScriptRoot "make_icons.ps1")

Write-Host "Resolving Flutter packages..."
Invoke-Native "flutter" @("pub", "get") "flutter pub get failed"

Write-Host "Building Capsi Rust native bridge..."
# The Windows release must not depend on the Visual C++ redistributable, so the
# bridge links the C runtime statically, exactly like the runner does (see
# windows/CMakeLists.txt). The C ABI hands every allocation back to the library
# that made it, so a private CRT is safe across the boundary.
$previousRustFlags = $env:RUSTFLAGS
$env:RUSTFLAGS = "-C target-feature=+crt-static"
try {
  Invoke-Native "cargo" @("build", "--manifest-path", "native/Cargo.toml", "--release") "Building the Rust FFI bridge failed"
} finally {
  $env:RUSTFLAGS = $previousRustFlags
}

$ffi = Resolve-Path "native/target/release/capsi_ffi.dll"

if ($useCmakeBuild) {
  # Flutter writes the CMake inputs for the project (windows/flutter/ephemeral/
  # generated_config.cmake, the engine headers and the plugin list) before it
  # validates the toolchain, so this machine can still build through CMake. Only
  # those inputs are wanted from that step, and proving they landed is a stricter
  # check than the exit code would have been; the Flutter failure itself is
  # already on screen.
  $generatedConfig = "windows/flutter/ephemeral/generated_config.cmake"
  if (-not (Test-Path $generatedConfig)) {
    Write-Host "Generating the Flutter Windows project inputs..."
    try {
      Invoke-Native "flutter" @("build", "windows", "--release") "flutter build windows --release failed"
    } catch {
      Write-Verbose "flutter build windows --release reported: $_"
    }
    if (-not (Test-Path $generatedConfig)) {
      throw "Flutter did not generate $generatedConfig, so the CMake release cannot be configured. Install the 'Desktop development with C++' workload and re-run."
    }
  }

  Write-Host "Building Capsi Windows application with CMake..."
  $windowsBuild = "build/windows/x64"
  if (-not (Test-Path (Join-Path $windowsBuild "CMakeCache.txt"))) {
    Invoke-Native $cmake @("-S", "windows", "-B", $windowsBuild, "-A", "x64") "Configuring the Windows CMake project failed"
  }
  Invoke-Native $cmake @("--build", $windowsBuild, "--config", "Release") "Building the Windows CMake project failed"
  # INSTALL is what stages flutter_windows.dll, the plugins and the data payload
  # next to capsi.exe. Without it the executable is built and cannot start.
  Invoke-Native $cmake @("--build", $windowsBuild, "--config", "Release", "--target", "INSTALL") "Installing the Windows release bundle failed"
} else {
  Write-Host "Building Capsi Windows application..."
  Invoke-Native "flutter" @("build", "windows", "--release") "flutter build windows --release failed"
}

$exe = Get-ChildItem -Path "build/windows" -Filter "capsi.exe" -Recurse -File |
  Select-Object -First 1

if (-not $exe) {
  throw "Flutter build completed but capsi.exe was not found under build/windows."
}

Copy-Item $ffi.Path (Join-Path $exe.DirectoryName "capsi_ffi.dll") -Force

# Prove the release really is self-contained instead of trusting the build
# system with it. A machine with nothing but Windows cannot start a binary that
# imports the Visual C++ redistributable, and the import table stores the name
# of every DLL it needs as plain text: a plugin compiled without the static
# runtime, or a stale object file, puts MSVCP140/VCRUNTIME140 back into the
# bundle. Fail the release here, where the cause and the fix are both known.
$redistributableImports = @("MSVCP140", "VCRUNTIME140")
$binaries = Get-ChildItem -Path $exe.DirectoryName -Recurse -File |
  Where-Object { $_.Extension -in @(".exe", ".dll") }
foreach ($binary in $binaries) {
  $text = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($binary.FullName))
  foreach ($name in $redistributableImports) {
    if ($text.Contains($name)) {
      throw ("$($binary.Name) imports $name, so this release would need the Visual C++ redistributable " +
        "installed first. The C runtime is linked statically by the /MT switch that windows/CMakeLists.txt " +
        "puts in place of the /MD one CMake defaults to, and the Rust bridge by " +
        "RUSTFLAGS=-C target-feature=+crt-static in this script. Rebuild from a clean build\windows directory.")
    }
  }
}

Write-Host ""
Write-Host "Capsi Windows release is ready:"
Write-Host $exe.DirectoryName

if (-not $SkipInstaller) {
  # The installer is the artifact that actually ships, so a release build ends
  # with one. Pass -SkipInstaller for the bare application bundle.
  & (Join-Path $PSScriptRoot "build_windows_installer.ps1") -BundleDirectory $exe.DirectoryName
}
