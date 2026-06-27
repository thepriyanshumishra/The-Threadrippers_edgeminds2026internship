#!/bin/bash
# Kivo Workspace — Interactive Web Launcher & Setup
# Purpose: Scans dependencies, compiles web assets, and starts the backend/frontend on a single port.
# Supports local network (LAN) sharing and optional secure public tunneling:
#   - Cloudflare Quick Tunnel (zero-signup, recommended)
#   - Localtunnel (custom subdomain)
#   - ngrok (recommended for Jetson/SSH evaluations — auto-downloaded, ARM64 + x86_64 supported)
# Includes full Google Colab / Headless automated detection and zero-interactive execution.

# The 'set -e' option instructs the script to immediately exit if any command fails.
set -e

# ==========================================
# 0. ANSI Color Codes Definitions
# ==========================================
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Clear the terminal screen to present a clean environment (only if run inside a real terminal).
if [ -t 1 ]; then
    clear 2>/dev/null || true
fi

# Detect if we are running in Google Colab to enable full automation.
IS_COLAB=false
if [ -f /usr/local/bin/colab-fileshim ] || [ -d "/content" ]; then
    IS_COLAB=true
fi

# Present the header banner of Kivo Workspace in Green.
echo -e "${GREEN}===================================================${NC}"
echo -e "${GREEN}       KIVO WORKSPACE — WEB INTERACTIVE SETUP       ${NC}"
echo -e "${GREEN}===================================================${NC}"
echo -e "System: $(uname -s) ($(uname -m))"
if [ "$IS_COLAB" = "true" ]; then
    echo -e "${GREEN}Google Colab detected! Activating headless automation...${NC}\n"
else
    echo ""
fi

# Jetson-specific performance optimizations (aarch64)
if [ "$(uname -m)" = "aarch64" ]; then
    echo "Applying NVIDIA Jetson optimizations..."
    sudo sysctl -w vm.overcommit_memory=1 2>/dev/null || true
    export OLLAMA_NUM_PARALLEL=1
    export OLLAMA_MAX_LOADED_MODELS=1
    export OLLAMA_GPU_OVERHEAD=0
fi

# ==========================================
# 1. Dependency Scanner (Step 1 of 3)
# ==========================================
# Scans the host machine for all backend and frontend prerequisites.
echo -e "${GREEN}[Step 1/3] Scanning dependencies...${NC}"

MISSING_SYS_PACKAGES=()
PYTHON_CMD=""
HAS_FLUTTER=true
HAS_WEB_BUILD=false

# Search for python3.12 or python3.11 first because newer python versions (like 3.13/3.14)
# might lack pre-compiled binaries (wheels) for ML-heavy libraries like onnxruntime/faiss-cpu.
for cmd in python3.12 python3.11 python3 python; do
    if command -v "$cmd" &> /dev/null; then
        VER=$("$cmd" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        if [ "$VER" = "3.11" ] || [ "$VER" = "3.12" ]; then
            PYTHON_CMD="$cmd"
            PYTHON_VER="$VER"
            break
        fi
    fi
done

# Fallback to any general python3 or python command on the PATH.
if [ -z "$PYTHON_CMD" ]; then
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    fi
    if [ -n "$PYTHON_CMD" ]; then
        PYTHON_VER=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    fi
fi

# Print status of Python detection.
if [ -n "$PYTHON_CMD" ]; then
    echo -e "  [${GREEN}✓${NC}] Python $PYTHON_VER (Selected: $PYTHON_CMD)"
    
    # On Debian/Ubuntu systems, check if the specific pythonX.X-venv package is installed.
    if [ "$(uname)" = "Linux" ] && command -v dpkg &> /dev/null; then
        PY_VER_SHORT=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
        if ! dpkg -s "python${PY_VER_SHORT}-venv" &> /dev/null; then
            MISSING_SYS_PACKAGES+=("python${PY_VER_SHORT}-venv")
        fi
    fi
else
    echo -e "  [${RED}✗${NC}] Python 3 (Required)"
    MISSING_SYS_PACKAGES+=("python3")
fi

# Check if Pip is available.
if [ -n "$PYTHON_CMD" ] && $PYTHON_CMD -m pip --version &> /dev/null; then
    echo -e "  [${GREEN}✓${NC}] Pip"
else
    echo -e "  [${RED}✗${NC}] Pip (Required)"
    MISSING_SYS_PACKAGES+=("python3-pip")
fi

# Check if FFmpeg is installed.
if command -v ffmpeg &> /dev/null; then
    echo -e "  [${GREEN}✓${NC}] FFmpeg (Audio/Video processing)"
else
    echo -e "  [!] FFmpeg (Recommended for audio transcription)"
    MISSING_SYS_PACKAGES+=("ffmpeg")
fi

# Check available disk space
if command -v df &> /dev/null; then
    AVAIL_KB=$(df / | awk 'NR==2 {print $4}')
    if [ -n "$AVAIL_KB" ]; then
        AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
        if [ "$AVAIL_GB" -lt 1 ]; then
            echo -e "  [${RED}✗${NC}] Low disk space: Only ${AVAIL_GB} GB free. Minimum 1 GB required."
            echo -e "${RED}Error: Extremely low disk space. Please clean up files and try again.${NC}"
            exit 1
        elif [ "$AVAIL_GB" -lt 3 ]; then
            echo -e "  [!] Low disk space warning: Only ${AVAIL_GB} GB free. On-demand features may fail to install."
        else
            echo -e "  [${GREEN}✓${NC}] Disk Space: ${AVAIL_GB} GB free"
        fi
    fi
fi

# Check Ollama service status
OLLAMA_RUNNING=false
if curl -s http://localhost:11434 &> /dev/null; then
    OLLAMA_RUNNING=true
    echo -e "  [${GREEN}✓${NC}] Ollama service is running"
else
    echo -e "  [!] Ollama service is not running on http://localhost:11434"
    if [ "$IS_COLAB" = "false" ]; then
        read -p "Do you want to attempt auto-installing/starting Ollama? [y/N]: " -r INSTALL_OLLAMA || true
        INSTALL_OLLAMA=${INSTALL_OLLAMA:-n}
        if [[ "$INSTALL_OLLAMA" =~ ^[Yy]$ ]]; then
            if ! command -v ollama &> /dev/null; then
                echo "Installing Ollama..."
                curl -fsSL https://ollama.com/install.sh | sh
            fi
            echo "Starting Ollama in the background..."
            ollama serve >/dev/null 2>&1 &
            for i in {1..12}; do
                if curl -s http://localhost:11434 &> /dev/null; then
                    OLLAMA_RUNNING=true
                    echo -e "  [${GREEN}✓${NC}] Ollama is active!"
                    break
                fi
                sleep 1
            done
        fi
    fi
fi

if [ "$OLLAMA_RUNNING" = "true" ]; then
    DEFAULT_MODEL="qwen2.5:1.5b"
    MODELS_JSON=$(curl -s http://localhost:11434/api/tags 2>/dev/null)
    if ! echo "$MODELS_JSON" | grep -q "$DEFAULT_MODEL"; then
        echo -e "  [!] Recommended Ollama model '${DEFAULT_MODEL}' is NOT pulled."
        read -p "Do you want to pull '${DEFAULT_MODEL}' now? [Y/n]: " -r PULL_MODEL || true
        PULL_MODEL=${PULL_MODEL:-y}
        if [[ "$PULL_MODEL" =~ ^[Yy]$ ]]; then
            echo "Pulling '${DEFAULT_MODEL}' model (this might take a few minutes)..."
            ollama pull "$DEFAULT_MODEL"
            echo -e "  [${GREEN}✓${NC}] Model '${DEFAULT_MODEL}' pulled successfully!"
        fi
    else
        echo -e "  [${GREEN}✓${NC}] Recommended Ollama model '${DEFAULT_MODEL}' is available"
    fi
fi

# Check if zstd is installed (required for Ollama extraction).
if command -v zstd &> /dev/null; then
    echo -e "  [${GREEN}✓${NC}] Zstd (Archive compression tool)"
else
    echo -e "  [!] Zstd (Required for Ollama installation)"
    MISSING_SYS_PACKAGES+=("zstd")
fi

# Check if lspci is installed (required for Ollama GPU detection on Linux).
if [ "$(uname)" = "Linux" ]; then
    if command -v lspci &> /dev/null; then
        echo -e "  [${GREEN}✓${NC}] Pciutils (lspci hardware detection)"
    else
        echo -e "  [!] Pciutils (Recommended for Ollama GPU detection)"
        MISSING_SYS_PACKAGES+=("pciutils")
    fi
fi

# Check if unzip is installed (only required for ngrok on Darwin).
if [ "$(uname)" = "Darwin" ]; then
    if command -v unzip &> /dev/null; then
        echo -e "  [${GREEN}✓${NC}] Unzip (Archive extraction tool)"
    else
        echo -e "  [!] Unzip (Required for ngrok installation)"
        MISSING_SYS_PACKAGES+=("unzip")
    fi
fi

# Check if the Flutter SDK is installed.
if command -v flutter &> /dev/null; then
    echo -e "  [${GREEN}✓${NC}] Flutter SDK"
else
    echo -e "  [!] Flutter SDK (Not installed)"
    HAS_FLUTTER=false
fi

# Check if a pre-compiled Flutter Web build folder exists.
if [ -d "frontend/build/web" ] && [ -f "frontend/build/web/index.html" ]; then
    HAS_WEB_BUILD=true
    echo -e "  [${GREEN}✓${NC}] Pre-compiled Web UI detected"
else
    echo -e "  [${RED}✗${NC}] Compiled Web UI not found"
fi

# Verify if we have Python.
if [ -z "$PYTHON_CMD" ]; then
    echo -e "\n${RED}Error: Python 3 is required to run the backend.${NC}"
    echo "Please install Python 3 and rerun this script."
    exit 1
fi

# Google Colab: Auto-install Flutter SDK if both Flutter is missing and the Web build is missing.
if [ "$IS_COLAB" = "true" ] && [ "$HAS_FLUTTER" = "false" ] && [ "$HAS_WEB_BUILD" = "false" ]; then
    echo -e "\nColab Automation: Downloading and setting up Flutter SDK..."
    curl -L -o /tmp/flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.4-stable.tar.xz
    
    # Extract to /content or user home directory
    if [ -d "/content" ]; then
        tar -xf /tmp/flutter.tar.xz -C /content/
        export PATH="$PATH:/content/flutter/bin"
        git config --global --add safe.directory /content/flutter || true
    else
        tar -xf /tmp/flutter.tar.xz -C "$HOME/"
        export PATH="$PATH:$HOME/flutter/bin"
        git config --global --add safe.directory "$HOME/flutter" || true
    fi
    rm -f /tmp/flutter.tar.xz
    HAS_FLUTTER=true
    echo -e "  [${GREEN}✓${NC}] Flutter SDK installed successfully"
fi

# Verify if we have a way to run the frontend.
if [ "$HAS_FLUTTER" = "false" ] && [ "$HAS_WEB_BUILD" = "false" ]; then
    echo -e "\n${RED}Error: Both Flutter SDK and compiled Web UI are missing.${NC}"
    echo "To run Kivo in a browser, you must either install the Flutter SDK on this device to compile it,"
    echo "or compile it on another computer and copy the 'frontend/build/web' directory here."
    exit 1
fi


# ==========================================
# 2. Environment Setup (Step 2 of 3)
# ==========================================
# Prepares system dependency packages, creates virtual environment, and builds Flutter Web assets.
echo -e "\n${GREEN}[Step 2/3] Preparing Environment...${NC}"

# Install missing system packages if any.
if [ ${#MISSING_SYS_PACKAGES[@]} -gt 0 ]; then
    INSTALL_CONFIRM=""
    if [ "$IS_COLAB" = "true" ]; then
        INSTALL_CONFIRM="y"
    else
        echo -e "The following system packages are missing/recommended: ${MISSING_SYS_PACKAGES[*]}"
        read -p "Do you want to install them automatically? (Requires sudo) [Y/n]: " -r INSTALL_CONFIRM || true
        INSTALL_CONFIRM=${INSTALL_CONFIRM:-y}
    fi

    if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
        if [ "$(uname)" = "Darwin" ]; then
            if command -v brew &> /dev/null; then
                echo "Installing packages via Homebrew..."
                brew install "${MISSING_SYS_PACKAGES[@]}"
            else
                echo -e "${RED}Homebrew not detected. Please install packages manually.${NC}"
            fi
        else
            echo "Installing packages via apt..."
            if ! (sudo apt-get update -y && DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${MISSING_SYS_PACKAGES[@]}"); then
                echo -e "${RED}[Warning] System package installation failed (your root filesystem might be read-only).${NC}"
                echo "Attempting to proceed anyway with local configurations..."
            fi
        fi
    fi
fi

# Google Colab: Auto-install and start Ollama in the background
if [ "$IS_COLAB" = "true" ]; then
    # Ensure Nvidia libraries are visible to the Ollama service
    export LD_LIBRARY_PATH="/usr/lib64-nvidia:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH"

    if ! command -v ollama &> /dev/null; then
        echo -e "\nColab Automation: Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo -e "\nColab Automation: Ollama is already installed."
    fi

    # Check if Ollama service is running, if not start it in background
    if ! curl -s http://localhost:11434 &> /dev/null; then
        echo -e "Colab Automation: Starting Ollama service in the background..."
        ollama serve >/dev/null 2>&1 &
        echo -e "Waiting for Ollama service to bind to port 11434..."
        for i in {1..12}; do
            if curl -s http://localhost:11434 &> /dev/null; then
                echo -e "  [✓] Ollama service is active and responsive."
                break
            fi
            sleep 1
        done
    else
        echo -e "Colab Automation: Ollama service is already running."
    fi
fi

# Create a local virtual environment (venv) inside the backend folder.
echo -e "\nSetting up Python virtual environment..."
cd backend
USE_VENV=true
if [ ! -d "venv" ]; then
    echo "Creating virtual environment in backend/venv..."
    if ! $PYTHON_CMD -m venv venv 2>/dev/null; then
        echo -e "${RED}[Warning] Failed to create virtual environment (python3-venv is missing or root is read-only).${NC}"
        echo "Falling back to installing python dependencies locally for the current user..."
        USE_VENV=false
    fi
fi

if [ "$USE_VENV" = "true" ] && [ -f "venv/bin/activate" ]; then
    # Activate virtual environment and install requirements.
    source venv/bin/activate
    echo "Installing/updating pip and python dependencies..."
    pip install --upgrade pip
    pip install -r requirements.txt
    pip install -r requirements-dev.txt
    pip cache purge
else
    echo "Installing/updating python dependencies in user-space (--user)..."
    $PYTHON_CMD -m pip install --upgrade pip --user || true
    $PYTHON_CMD -m pip install -r requirements.txt --user
    $PYTHON_CMD -m pip install -r requirements-dev.txt --user
    $PYTHON_CMD -m pip cache purge || true
fi
cd ..

# Determine if compiling the Flutter Web frontend is necessary.
BUILD_WEB=false
if [ "$HAS_FLUTTER" = "true" ]; then
    if [ "$HAS_WEB_BUILD" = "false" ]; then
        BUILD_WEB=true
    else
        if [ "$IS_COLAB" = "true" ]; then
            BUILD_WEB=false
        else
            read -p "Pre-compiled Web UI exists. Rebuild web frontend? [y/N]: " -r REBUILD_CONFIRM || true
            REBUILD_CONFIRM=${REBUILD_CONFIRM:-n}
            if [[ "$REBUILD_CONFIRM" =~ ^[Yy]$ ]]; then
                BUILD_WEB=true
            fi
        fi
    fi
fi

# Compile Flutter Web frontend using Flutter CLI tools.
if [ "$BUILD_WEB" = "true" ]; then
    echo -e "\nCompiling Flutter Web application (this might take a few minutes)..."
    cd frontend
    # Make sure we add flutter path in Colab
    if [ "$IS_COLAB" = "true" ]; then
        export PATH="$PATH:/content/flutter/bin:$HOME/flutter/bin"
        git config --global --add safe.directory /content/flutter || true
    fi
    flutter pub get
    flutter build web
    cd ..
    echo -e "${GREEN}Web build compilation complete!${NC}"
else
    echo -e "\n${GREEN}Using existing pre-compiled Web UI.${NC}"
fi


# ==========================================
# 3. Server Startup & Public Tunnel (Step 3 of 3)
# ==========================================
# Exposes the server locally, over LAN, and sets up the selected public tunnel.
echo -e "\n${GREEN}[Step 3/3] Starting Kivo Workspace...${NC}"

# Detect host LAN IP.
if [ "$(uname)" = "Darwin" ]; then
    LAN_IP=$(ipconfig getifaddr en0 || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n1)
else
    LAN_IP=$(hostname -I | awk '{print $1}' || ip route get 1 | awk '{print $NF;exit}' || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n1)
fi

# Tunnel Choice configuration. If running in Colab, automatically default to Cloudflare.
TUNNEL_CHOICE="1"
if [ "$IS_COLAB" = "true" ]; then
    echo "Colab Automation: Exposing public link via Cloudflare Quick Tunnel..."
    TUNNEL_CHOICE="2"
else
    echo -e "\nDo you want to expose a public link?"
    echo -e "  1. No (Local Network only)"
    echo -e "  2. (recommended) Yes, via Cloudflare Quick Tunnel (Zero-signup, readable words link)"
    echo -e "  3. Yes, via Localtunnel (Zero-signup, persistent/custom subdomain)"
    echo -e "  4. Yes, via ngrok (Best for SSH/Jetson evaluations — requires free account token)"
    read -p "Enter choice [1-4]: " -r TUNNEL_CHOICE || true
    TUNNEL_CHOICE=${TUNNEL_CHOICE:-1}
fi

# Setup cleanup traps to kill server and tunnel processes on exit.
BACKEND_PID=""
TUNNEL_PID=""
cleanup() {
    echo -e "\n\nStopping Kivo Workspace servers..."
    if [ -n "$BACKEND_PID" ]; then
        kill "$BACKEND_PID" 2>/dev/null || true
    fi
    if [ -n "$TUNNEL_PID" ]; then
        kill "$TUNNEL_PID" 2>/dev/null || true
    fi
    # Remove temporary logs to keep workspace clean.
    rm -f cloudflared.log localtunnel.log ngrok.log
    echo -e "${GREEN}Shutdown complete. Goodbye!${NC}"
}
trap cleanup SIGINT SIGTERM EXIT

# Ensure Nvidia target library paths are visible on local Linux environments
if [ "$(uname)" = "Linux" ]; then
    export LD_LIBRARY_PATH="/usr/lib64-nvidia:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/cuda/targets/aarch64-linux/lib:$LD_LIBRARY_PATH"
fi

# Start backend in the background and redirect output to uvicorn.log.
echo "Launching FastAPI server..."
cd backend
if [ -f "uvicorn.log" ]; then
    LOG_SIZE=$(wc -c < uvicorn.log 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 10485760 ]; then
        echo "Rotating uvicorn.log (exceeded 10MB)..."
        mv uvicorn.log uvicorn.log.old
    fi
fi

if [ -d "venv" ] && [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    python -m uvicorn main:app --host 0.0.0.0 --port 8000 > /dev/null 2>&1 &
else
    $PYTHON_CMD -m uvicorn main:app --host 0.0.0.0 --port 8000 > /dev/null 2>&1 &
fi
BACKEND_PID=$!

# Trigger non-blocking sequential background model warming (first Ollama, then Embedding)
(sleep 3 && curl -s -o /dev/null -X POST http://localhost:11434/api/generate -d '{"model": "qwen2.5:1.5b", "prompt": ""}') &

cd ..

# Initialize selected tunnel configuration.
PUBLIC_URL="Not enabled"
if [ "$TUNNEL_CHOICE" = "2" ]; then
    # --- Option 2: Cloudflare Quick Tunnel ---
    CLOUDFLARED_CMD=""
    if command -v cloudflared &> /dev/null; then
        CLOUDFLARED_CMD="cloudflared"
    elif [ -f "./cloudflared" ]; then
        CLOUDFLARED_CMD="./cloudflared"
    else
        echo "Downloading cloudflared for public tunneling..."
        OS=$(uname -s)
        ARCH=$(uname -m)
        if [ "$OS" = "Linux" ]; then
            if [ "$ARCH" = "x86_64" ]; then
                curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
            elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
            else
                echo -e "${RED}Unsupported Linux architecture: $ARCH${NC}"
                exit 1
            fi
            chmod +x cloudflared
            CLOUDFLARED_CMD="./cloudflared"
        elif [ "$OS" = "Darwin" ]; then
            curl -L -o cloudflared.tgz https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz
            tar -xzf cloudflared.tgz
            rm -f cloudflared.tgz
            chmod +x cloudflared
            CLOUDFLARED_CMD="./cloudflared"
        else
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
        fi
    fi

    echo "Initializing Cloudflare Quick Tunnel..."
    rm -f cloudflared.log
    $CLOUDFLARED_CMD tunnel --url http://localhost:8000 > cloudflared.log 2>&1 &
    TUNNEL_PID=$!

    # Poll cloudflared.log for up to 15 seconds to find the tunnel URL.
    echo "Waiting for Cloudflare tunnel URL to generate..."
    for i in {1..15}; do
        sleep 1
        PUBLIC_URL=$(grep -o 'https://[^ ]*\.trycloudflare\.com' cloudflared.log | head -n1 || true)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    done
    if [ -z "$PUBLIC_URL" ]; then
        PUBLIC_URL="${RED}Failed to establish Cloudflare tunnel (Check cloudflared.log)${NC}"
    fi

elif [ "$TUNNEL_CHOICE" = "3" ]; then
    # --- Option 3: Localtunnel ---
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}Error: npm is not installed. Node.js/npm is required for Localtunnel.${NC}"
        exit 1
    fi

    # Prompt for custom subdomain.
    CUSTOM_SUBDOMAIN="kivo-workspace"
    if [ "$IS_COLAB" = "false" ]; then
        read -p "Enter custom subdomain [default: kivo-workspace]: " -r CUSTOM_SUBDOMAIN || true
        CUSTOM_SUBDOMAIN=${CUSTOM_SUBDOMAIN:-kivo-workspace}
    fi

    echo "Initializing Localtunnel..."
    rm -f localtunnel.log
    npx localtunnel --port 8000 --subdomain "$CUSTOM_SUBDOMAIN" > localtunnel.log 2>&1 &
    TUNNEL_PID=$!

    # Poll localtunnel.log for up to 15 seconds to find the tunnel URL.
    echo "Waiting for Localtunnel URL to generate..."
    for i in {1..15}; do
        sleep 1
        PUBLIC_URL=$(grep -o 'https://[^ ]*\.localtunnel\.me' localtunnel.log | head -n1 || true)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    done
    if [ -z "$PUBLIC_URL" ]; then
        PUBLIC_URL="${RED}Failed to establish Localtunnel (Check localtunnel.log)${NC}"
    fi

elif [ "$TUNNEL_CHOICE" = "4" ]; then
    # --- Option 4: ngrok (Recommended for Jetson SSH evaluations) ---
    # Detect or download ngrok binary for the current OS/Architecture.
    NGROK_CMD=""
    if command -v ngrok &> /dev/null; then
        NGROK_CMD="ngrok"
    elif [ -f "./ngrok" ]; then
        NGROK_CMD="./ngrok"
    else
        echo "Downloading ngrok binary for public tunneling..."
        OS=$(uname -s)
        ARCH=$(uname -m)
        if [ "$OS" = "Linux" ]; then
            NGROK_TGZ="ngrok.tgz"
            if [ "$ARCH" = "x86_64" ]; then
                curl -L -o "$NGROK_TGZ" https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
            elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                # ARM64 build — correct for Jetson Orin/Nano
                curl -L -o "$NGROK_TGZ" https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz
            else
                echo -e "${RED}Unsupported Linux architecture for ngrok: $ARCH${NC}"
                exit 1
            fi
            tar -xzf "$NGROK_TGZ"
            rm -f "$NGROK_TGZ"
        elif [ "$OS" = "Darwin" ]; then
            NGROK_ZIP="ngrok.zip"
            curl -L -o "$NGROK_ZIP" https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip
            unzip -o "$NGROK_ZIP" ngrok -d . &> /dev/null
            rm -f "$NGROK_ZIP"
        else
            echo -e "${RED}Unsupported OS for ngrok: $OS${NC}"
            exit 1
        fi
        chmod +x ./ngrok
        NGROK_CMD="./ngrok"
    fi

    # Prompt for ngrok auth token (required for stable tunnels).
    echo -e "\n${GREEN}ngrok requires a free auth token to create stable tunnels.${NC}"
    echo -e "Get yours free at: https://dashboard.ngrok.com/get-started/your-authtoken"
    read -p "Enter your ngrok auth token [Press Enter to use default]: " -r NGROK_TOKEN || true
    NGROK_TOKEN=${NGROK_TOKEN:-3FgoiF0tXrXVhb65TatXbOyNIog_48qvXfc4NxWabBEnoxZsd}
    if [ -n "$NGROK_TOKEN" ]; then
        $NGROK_CMD config add-authtoken "$NGROK_TOKEN" &> /dev/null || true
    fi

    echo "Initializing ngrok tunnel on port 8000..."
    rm -f ngrok.log
    # Start ngrok as background process. It exposes the local FastAPI server.
    $NGROK_CMD http 8000 --log=stdout > ngrok.log 2>&1 &
    TUNNEL_PID=$!

    # Poll ngrok.log for up to 20 seconds to find the public URL.
    echo "Waiting for ngrok tunnel URL to generate..."
    for i in {1..20}; do
        sleep 1
        # ngrok logs the URL in format: url=https://xxxx.ngrok-free.app or url=https://xxxx.ngrok.io
        PUBLIC_URL=$(grep -o 'url=https://[^ ]*' ngrok.log | head -n1 | sed 's/url=//' || true)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    done
    if [ -z "$PUBLIC_URL" ]; then
        # Also try the ngrok API endpoint as fallback
        sleep 2
        PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | head -n1 | sed 's/"public_url":"//;s/"//' || true)
    fi
    if [ -z "$PUBLIC_URL" ]; then
        PUBLIC_URL="${RED}Failed to establish ngrok tunnel (Check ngrok.log or ngrok dashboard)${NC}"
    fi
fi

# Wait for backend uvicorn server to initialize.
sleep 1

# Present a clean, user-friendly green dashboard containing all access URLs.
if [ -t 1 ]; then
    clear 2>/dev/null || true
fi
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}       🚀 KIVO WORKSPACE IS SUCCESSFULLY RUNNING!     ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  Backend/Web port:  8000${NC}"
echo -e "${GREEN}  Local access:      http://localhost:8000${NC}"
if [ -n "$LAN_IP" ]; then
    echo -e "${GREEN}  Local Network:     http://${LAN_IP}:8000  <-- Open this on your PC!${NC}"
fi
if [ "$TUNNEL_CHOICE" != "1" ]; then
    echo -e "${GREEN}  Public Link:       ${PUBLIC_URL}${NC}"
fi
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}Logs are streaming below. Press Ctrl+C to stop the server.${NC}\n"

# Stream the backend logs directly into the terminal window.
tail -f backend/uvicorn.log
