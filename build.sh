#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release --locked --manifest-path core/Cargo.toml
APP="$PWD/build/起身一下.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -enable-upcoming-feature NonisolatedNonsendingByDefault -O -target arm64-apple-macosx14.0 Timing/*.swift Sources/*.swift -o "$APP/Contents/MacOS/MiBreak" -framework SwiftUI -framework AppKit -framework Security
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp -R licenses "$APP/Contents/Resources/"
cp core/target/release/mi-break-core "$APP/Contents/Resources/mi-break-core"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.mibreak.menu</string>
<key>CFBundleName</key><string>起身一下</string>
<key>CFBundleDisplayName</key><string>起身一下</string>
<key>CFBundleExecutable</key><string>MiBreak</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Resources/mi-break-core"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
