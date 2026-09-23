@echo off
:: Build the Capsi desktop app for Windows (MSVC x86_64) and, optionally, the
:: NSIS installer that end users download.
::
:: Why MSVC and not GNU: the MSVC toolchain is what a normal Windows developer
:: machine has, Rust's default host is x86_64-pc-windows-msvc, and `rc.exe` from
:: the Windows SDK is what embeds the icon, manifest and version metadata
:: (CompanyName CAPSICOM) into the executable. Without a resource compiler
:: `src-tauri/build.rs` still builds, but the exe ships unbadged.
::
:: Usage:
::   scripts\build-msvc.bat            debug build for local testing
::   scripts\build-msvc.bat release    release exe (target\release\capsi.exe)
::   scripts\build-msvc.bat bundle     release exe + NSIS installer
::
:: `bundle` needs the Tauri CLI. It does NOT need NSIS installed: the CLI
:: downloads its own NSIS (currently 3.11) into %LOCALAPPDATA%\tauri\NSIS the
:: first time it bundles. The installer lands in
:: target\release\bundle\nsis\Capsi_<version>_x64-setup.exe - that is the file
:: to hand to another Windows user. A bare capsi.exe is portable, not installable.
setlocal
:: VsDevCmd.bat resolves `vswhere.exe` relative to the current directory. If
:: NoDefaultCurrentDirectoryInExePath=1 is set (VS Code's shell sets it) that
:: lookup fails silently, vcvars ends half-initialised, and rc.exe/link.exe stay
:: off PATH - which is why the exe would come out with no icon or version info.
set "NoDefaultCurrentDirectoryInExePath="

set "VCVARS="
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
  pushd "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"
  for /f "delims=" %%i in ('vswhere.exe -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath') do set "VSROOT=%%i"
  popd
)
if defined VSROOT if exist "%VSROOT%\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=%VSROOT%\VC\Auxiliary\Build\vcvars64.bat"

:: Fallback for the common layouts when vswhere is unavailable.
if not defined VCVARS for %%r in (
  "%ProgramFiles%\Microsoft Visual Studio\18\Community"
  "%ProgramFiles%\Microsoft Visual Studio\2022\Community"
  "%ProgramFiles%\Microsoft Visual Studio\2022\Professional"
  "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools"
) do if not defined VCVARS if exist "%%~r\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=%%~r\VC\Auxiliary\Build\vcvars64.bat"

if not defined VCVARS (
  echo Capsi: no Visual Studio C++ toolchain found.
  echo Install the Desktop development with C++ workload, then run this script again.
  exit /b 1
)

call "%VCVARS%"
if errorlevel 1 exit /b 1

set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
:: A launcher for the Tauri CLI placed by hand (see README) takes second place
:: only to a real `cargo install tauri-cli`.
if exist "%USERPROFILE%\.capsi-tools\bin\tauri.cmd" set "PATH=%USERPROFILE%\.capsi-tools\bin;%PATH%"
cd /d "%~dp0.."

if /i "%~1"=="bundle" (
  rem `cargo tauri` comes from `cargo install tauri-cli`; `tauri` from the npm
  rem package (@tauri-apps/cli). Accept whichever is present.
  where tauri >NUL 2>&1
  if errorlevel 1 (
    cargo tauri build --bundles nsis
  ) else (
    tauri build --bundles nsis
  )
) else if /i "%~1"=="release" (
  cargo build --release -p capsi
) else (
  cargo build -p capsi
)

