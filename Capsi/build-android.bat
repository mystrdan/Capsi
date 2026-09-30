@echo off
:: Build the Capsi Android application through Flutter.
::
:: The application UI is Flutter and the native product logic is the shared
:: Rust core exposed through Capsi/flutter/native. The Rust core is
:: cross-compiled with cargo-ndk for arm64-v8a, armeabi-v7a and x86_64 and
:: packaged into the runner as jniLibs before the APK is assembled.
::
:: Usage:
::   build-android.bat
::
:: Generate the Android runner first when needed:
::   cd flutter && tool\bootstrap_platforms.ps1

setlocal
cd /d "%~dp0flutter"

if not exist "tool\build_android.ps1" (
  echo Capsi: Flutter Android build script is missing.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "tool\build_android.ps1"
exit /b %errorlevel%
