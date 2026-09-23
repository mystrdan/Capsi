<#
Capsi - install the mingw-w64 binutils the GNU toolchain needs but does not ship.

`rustup`'s x86_64-pc-windows-gnu toolchain brings a linker, the CRT objects and
the import libraries, plus a `gcc` that warns next to itself that it is only good
for linking - but it has no assembler for `dlltool` to call and no `windres` at
all. Capsi's build needs both:

  * `dlltool` converts the `.def` files rustc emits for `raw-dylib` links into
    import libraries, assembling them with `as`. Without it, every crate that
    names a Windows API - `getrandom`, `parking_lot_core`, `windows-sys` - fails
    to build. Rusts's copy of `dlltool` can run but has nothing to run.
  * `windres` compiles the `.rc` file `tauri-build` generates, which is how the
    icon, the manifest and the version metadata get into the executable. Its
    preprocessor is `scripts\install-rc-preproc.bat`'s job.

This script downloads the mingw-w64 build of them from the MSYS2 mirrors and
installs the programs, together with the runtime DLLs they link against, into
the toolchain's `bin\self-contained` directory: that is the directory rustc
already asks for `dlltool` in, and the first place Windows looks for a program's
DLLs. Anything it would overwrite is kept alongside as `*.before-capsi-binutils`
- in particular rustup's own `dlltool.exe` and `ld.exe`, which `rustup component
remove rust-mingw-x86_64-pc-windows-gnu` and `add` restores.

Safe to re-run; prints what it installed.

Usage:  powershell -ExecutionPolicy Bypass -File scripts\install-gnu-binutils.ps1
#>

$ErrorActionPreference = 'Stop'
# Without this, Invoke-WebRequest's progress bar makes these downloads crawl on
# Windows PowerShell.
$ProgressPreference = 'SilentlyContinue'

$selfContained = Join-Path $env:USERPROFILE (
    '.rustup\toolchains\stable-x86_64-pc-windows-gnu\lib\rustlib\x86_64-pc-windows-gnu\bin\self-contained')

if (-not (Test-Path $selfContained)) {
    Write-Error "Toolchain directory not found: $selfContained`nAdd the target first: rustup target add x86_64-pc-windows-gnu"
}

if (-not (Get-Command tar.exe -ErrorAction SilentlyContinue)) {
    Write-Error 'tar.exe is required (it ships with Windows 10 1803+ and reads the .zst packages directly).'
}

# Each package and the reason Capsi's build needs a file from it. `Members` are
# paths inside the package; the binutils archive is taken whole because which of
# its programs a future build step wants is not worth predicting.
$mirror = 'https://mirror.msys2.org/mingw/mingw64'
$packages = @(
    @{
        Name = 'mingw-w64-x86_64-binutils-2.47-3-any.pkg.tar.zst'
        Why = 'as, dlltool, windres, ld, ar and the rest of binutils'
        Members = @()   # empty = everything under mingw64/bin
    },
    @{
        Name = 'mingw-w64-x86_64-gettext-runtime-1.0-1-any.pkg.tar.zst'
        Why = 'libintl-8.dll, linked by every binutils program'
        Members = @('mingw64/bin/libintl-8.dll')
    },
    @{
        Name = 'mingw-w64-x86_64-libiconv-1.19-1-any.pkg.tar.zst'
        Why = 'libiconv-2.dll and libcharset-1.dll, linked by libintl'
        Members = @('mingw64/bin/libiconv-2.dll', 'mingw64/bin/libcharset-1.dll')
    },
    @{
        Name = 'mingw-w64-x86_64-zlib-1.3.2-2-any.pkg.tar.zst'
        Why = 'zlib1.dll, linked by the binutils readers'
        Members = @('mingw64/bin/zlib1.dll')
    },
    @{
        Name = 'mingw-w64-x86_64-zstd-1.5.7-2-any.pkg.tar.zst'
        Why = 'libzstd.dll, linked by the binutils readers'
        Members = @('mingw64/bin/libzstd.dll')
    }
)

$work = Join-Path $env:TEMP 'capsi-gnu-binutils'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item $work -ItemType Directory | Out-Null

# Fetch one package. MSYS2's mirrors serve the small packages quickly but
# occasionally stall part way through a large one, so curl is used when it is
# available: it can be told to abandon a transfer that has stopped moving and to
# try again. `Invoke-WebRequest` covers machines without curl (Windows 10 1803+
# ships it in System32).
function Get-Msys2Package {
    param([string]$Url, [string]$Destination)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($curl) {
            # Give up on a transfer that drops below 1 KB/s for 30 seconds, and
            # retry those aborts as well as the ordinary network errors.
            & $curl.Source -L --fail --silent --show-error `
                --retry 3 --retry-all-errors `
                --speed-limit 1024 --speed-time 30 `
                -o $Destination $Url
            if ($LASTEXITCODE -eq 0) { return }
        } else {
            try {
                Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 900
                return
            } catch {
                Write-Host "  $($_.Exception.Message)"
            }
        }

        Write-Host "  attempt $attempt did not finish, retrying"
        Remove-Item $Destination -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-Error "could not download $Url"
}

$installed = @()
foreach ($package in $packages) {
    $archive = Join-Path $work $package.Name
    Write-Host "downloading $($package.Name)"
    Get-Msys2Package -Url "$mirror/$($package.Name)" -Destination $archive

    $unpacked = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($package.Name))
    New-Item $unpacked -ItemType Directory | Out-Null
    & tar.exe -xf $archive -C $unpacked
    if ($LASTEXITCODE -ne 0) { Write-Error "tar failed on $($package.Name)" }

    $bin = Join-Path $unpacked 'mingw64\bin'
    if ($package.Members.Count -gt 0) {
        $sources = $package.Members | ForEach-Object { Join-Path $unpacked ($_ -replace '/', '\') }
    } else {
        # binutils: every program it ships, and nothing else from the archive.
        $sources = (Get-ChildItem $bin -Filter *.exe).FullName
    }

    foreach ($source in $sources) {
        if (-not (Test-Path $source)) { Write-Error "missing from package: $source" }

        $destination = Join-Path $selfContained (Split-Path $source -Leaf)
        if (Test-Path $destination) {
            if ((Get-FileHash $source).Hash -eq (Get-FileHash $destination).Hash) {
                continue   # already installed by an earlier run
            }
            $backup = "$destination.before-capsi-binutils"
            if (-not (Test-Path $backup)) { Move-Item $destination $backup }
        }
        Copy-Item $source $destination -Force
        $installed += Split-Path $source -Leaf
    }
    Write-Host "  $($package.Why)"
}

Remove-Item $work -Recurse -Force

Write-Host ''
Write-Host "installed into $selfContained :"
$installed | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host 'Next: scripts\install-rc-preproc.bat, then scripts\build-gnu.bat'
