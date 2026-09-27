@echo off
:: Build the Capsi mobile app (Android APK) from the same source as desktop.
::
:: Same Rust core + same frontend, repackaged by Tauri for Android. Desktop
:: behaviour is unchanged.
::
:: Requirements (one-time):
::   1. Android Studio (SDK + NDK) with ANDROID_HOME / NDK_HOME set.
::   2. Rust Android targets:
::        rustup target add aarch64-linux-android armv7-linux-androideabi ^
::          x86_64-linux-android i686-linux-android
::   3. Tauri CLI v2:  cargo install tauri-cli --version "^2" --locked
::   4. Java 17+ on PATH.
::   5. First run only:  build-android.bat init
::
:: Usage:
::   build-android.bat init     create Capsi\src-tauri\gen\android
::   build-android.bat apk      debug APK for local testing
::   build-android.bat release  signed release APK (needs keystore env)
::
:: `release` signs with the keystore from these env vars:
::   CAPSI_KEYSTORE, CAPSI_KEY_ALIAS, CAPSI_KEYSTORE_PASSWORD, CAPSI_KEY_PASSWORD
setlocal
cd /d "%~dp0src-tauri"

if /i "%~1"=="init" (
  cargo tauri android init
  exit /b %errorlevel%
)

set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
if exist "%USERPROFILE%\.capsi-tools\bin\tauri.cmd" set "PATH=%USERPROFILE%\.capsi-tools\bin;%PATH%"

if /i "%~1"=="release" (
  if not defined CAPSI_KEYSTORE (
    echo Capsi: set CAPSI_KEYSTORE, CAPSI_KEY_ALIAS, CAPSI_KEYSTORE_PASSWORD,
    echo Capsi: and CAPSI_KEY_PASSWORD to sign the release APK.
    exit /b 1
  )
  rem Release APKs always ship a fresh patch version first.
  rem Debug APKs intentionally keep the version stable.
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts/bump-version.ps1" patch
  if errorlevel 1 exit /b 1
  cargo tauri android build --apk --target aarch64 -- ^
    --keystore "%CAPSI_KEYSTORE%" ^
    --keystore-alias "%CAPSI_KEY_ALIAS%" ^
    --keystore-password "%CAPSI_KEYSTORE_PASSWORD%" ^
    --key-password "%CAPSI_KEY_PASSWORD%"
) else (
  cargo tauri android build --apk --debug --target aarch64
)
