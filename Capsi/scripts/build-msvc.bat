@echo off
:: Build the Capsi desktop app for Windows (MSVC x86_64).
::
:: Visual Studio 18 Community is installed on this machine, so the MSVC
:: toolchain links natively. `rc.exe` from the Windows 10 SDK embeds the
:: icon, manifest and version metadata (publisher CAPSICOM).
::
:: Usage:
::   scripts\build-msvc.bat            - debug build for local testing
::   scripts\build-msvc.bat release    - release exe (no installer)
::   scripts\build-msvc.bat bundle     - release exe + NSIS/MSI installers
::                                       (requires Tauri CLI + NSIS + WiX)
set "VCVARS=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
if exist "%VCVARS%" call "%VCVARS%" >NUL
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
cd /d "%~dp0.."
if /i "%~1"=="bundle" (
  cargo tauri build
) else if /i "%~1"=="release" (
  cargo build --release -p capsi
) else (
  cargo build -p capsi
)
