APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/ripplebeam-*/Build/Products/Debug/ripplebeam.app"
PYTHON_FRAMEWORK_SRC="${SRCROOT}/Embedded2/Python.framework"
PYTHON_FRAMEWORK_DEST="$APP_PATH/Contents/Frameworks/Python.framework"
PYTHON_EXEC="$PYTHON_FRAMEWORK_DEST/Versions/3.11/bin/python3"

echo "🔁 Copying Python.framework..."
rm -rf "$PYTHON_FRAMEWORK_DEST"
cp -R "$PYTHON_FRAMEWORK_SRC" "$PYTHON_FRAMEWORK_DEST"

echo "🔏 Signing python3 executable..."
codesign --force --sign - "$PYTHON_EXEC"