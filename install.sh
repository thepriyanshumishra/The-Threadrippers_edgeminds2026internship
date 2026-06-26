#!/bin/bash
# Kivo Workspace — Terminal Installer for macOS and Linux
# Purpose: Downloads the latest pre-compiled production release from GitHub and installs it on the user's system.

set -e

# --- Configuration ---
GITHUB_REPO="thepriyanshumishra/The-Threadrippers_edgeminds2026internship"

# ANSI Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}      Installing Kivo Workspace          ${NC}"
echo -e "${GREEN}=========================================${NC}"

# Detect OS and Architecture
OS=$(uname -s)
ARCH=$(uname -m)

echo -e "Detecting System: ${YELLOW}$OS ($ARCH)${NC}"

# Determine which release file to download
if [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "arm64" ]; then
        PLATFORM_KEY="Silicon"
    else
        PLATFORM_KEY="Intel"
    fi
    FILE_EXT="dmg"
elif [ "$OS" = "Linux" ]; then
    PLATFORM_KEY="Linux"
    FILE_EXT="AppImage"
else
    echo -e "${RED}Error: Unsupported operating system: $OS${NC}"
    exit 1
fi

echo -e "Checking latest release from GitHub (${YELLOW}$GITHUB_REPO${NC})..."

# Fetch the release info from GitHub API
RELEASE_JSON=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest")

# Check if rate limited or repo not found
if echo "$RELEASE_JSON" | grep -q "message.*rate limit"; then
    echo -e "${RED}Error: GitHub API rate limit exceeded. Please try again later.${NC}"
    exit 1
fi

# Find download URL for the target asset
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep "browser_download_url" | cut -d '"' -f 4 | grep -i "$PLATFORM_KEY" | grep -i "$FILE_EXT" | head -n 1)

if [ -z "$DOWNLOAD_URL" ]; then
    # Fallback to general file match
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep "browser_download_url" | cut -d '"' -f 4 | grep -i "$OS" | grep -i "$FILE_EXT" | head -n 1)
fi

if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "${RED}Error: Could not find release package matching $OS ($ARCH) with ext .$FILE_EXT on GitHub Releases.${NC}"
    echo "Please ensure the GitHub Actions build has completed and uploaded the release packages."
    exit 1
fi

FILENAME=$(basename "$DOWNLOAD_URL")
TEMP_DIR=$(mktemp -d)
TEMP_FILE="$TEMP_DIR/$FILENAME"

echo -e "Downloading package: ${GREEN}$FILENAME${NC}"
curl -L -o "$TEMP_FILE" "$DOWNLOAD_URL"

# Install paths
if [ "$OS" = "Darwin" ]; then
    INSTALL_DIR="/Applications"
    if [ ! -w "$INSTALL_DIR" ]; then
        INSTALL_DIR="$HOME/Applications"
        mkdir -p "$INSTALL_DIR"
    fi
    
    echo -e "Installing macOS App from DMG..."
    MOUNT_POINT=$(mktemp -d)
    
    # Mount DMG
    hdiutil attach "$TEMP_FILE" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
    
    echo -e "Copying Kivo Workspace.app to ${YELLOW}$INSTALL_DIR${NC}..."
    rm -rf "$INSTALL_DIR/Kivo Workspace.app"
    cp -R "$MOUNT_POINT/Kivo Workspace.app" "$INSTALL_DIR/"
    
    # Detach DMG
    hdiutil detach "$MOUNT_POINT" -quiet
    rm -rf "$MOUNT_POINT"
    
    echo -e "${GREEN}Kivo Workspace installed successfully inside $INSTALL_DIR!${NC}"
    echo "You can now open it from your Applications folder or launch it via Spotlight."
else
    # Linux AppImage installation
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    
    echo -e "Installing Kivo Workspace AppImage to ${YELLOW}$INSTALL_DIR${NC}..."
    cp "$TEMP_FILE" "$INSTALL_DIR/kivoworkspace"
    chmod +x "$INSTALL_DIR/kivoworkspace"
    
    # Create Desktop shortcut for Linux app launcher integration
    SHORTCUT_DIR="$HOME/.local/share/applications"
    mkdir -p "$SHORTCUT_DIR"
    
    cat <<EOF > "$SHORTCUT_DIR/kivo-workspace.desktop"
[Desktop Entry]
Version=1.1
Type=Application
Name=Kivo Workspace
Comment=Edge-first AI Knowledge Workspace
Exec=$INSTALL_DIR/kivoworkspace
Icon=kivoworkspace
Terminal=false
Categories=Utility;Office;
EOF
    
    chmod +x "$SHORTCUT_DIR/kivo-workspace.desktop"
    
    echo -e "${GREEN}Kivo Workspace installed successfully!${NC}"
    echo "The AppImage is installed in $INSTALL_DIR/kivoworkspace and registered in your system app menu."
fi

# Cleanup
rm -rf "$TEMP_DIR"
echo -e "${GREEN}Installation complete!${NC}"
