#!/bin/bash
# Kivo Workspace — Development Setup & Launcher for macOS and Linux
# Purpose: Installs prerequisites, sets up venv, and launches frontend + backend concurrently.

set -e

# ANSI Color Codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}   Kivo Workspace Developer Launcher     ${NC}"
echo -e "${GREEN}=========================================${NC}"

# --- 1. Prerequisite Checks ---
echo -e "\n${YELLOW}[1/4] Checking prerequisites...${NC}"

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter SDK is not installed or not in PATH.${NC}"
    echo "Please install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
fi
echo -e "Flutter: ${GREEN}Detected${NC}"

# Find Python 3 command
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo -e "${RED}Error: Python is not installed or not in PATH.${NC}"
    echo "Please install Python 3.11 or 3.12: https://www.python.org/downloads/"
    exit 1
fi

# Verify Python Version is 3
PYTHON_VER=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
MAJOR_VER=$(echo $PYTHON_VER | cut -d. -f1)
MINOR_VER=$(echo $PYTHON_VER | cut -d. -f2)

if [ "$MAJOR_VER" -lt 3 ]; then
    echo -e "${RED}Error: Python 3 is required. Detected version: $PYTHON_VER${NC}"
    exit 1
fi
echo -e "Python $PYTHON_VER: ${GREEN}Detected${NC}"

# --- 2. Backend Environment Setup ---
echo -e "\n${YELLOW}[2/4] Setting up Python virtual environment...${NC}"
cd backend

if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    $PYTHON_CMD -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

echo "Installing backend dependencies (this may take a minute)..."
pip install --upgrade pip
pip install -r requirements.txt
pip install -r requirements-dev.txt
cd ..

# --- 3. Frontend Packages Setup ---
echo -e "\n${YELLOW}[3/4] Installing Dart packages...${NC}"
cd frontend
flutter pub get
cd ..

# --- 4. Launching Servers ---
echo -e "\n${YELLOW}[4/4] Starting Kivo Workspace...${NC}"

# Cleanup function to kill backend when user stops the script
cleanup() {
    echo -e "\n${YELLOW}Stopping backend server (PID: $BACKEND_PID)...${NC}"
    kill $BACKEND_PID 2>/dev/null || true
    echo -e "${GREEN}Shutdown complete. Goodbye!${NC}"
}
trap cleanup SIGINT SIGTERM EXIT

# Start FastAPI backend in the background
echo "Launching local RAG API server in background..."
cd backend
source venv/bin/activate
# Start FastAPI backend in the background (no --reload for clean dev launch)
python -m uvicorn main:app --port 8000 &
BACKEND_PID=$!
cd ..

# Wait 2 seconds for backend to initialize
sleep 2

# Launch Flutter frontend in the foreground
echo "Launching Flutter app..."
cd frontend
TARGET_DEV="macos"
if [ "$(uname)" = "Linux" ]; then
    TARGET_DEV="linux"
fi
flutter run -d $TARGET_DEV
cd ..
