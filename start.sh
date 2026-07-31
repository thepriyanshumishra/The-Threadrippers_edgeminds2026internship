#!/bin/bash
# Kivo Workspace — Interactive Web Launcher & Setup
# Purpose: Scans dependencies, compiles web assets, and starts the backend/frontend on a single port.
# Features a beautiful developer CLI, telemetry dashboard, silent spinners, and interactive utilities.
# Disabling set -e to allow robust handling of dependency checks and soft warning exits.

# ==========================================
# 0. Color Definitions & Setup
# ==========================================
TEAL='\033[38;2;0;203;169m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Create logs directory
mkdir -p logs

# Detect if we are running in Google Colab
IS_COLAB=false
if [ -f /usr/local/bin/colab-fileshim ] || [ -d "/content" ]; then
    IS_COLAB=true
fi

# Clean up leftover backend or tunnel processes
pkill -f cloudflared 2>/dev/null || true
pkill -f localtunnel 2>/dev/null || true
pkill -f "python.*main.py" 2>/dev/null || true

# Jetson-specific performance optimizations (aarch64)
if [ "$(uname -m)" = "aarch64" ]; then
    sudo sysctl -w vm.overcommit_memory=1 2>/dev/null || true
    export OLLAMA_NUM_PARALLEL=1
    export OLLAMA_MAX_LOADED_MODELS=1
    export OLLAMA_GPU_OVERHEAD=0
fi

# Set Ollama keep-alive variables
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_KEEP_ALIVE=5m

# ==========================================
# 1. UI Components
# ==========================================

print_logo() {
    # Sharp brand-accurate 2x2 teal squares with clean typography
    echo -e "  ${TEAL}▄▄▄▄   ▄▄▄▄${NC}"
    echo -e "  ${TEAL}████   ████${NC}"
    echo -e "  ${TEAL}▀▀▀▀   ▀▀▀▀${NC}      ${WHITE}K I V O   W O R K S P A C E${NC}"
    echo -e "  ${TEAL}▄▄▄▄   ▄▄▄▄${NC}      ${GRAY}Edge Intelligence Platform${NC}"
    echo -e "  ${TEAL}████   ████${NC}"
    echo -e "  ${TEAL}▀▀▀▀   ▀▀▀▀${NC}"
    echo -e "  ${GRAY}──────────────────────────────────────────────────────${NC}"
}

show_spinner() {
    local pid=$1
    local message="$2"
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local delay=0.1
    tput civis 2>/dev/null || printf "\033[?25l"
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "  ${TEAL}%c${NC}  %s\r" "$spinstr" "$message"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    tput cnorm 2>/dev/null || printf "\033[?25h"
    printf "\r\033[K"
}

# ==========================================
# 2. Silent Dependency Scanner
# ==========================================

run_silent_scanner() {
    OS_NAME=$(uname -s)
    OS_ARCH=$(uname -m)
    MISSING_SYS_PACKAGES=()
    
    if [ "$OS_NAME" = "Darwin" ]; then
        CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
        TOTAL_RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))
        FREE_RAM_GB=$(vm_stat | awk '/free/ {print int($3*4096/1024/1024/1024)}')
        [ -z "$FREE_RAM_GB" ] && FREE_RAM_GB=4
    else
        CPU_CORES=$(nproc 2>/dev/null || echo 1)
        TOTAL_RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
        FREE_RAM_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
        FREE_RAM_GB=$((FREE_RAM_KB / 1024 / 1024))
    fi

    # Disk Space Check
    FREE_DISK_GB=0
    if command -v df &> /dev/null; then
        FREE_DISK_KB=$(df / | awk 'NR==2 {print $4}')
        FREE_DISK_GB=$((FREE_DISK_KB / 1024 / 1024))
    fi

    # Python Check
    PYTHON_CMD=""
    PYTHON_VER=""
    for cmd in python3.12 python3.11 python3 python; do
        if command -v "$cmd" &> /dev/null; then
            VER=$("$cmd" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
            if [ "$VER" = "3.11" ] || [ "$VER" = "3.12" ]; then
                PYTHON_CMD="$cmd"
                PYTHON_VER="$VER"
                break
            fi
        fi
    done
    if [ -z "$PYTHON_CMD" ]; then
        if command -v python3 &> /dev/null; then
            PYTHON_CMD="python3"
        elif command -v python &> /dev/null; then
            PYTHON_CMD="python"
        fi
        if [ -n "$PYTHON_CMD" ]; then
            PYTHON_VER=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
        fi
    fi

    if [ -n "$PYTHON_CMD" ]; then
        PYTHON_ICON="${GREEN}✓${NC}"
        PYTHON_VER_STR="${GREEN}$PYTHON_VER (Selected: $PYTHON_CMD)${NC}"
        
        # Check venv package
        if [ "$OS_NAME" = "Linux" ] && command -v dpkg &> /dev/null; then
            PY_VER_SHORT=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
            if ! dpkg -s "python${PY_VER_SHORT}-venv" &> /dev/null; then
                MISSING_SYS_PACKAGES+=("python${PY_VER_SHORT}-venv")
            fi
        fi
    else
        PYTHON_ICON="${RED}✗${NC}"
        PYTHON_VER_STR="${RED}Missing (Python 3.11/3.12 required)${NC}"
    fi

    # Pip Check
    if [ -n "$PYTHON_CMD" ] && $PYTHON_CMD -m pip --version &> /dev/null; then
        PIP_ICON="${GREEN}✓${NC}"
    else
        PIP_ICON="${RED}✗${NC}"
        MISSING_SYS_PACKAGES+=("python3-pip")
    fi

    # FFmpeg Check
    if command -v ffmpeg &> /dev/null; then
        FFMPEG_ICON="${GREEN}✓${NC}"
    else
        FFMPEG_ICON="${YELLOW}⚠${NC} ${GRAY}(Optional)${NC}"
        MISSING_SYS_PACKAGES+=("ffmpeg")
    fi

    # Ollama Check
    OLLAMA_RUNNING=false
    if curl -s http://localhost:11434 &> /dev/null; then
        OLLAMA_RUNNING=true
        OLLAMA_ICON="${GREEN}✓${NC}"
        OLLAMA_STATUS="${GREEN}Active${NC}"
    else
        OLLAMA_ICON="${YELLOW}⚠${NC}"
        OLLAMA_STATUS="${YELLOW}Inactive (Auto-install/start supported)${NC}"
    fi

    # Zstd Check
    if command -v zstd &> /dev/null; then
        ZSTD_ICON="${GREEN}✓${NC}"
    else
        ZSTD_ICON="${YELLOW}⚠${NC}"
        MISSING_SYS_PACKAGES+=("zstd")
    fi

    # Flutter Check
    if command -v flutter &> /dev/null; then
        HAS_FLUTTER=true
        FLUTTER_ICON="${GREEN}✓${NC}"
        FLUTTER_STATUS="${GREEN}Active${NC}"
    else
        HAS_FLUTTER=false
        FLUTTER_ICON="${YELLOW}⚠${NC}"
        FLUTTER_STATUS="${YELLOW}Missing (Bypassed if precompiled Web Assets exist)${NC}"
    fi

    # Web Assets Check
    if [ -d "frontend/build/web" ] && [ -f "frontend/build/web/index.html" ]; then
        HAS_WEB_BUILD=true
        WEB_BUILD_ICON="${GREEN}✓${NC}"
        WEB_BUILD_STATUS="${GREEN}Found${NC}"
    else
        HAS_WEB_BUILD=false
        WEB_BUILD_ICON="${RED}✗${NC}"
        WEB_BUILD_STATUS="${RED}Not Found (Needs compilation)${NC}"
    fi
}

print_dashboard() {
    if [ -t 1 ]; then
        clear 2>/dev/null || true
    fi
    print_logo

    # Telemetry Box
    echo -e "  ${WHITE}┌── SYSTEM TELEMETRY ────────────────────────────────┐${NC}"
    echo -e "  ${WHITE}│${NC}  • OS:      ${OS_NAME} (${OS_ARCH})"
    echo -e "  ${WHITE}│${NC}  • CPU:     ${CPU_CORES} Cores"
    echo -e "  ${WHITE}│${NC}  • RAM:     ${TOTAL_RAM_GB} GB (${FREE_RAM_GB} GB Free)"
    echo -e "  ${WHITE}│${NC}  • Disk:    ${FREE_DISK_GB} GB Available"
    if [ "$OS_NAME" = "Linux" ] && [ "$TOTAL_RAM_GB" -le 8 ]; then
        echo -e "  ${WHITE}│${NC}  ${YELLOW}• WARNING: Low Memory. Ensure SWAP is enabled${NC}"
        echo -e "  ${WHITE}│${NC}  ${YELLOW}           to avoid OOM freezes during RAG!${NC}"
    fi
    echo -e "  ${WHITE}└────────────────────────────────────────────────────┘${NC}"

    # Prerequisite Status Box
    echo -e "  ${WHITE}┌── PREREQUISITE STATUS ──────────────────────────────┐${NC}"
    echo -e "  ${WHITE}│${NC}  [${PYTHON_ICON}] Python: ${PYTHON_VER_STR}"
    echo -e "  ${WHITE}│${NC}  [${PIP_ICON}] Pip Package Manager"
    echo -e "  ${WHITE}│${NC}  [${FFMPEG_ICON}] FFmpeg (Audio/Video processing)"
    echo -e "  ${WHITE}│${NC}  [${OLLAMA_ICON}] Ollama Service: ${OLLAMA_STATUS}"
    echo -e "  ${WHITE}│${NC}  [${FLUTTER_ICON}] Flutter SDK: ${FLUTTER_STATUS}"
    echo -e "  ${WHITE}│${NC}  [${WEB_BUILD_ICON}] Precompiled Web UI: ${WEB_BUILD_STATUS}"
    echo -e "  ${WHITE}└─────────────────────────────────────────────────────┘${NC}"
}

# ==========================================
# 3. Interactive Menu Routines
# ==========================================

run_diagnostics() {
    echo -e "\n${WHITE}🔧 RUNNING KIVO SYSTEM DIAGNOSTICS...${NC}\n"
    if [ "$(uname)" = "Linux" ]; then
        echo -e "Checking SWAP memory space..."
        local swap_total=$(free -h | awk '/Swap:/ {print $2}')
        local swap_used=$(free -h | awk '/Swap:/ {print $3}')
        echo -e "  Total Swap Space: ${swap_total}"
        echo -e "  Used Swap Space:  ${swap_used}"
        
        if command -v nvidia-smi &> /dev/null; then
            echo -e "\nNVIDIA GPU Detected:"
            nvidia-smi --query-gpu=gpu_name,memory.total,memory.free --format=csv,noheader || true
        else
            echo -e "\nNo discrete NVIDIA GPU detected via nvidia-smi."
        fi
    fi
    
    if [ ${#MISSING_SYS_PACKAGES[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Missing/Recommended System Packages:${NC}"
        for pkg in "${MISSING_SYS_PACKAGES[@]}"; do
            echo -e "  • ${pkg}"
        done
        echo -e "\nYou can manually install them using:"
        if [ "$(uname)" = "Darwin" ]; then
            echo -e "  ${GREEN}brew install ${MISSING_SYS_PACKAGES[*]}${NC}"
        else
            echo -e "  ${GREEN}sudo apt-get update && sudo apt-get install -y ${MISSING_SYS_PACKAGES[*]}${NC}"
        fi
    else
        echo -e "\n${GREEN}✓ All recommended system packages are installed!${NC}"
    fi
    
    echo -e "\nPython Details:"
    echo -e "  Selected Python binary: $PYTHON_CMD"
    echo -e "  Python version:         $PYTHON_VER"
    
    if [ "$OLLAMA_RUNNING" = "true" ]; then
        echo -e "\nOllama Models Installed:"
        curl -s http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' || echo "  None"
    fi
    
    echo -e "\nPress enter to return to the main menu..."
    read -r || true
}

clean_workspace() {
    echo -e "\n${WHITE}🧹 CLEANING & RESETTING WORKSPACE...${NC}\n"
    if [ -f "./clean.sh" ]; then
        chmod +x ./clean.sh
        ./clean.sh
    else
        echo "clean.sh not found. Purging backend/venv and frontend build assets manually..."
        rm -rf backend/venv frontend/build frontend/.dart_tool logs/
    fi
    echo -e "\n${GREEN}✓ Workspace cleared successfully!${NC}"
    echo -e "Press enter to return to the main menu..."
    read -r || true
}

show_help() {
    echo -e "\n${WHITE}❓ KIVO CLI HELP & TROUBLESHOOTING${NC}\n"
    echo -e "  ${WHITE}1. Ports Used:${NC}"
    echo -e "     - Backend & Web UI:  Port 8000"
    echo -e "     - Ollama Local API:  Port 11434"
    echo -e "\n  ${WHITE}2. Environment Variables:${NC}"
    echo -e "     - ${GREEN}NGROK_AUTHTOKEN${NC}: Securely pre-configure ngrok tunnel token"
    echo -e "     - ${GREEN}OLLAMA_NUM_PARALLEL${NC}: Limit concurrent threads (Default: 1 on Jetson)"
    echo -e "     - ${GREEN}OLLAMA_KEEP_ALIVE${NC}: Idle unload timer (Default: 5m)"
    echo -e "\n  ${WHITE}3. Common Jetson Nano Issues:${NC}"
    echo -e "     - ${YELLOW}Out of Memory (OOM) Crashes:${NC} If the backend crashes during similarity"
    echo -e "       search or model swapping, check if you have at least 4GB of SWAP space enabled."
    echo -e "     - ${YELLOW}Slow Ingestion:${NC} Quantized embeddings are enabled. Ensure Ollama"
    echo -e "       keep-alive is configured to prevent model reload delay."
    echo -e "\nPress enter to return to the main menu..."
    read -r || true
}

# ==========================================
# 4. Interactive Loop Entry
# ==========================================

while true; do
    run_silent_scanner
    print_dashboard
    
    echo -e "\n  What would you like to do?"
    echo -e "  ${GRAY}──────────────────────────────────────────────────────${NC}"
    echo -e "  [1] 🚀 Start Kivo Workspace (Default: Auto-Build & Launch)"
    echo -e "  [2] 🔧 Run System Diagnostics & Check Missing Libraries"
    echo -e "  [3] 🧹 Clean & Reset Workspace (Purge build assets/caches)"
    echo -e "  [4] ❓ Show CLI Help & Troubleshooting Info"
    echo -e "  [5] ❌ Exit"
    echo ""
    
    if [ "$IS_COLAB" = "true" ]; then
        CHOICE="1"
    else
        CHOICE=""
        # Prompt choice with 5-second automatic countdown
        read -t 5 -p "  Select option (1-5) [1]: " CHOICE || true
    fi
    
    if [ -z "$CHOICE" ]; then
        CHOICE="1"
        echo -e "\n  Auto-selecting Option [1]..."
        sleep 1
    fi
    
    case "$CHOICE" in
        1)
            # Break out of loop to launch Kivo
            break
            ;;
        2)
            run_diagnostics
            ;;
        3)
            clean_workspace
            ;;
        4)
            show_help
            ;;
        5)
            echo -e "\nExiting Kivo Launcher. Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option selected. Please choose between 1 and 5.${NC}"
            sleep 1.5
            ;;
    esac
done

# ==========================================
# 5. Core Execution (Option 1)
# ==========================================

# Pre-checks before starting
if [ -z "$PYTHON_CMD" ]; then
    echo -e "\n${RED}Error: Python 3 is required to run the backend.${NC}"
    echo "Please install Python 3.11/3.12 and rerun this script."
    exit 1
fi

if [ "$HAS_FLUTTER" = "false" ] && [ "$HAS_WEB_BUILD" = "false" ]; then
    echo -e "\n${RED}Error: Both Flutter SDK and compiled Web UI are missing.${NC}"
    echo "You must either install the Flutter SDK to build the UI, or obtain a precompiled Web UI."
    exit 1
fi

echo -e "\n${WHITE}🚀 STARTING SYSTEM LAUNCH PIPELINE...${NC}"
echo -e "${GRAY}──────────────────────────────────────────────────────${NC}"

# Colab Automation: Download and extract Flutter SDK if missing
if [ "$IS_COLAB" = "true" ] && [ "$HAS_FLUTTER" = "false" ] && [ "$HAS_WEB_BUILD" = "false" ]; then
    (
        curl -L -o /tmp/flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.44.4-stable.tar.xz
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
    ) &
    local cmd_pid=$!
    show_spinner "$cmd_pid" "Colab: Downloading and setting up Flutter SDK..."
    wait "$cmd_pid"
    HAS_FLUTTER=true
    echo -e "  [${GREEN}✓${NC}] Flutter SDK setup successfully."
fi

# Install system dependencies if required
if [ ${#MISSING_SYS_PACKAGES[@]} -gt 0 ]; then
    if [ "$IS_COLAB" = "true" ]; then
        (
            apt-get update -y > logs/sys_install.log 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_SYS_PACKAGES[@]}" >> logs/sys_install.log 2>&1
        ) &
        cmd_pid=$!
        show_spinner "$cmd_pid" "Colab: Installing missing system packages (${MISSING_SYS_PACKAGES[*]})..."
        wait "$cmd_pid"
        echo -e "  [${GREEN}✓${NC}] System packages installed."
    else
        echo -e "${YELLOW}Missing recommended system packages: ${MISSING_SYS_PACKAGES[*]}${NC}"
        read -p "Would you like to install them via sudo? [y/N]: " -r INSTALL_CONFIRM || true
        if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
            if [ "$(uname)" = "Darwin" ]; then
                if command -v brew &> /dev/null; then
                    brew install "${MISSING_SYS_PACKAGES[@]}"
                else
                    echo -e "${RED}Homebrew not detected. Skip installation.${NC}"
                fi
            else
                (
                    sudo apt-get update -y > logs/sys_install.log 2>&1
                    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "${MISSING_SYS_PACKAGES[@]}" >> logs/sys_install.log 2>&1
                ) &
                cmd_pid=$!
                show_spinner "$cmd_pid" "Installing missing system packages..."
                wait "$cmd_pid"
                install_status=$?
                if [ $install_status -eq 0 ]; then
                    echo -e "  [${GREEN}✓${NC}] System packages installed."
                else
                    echo -e "  [${RED}⚠${NC}] Package installation failed. Proceeding anyway..."
                fi
            fi
        fi
    fi
fi

# Ensure Ollama is installed and running
export PATH="/usr/local/bin:$PATH"
OS_TYPE=$(uname -s)

if ! command -v ollama &> /dev/null; then
    (
        if [[ "$OS_TYPE" == *"MINGW"* || "$OS_TYPE" == *"MSYS"* || "$OS_TYPE" == *"CYGWIN"* ]]; then
            powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://ollama.com/install.ps1 | iex"
        elif [ "$OS_TYPE" = "Darwin" ]; then
            if command -v brew &> /dev/null; then
                brew install ollama
            else
                curl -L -o Ollama.zip https://ollama.com/download/Ollama-darwin.zip
                unzip -o Ollama.zip -d /Applications/
                rm -f Ollama.zip
            fi
        else
            # Linux (General / Jetson / Colab) — try curl first, fall back to wget
            if command -v curl &> /dev/null; then
                curl -fsSL https://ollama.com/install.sh | sh
            elif command -v wget &> /dev/null; then
                wget -qO- https://ollama.com/install.sh | sh
            else
                echo "Neither curl nor wget found. Cannot auto-install Ollama. Please install it manually from https://ollama.com" >&2
            fi
        fi
    ) > logs/ollama_install.log 2>&1 &
    show_spinner $! "Installing Ollama Engine automatically..."
    wait $!
fi

# Ensure service is running
if ! curl -s http://localhost:11434 &> /dev/null; then
    if [ "$IS_COLAB" = "true" ]; then
        export LD_LIBRARY_PATH="/usr/lib64-nvidia:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH"
    fi
    
    (
        if [[ "$OS_TYPE" == *"MINGW"* || "$OS_TYPE" == *"MSYS"* || "$OS_TYPE" == *"CYGWIN"* ]]; then
            home="${USERPROFILE:-C:}"
            local_app_data="${LOCALAPPDATA:-$home/AppData/Local}"
            ollama_path="$local_app_data/Programs/Ollama/ollama.exe"
            if [ -f "$ollama_path" ]; then
                "$ollama_path" serve > logs/ollama_server.log 2>&1 &
            else
                ollama serve > logs/ollama_server.log 2>&1 &
            fi
        else
            ollama serve > logs/ollama_server.log 2>&1 &
        fi
    ) &
    
    # Wait for Ollama service to become responsive (up to 20 seconds)
    (
        for i in {1..20}; do
            if curl -s http://localhost:11434 &>/dev/null; then
                exit 0
            fi
            sleep 1
        done
        exit 1
    ) &
    show_spinner $! "Starting Ollama background service..."
    wait $!
    
    if [ $? -ne 0 ]; then
        # Self-healing: if service failed to start, force a clean reinstall
        echo -e "  [${YELLOW}⚠${NC}] Ollama service startup failed. Reinstalling..."
        (
            if [[ "$OS_TYPE" == *"MINGW"* || "$OS_TYPE" == *"MSYS"* || "$OS_TYPE" == *"CYGWIN"* ]]; then
                powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://ollama.com/install.ps1 | iex"
            elif [ "$OS_TYPE" = "Darwin" ]; then
                if command -v brew &> /dev/null; then
                    brew install ollama
                else
                    curl -L -o Ollama.zip https://ollama.com/download/Ollama-darwin.zip
                    unzip -o Ollama.zip -d /Applications/
                    rm -f Ollama.zip
                fi
            else
                # Linux reinstall — try curl first, fall back to wget
                if command -v curl &> /dev/null; then
                    curl -fsSL https://ollama.com/install.sh | sh
                elif command -v wget &> /dev/null; then
                    wget -qO- https://ollama.com/install.sh | sh
                else
                    echo "Neither curl nor wget found. Cannot reinstall Ollama." >&2
                fi
            fi
        ) > logs/ollama_install.log 2>&1 &
        show_spinner $! "Reinstalling Ollama Engine..."
        wait $!
        
        # Try starting it again after reinstall
        (
            if [[ "$OS_TYPE" == *"MINGW"* || "$OS_TYPE" == *"MSYS"* || "$OS_TYPE" == *"CYGWIN"* ]]; then
                home="${USERPROFILE:-C:}"
                local_app_data="${LOCALAPPDATA:-$home/AppData/Local}"
                ollama_path="$local_app_data/Programs/Ollama/ollama.exe"
                if [ -f "$ollama_path" ]; then
                    "$ollama_path" serve > logs/ollama_server.log 2>&1 &
                else
                    ollama serve > logs/ollama_server.log 2>&1 &
                fi
            else
                ollama serve > logs/ollama_server.log 2>&1 &
            fi
        ) &
        
        # Wait for Ollama service to become responsive (up to 20 seconds)
        (
            for i in {1..20}; do
                if curl -s http://localhost:11434 &>/dev/null; then
                    exit 0
                fi
                sleep 1
            done
            exit 1
        ) &
        show_spinner $! "Waiting for Ollama service to start after reinstall..."
        wait $!
        
        if [ $? -ne 0 ]; then
            echo -e "  [${RED}✗${NC}] Ollama service failed to become responsive after reinstall. Check logs/ollama_server.log"
        else
            echo -e "  [${GREEN}✓${NC}] Ollama service is active."
        fi
    else
        echo -e "  [${GREEN}✓${NC}] Ollama service is active."
    fi
fi

# Default model pulling skipped (user will choose in the UI)

# Setup Python virtual environment & install pip packages silently
cd backend
USE_VENV=true
if [ ! -d "venv" ]; then
    if ! $PYTHON_CMD -m venv venv 2>/dev/null; then
        USE_VENV=false
    fi
fi

# Reinstall dependencies if requirements.txt changed OR if venv/uvicorn is missing
REQ_HASH_FILE=".requirements_hash"
CURRENT_HASH=$(md5 requirements.txt 2>/dev/null || md5sum requirements.txt 2>/dev/null | awk '{print $1}')

NEED_PIP_INSTALL=false
if [ ! -f "$REQ_HASH_FILE" ] || [ "$(cat $REQ_HASH_FILE 2>/dev/null)" != "$CURRENT_HASH" ]; then
    NEED_PIP_INSTALL=true
elif [ "$USE_VENV" = "true" ] && [ ! -f "venv/bin/uvicorn" ]; then
    NEED_PIP_INSTALL=true
fi

if [ "$NEED_PIP_INSTALL" = "true" ]; then
    echo "📦 Installing/updating Python dependencies..."
    if [ "$USE_VENV" = "true" ] && [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        pip install --upgrade pip 2>&1 | tee ../logs/pip_install.log
        pip install -r requirements.txt 2>&1 | tee -a ../logs/pip_install.log
        pip install -r requirements-dev.txt 2>&1 | tee -a ../logs/pip_install.log
        pip_status=${PIPESTATUS[0]}
    else
        $PYTHON_CMD -m pip install --upgrade pip --user 2>&1 | tee ../logs/pip_install.log || true
        $PYTHON_CMD -m pip install -r requirements.txt --user 2>&1 | tee -a ../logs/pip_install.log
        $PYTHON_CMD -m pip install -r requirements-dev.txt --user 2>&1 | tee -a ../logs/pip_install.log
        pip_status=${PIPESTATUS[0]}
    fi

    if [ $pip_status -ne 0 ]; then
        echo -e "  [${RED}✗${NC}] Backend dependencies installation failed."
        exit 1
    else
        echo -e "  [${GREEN}✓${NC}] Backend dependencies installed."
        echo "$CURRENT_HASH" > "$REQ_HASH_FILE"
    fi
else
    echo "✅ Python dependencies up to date (requirements.txt unchanged)"
fi
cd ..

# Compile Flutter Web frontend — always rebuild if source has changed
BUILD_WEB=false
FLUTTER_HASH_FILE="frontend/.flutter_build_hash"

if [ "$HAS_FLUTTER" = "true" ]; then
    if [ "$HAS_WEB_BUILD" = "false" ]; then
        # No build at all — must compile
        BUILD_WEB=true
        echo -e "  [${YELLOW}!${NC}] No pre-compiled Web UI found. Building now..."
    else
        # Build exists — check if source code has changed since last build
        CURRENT_SRC_HASH=""
        if command -v find &> /dev/null; then
            # Hash based on: all .dart files + pubspec.yaml modification times
            CURRENT_SRC_HASH=$(find frontend/lib frontend/pubspec.yaml frontend/pubspec.lock -type f 2>/dev/null \
                | sort | xargs stat -f "%m %N" 2>/dev/null \
                || find frontend/lib frontend/pubspec.yaml frontend/pubspec.lock -type f 2>/dev/null \
                | sort | xargs stat --format="%Y %n" 2>/dev/null \
                | md5sum 2>/dev/null | awk '{print $1}')
        fi

        SAVED_HASH=$(cat "$FLUTTER_HASH_FILE" 2>/dev/null || echo "")

        if [ -n "$CURRENT_SRC_HASH" ] && [ "$CURRENT_SRC_HASH" != "$SAVED_HASH" ]; then
            BUILD_WEB=true
            echo -e "  [${YELLOW}!${NC}] Source changes detected — rebuilding Flutter Web UI..."
        else
            echo -e "  [${GREEN}✓${NC}] Flutter source unchanged — using existing build."
        fi
    fi
fi

if [ "$BUILD_WEB" = "true" ]; then
    echo "🔨 Compiling Flutter Web application..."
    cd frontend
    if [ "$IS_COLAB" = "true" ]; then
        export PATH="$PATH:/content/flutter/bin:$HOME/flutter/bin"
        git config --global --add safe.directory /content/flutter || true
    fi
    flutter pub get 2>&1 | tee ../logs/flutter_build.log
    flutter build web 2>&1 | tee -a ../logs/flutter_build.log
    flutter_status=${PIPESTATUS[0]}
    cd ..
    if [ $flutter_status -ne 0 ]; then
        echo -e "  [${RED}✗${NC}] Flutter Web build failed. Check logs/flutter_build.log for details."
        exit 1
    else
        echo -e "  [${GREEN}✓${NC}] Flutter Web application compiled successfully."
        # Save the new source hash so next run skips rebuild if nothing changed
        if [ -n "$CURRENT_SRC_HASH" ]; then
            echo "$CURRENT_SRC_HASH" > "$FLUTTER_HASH_FILE"
        fi
    fi
elif [ "$HAS_WEB_BUILD" = "true" ]; then
    echo -e "  [${GREEN}✓${NC}] Using existing pre-compiled Web assets."
fi


# ==========================================
# 6. Service Startup & Expose Tunnel
# ==========================================

# Get host LAN IP
if [ "$(uname)" = "Darwin" ]; then
    LAN_IP=$(ipconfig getifaddr en0 || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n1 || echo "")
else
    LAN_IP=$(hostname -I | awk '{print $1}' || true)
    if [ -z "$LAN_IP" ]; then
        LAN_IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}' || ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n1 || true)
    fi
fi

# Tunnel Choice Selection
TUNNEL_CHOICE="1"
if [ "$IS_COLAB" = "true" ]; then
    TUNNEL_CHOICE="2"
else
    echo -e "\n  Do you want to expose a public link?"
    echo -e "  ${GRAY}──────────────────────────────────────────────────────${NC}"
    echo -e "  1. No (Local Network only)"
    echo -e "  2. Yes, via Cloudflare Quick Tunnel (Recommended — Zero Setup, Auto-Binary)"
    echo -e "  3. Yes, via ngrok (Pre-configured authtoken)"
    echo -e "  4. Yes, via Tailscale Funnel (Requires Tailscale account setup)"
    echo -e "  5. Yes, via Localtunnel (Requires Node.js/npm)"
    read -p "  Enter choice [1-5]: " -r TUNNEL_CHOICE || true
    TUNNEL_CHOICE=${TUNNEL_CHOICE:-2}
fi

# Setup cleanup traps
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
    rm -f cloudflared.log localtunnel.log ngrok.log tailscale.log
    echo -e "${GREEN}Shutdown complete. Goodbye!${NC}"
}
trap cleanup SIGINT SIGTERM EXIT

# Expose Nvidia paths
if [ "$(uname)" = "Linux" ]; then
    export LD_LIBRARY_PATH="/usr/lib64-nvidia:/usr/local/nvidia/lib64:/usr/local/cuda/lib64:/usr/local/cuda/targets/aarch64-linux/lib:$LD_LIBRARY_PATH"
fi

# Start FastAPI server in background
echo "Launching FastAPI server..."
cd backend
if [ -f "uvicorn.log" ]; then
    LOG_SIZE=$(wc -c < uvicorn.log 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 10485760 ]; then
        mv uvicorn.log uvicorn.log.old
    fi
fi

if [ "$USE_VENV" = "true" ] && [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
fi
python -m uvicorn main:app --host 0.0.0.0 --port 8000 2>&1 | tee uvicorn.log &
BACKEND_PID=$!
cd ..

# Wait for FastAPI backend server to become responsive
for i in {1..30}; do
    if curl -s http://localhost:8000/docs &>/dev/null; then
        echo -e "  [${GREEN}✓${NC}] Backend is fully responsive and active."
        break
    fi
    sleep 1
done

# Tunnel setup
PUBLIC_URL="Not enabled"
if [ "$TUNNEL_CHOICE" = "2" ]; then
    CLOUDFLARED_CMD=""
    if command -v cloudflared &> /dev/null; then
        CLOUDFLARED_CMD="cloudflared"
    elif [ -f "./cloudflared" ]; then
        CLOUDFLARED_CMD="./cloudflared"
    else
        echo "Downloading cloudflared binary for public tunneling..."
        OS=$(uname -s)
        ARCH=$(uname -m)
        if [ "$OS" = "Linux" ]; then
            if [ "$ARCH" = "x86_64" ]; then
                curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
            else
                curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
            fi
            chmod +x cloudflared
            CLOUDFLARED_CMD="./cloudflared"
        else
            if [ "$ARCH" = "x86_64" ]; then
                curl -L -o cloudflared.tgz https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz
            else
                curl -L -o cloudflared.tgz https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64.tgz
            fi
            tar -xzf cloudflared.tgz
            rm -f cloudflared.tgz
            chmod +x cloudflared
            CLOUDFLARED_CMD="./cloudflared"
        fi
    fi

    echo "Initializing Cloudflare Quick Tunnel..."
    rm -f cloudflared.log
    $CLOUDFLARED_CMD tunnel --url http://localhost:8000 > cloudflared.log 2>&1 &
    TUNNEL_PID=$!

    for i in {1..15}; do
        sleep 1
        PUBLIC_URL=$(grep -o 'https://[^ ]*\.trycloudflare\.com' cloudflared.log | head -n1 || true)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    done

    # Verify public tunnel URL propagation and reachability before displaying
    if [ -n "$PUBLIC_URL" ] && [[ "$PUBLIC_URL" =~ ^https:// ]]; then
        echo "🌐 Verifying Cloudflare public tunnel reachability..."
        for i in {1..15}; do
            status=$(curl -s -o /dev/null -I -L -w "%{http_code}" --connect-timeout 2 "$PUBLIC_URL" || echo "000")
            if [ "$status" != "000" ] && [ "$status" -ne 502 ] && [ "$status" -ne 503 ]; then
                echo -e "  [${GREEN}✓${NC}] Cloudflare public tunnel active and verified live!"
                break
            fi
            sleep 1
        done
    else
        PUBLIC_URL="${RED}Failed to establish Cloudflare tunnel${NC}"
    fi

elif [ "$TUNNEL_CHOICE" = "3" ]; then
    NGROK_CMD=""
    if command -v ngrok &> /dev/null; then
        NGROK_CMD="ngrok"
    elif [ -f "./ngrok" ]; then
        NGROK_CMD="./ngrok"
    else
        echo "Downloading ngrok binary..."
        OS=$(uname -s)
        ARCH=$(uname -m)
        if [ "$OS" = "Linux" ]; then
            NGROK_TGZ="ngrok.tgz"
            if [ "$ARCH" = "x86_64" ]; then
                curl -L -o "$NGROK_TGZ" https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
            else
                curl -L -o "$NGROK_TGZ" https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz
            fi
            tar -xzf "$NGROK_TGZ"
            rm -f "$NGROK_TGZ"
        else
            NGROK_ZIP="ngrok.zip"
            curl -L -o "$NGROK_ZIP" https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip
            unzip -o "$NGROK_ZIP" ngrok -d . &> /dev/null
            rm -f "$NGROK_ZIP"
        fi
        chmod +x ./ngrok
        NGROK_CMD="./ngrok"
    fi

    NGROK_TOKEN="${NGROK_AUTHTOKEN:-3HEy8jnU0iosJdlsfUeZysHhEJZ_211Ub5wALgdEBpstfQjT8}"
    if [ -z "$NGROK_TOKEN" ] && [ -f "backend/.env" ]; then
        NGROK_TOKEN=$(grep -E '^NGROK_AUTHTOKEN=' backend/.env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'")
    fi
    if [ -z "$NGROK_TOKEN" ]; then
        NGROK_TOKEN="3HEy8jnU0iosJdlsfUeZysHhEJZ_211Ub5wALgdEBpstfQjT8"
    fi
    if [ -n "$NGROK_TOKEN" ]; then
        $NGROK_CMD config add-authtoken "$NGROK_TOKEN" &> /dev/null || true
    fi

    echo "Initializing ngrok tunnel..."
    rm -f ngrok.log
    $NGROK_CMD http 8000 --log=stdout > ngrok.log 2>&1 &
    TUNNEL_PID=$!

    for i in {1..20}; do
        sleep 1
        PUBLIC_URL=$(grep -o 'url=https://[^ ]*' ngrok.log | head -n1 | sed 's/url=//' || true)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    done
    if [ -z "$PUBLIC_URL" ]; then
        sleep 2
        PUBLIC_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | head -n1 | sed 's/"public_url":"//;s/"//' || true)
    fi
    [ -z "$PUBLIC_URL" ] && PUBLIC_URL="${RED}Failed to establish ngrok tunnel${NC}"

elif [ "$TUNNEL_CHOICE" = "4" ]; then
    echo "Initializing Tailscale Funnel..."
    if ! command -v tailscale &> /dev/null; then
        echo -e "  [${YELLOW}⚠${NC}] Tailscale CLI not found."
        if [ "$(uname)" = "Darwin" ]; then
            echo "  Installing Tailscale via Homebrew..."
            brew install tailscale 2>/dev/null || true
        else
            echo "  Installing Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | sh 2>/dev/null || true
        fi
    fi

    if command -v tailscale &> /dev/null; then
        if ! pgrep tailscaled &>/dev/null; then
            echo "  [⚙️] Starting Tailscale background daemon (tailscaled)..."
            if [ "$(uname)" = "Darwin" ]; then
                sudo brew services start tailscale 2>/dev/null || sudo tailscaled &>/dev/null &
            else
                sudo systemctl start tailscaled 2>/dev/null || sudo tailscaled &>/dev/null &
            fi
            sleep 2
        fi

        TAILSCALE_CMD="tailscale"
        if ! tailscale status &>/dev/null && sudo tailscale status &>/dev/null; then
            TAILSCALE_CMD="sudo tailscale"
        fi

        if ! $TAILSCALE_CMD status &>/dev/null; then
            echo -e "  [${YELLOW}🔑${NC}] Tailscale login required. Launching Tailscale authentication..."
            $TAILSCALE_CMD up || true
        fi

        rm -f tailscale.log
        $TAILSCALE_CMD funnel 8000 > tailscale.log 2>&1 &
        TUNNEL_PID=$!
        sleep 2

        FUNNEL_ENABLE_LINK=$(grep -o 'https://login\.tailscale\.com/f/funnel[^ ]*' tailscale.log | head -n1 || true)
        if [ -n "$FUNNEL_ENABLE_LINK" ]; then
            echo -e "  [${YELLOW}⚠️${NC}] Tailscale Funnel needs 1-click enabling on your account."
            echo -e "  [👉] Click here to enable: ${FUNNEL_ENABLE_LINK}"
            PUBLIC_URL="${YELLOW}Enable Funnel first at: ${FUNNEL_ENABLE_LINK}${NC}"
        else
            PUBLIC_URL=$(grep -o 'https://[^ ]*\.ts\.net' tailscale.log | head -n1 || true)
            if [ -z "$PUBLIC_URL" ]; then
                PUBLIC_URL=$($PYTHON_CMD -c "import subprocess, json; data=json.loads(subprocess.check_output(['tailscale', 'status', '--json'])); print('https://' + data['Self']['DNSName'].rstrip('.'))" 2>/dev/null || true)
            fi
        fi
    fi
    if [ -z "$PUBLIC_URL" ] || [[ "$PUBLIC_URL" == "https://" ]]; then
        PUBLIC_URL="${RED}Failed to establish Tailscale Funnel. Run 'tailscale funnel 8000' manually.${NC}"
    fi

elif [ "$TUNNEL_CHOICE" = "5" ]; then
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}Error: npm is not installed. Node.js required for Localtunnel.${NC}"
        exit 1
    fi
    echo "Initializing Localtunnel..."
    rm -f localtunnel.log
    npx localtunnel --port 8000 --subdomain "kivo-workspace" > localtunnel.log 2>&1 &
    TUNNEL_PID=$!

    for i in {1..15}; do
        sleep 1
        PUBLIC_URL=$(grep -o 'https://[^ ]*\.localtunnel\.me' localtunnel.log | head -n1 || true)
        if [ -n "$PUBLIC_URL" ]; then
            break
        fi
    done
    [ -z "$PUBLIC_URL" ] && PUBLIC_URL="${RED}Failed to establish Localtunnel${NC}"
fi

# Verify public tunnel URL propagation and reachability
if [ "$TUNNEL_CHOICE" != "1" ] && [ -n "$PUBLIC_URL" ] && [[ "$PUBLIC_URL" =~ ^https:// ]]; then
    echo "🌐 Waiting for Cloudflare public tunnel DNS propagation..."
    for i in {1..20}; do
        status=$(curl -s -o /dev/null -I -L -w "%{http_code}" --connect-timeout 2 "$PUBLIC_URL" || echo "000")
        if [ "$status" != "000" ] && [ "$status" -ne 502 ] && [ "$status" -ne 503 ]; then
            echo -e "  [${GREEN}✓${NC}] Public tunnel DNS active and reachable!"
            break
        fi
        sleep 1
    done
fi

sleep 1

# Present running dashboard
print_logo
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}       🚀 KIVO WORKSPACE IS SUCCESSFULLY RUNNING!     ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo -e "  Local access (This Mac):     http://localhost:8000"
if [ -n "$LAN_IP" ]; then
    echo -e "  Local Network (Same Wi-Fi):  http://${LAN_IP}:8000"
fi
if [ "$TUNNEL_CHOICE" != "1" ]; then
    echo -e "  Public Link (Remote access): ${PUBLIC_URL}"
fi
echo -e "${GREEN}======================================================${NC}"
echo -e "Streaming backend logs live below. Press Ctrl+C to stop.
"

wait $BACKEND_PID
