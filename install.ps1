# Kivo Workspace — Windows Terminal Installer
# Purpose: Downloads the latest pre-compiled standalone production EXE from GitHub and creates Start Menu & Desktop shortcuts.

$ErrorActionPreference = "Stop"

# --- Configuration ---
$GitHubRepo = "thepriyanshumishra/The-Threadrippers_edgeminds2026internship"

Write-Host "=========================================" -ForegroundColor Green
Write-Host "      Installing Kivo Workspace          " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

Write-Host "Checking latest release from GitHub ($GitHubRepo)..."

# Fetch release JSON
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ReleaseUrl = "https://api.github.com/repos/$GitHubRepo/releases/latest"

try {
    $ReleaseInfo = Invoke-RestMethod -Uri $ReleaseUrl -UseBasicParsing
} catch {
    Write-Error "Error: Could not connect to GitHub API. Please check your internet connection or repository path."
    exit 1
}

# Find download URL for Windows x64 executable asset
$Assets = $ReleaseInfo.assets
$DownloadAsset = $null
foreach ($Asset in $Assets) {
    if ($Asset.name -like "*Windows*" -and $Asset.name -like "*.exe") {
        $DownloadAsset = $Asset
        break
    }
}

if (-not $DownloadAsset) {
    # Try general exe fallback
    foreach ($Asset in $Assets) {
        if ($Asset.name -like "*.exe") {
            $DownloadAsset = $Asset
            break
        }
    }
}

if (-not $DownloadAsset) {
    Write-Error "Error: Could not find Windows release executable (.exe) on GitHub Releases page."
    Write-Host "Please ensure the GitHub Action has completed compiling and uploaded the packages." -ForegroundColor Yellow
    exit 1
}

$Filename = $DownloadAsset.name
$DownloadUrl = $DownloadAsset.browser_download_url

$InstallDir = Join-Path $env:LOCALAPPDATA "KivoWorkspace"
if (Test-Path $InstallDir) {
    Write-Host "Removing previous installation folder..." -ForegroundColor Yellow
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$ExePath = Join-Path $InstallDir "KivoWorkspace.exe"

Write-Host "Downloading release executable: $Filename..." -ForegroundColor Green
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ExePath -UseBasicParsing

# --- Create Shortcuts ---
Write-Host "Creating application shortcuts..." -ForegroundColor Yellow

$WshShell = New-Object -ComObject WScript.Shell

# 1. Desktop Shortcut
$DesktopPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
$DesktopShortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "Kivo Workspace.lnk"))
$DesktopShortcut.TargetPath = $ExePath
$DesktopShortcut.WorkingDirectory = $InstallDir
$DesktopShortcut.Save()

# 2. Start Menu Shortcut
$StartMenuPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Programs)
$StartMenuShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuPath "Kivo Workspace.lnk"))
$StartMenuShortcut.TargetPath = $ExePath
$StartMenuShortcut.WorkingDirectory = $InstallDir
$StartMenuShortcut.Save()

Write-Host "`nKivo Workspace installed successfully!" -ForegroundColor Green
Write-Host "Start Menu and Desktop shortcuts have been created. You can search for 'Kivo Workspace' in your Start menu or launch it from your Desktop." -ForegroundColor Green
