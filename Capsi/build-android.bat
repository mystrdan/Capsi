@echo off
:: Build the Capsi Android application through Flutter.
::
:: The application UI is Flutter and the native product logic is the shared
:: Rust core exposed through Capsi/flutter/native.
::
:: Usage:
::   build-android.bat
::
:: Generate the Android runner first when needed:
::   cd flutter && tool\bootstrap_platforms.ps1

setlocal
cd /d "%~dp0flutter"

if not exist "tool\bootstrap_platforms.ps1" (
  echo Capsi: Flutter Android bootstrap script is missing.
  exit /b 1
)

if not exist "android" (
  echo Capsi: Flutter Android runner has not been generated.
  echo Capsi: run tool\bootstrap_platforms.ps1 first.
  exit /b 1
)

flutter pub get
if errorlevel 1 exit /b 1

cargo build --manifest-path native\Cargo.toml --release
if errorlevel 1 exit /b 1

flutter build apk --release
exit /b %errorlevel%
