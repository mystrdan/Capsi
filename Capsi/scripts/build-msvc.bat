@echo off
:: Build the Capsi Windows application through the Flutter client.
::
:: The application UI is Flutter and the native product logic is the shared
:: Rust core exposed through Capsi/flutter/native.
::
:: Usage:
::   scripts\build-msvc.bat
::   scripts\build-msvc.bat release
::
:: Run from any directory.

setlocal
cd /d "%~dp0..\flutter"

if not exist "tool\build_windows.ps1" (
  echo Capsi: Flutter Windows build script is missing.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "tool\build_windows.ps1"
exit /b %errorlevel%
