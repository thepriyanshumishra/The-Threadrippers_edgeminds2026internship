# Kivo Workspace — Development Setup & Launcher for Windows
# Purpose: Installs prerequisites, sets up venv, and launches frontend + backend concurrently.

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Green
Write-Host "   Kivo Workspace Developer Launcher     " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green

# --- 1. Prerequisite Checks ---
Write-Host "`n[1/4] Checking prerequisites..." -ForegroundColor Yellow

# Check Flutter
$flutterCheck = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCheck) {
    Write-Error "Error: Flutter SDK is not installed or not in PATH. Please install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
}
Write-Host "Flutter: Detected" -ForegroundColor Green

# Check Python
$pythonCheck = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCheck) {
    Write-Error "Error: Python is not installed or not in PATH. Please install Python 3.11 or 3.12: https://www.python.org/downloads/"
    exit 1
}

# Verify Python Version is 3
$pythonVer = python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
$majorVer = [int]$pythonVer.Split('.')[0]

if ($majorVer -lt 3) {
    Write-Error "Error: Python 3 is required. Detected version: $pythonVer"
    exit 1
}
Write-Host "Python $pythonVer: Detected" -ForegroundColor Green

# --- 2. Backend Environment Setup ---
Write-Host "`n[2/4] Setting up Python virtual environment..." -ForegroundColor Yellow

Set-Location "$PSScriptRoot\backend"

if (-not (Test-Path "venv")) {
    Write-Host "Creating virtual environment..."
    python -m venv venv
}

# Activate virtual environment
& "venv\Scripts\Activate.ps1"

Write-Host "Installing backend dependencies (this may take a minute)..."
python -m pip install --upgrade pip
pip install -r requirements.txt
pip install -r requirements-dev.txt
Set-Location "$PSScriptRoot"

# --- 3. Frontend Packages Setup ---
Write-Host "`n[3/4] Installing Dart packages..." -ForegroundColor Yellow
Set-Location "$PSScriptRoot\frontend"
flutter pub get
Set-Location "$PSScriptRoot"

# --- 4. Launching Servers ---
Write-Host "`n[4/4] Starting Kivo Workspace..." -ForegroundColor Yellow

# Start FastAPI backend in the background
Write-Host "Launching local RAG API server in background..."
Set-Location "$PSScriptRoot\backend"
$backendProcess = Start-Process venv\Scripts\python.exe -ArgumentList "-m", "uvicorn", "main:app", "--port", "8000" -PassThru -NoNewWindow

# Wait 2 seconds for backend to initialize
Start-Sleep -Seconds 2

try {
    # Launch Flutter frontend in the foreground
    Write-Host "Launching Flutter app..." -ForegroundColor Green
    Set-Location "$PSScriptRoot\frontend"
    flutter run
}
finally {
    # Cleanup backend process on exit
    if ($backendProcess) {
        Write-Host "`nStopping backend server (PID: $($backendProcess.Id))..." -ForegroundColor Yellow
        Stop-Process -Id $backendProcess.Id -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Shutdown complete. Goodbye!" -ForegroundColor Green
    Set-Location "$PSScriptRoot"
}
