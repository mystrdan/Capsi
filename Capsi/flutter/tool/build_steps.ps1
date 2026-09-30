# Shared helper for the Capsi build scripts. Dot-source it:
#   . (Join-Path $PSScriptRoot "build_steps.ps1")
#
# Flutter, cargo, CMake and Gradle report progress and warnings on stderr.
# PowerShell promotes every line a native tool writes there into an error record,
# so under $ErrorActionPreference = "Stop" a build that is going perfectly aborts
# on its first progress message - silently, when the output is redirected into a
# log. Native steps are therefore judged by the only signal that actually means
# failure: the process exit code.
#
# Call it with the tool name and a pre-expanded argument array:
#   Invoke-Native "cargo" @("build", "--release") "Rust build failed"
# The array travels by value, so there is no caller-scope capture to get wrong
# (script blocks run in the helper's scope, where caller locals like $ndkArgs
# would resolve empty or stale).
function Invoke-Native {
  param(
    [string]$Command,
    [string[]]$Arguments = @(),
    [string]$Failure
  )
  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    # Surface native stderr as ordinary build text: without this, Windows
    # PowerShell turns each line into a NativeCommandError record.
    # NOTE: the step must run as a plain statement, not the head of a pipeline.
    # `& $Command @Arguments 2>&1 | ForEach-Object { ... }` runs the step in a
    # child scope, so $LASTEXITCODE read back here belongs to ForEach-Object
    # (always 0) and a failed build step would silently pass. Collect first,
    # then print.
    # $LASTEXITCODE is reset first: a step that never launches a process leaves
    # it untouched, so without this a stale code from an earlier native call
    # would fail (or mask) the current step.
    $global:LASTEXITCODE = 0
    $output = & $Command @Arguments 2>&1
    foreach ($line in $output) {
      if ($line -is [System.Management.Automation.ErrorRecord]) { $line.Exception.Message } else { $line }
    }
    # The tool ran as a plain statement (not the head of a pipeline) and the
    # loop above is a language keyword, so neither overwrote it - $LASTEXITCODE
    # here is the native command's exit code.
    if ($LASTEXITCODE -ne 0) {
      throw "$Failure (exit code $LASTEXITCODE)"
    }
  } finally {
    $ErrorActionPreference = $previous
  }
}
