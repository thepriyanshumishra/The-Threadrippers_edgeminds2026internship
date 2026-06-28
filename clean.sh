#!/bin/bash
# Kivo Workspace — Purge Caches and Reset System
# Purpose: Deletes virtual environments, local database storages, pip caches, playwright binaries, and huggingface cache.
# Run: chmod +x clean.sh && ./clean.sh

# ANSI Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=========================================${NC}"
echo -e "${RED}   KIVO WORKSPACE — COMPLETE PURGE       ${NC}"
echo -e "${RED}=========================================${NC}"
echo -e "${YELLOW}This script will delete virtual envs, databases, and system caches.${NC}\n"

# 1. Clean local project files
echo -e "${YELLOW}[1/6] Cleaning frontend Flutter build...${NC}"
if [ -d "frontend" ]; then
    cd frontend
    flutter clean 2>/dev/null || true
    rm -rf .dart_tool .packages pubspec.lock
    cd ..
    echo -e "${GREEN}✓ Frontend cleaned.${NC}"
else
    echo "Frontend directory not found. Skipping..."
fi

# 2. Delete virtual environments
echo -e "\n${YELLOW}[2/6] Deleting virtual environments (venv)...${NC}"
rm -rf venv backend/venv
echo -e "${GREEN}✓ Virtual environments deleted.${NC}"

# 3. Clean python cache files
echo -e "\n${YELLOW}[3/6] Purging python cache files (__pycache__)...${NC}"
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name ".ruff_cache" -exec rm -rf {} + 2>/dev/null || true
echo -e "${GREEN}✓ Python caches deleted.${NC}"

# 4. Clean local databases and storage
echo -e "\n${YELLOW}[4/6] Deleting KivoWorkspace SQLite database and source storage...${NC}"
rm -rf ~/.local/share/KivoWorkspace
rm -rf ~/Library/Application\ Support/KivoWorkspace
echo -e "${GREEN}✓ Local database storage cleared.${NC}"

# 5. Clean browser and models cache
echo -e "\n${YELLOW}[5/6] Deleting system cache directories (Playwright, HuggingFace)...${NC}"
rm -rf ~/.cache/ms-playwright
rm -rf ~/.cache/huggingface
echo -e "${GREEN}✓ Playwright and HuggingFace caches deleted.${NC}"

# 6. Purge pip installation cache
echo -e "\n${YELLOW}[6/6] Purging pip package cache...${NC}"
rm -rf ~/.cache/pip
echo -e "${GREEN}✓ Pip cache cleared.${NC}"

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}          PURGE COMPLETE                 ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo "You can now run ./start.sh to perform a fresh launch."
