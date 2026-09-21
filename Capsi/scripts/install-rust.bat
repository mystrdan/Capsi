@echo off
:: Silent, non-interactive Rust toolchain install.
:: Logs to %TEMP%\rust_install.log and writes a marker when finished.
"%TEMP%\rustup-init.exe" -y --default-toolchain stable --profile minimal > "%TEMP%\rust_install.log" 2>&1
echo 1 > "%TEMP%\rust_done.marker"
