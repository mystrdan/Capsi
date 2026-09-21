# Runs Capsi's Rust test-suite.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/test-core.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/test-core.ps1 -Args '-p','capsi-core'
#
# On a normal Windows machine the MSVC toolchain and Visual Studio Build Tools
# are used. This script also knows about the GNU toolchain, whose mingw-w64
# `gcc`, `ld` and `dlltool` live in a `self-contained` folder that is not on
# PATH by default (without it `windows-sys` fails with "error calling dlltool").
param(
    [string[]] $Args = @('-p', 'capsi-core')
)

$ErrorActionPreference = 'Continue'

$repo = Split-Path -Parent $PSScriptRoot
$gnu = "$env:USERPROFILE\.rustup\toolchains\stable-x86_64-pc-windows-gnu"
$selfContained = "$gnu\lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained"

$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"

# Prefer the GNU toolchain only when the MSVC one cannot link (no link.exe),
# and only when the GNU toolchain is actually installed.
$useGnu = -not (Get-Command link.exe -ErrorAction SilentlyContinue) -and (Test-Path $gnu)
Push-Location $repo
if ($useGnu) {
    Write-Host 'Using the GNU toolchain (no MSVC linker found on this machine).' -ForegroundColor Yellow
    $env:PATH = "$selfContained;$gnu\bin;$env:PATH"
    # raw-dylib import libraries are produced with dlltool; rust's bundled copy
    # cannot run here, so Zig's llvm-dlltool is used instead. RUSTFLAGS is used
    # because it is guaranteed to reach rustc.
    $zigDlltool = 'd:\Capsi\.toolchain\zig-dlltool.bat'
    if (Test-Path $zigDlltool) {
        $env:RUSTFLAGS = "-C dlltool=$zigDlltool"
        $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_DLLTOOL = $zigDlltool
    }
    & rustup run stable-x86_64-pc-windows-gnu cargo test @Args
} else {
    & cargo test @Args
}
$code = $LASTEXITCODE
Pop-Location

exit $code