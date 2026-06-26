#!/bin/bash
set -e

echo "=== 1. Building Flutter Frontend (Web) ==="
cd frontend
flutter pub get
flutter build web --release
cd ..

echo "=== 2. Setting up Web Assets for Backend ==="
rm -rf backend/web
cp -R frontend/build/web backend/web

echo "=== 3. Compiling Python Backend (with Embedded Web Assets) ==="
ICON_SRC="frontend/macos/Runner/Assets.xcassets/AppIcon.appiconset"
ICONSET_DIR="AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16   16   "$ICON_SRC/app_icon_16.png"   --out "$ICONSET_DIR/icon_16x16.png"   > /dev/null
sips -z 32   32   "$ICON_SRC/app_icon_32.png"   --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32   32   "$ICON_SRC/app_icon_32.png"   --out "$ICONSET_DIR/icon_32x32.png"   > /dev/null
sips -z 64   64   "$ICON_SRC/app_icon_64.png"   --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128  128  "$ICON_SRC/app_icon_128.png"  --out "$ICONSET_DIR/icon_128x128.png"  > /dev/null
sips -z 256  256  "$ICON_SRC/app_icon_256.png"  --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256  256  "$ICON_SRC/app_icon_256.png"  --out "$ICONSET_DIR/icon_256x256.png"  > /dev/null
sips -z 512  512  "$ICON_SRC/app_icon_512.png"  --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512  512  "$ICON_SRC/app_icon_512.png"  --out "$ICONSET_DIR/icon_512x512.png"  > /dev/null
sips -z 1024 1024 "$ICON_SRC/app_icon_1024.png" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
iconutil -c icns "$ICONSET_DIR" -o AppIcon.icns
rm -rf "$ICONSET_DIR"
# Find a suitable python version
if command -v python3.12 &>/dev/null; then
  PYTHON_EXE="python3.12"
elif command -v python3.11 &>/dev/null; then
  PYTHON_EXE="python3.11"
elif command -v python3.10 &>/dev/null; then
  PYTHON_EXE="python3.10"
else
  PYTHON_EXE="python3"
fi
echo "Using Python: $PYTHON_EXE"

cd backend
rm -rf .venv
$PYTHON_EXE -m venv .venv
.venv/bin/pip install --upgrade pip
.venv/bin/pip install --prefer-binary -r requirements_ci.txt
.venv/bin/pip install pyinstaller
.venv/bin/pyinstaller --noconfirm --onedir --noconsole --name "Kivo Workspace" --add-data "web:web" --icon "../AppIcon.icns" main.py
cd ..

echo "=== 4. Packaging Drag-and-Drop DMG Installer ==="
cd backend/dist
rm -rf dmg_staging
mkdir -p dmg_staging
cp -R "Kivo Workspace.app" dmg_staging/
ln -s /Applications dmg_staging/Applications
rm -f ../../KivoWorkspace-macOS.dmg
hdiutil create -fs HFS+ -srcfolder dmg_staging -volname "Kivo Workspace" -format UDZO ../../KivoWorkspace-macOS.dmg
rm -rf dmg_staging
cd ../..

echo "=== Done! macOS DMG is ready in the project root folder. ==="
