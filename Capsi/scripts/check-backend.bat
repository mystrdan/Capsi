@echo off
:: Run `cargo check` for the Tauri backend, logging to a file and writing a
:: completion marker when done. Run detached so it survives the 30s shell limit.
set "CARGO=%USERPROFILE%\.cargo\bin"
set "PATH=%CARGO%;%PATH%"
cd /d "d:\Capsi\Capsi\src-tauri"
cargo check > "%TEMP%\capsi_cargo_check.log" 2>&1
echo %ERRORLEVEL% > "%TEMP%\capsi_cargo_done.marker"
