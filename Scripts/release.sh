#!/usr/bin/env bash
# Build a Release SpaceInvaders.app, Developer ID sign with Hardened Runtime,
# notarize via Apple, staple the ticket, and package it as a distributable .dmg.
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ SPARKLE SIGNING KEY — DO NOT REGENERATE                                  │
# │                                                                          │
# │ Updates are EdDSA-signed with the private key in the login keychain      │
# │ under account "SpaceInvaders" (used by sign_update below). Its public    │
# │ half is embedded in the app as SUPublicEDKey in project.yml:             │
# │     mzpzGs9uFpTOCv2NacUqekZc0yRfTP0gyGrtOikqEjE=                         │
# │                                                                          │
# │ NEVER run `generate_keys` again for this account and NEVER change        │
# │ SUPublicEDKey — doing so makes every installed app reject all future     │
# │ auto-updates. A backup exists outside the repo (see MEMORY.md).          │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Usage: ./Scripts/release.sh <version>     e.g. ./Scripts/release.sh 1.0.0
#
# Outputs release/SpaceInvaders-<version>.dmg (notarized, stapled, Sparkle-
# signed) and regenerates appcast.xml. Does NOT push to GitHub — prints the
# suggested `gh release create` command.

set -euo pipefail

VERSION="${1:?Usage: ./Scripts/release.sh <version>  (e.g. ./Scripts/release.sh 1.0.0)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 1. Sanity check: project.yml must declare the same MARKETING_VERSION
if ! grep -q "MARKETING_VERSION: \"$VERSION\"" project.yml; then
  echo "✗ MARKETING_VERSION in project.yml does not match $VERSION" >&2
  grep "MARKETING_VERSION" project.yml | sed 's/^/    /' >&2
  exit 1
fi

# 2. Generated assets must exist (they are committed, but just in case)
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  echo "→ Generated assets missing, running Scripts/generate_assets.py"
  python3 "$ROOT/Scripts/generate_assets.py"
fi

# 3. Regenerate xcodeproj + build Release.
# CODE_SIGNING_ALLOWED=NO works around the com.apple.provenance xattr that
# breaks codesign in CLI builds; we sign manually below from a clean staging.
echo "→ xcodegen generate"
xcodegen generate >/dev/null
echo "→ xcodebuild Release"
xcodebuild -project SpaceInvaders.xcodeproj \
  -scheme SpaceInvaders \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -3

APP="$ROOT/build/Build/Products/Release/SpaceInvaders.app"
[ -d "$APP" ] || { echo "✗ Build did not produce $APP" >&2; exit 1; }

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Vincent LAURIAT (KFLACS69T9)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AppliMacVincentGithub}"

STAGING_DIR="$(mktemp -d)"
STAGING="$STAGING_DIR/Space Invaders.app"
echo "→ Staging to $STAGING_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGING"

# Apple's timestamp server is intermittently flaky — retry up to 5 times.
codesign_ts() {
  local target="$1" attempt
  for attempt in 1 2 3 4 5; do
    if codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target" 2>&1; then
      return 0
    fi
    [ "$attempt" -lt 5 ] && { echo "  ↻ codesign failed ($attempt/5), retry in 5s…"; sleep 5; }
  done
  echo "✗ codesign $target failed after 5 attempts" >&2
  return 1
}

echo "→ Codesigning Sparkle.framework nested binaries (deepest first)"
SPARKLE_FW="$STAGING/Contents/Frameworks/Sparkle.framework"
SPARKLE_VER="$SPARKLE_FW/Versions/B"
codesign_ts "$SPARKLE_VER/Autoupdate"
codesign_ts "$SPARKLE_VER/XPCServices/Downloader.xpc"
codesign_ts "$SPARKLE_VER/XPCServices/Installer.xpc"
codesign_ts "$SPARKLE_VER/Updater.app"
codesign_ts "$SPARKLE_FW"

echo "→ Codesigning the app itself with Developer ID + Hardened Runtime"
codesign_ts "$STAGING"
codesign --verify --strict --deep "$STAGING"

RELEASE_DIR="$ROOT/release"
mkdir -p "$RELEASE_DIR"
DMG="$RELEASE_DIR/SpaceInvaders-$VERSION.dmg"
rm -f "$DMG"

# 4. DMG with the app and an /Applications alias for drag-install
DMG_LAYOUT_DIR="$STAGING_DIR/dmg-layout"
mkdir -p "$DMG_LAYOUT_DIR"
ditto --norsrc --noextattr --noacl "$STAGING" "$DMG_LAYOUT_DIR/Space Invaders.app"
ln -s /Applications "$DMG_LAYOUT_DIR/Applications"

echo "→ Creating $DMG"
hdiutil create -volname "Space Invaders $VERSION" -srcfolder "$DMG_LAYOUT_DIR" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

rm -rf "$STAGING_DIR"

# 5. Notarize + staple
echo "→ Submitting $DMG to Apple notary service (2–5 min)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
echo "→ Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# 6. Sparkle EdDSA signature + appcast.xml
SPARKLE_VERSION="2.9.1"
SPARKLE_TOOLS="$ROOT/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS/bin/sign_update" ]; then
  echo "→ Fetching Sparkle $SPARKLE_VERSION tools (one-time setup)"
  mkdir -p "$SPARKLE_TOOLS"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$SPARKLE_TOOLS"
fi

echo "→ Signing $DMG with Sparkle EdDSA key"
SPARKLE_SIG_LINE=$("$SPARKLE_TOOLS/bin/sign_update" --account "SpaceInvaders" "$DMG")

# Sparkle compares <sparkle:version> against CFBundleVersion (build number),
# not the marketing version — read the real one from the built app.
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

echo "→ Writing appcast.xml (sparkle:version=$BUILD_NUMBER, shortVersionString=$VERSION)"
PUB_DATE=$(date -R)
cat > "$ROOT/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Space Invaders</title>
    <link>https://raw.githubusercontent.com/vincentlauriat/SpaceInvaders/main/appcast.xml</link>
    <description>Space Invaders release feed</description>
    <language>en</language>
    <item>
      <title>v$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/vincentlauriat/SpaceInvaders/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure
        url="https://github.com/vincentlauriat/SpaceInvaders/releases/download/v$VERSION/SpaceInvaders-$VERSION.dmg"
        type="application/octet-stream"
        $SPARKLE_SIG_LINE />
    </item>
  </channel>
</rss>
APPCAST

DMG_SIZE=$(ls -lh "$DMG" | awk '{print $5}')
echo ""
echo "✅ Built, signed, notarized, stapled and Sparkle-signed: $DMG ($DMG_SIZE)"
echo "✅ appcast.xml written for v$VERSION"
echo ""
echo "Next steps:"
echo "  1. gh release create v$VERSION $DMG --title \"v$VERSION\" --notes-file release/release-notes-$VERSION.md"
echo "  2. git add appcast.xml && git commit -m 'docs: appcast for v$VERSION' && git push"
