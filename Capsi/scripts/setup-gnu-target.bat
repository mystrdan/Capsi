@echo off
:: Install the GNU (mingw-w64) target. Unlike the MSVC target, Rust ships its
:: own linker/CRT for windows-gnu, so a build can complete on machines that do
:: not have Visual Studio Build Tools installed.
:: Runs detached: logs to %TEMP%\capsi_gnu_target.log and writes a marker when done.
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
rustup target add x86_64-pc-windows-gnu > "%TEMP%\capsi_gnu_target.log" 2>&1
echo %ERRORLEVEL% > "%TEMP%\capsi_gnu_target.marker"