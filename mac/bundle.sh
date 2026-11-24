#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/NotifyBridge.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotifyBridge "$APP/Contents/MacOS/NotifyBridge"
mkdir -p "$APP/Contents/Resources"
# compile the icon catalog so macOS (notifications, Settings) finds the icon by CFBundleIconName
ICONOUT=$(mktemp -d)
xcrun actool Assets.xcassets --compile "$ICONOUT" --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon --output-partial-info-plist "$ICONOUT/partial.plist" >/dev/null
cp "$ICONOUT/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ICONOUT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R Localization/en.lproj Localization/tr.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
<key>CFBundleIdentifier</key><string>com.notifybridge.desktop</string>
<key>CFBundleName</key><string>NotifyBridge</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIconName</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>NotifyBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Local network access is needed to receive notifications from your phone.</string>
<key>NSBonjourServices</key><array><string>_notifybridge._tcp</string></array>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "OK: $APP"
