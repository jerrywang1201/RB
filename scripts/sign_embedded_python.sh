#!/bin/bash
set -e

APP=$(find ~/Library/Developer/Xcode/DerivedData/ -type d -name ripplebeam.app -path "*Build/Products/Debug/ripplebeam.app" ! -path "*Index.noindex*" | head -n 1)
PYTHON_SRC="./Embedded2/Python.framework"
PYTHON_DST="$APP/Contents/Frameworks/Python.framework"
PYTHON_DST_DIR="$APP/Contents/Frameworks"
PYTHON_BIN="$PYTHON_DST/Versions/3.11/bin/python3.11"

echo "📁 Ensuring target directory exists..."
mkdir -p "$PYTHON_DST_DIR"

echo "🧹 Cleaning previous Python.framework..."
rm -rf "$PYTHON_DST"

echo "📦 Copying Python.framework..."
cp -R "$PYTHON_SRC" "$PYTHON_DST"

echo "🔏 Signing Python binary..."
codesign --force --deep --sign - "$PYTHON_BIN"

echo "✅ Done!"