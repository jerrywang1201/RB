#!/bin/bash
set -e

APP="$BUILT_PRODUCTS_DIR/$FULL_PRODUCT_NAME"
PYTHON_SRC="${SRCROOT}/Embedded2/Python.framework"
PYTHON_DST="$APP/Contents/Frameworks/Python.framework"

echo "🔁 Copying Python.framework to app bundle..."
rm -rf "$PYTHON_DST"
cp -R "$PYTHON_SRC" "$PYTHON_DST"

echo "🔏 Codesigning python3..."
codesign --force --deep --sign - "$PYTHON_DST/Versions/3.11/bin/python3"