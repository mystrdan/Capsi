@echo off
:: Build scripts\rc-preproc\main.rs and install it as `gcc.exe` inside the
:: toolchain, which is where GNU `windres` goes looking for the preprocessor it
:: runs a `.rc` file through. Read scripts\rc-preproc\main.rs for the why.
::
:: Idempotent: re-run it after changing the shim's source. Any `gcc.exe` that
:: was already there is moved aside (once) instead of being overwritten.
::
:: Runs detached: logs to %TEMP%\capsi_rc_preproc.log and writes a marker when done.
setlocal
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
set "SC=%USERPROFILE%\.rustup\toolchains\stable-x86_64-pc-windows-gnu\lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained"
set "LOG=%TEMP%\capsi_rc_preproc.log"

if not exist "%SC%\" (
    echo Toolchain directory not found: "%SC%" > "%LOG%"
    echo Install the GNU target first: rustup target add x86_64-pc-windows-gnu >> "%LOG%"
    echo 1 > "%TEMP%\capsi_rc_preproc.marker"
    exit /b 1
)

if exist "%SC%\gcc.exe" if not exist "%SC%\gcc.exe.before-capsi-shim" (
    move "%SC%\gcc.exe" "%SC%\gcc.exe.before-capsi-shim" >nul
)

rustc +stable-x86_64-pc-windows-gnu --target x86_64-pc-windows-gnu -O -o "%SC%\gcc.exe" "%~dp0rc-preproc\main.rs" > "%LOG%" 2>&1
set "STATUS=%ERRORLEVEL%"

if not "%STATUS%"=="0" (
    type "%LOG%"
    echo %STATUS% > "%TEMP%\capsi_rc_preproc.marker"
    exit /b %STATUS%
)

"%SC%\gcc.exe" --version >> "%LOG%" 2>&1
echo %STATUS% > "%TEMP%\capsi_rc_preproc.marker"
endlocal
