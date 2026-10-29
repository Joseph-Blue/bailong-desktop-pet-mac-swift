#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache dist
xcrun swiftc -O -whole-module-optimization -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/module-cache Sources/BailongPet/*.swift -o .build/BailongPet -framework AppKit -lsqlite3
app="dist/白龙桌宠.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/BailongPet "$app/Contents/MacOS/BailongPet"
cp -R local-assets/. "$app/Contents/Resources/"
cp VERSION "$app/Contents/Resources/VERSION"
version="$(cat VERSION)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit</string>
<key>CFBundleName</key><string>白龙桌宠</string>
<key>CFBundleExecutable</key><string>BailongPet</string>
<key>CFBundleShortVersionString</key><string>${version%%-*}</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>BailongVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>BailongPet</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
print "已构建 $app（$version，arm64，本地签名）"
