#!/bin/bash
# Scripts/release.sh <version> — archive, sign, notarize, staple, dmg, appcast entry
set -euo pipefail
VERSION="${1:?usage: release.sh 1.0.0}"
IDENTITY="Developer ID Application"   # picks up the cert by prefix
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project Compress.xcodeproj -scheme Compress -configuration Release \
  MARKETING_VERSION="$VERSION" -derivedDataPath build/dd -destination "generic/platform=macOS" \
  archive -archivePath build/Compress.xcarchive
APP="build/Compress.xcarchive/Products/Applications/Compress.app"

# Verify the archived binary is truly universal before signing/shipping it.
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Compress")"
echo "Archive architectures: $ARCHS"
case "$ARCHS" in
  *x86_64*arm64*|*arm64*x86_64*) ;;
  *) echo "ERROR: expected universal (x86_64 arm64) binary, got: $ARCHS" >&2; exit 1 ;;
esac

# Sign bundled ffmpeg/ffprobe first (nested code), then the app
for tool in ffmpeg ffprobe; do
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/$tool"
done
codesign --force --deep --options runtime --timestamp \
  --entitlements App/Compress.entitlements --sign "$IDENTITY" "$APP"

hdiutil create -volname Compress -srcfolder "$APP" -ov -format UDZO "build/Compress-$VERSION.dmg"
xcrun notarytool submit "build/Compress-$VERSION.dmg" --keychain-profile compress-notary --wait
xcrun stapler staple "build/Compress-$VERSION.dmg"

# Sparkle signature for appcast
SIGNATURE=$(./build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update "build/Compress-$VERSION.dmg")
echo "appcast enclosure attrs: $SIGNATURE"
echo "DONE: build/Compress-$VERSION.dmg"

# -----------------------------------------------------------------------------
# Docs: one-time setup required before this script can run end-to-end.
# None of the following has been done on this machine yet — `security
# find-identity -v -p codesigning` shows no "Developer ID Application" cert,
# and no `compress-notary` keychain profile exists.
#
# 1. Create a "Developer ID Application" certificate:
#    - Xcode: Settings > Accounts > (Apple ID) > Manage Certificates... >
#      "+" > "Developer ID Application" (requires an active Apple Developer
#      Program membership on the account).
#    - Or via the web: https://developer.apple.com/account/resources/certificates/list
#      > "+" > "Developer ID Application" > follow the CSR steps, download,
#      double-click to install into the login keychain.
#    - Verify with: security find-identity -v -p codesigning
#      (should list "Developer ID Application: <Your Name> (<TEAMID>)").
#
# 2. Create an App Store Connect API key and store notarytool credentials:
#    - https://appstoreconnect.apple.com/access/api > Keys > "+" (role:
#      Developer is sufficient) > download the .p8, note the Key ID and
#      Issuer ID.
#    - Run once:
#        xcrun notarytool store-credentials compress-notary \
#          --key /path/to/AuthKey_XXXX.p8 \
#          --key-id <KEY_ID> \
#          --issuer <ISSUER_ID>
#      This stores the credential in the login keychain under the profile
#      name "compress-notary" that this script references.
#    - Verify with: xcrun notarytool history --keychain-profile compress-notary
#
# 3. Generate the Sparkle EdDSA signing keys (one time):
#    - After `xcodegen generate`, the Sparkle SPM package's tools are under
#      build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/ once a build
#      has run; alternatively download the Sparkle release archive from
#      https://github.com/sparkle-project/Sparkle/releases and use the
#      bin/generate_keys tool.
#    - Run: ./generate_keys
#      This creates a private key in the login Keychain (used later by
#      bin/sign_update, invoked above) and prints a public key string.
#    - Paste the printed public key into project.yml's
#      targets.Compress.info.properties.SUPublicEDKey (replacing
#      REPLACE_WITH_generate_keys_OUTPUT), then re-run `xcodegen generate`.
#    - Re-run generate_keys -p at any time to reprint the existing public key
#      without creating a new keypair.
#
# 4. Set the real feed URL:
#    - Replace SUFeedURL in project.yml (currently
#      https://REPLACE-AT-LAUNCH.example/appcast.xml) with the actual hosted
#      location of Site/appcast.xml (see Task 12 for Site/ deployment).
#
# Once all four are done, `./Scripts/release.sh <version>` should run
# unattended through archive, codesign, notarization ("status: Accepted"),
# stapling, and print the sign_update output to paste into
# Site/appcast.xml's sparkle:edSignature attribute for that release.
# -----------------------------------------------------------------------------
