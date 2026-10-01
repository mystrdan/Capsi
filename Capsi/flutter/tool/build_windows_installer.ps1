# Builds the Capsi Windows installer: one MSI that puts a complete Capsi on a
# machine that has never seen the project.
#
# Run from anywhere: .\tool\build_windows_installer.ps1
#
# The input is the release bundle the Windows build wrote (capsi.exe, the
# Flutter engine DLL, capsi_ffi.dll and the data\ payload). The installer adds
# Start Menu and desktop shortcuts, an Add/Remove Programs entry published by
# Capsicom that links the product website, and the application icon.
#
# The release has no prerequisites to install first: the runner and the Rust
# bridge link the C runtime statically (windows/CMakeLists.txt and
# tool/build_windows.ps1), so the MSI only ever copies files.
#
# WiX is used from its portable release archive instead of an installed
# toolset. Building an installer must not require an elevated machine, and WiX
# v3 is the last line that ships standalone candle.exe/light.exe: v4 and later
# are .NET tools, which would add a .NET SDK to the build prerequisites.

param(
  [string]$BundleDirectory,
  [string]$OutputDirectory,
  [string]$Publisher = "Capsicom",
  [string]$ProductName = "Capsi",
  [string]$Website = "https://capsi.win",
  [switch]$ForceReinstallToolset
)

$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")

. (Join-Path $PSScriptRoot "build_steps.ps1")

# Never regenerate this: the upgrade code is what makes a new MSI an upgrade of
# an installed Capsi instead of a second copy installed beside it.
$UpgradeCode = "{4F9B7C3E-2A61-4E88-9C3D-B5A1E7D0F2C4}"

$WixVersion = "3.14.1"
$WixArchiveUrl = "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip"
# The toolchain is pinned like any other build input: an upstream release must
# not be able to change what this project ships inside a signed installer.
$WixArchiveSha256 = "6AC824E1642D6F7277D0ED7EA09411A508F6116BA6FAE0AA5F2C7DAA2FF43D31"

function Get-CapsiVersion {
  # pubspec.yaml is the single version source for the Flutter client; the MSI
  # product version has to move with it or upgrades stop being detected.
  $pubspec = Get-Content "pubspec.yaml" -Raw
  if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    throw "Could not read the Capsi version from pubspec.yaml."
  }
  return $Matches[1]
}

function Get-CapsiPort([string]$Name) {
  # The firewall rules below have to name the ports the applications actually
  # bind, and those are published by the Rust core. Reading them from there
  # keeps one source of truth: a rule opened for a port nothing listens on is
  # worse than no rule at all, because discovery then looks allowed through when
  # it is not.
  $lib = Join-Path (Get-Location).Path "..\crates\capsi-core\src\lib.rs"
  if (-not (Test-Path $lib)) {
    throw "The Rust core is missing at $lib, so the ports the installer opens cannot be read."
  }
  $text = [System.IO.File]::ReadAllText($lib)
  $match = [regex]::Match($text, "(?m)^pub const $Name\s*:\s*u16\s*=\s*(?<port>[0-9]+)\s*;")
  if (-not $match.Success) {
    throw "Could not read $Name from $lib."
  }
  return [int]$match.Groups["port"].Value
}

function Get-StableHash([string]$Seed) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try {
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Seed.ToLowerInvariant()))
  } finally {
    $md5.Dispose()
  }
  return ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Get-StableGuid([string]$Seed) {
  # MSI needs one component GUID per installed path and the same GUID on every
  # build of that path, otherwise an upgrade reinstalls or orphans the file.
  # Deriving them from the install path keeps them stable without a checked-in
  # table, which is the same trick WiX's own GUID="*" uses.
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try {
    $bytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Seed.ToLowerInvariant()))
  } finally {
    $md5.Dispose()
  }
  return "{" + ([System.Guid]::new([byte[]]$bytes)).ToString().ToUpperInvariant() + "}"
}

function Get-WixToolset {
  # Respect an installed WiX v3 when there is one, so a machine with the
  # toolset already present never downloads anything.
  $installed = @()
  if ($env:WIX) { $installed += (Join-Path $env:WIX "bin\candle.exe") }
  $installed += "${env:ProgramFiles(x86)}\WiX Toolset v3.14\bin\candle.exe"
  $installed += "${env:ProgramFiles(x86)}\WiX Toolset v3.11\bin\candle.exe"
  foreach ($candidate in $installed) {
    if ($candidate -and (Test-Path $candidate)) { return (Split-Path $candidate -Parent) }
  }

  # Otherwise cache the portable archive inside the ignored build tree, so a
  # rebuild does not download it again.
  $cache = Join-Path (Get-Location).Path "build/tools/wix-$WixVersion"
  if ($ForceReinstallToolset -and (Test-Path $cache)) {
    Remove-Item $cache -Recurse -Force
  }
  if (-not (Test-Path (Join-Path $cache "candle.exe"))) {
    Write-Host "Downloading the WiX $WixVersion toolset..."
    $archive = Join-Path ([System.IO.Path]::GetTempPath()) "capsi-wix-$WixVersion.zip"
    $progress = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    try {
      Invoke-WebRequest -Uri $WixArchiveUrl -OutFile $archive -UseBasicParsing -TimeoutSec 300
    } finally {
      $ProgressPreference = $progress
    }
    $actual = (Get-FileHash $archive -Algorithm SHA256).Hash
    if ($actual -ne $WixArchiveSha256) {
      Remove-Item $archive -Force -ErrorAction SilentlyContinue
      throw "The WiX $WixVersion archive has SHA-256 $actual and not the pinned $WixArchiveSha256. Refusing to build the installer with it."
    }
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    Expand-Archive -Path $archive -DestinationPath $cache -Force
    Remove-Item $archive -Force
  }
  return $cache
}

function Write-LicenseRtf([string]$Path, [string]$Version) {
  # WiX's license page renders RTF. Braces and backslashes are RTF syntax, so
  # the text below deliberately contains neither.
  $year = (Get-Date).Year
  $body = @(
    "\pard\f0\fs20\b Capsi $Version\b0\par",
    "\par",
    "Published by $Publisher\par",
    "Copyright (C) $year $Publisher. All rights reserved.\par",
    "$Website\par",
    "\par",
    "Capsi sends messages and files directly between your own devices. It needs no Capsi account and no Capsi server: nothing you send is routed through us.\par",
    "\par",
    "A device has to be accepted before it can talk to yours, and you can remove an accepted device at any time.\par",
    "\par",
    "Capsi is provided as is, without warranty of any kind. You are responsible for the devices you accept and for what you send to them.\par"
  ) -join "`r`n"
  $rtf = "{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Segoe UI;}}`r`n$body`r`n}`r`n"
  [System.IO.File]::WriteAllText($Path, $rtf, (New-Object System.Text.UTF8Encoding($false)))
}

function New-CapsiDirectory([string]$Name, [string]$Id) {
  return [pscustomobject]@{
    Name     = $Name
    Id       = $Id
    Files    = New-Object System.Collections.ArrayList
    Children = New-Object System.Collections.ArrayList
  }
}

$Version = Get-CapsiVersion
$ExecutableName = "capsi.exe"
$DiscoveryPort = Get-CapsiPort "DISCOVERY_PORT"
$ServicePort = Get-CapsiPort "TCP_SERVICE_PORT"

if (-not $BundleDirectory) { $BundleDirectory = "build/windows/x64/runner/Release" }
if (-not (Test-Path $BundleDirectory)) {
  throw "The Windows release bundle was not found at $BundleDirectory. Run tool\build_windows.ps1 first."
}
$bundleRoot = (Resolve-Path $BundleDirectory).Path

# A bundle missing any of these installs cleanly and then fails at startup,
# which is the worst possible installer bug. Refuse to build one.
$required = @(
  $ExecutableName,
  "flutter_windows.dll",
  "capsi_ffi.dll",
  "data\app.so",
  "data\icudtl.dat",
  "data\flutter_assets\NOTICES.Z"
)
foreach ($entry in $required) {
  if (-not (Test-Path (Join-Path $bundleRoot $entry))) {
    throw "$entry is missing from the bundle at $bundleRoot. Run tool\build_windows.ps1, which stages the bundle through the CMake INSTALL target, and try again."
  }
}

$payload = Get-ChildItem $bundleRoot -Recurse -File |
  Where-Object { $_.Extension -notin @(".pdb", ".lib", ".exp", ".ilk") } |
  ForEach-Object {
    [pscustomobject]@{
      Source   = $_.FullName
      Relative = $_.FullName.Substring($bundleRoot.Length + 1)
    }
  } |
  Sort-Object Relative

if ($payload.Count -lt 5) {
  throw "The bundle at $bundleRoot holds only $($payload.Count) files, which is not a complete Capsi release."
}

# Mirror the bundle's own directory structure inside the install folder.
$installRoot = New-CapsiDirectory -Name $ProductName -Id "INSTALLFOLDER"
foreach ($file in $payload) {
  $parts = $file.Relative -split "\\"
  $node = $installRoot
  for ($index = 0; $index -lt ($parts.Length - 1); $index++) {
    $child = $node.Children | Where-Object { $_.Name -eq $parts[$index] } | Select-Object -First 1
    if (-not $child) {
      # Directory ids come from the folder's own relative path, so adding a
      # folder to the bundle never renumbers - and therefore never re-guids -
      # the components that were already there.
      $child = New-CapsiDirectory -Name $parts[$index] `
        -Id ("CAPSI_DIR_" + (Get-StableHash ("dir|" + ($parts[0..$index] -join "/"))).Substring(0, 12))
      [void]$node.Children.Add($child)
    }
    $node = $child
  }
  [void]$node.Files.Add([pscustomobject]@{ Name = $parts[-1]; Source = $file.Source })
}

if (-not $OutputDirectory) { $OutputDirectory = "build" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$wixDirectory = Join-Path $OutputDirectory "wix"
if (Test-Path $wixDirectory) { Remove-Item $wixDirectory -Recurse -Force }
New-Item -ItemType Directory -Force -Path $wixDirectory | Out-Null

$licenseRtf = Join-Path $wixDirectory "CapsiLicense.rtf"
Write-LicenseRtf -Path $licenseRtf -Version $Version

$icon = Join-Path (Get-Location).Path "windows/runner/resources/app_icon.ico"
if (-not (Test-Path $icon)) {
  throw "The application icon is missing at $icon. Run tool\make_icons.ps1 first."
}

# ---------------------------------------------------------------------------
# Build the WiX source. Every component is generated from the bundle, so the
# installer always matches what the release build actually produced.
# ---------------------------------------------------------------------------
$componentIds = New-Object System.Collections.ArrayList

function Get-DirectoryXml {
  param([object]$Node, [int]$Depth)

  $pad = "      " + ("  " * $Depth)
  $lines = New-Object System.Collections.ArrayList
  [void]$lines.Add("$pad<Directory Id=`"$($Node.Id)`" Name=`"$($Node.Name)`">")

  foreach ($file in ($Node.Files | Sort-Object Name)) {
    # One component per file. MSI identifies a component by the path of its key
    # file, which is what lets an upgrade replace exactly the files that changed
    # and leave the rest alone.
    $seed = "capsi|$($Node.Id)|$($file.Name)"
    $hash = Get-StableHash $seed
    $componentId = "cmp_" + $hash.Substring(0, 32)
    [void]$componentIds.Add($componentId)
    [void]$lines.Add("$pad  <Component Id=`"$componentId`" Guid=`"$(Get-StableGuid $seed)`">")
    [void]$lines.Add("$pad    <File Id=`"fil_$($hash.Substring(0, 32))`" Source=`"$($file.Source)`" KeyPath=`"yes`" />")
    if ($file.Name -eq $ExecutableName) {
      # Windows Firewall silently drops inbound traffic for a program that has
      # no rule, and both halves of Capsi are inbound: a peer's discovery
      # broadcast arrives on the UDP port, and its messages and files arrive on
      # the TCP one. Without these rules a fresh install can never be found -
      # every device shows an empty Nearby list while nothing else looks wrong.
      #
      # Each rule names the executable as well as the port, so nothing else on
      # the machine is opened up, and both are scoped to the local subnet
      # because Capsi's peers are only ever on the same network. All profiles
      # are covered because a home or office Wi-Fi network is just as often
      # marked Public as Private, and a rule for the wrong profile does nothing.
      $fileId = "fil_" + $hash.Substring(0, 32)
      [void]$lines.Add("$pad    <firewall:FirewallException Id=`"fw_Discovery`"")
      [void]$lines.Add("$pad        Name=`"$ProductName discovery (UDP $DiscoveryPort)`"")
      [void]$lines.Add("$pad        Description=`"Lets other devices on this network find $ProductName.`"")
      [void]$lines.Add("$pad        Program=`"[#$fileId]`" Port=`"$DiscoveryPort`" Protocol=`"udp`" Scope=`"localSubnet`" Profile=`"all`" />")
      [void]$lines.Add("$pad    <firewall:FirewallException Id=`"fw_Service`"")
      [void]$lines.Add("$pad        Name=`"$ProductName messages and files (TCP $ServicePort)`"")
      [void]$lines.Add("$pad        Description=`"Lets trusted devices send messages and files to $ProductName.`"")
      [void]$lines.Add("$pad        Program=`"[#$fileId]`" Port=`"$ServicePort`" Protocol=`"tcp`" Scope=`"localSubnet`" Profile=`"all`" />")
    }
    [void]$lines.Add("$pad  </Component>")
  }

  foreach ($child in ($Node.Children | Sort-Object Name)) {
    [void]$lines.Add((Get-DirectoryXml -Node $child -Depth ($Depth + 1)))
  }

  [void]$lines.Add("$pad</Directory>")
  return ($lines -join "`r`n")
}

$menuComponentId = "cmp_ProgramMenuShortcut"
$desktopComponentId = "cmp_DesktopShortcut"
$menuComponentGuid = Get-StableGuid "capsi|shortcut|program-menu"
$desktopComponentGuid = Get-StableGuid "capsi|shortcut|desktop"

# The tree walk is what assigns component ids, so it has to run before the
# feature that references them is assembled.
$installTree = Get-DirectoryXml -Node $installRoot -Depth 2

$featureRefs = New-Object System.Collections.ArrayList
foreach ($id in (@($menuComponentId, $desktopComponentId) + $componentIds)) {
  [void]$featureRefs.Add("      <ComponentRef Id=`"$id`" />")
}

$productWxs = @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/build_windows_installer.ps1 from the Windows release
     bundle. Do not edit this file: change the script and rebuild instead. -->
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi"
     xmlns:firewall="http://schemas.microsoft.com/wix/FirewallExtension">
  <Product Id="*" Name="$ProductName" Language="1033" Version="$Version"
           Manufacturer="$Publisher" UpgradeCode="$UpgradeCode">
    <Package Id="*" Keywords="Installer" Description="Capsi - messages and files, device to device."
             Manufacturer="$Publisher" InstallerVersion="500" Compressed="yes"
             InstallScope="perMachine" Platform="x64" />

    <!-- A rebuild of the same version is an upgrade, not a second copy beside it. -->
    <MajorUpgrade AllowSameVersionUpgrades="yes"
                  DowngradeErrorMessage="A newer version of Capsi is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <!-- Add/Remove Programs shows Capsi as published by $Publisher and links the
         product website. -->
    <Property Id="ARPPRODUCTICON" Value="CapsiIcon" />
    <Property Id="ARPURLINFOABOUT" Value="$Website" />
    <Property Id="ARPHELPLINK" Value="$Website" />
    <Property Id="WIXUI_INSTALLDIR" Value="INSTALLFOLDER" />

    <Condition Message="Capsi needs 64-bit Windows.">VersionNT64</Condition>
    <Icon Id="CapsiIcon" SourceFile="$icon" />
    <WixVariable Id="WixUILicenseRtf" Value="$licenseRtf" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
$installTree
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="CapsiProgramMenuFolder" Name="$ProductName">
          <Component Id="$menuComponentId" Guid="$menuComponentGuid">
            <Shortcut Id="CapsiStartMenuShortcut" Name="$ProductName"
                      Description="Capsi - messages and files, device to device."
                      Target="[INSTALLFOLDER]capsi.exe" WorkingDirectory="INSTALLFOLDER"
                      Icon="CapsiIcon" />
            <RemoveFolder Id="RemoveCapsiProgramMenuFolder" On="uninstall" />
            <RegistryValue Root="HKCU" Key="Software\$Publisher\$ProductName"
                           Name="StartMenuShortcut" Type="integer" Value="1" KeyPath="yes" />
          </Component>
        </Directory>
      </Directory>
      <Directory Id="DesktopFolder">
        <Component Id="$desktopComponentId" Guid="$desktopComponentGuid">
          <Shortcut Id="CapsiDesktopShortcut" Name="$ProductName"
                    Description="Capsi - messages and files, device to device."
                    Target="[INSTALLFOLDER]capsi.exe" WorkingDirectory="INSTALLFOLDER"
                    Icon="CapsiIcon" />
          <RegistryValue Root="HKCU" Key="Software\$Publisher\$ProductName"
                         Name="DesktopShortcut" Type="integer" Value="1" KeyPath="yes" />
        </Component>
      </Directory>
    </Directory>

    <Feature Id="Capsi" Title="$ProductName" Level="1" Display="expand">
$($featureRefs -join "`r`n")
    </Feature>

    <UIRef Id="WixUI_InstallDir" />
  </Product>
</Wix>
"@

$wxsPath = Join-Path $wixDirectory "Capsi.wxs"
[System.IO.File]::WriteAllText($wxsPath, $productWxs, (New-Object System.Text.UTF8Encoding($false)))

$toolset = Get-WixToolset
$candle = Join-Path $toolset "candle.exe"
$light = Join-Path $toolset "light.exe"
$wixObj = Join-Path $wixDirectory "Capsi.wixobj"
$msi = Join-Path $OutputDirectory "$ProductName-$Version-x64.msi"

Write-Host "Compiling the installer definition..."
Invoke-Native $candle @("-nologo", "-arch", "x64", "-ext", "WixFirewallExtension", "-out", $wixObj, $wxsPath) "Compiling the WiX source failed"

Write-Host "Linking $([System.IO.Path]::GetFileName($msi))..."
# Two validation warnings are suppressed on purpose:
#   ICE60 - the engine DLL carries a version resource with no language. Capsi
#           installs a private copy under its own folder and shares nothing, so
#           the language column has no bearing on upgrades or repair.
#   ICE61 - this product may remove an installed copy of its own version, which
#           is exactly what AllowSameVersionUpgrades asks for: rebuilding a
#           version has to be able to replace the build already on the machine.
Invoke-Native $light @("-nologo", "-cultures:en-us", "-sice:ICE60", "-sice:ICE61", "-ext", "WixUIExtension", "-ext", "WixFirewallExtension", "-out", $msi, $wixObj) "Linking the Capsi installer failed"

function Get-MsiProperty([string]$Path, [string]$Name) {
  # Reading the built database back is the only way to prove what the installer
  # actually declares, rather than what the script meant to declare.
  $installer = New-Object -ComObject WindowsInstaller.Installer
  $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($Path, 0))
  $query = "SELECT ``Value`` FROM ``Property`` WHERE ``Property``='" + $Name + "'"
  $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, @($query))
  [void]$view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
  $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
  if (-not $record) { return $null }
  return $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, @(1))
}

function Get-MsiRowCount([string]$Path, [string]$Query) {
  # Same database as Get-MsiProperty, but for proving a table actually has rows.
  # The firewall rules are what make a fresh install findable on the network, so
  # they are checked as built rather than assumed from the generated WiX source.
  $installer = New-Object -ComObject WindowsInstaller.Installer
  $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($Path, 0))
  $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, @($Query))
  [void]$view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
  $count = 0
  while ($view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)) {
    $count++
  }
  return $count
}

$declaredPublisher = Get-MsiProperty $msi "Manufacturer"
$declaredProduct = Get-MsiProperty $msi "ProductName"
$declaredVersion = Get-MsiProperty $msi "ProductVersion"
$declaredWebsite = Get-MsiProperty $msi "ARPURLINFOABOUT"

if ($declaredPublisher -ne $Publisher) {
  throw "The installer publishes as '$declaredPublisher' instead of '$Publisher'."
}
if ($declaredProduct -ne $ProductName) {
  throw "The installer installs '$declaredProduct' instead of '$ProductName'."
}
if ($declaredVersion -ne $Version) {
  throw "The installer carries version '$declaredVersion' instead of '$Version'."
}
if ($declaredWebsite -ne $Website) {
  throw "The installer links '$declaredWebsite' instead of '$Website'."
}

try {
  # WiX's firewall extension stages its rules in its own WixFirewallException
  # table and copies them into the standard FirewallException table at install
  # time, so this is the table to look in.
  $firewallRules = Get-MsiRowCount $msi "SELECT ``Name`` FROM ``WixFirewallException``"
} catch {
  throw "The installer has no WixFirewallException table, so the discovery and transfer rules were not linked in. The WixFirewallExtension was probably not passed to candle and light. ($($_.Exception.Message))"
}
if ($firewallRules -lt 2) {
  throw "The installer declares $firewallRules firewall exception(s) instead of the two Capsi needs, so a fresh install could not be found on the network."
}

Write-Host ""
Write-Host "Capsi Windows installer is ready:"
Write-Host "  $msi ($([math]::Round((Get-Item $msi).Length / 1MB, 1)) MB)"
Write-Host "  $declaredProduct $declaredVersion by $declaredPublisher - $declaredWebsite"
Write-Host "  Installs $($payload.Count) files into Program Files\$ProductName, with Start Menu and desktop shortcuts."
Write-Host "  Opens $firewallRules firewall rule(s) for capsi.exe on the local subnet: UDP $DiscoveryPort for discovery, TCP $ServicePort for messages and files."

