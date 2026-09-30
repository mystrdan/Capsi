# Regenerates every platform icon set from the official Capsi logo.
#
# `flutter create` drops the stock Flutter icon into the runner, so the logo has
# to be stamped in afterwards: this runs scripts/make-icons.mjs, which writes the
# Android launcher set (legacy + adaptive + launch screen) and the Windows
# .ico/PNG set used by the runner.

$ErrorActionPreference = "Stop"

$flutter = Split-Path -Parent $PSScriptRoot
$generator = Join-Path (Split-Path -Parent $flutter) "scripts/make-icons.mjs"

# Loaded after the path setup: the shared helper only provides Invoke-Native,
# which is used for the node call below.
. (Join-Path $PSScriptRoot "build_steps.ps1")

if (-not (Test-Path $generator)) {
  throw "Capsi icon generator is missing: $generator"
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  if (Test-Path (Join-Path $flutter "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml")) {
    Write-Warning "Node.js is not on PATH; keeping the committed Capsi icons instead of regenerating them."
    return
  }
  throw "Node.js is required to stamp the Capsi logo into the generated runner icons."
}

Write-Host "Stamping the Capsi logo into the platform icon sets..."
Invoke-Native "node" @($generator) "scripts/make-icons.mjs failed"
