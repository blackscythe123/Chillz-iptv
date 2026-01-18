<#
Usage:
  .\bundle_libvlc.ps1 -Source "C:\Program Files\VideoLAN\VLC" -Configuration Release

This copies libvlc.dll, libvlccore.dll and the plugins folder from a VLC install
into the Flutter Windows build output for the specified configuration (Debug/Release).
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Source,

    [ValidateSet('Debug','Release')]
    [string]$Configuration = 'Release',

    [switch]$DryRun
)

function Write-Info([string]$m) { Write-Output "[INFO] $m" }
function Write-Err([string]$m) { Write-Output "[ERROR] $m" }

$srcLib = Join-Path $Source 'libvlc.dll'
$srcCore = Join-Path $Source 'libvlccore.dll'
$srcPlugins = Join-Path $Source 'plugins'

if (-not (Test-Path $srcLib) -or -not (Test-Path $srcCore)) {
    Write-Err "libvlc.dll or libvlccore.dll not found in source: $Source"
    exit 1
}

$buildRoot = Join-Path (Get-Location) "build\windows\x64\runner\$Configuration"
if (-not (Test-Path $buildRoot)) {
    Write-Err "Build output folder not found: $buildRoot";
    Write-Info "Run a build first: flutter build windows -d windows --$Configuration or flutter run -d windows"
    exit 1
}

$dstLib = Join-Path $buildRoot 'libvlc.dll'
$dstCore = Join-Path $buildRoot 'libvlccore.dll'
$dstPlugins = Join-Path $buildRoot 'plugins'

Write-Info "Source: $Source"
Write-Info "Destination: $buildRoot"

if ($DryRun) {
    Write-Info "Dry run: would copy $srcLib -> $dstLib"
    Write-Info "Dry run: would copy $srcCore -> $dstCore"
    if (Test-Path $srcPlugins) { Write-Info "Dry run: would copy plugins folder -> $dstPlugins" }
    exit 0
}

try {
    Copy-Item -Path $srcLib -Destination $dstLib -Force
    Copy-Item -Path $srcCore -Destination $dstCore -Force
    Write-Info "Copied libvlc DLLs"

    if (Test-Path $srcPlugins) {
        if (Test-Path $dstPlugins) { Remove-Item -Path $dstPlugins -Recurse -Force }
        Copy-Item -Path $srcPlugins -Destination $dstPlugins -Recurse -Force
        Write-Info "Copied plugins folder"
    } else {
        Write-Info "No plugins folder found in source; continuing"
    }

    Write-Info "libVLC files bundled successfully into $buildRoot"
} catch {
    Write-Err "Failed to copy: $_"
    exit 1
}
