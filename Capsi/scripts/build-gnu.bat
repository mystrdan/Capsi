@echo off
:: Build the Capsi desktop app with the GNU toolchain.
::
:: The GNU target is the one that can link without Visual Studio, and this
:: machine has no `link.exe`, so the toolchain is named explicitly - the default
:: one is MSVC.
::
:: Two things have to be on PATH, and both of them live inside the toolchain:
::   * its binutils - `dlltool` for the `raw-dylib` import libraries rustc
::     generates for the Windows API, and `windres`, which `tauri-build` uses to
::     embed the icon, manifest and version metadata;
::   * the resource-file preprocessor shim installed by
::     scripts\install-rc-preproc.bat, because `windres` runs a `.rc` file
::     through `gcc -E` and a GNU Rust toolchain has no C compiler.
::
:: Runs detached: logs to %TEMP%\capsi_build.log and writes a marker when done.
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
set "SELF_CONTAINED=%USERPROFILE%\.rustup\toolchains\stable-x86_64-pc-windows-gnu\lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained"
set "PATH=%SELF_CONTAINED%;%PATH%"
set "CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=%SELF_CONTAINED%\x86_64-w64-mingw32-gcc.exe"
cd /d "%~dp0.."
cargo +stable-x86_64-pc-windows-gnu build -p capsi > "%TEMP%\capsi_build.log" 2>&1
echo %ERRORLEVEL% > "%TEMP%\capsi_build_done.marker"
