#!/bin/bash
# Builds what a release ships, signed and notarized: the zip for the update bar and the disk image for the website.
#   release.sh version [out-dir]    out-dir defaults to dist/release-version. Publishes nothing.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; PROJECT="$(dirname "$HERE")"
VER="$1"; OUT="${2:-$PROJECT/dist/release-$VER}"
NAME="Downstage Find"; ZIPNAME="Downstage-Find"; DMGTOOL="${DMGTOOL:-$(dirname "$PROJECT")/virtual-deck/macapp/dmg/make-dmg.sh}"
. "$HERE/signing.conf"
notarize() { local r; r="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait)"; echo "$r" | tail -2; case "$r" in *"status: Accepted"*) ;; *) return 1 ;; esac; }
STAGE="$(mktemp -d)"
DOWNSTAGE_SIGN=1 DOWNSTAGE_OUT="$STAGE" "$HERE/build.sh" "$VER" >/dev/null
notarize "$STAGE/$ZIPNAME.zip"
xcrun stapler staple "$STAGE/$NAME.app"
xattr -cr "$STAGE/$NAME.app"
spctl -a -vv -t exec "$STAGE/$NAME.app"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/$NAME.app" "$OUT/$ZIPNAME.zip"
"$DMGTOOL" "$OUT/$ZIPNAME.zip" "$OUT/$ZIPNAME.dmg"
codesign --force --timestamp -s "$SIGN_ID" "$OUT/$ZIPNAME.dmg"
notarize "$OUT/$ZIPNAME.dmg"
xcrun stapler staple "$OUT/$ZIPNAME.dmg"
spctl -a -vv -t open --context context:primary-signature "$OUT/$ZIPNAME.dmg"
shasum -a 256 "$OUT/$ZIPNAME.zip" "$OUT/$ZIPNAME.dmg"
